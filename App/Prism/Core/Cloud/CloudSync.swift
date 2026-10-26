//
//  CloudSync.swift
//  Prism
//

import Foundation
import HealthCloud
import HealthExportCore
import HealthExportHealthKit
import Observation
import SyncCore
import SyncSupabase
#if canImport(HealthKit)
import HealthKit
#endif

/// File writes for the sync's own small state: atomic, and readable after the
/// first unlock so a background pass at night can use them.
nonisolated enum CloudFiles {
    static var writeOptions: Data.WritingOptions {
#if os(macOS)
        .atomic
#else
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
#endif
    }
}

/// Everything that leaves the phone for the app's Supabase project, run
/// while someone is signed in.
///
/// - The stores' records (Journal, Soma asks, moods, Mind check-ins, Track,
///   lab panels, scores, the inbox, provider connections) go through
///   SyncCore: ``CloudMirror`` saves what changed into the outbox, and the
///   session's sync agent pushes it with retries and pulls the person's
///   records back.
/// - Apple Health samples go through `HealthSampleUploader` (WellnessKit's
///   HealthCloud): anchored reads, idempotent upserts, daily rows.
/// - The profile, its photo and this phone go through ``ProfileCloud``.
/// - Ask's conversations go through ``AskHistorySync``, both ways: every
///   kept turn up, every conversation from another phone down.
///
/// A pass runs when the app comes forward, a few seconds after a store
/// changes, and in the background (``CloudBackground``). Nothing here asks
/// for a permission: Health is read only once the one Health sheet has been
/// answered (``HealthAccess``).
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    nonisolated enum Status: Equatable, Sendable {
        case off
        case syncing
        case idle(lastSync: Date?)
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var lastHealthReport: HealthUploadReport?

    private var session: WellnessSession?
    private var mirror: CloudMirror?
    private var profile: ProfileCloud?
    private var askHistory: AskHistorySync?
    private var uploader: HealthSampleUploader?
    private var services: SupabaseServices?
    private var userID: UserID?
    private var starting: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var debounce: Task<Void, Never>?

    /// The Health reader the pages use, for the scores. Set by `.somaCloud`.
    private weak var health: HealthDashboard?
    private var journal: JournalStore?

    // MARK: Wiring

    /// Hands the sync the app's environment objects, and starts it if
    /// someone is already signed in.
    func attach(health: HealthDashboard, journal: JournalStore) {
        self.health = health
        self.journal = journal
        accountDidSignIn()
    }

    /// Opens the person's sync session if it is not open yet.
    func accountDidSignIn() {
        guard session == nil, starting == nil,
              let account = AccountSession.shared.state.user,
              let tokens = AccountSession.shared.tokens,
              let services = AccountSession.shared.services,
              let settings = AccountSession.shared.settings else { return }
        starting = Task {
            await open(user: account, tokens: tokens, services: services, settings: settings)
            starting = nil
            await syncNow()
        }
    }

    private func open(user: AccountUser, tokens: AccountTokens, services: SupabaseServices, settings: SupabaseSettings) async {
        let id = UserID(user.id)
        let configuration = settings.configuration
        do {
            let session = try await WellnessSession.open(
                WellnessEnvironment(
                    userID: id,
                    tokens: tokens,
                    records: SupabaseRecordStore(configuration: configuration),
                    objects: SupabaseObjectStore(configuration: configuration),
                    logSubsystem: "Soma.Prism.cloud"
                ),
                modules: [CloudRecords.module]
            )
            self.session = session
            self.userID = id
            self.services = services
            self.mirror = CloudMirror(session: session)
            self.profile = ProfileCloud(userID: id, services: services, directory: session.directory)
            self.askHistory = AskHistorySync(
                local: AskHistoryStore.shared,
                remote: SupabaseAskHistoryRemote(services: services, userID: id.rawValue),
                ledgerURL: session.directory.appending(path: "ask-history.json")
            )
            if let source = HealthDashboard.launchSource() as? any HealthAnchoredSampleSource {
                self.uploader = HealthSampleUploader(
                    source: source,
                    writer: SupabaseHealthWriter(services: services),
                    anchors: FileHealthAnchorStore(url: session.directory.appending(path: "health-anchors.json")),
                    userID: id,
                    configuration: HealthUploadConfiguration(
                        metrics: HealthUploadConfiguration.catalogMetrics(),
                        installationID: InstallationID.current()
                    )
                )
            }
            status = .idle(lastSync: nil)
            observeStores()
        } catch {
            status = .failed(String(describing: error))
        }
    }

    /// Closes the session. What is on the phone stays; the local sync
    /// database stays too, so signing back in resumes rather than resends.
    func stop() async {
        starting?.cancel()
        starting = nil
        debounce?.cancel()
        running?.cancel()
        let closing = session
        session = nil
        mirror = nil
        profile = nil
        askHistory = nil
        uploader = nil
        services = nil
        userID = nil
        status = .off
        await closing?.close()
    }

    // MARK: Passes

    /// One full pass: mirror the stores, push and pull records, the profile,
    /// then Health. Joins a pass already running.
    func syncNow() async {
        if let running { return await running.value }
        guard session != nil else { return }
        let task = Task { await pass() }
        running = task
        await task.value
        running = nil
    }

    /// A pass started by the system in the background. True when it ran to
    /// the end.
    func backgroundPass() async -> Bool {
        if session == nil, starting == nil { accountDidSignIn() }
        await starting?.value
        guard session != nil else { return false }
        await syncNow()
        if case .failed = status { return false }
        return !Task.isCancelled
    }

    private func pass() async {
        guard let session, let mirror else { return }
        status = .syncing
        var problem: String?
        do {
            try await mirrorStores(mirror)
        } catch {
            problem = "records: \(error)"
        }
        let report = await session.syncNow()
        if let stop = report.records.stoppedBy, stop != .offline { problem = problem ?? "sync: \(stop)" }
        do {
            try await syncProfile()
        } catch {
            problem = problem ?? "profile: \(error)"
        }
        if let problemWithAsk = await syncAskHistory() { problem = problem ?? problemWithAsk }
        if let uploader, await healthWasAnswered() {
            let health = await uploader.run()
            lastHealthReport = health
            if let stop = health.stoppedBy {
                switch stop {
                case .offline, .backingOff, .sourceUnavailable, .cancelled: break
                default: problem = problem ?? "health: \(stop)"
                }
            }
        }
        status = problem.map { .failed($0) } ?? .idle(lastSync: Date())
    }

    private func mirrorStores(_ mirror: CloudMirror) async throws {
        guard let userID else { return }
        let id = userID.rawValue
        let calendar = Calendar.current
        let journal = self.journal ?? JournalStore()
        let track = TrackLogStore.shared
        let mind = MindStore.shared

        try await mirror.mirror(CloudSnapshots.journal(journal.days, userID: id))
        try await mirror.mirror(CloudSnapshots.checkIns(CheckInStore.shared.days, userID: id))
        try await mirror.mirror(CloudSnapshots.moods(mind: mind.moods, track: track.moods))
        try await mirror.mirror(CloudSnapshots.mindCheckIns(mind.checkIns))
        try await mirror.mirror(CloudSnapshots.track(CloudSnapshots.TrackInput(
            drinks: track.drinks, meals: track.meals, supplements: track.supplements, doses: track.doses,
            fasts: track.fasts, practices: track.practices, measures: track.measures, wakeRatings: track.wakeRatings
        ), userID: id, calendar: calendar))
        try await mirror.mirror(CloudSnapshots.labs(BloodPanelStore.shared.panels, calendar: calendar))
        if let scores = health?.scores {
            try await mirror.mirror(CloudSnapshots.scores(scores, today: Date(), userID: id, calendar: calendar))
        }
        try await mirror.mirror(CloudSnapshots.inbox(SomaNotifications.shared.inbox, userID: id))
        let providers = ProviderConnections.shared
        try await mirror.mirror(CloudSnapshots.providers(providers.states, connectedAt: providers.connectionDates(), userID: id))
    }

    /// Ask's conversations, both ways, on their own: the history drawer's
    /// pull to refresh runs this rather than a whole pass. Nil when it went
    /// through or stopped for want of a network, the problem otherwise.
    @discardableResult
    func syncAskHistory() async -> String? {
        guard let askHistory else { return nil }
        do {
            try await askHistory.run()
            return nil
        } catch {
            switch SupabaseServices.remoteError(error) {
            case .offline, .timeout, .transient, .cancelled: return nil
            default: return "ask history: \(error)"
            }
        }
    }

    private func syncProfile() async throws {
        guard let profile else { return }
        let store = SomaProfileStore.shared
        let restored = try await profile.restore(hasPhoto: store.photo != nil)
        if let row = restored.fields { fillGaps(from: row) }
        if let photo = restored.photo, store.photo == nil { _ = store.setPhoto(photo) }
        try await profile.push(profile: store.profile, photo: store.photo)
        try await profile.registerDevice()
    }

    /// Fills only what this phone does not know yet.
    private func fillGaps(from row: ProfileRow) {
        SomaProfileStore.shared.update { local in
            if local.firstName == nil, let name = row.firstName { local.name = name }
            if local.birthday == nil, let day = row.birthDate { local.birthday = CloudSnapshots.date(fromDayKey: day, calendar: .current) }
            if local.sex == nil, let sex = row.sex { local.sex = BiologicalSex(rawValue: sex) }
            if local.focus.isEmpty { local.focus = row.focus.compactMap(FocusArea.init(rawValue:)) }
            if local.chronotype == nil { local.chronotype = row.chronotype }
            if local.onboardedAt == nil { local.onboardedAt = row.onboardedAt }
        }
    }

    /// Whether the one Health sheet has been answered. The upload never
    /// asks: until the person met that sheet, Health is not read.
    private func healthWasAnswered() async -> Bool {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            let status = try await HKHealthStore().statusForAuthorizationRequest(toShare: HealthAccess.shareTypes(), read: HealthAccess.readTypes())
            return status == .unnecessary
        } catch {
            return false
        }
#else
        return false
#endif
    }

    // MARK: Store changes

    /// Watches the stores and runs a pass a few seconds after the last change.
    private func observeStores() {
        guard session != nil else { return }
        withObservationTracking {
            _ = journal?.days
            _ = CheckInStore.shared.days
            _ = MindStore.shared.moods
            _ = MindStore.shared.checkIns
            let track = TrackLogStore.shared
            _ = (track.drinks, track.meals, track.supplements, track.doses, track.fasts, track.practices, track.moods, track.measures, track.wakeRatings)
            _ = BloodPanelStore.shared.panels
            _ = SomaNotifications.shared.inbox
            _ = ProviderConnections.shared.states
            _ = SomaProfileStore.shared.profile
            _ = SomaProfileStore.shared.photo
            _ = AskHistoryStore.shared.conversations
            _ = AskHistoryStore.shared.pendingDeletes
            _ = health?.scores
        } onChange: {
            Task { @MainActor in CloudSync.shared.storeChanged() }
        }
    }

    private func storeChanged() {
        observeStores()
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    // MARK: Files

    /// Uploads a data file (an "Export my data" archive, an NDJSON batch) to
    /// the private `health-uploads` bucket under the person's folder, and
    /// returns its path there. JSON, CSV, ZIP, NDJSON or gzip, up to 200 MB.
    func uploadDataFile(_ file: URL, folder: String = "exports", name: String? = nil) async throws -> String {
        guard let userID, let services else { throw AuthError.signedOut }
        let fileName = name ?? file.lastPathComponent
        let path = StoragePath.healthUpload(userID: userID, folder: folder, name: fileName)
        try await services.upload(file: file, bucket: StoragePath.healthUploadsBucket, path: path, contentType: Self.contentType(for: fileName))
        return path
    }

    nonisolated static func contentType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "json": "application/json"
        case "csv": "text/csv"
        case "zip": "application/zip"
        case "ndjson", "jsonl": "application/x-ndjson"
        case "gz": "application/gzip"
        default: "application/octet-stream"
        }
    }
}
