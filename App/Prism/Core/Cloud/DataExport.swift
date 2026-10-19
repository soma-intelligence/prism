//
//  DataExport.swift
//  Prism
//

import Foundation
import HealthExportCore
import SyncSupabase

/// "Export my data": one ZIP of everything Soma holds about the person on
/// this phone, made locally, handed to the share sheet, and uploaded to the
/// private `health-uploads` bucket when they ask.
///
/// Inside the archive:
///
/// - `README.txt`: what each file is.
/// - `profile.json` and `profile.jpg` (the photo, when there is one).
/// - One JSON file per table, in the same shape the cloud stores it:
///   `journal_days.json`, `check_in_answers.json`, `mood_logs.json`,
///   `mind_check_ins.json`, `track_logs.json`, `lab_results.json`,
///   `scores_daily.json`, `notification_inbox.json`, `provider_connections.json`,
///   and `ask_conversations.json` (each conversation with its messages).
/// - `health/<HealthKit identifier>.ndjson`: every Apple Health sample the app
///   may read, one JSON object a line, with its provenance.
///
/// The Settings row calls ``run(upload:)`` and offers the returned file with
/// `ShareLink(item:)`.
@MainActor
enum DataExport {
    struct Result: Sendable {
        /// The archive, in the temporary directory. The share sheet reads it.
        var file: URL
        /// Its path in `health-uploads` when it was uploaded.
        var uploadedPath: String?
    }

    /// Builds the archive, and uploads it to
    /// `health-uploads/<uid>/exports/<date>.zip` when `upload` is true and
    /// someone is signed in.
    static func run(upload: Bool = false, health: (any HealthSampleSource)? = nil, now: Date = Date()) async throws -> Result {
        let day = CloudSnapshots.dayKey(now, calendar: .current)
        let file = FileManager.default.temporaryDirectory.appending(path: "soma-export-\(day).zip")
        try? FileManager.default.removeItem(at: file)
        let zip = try ZipWriter(url: file, modified: now)
        try await write(into: zip, health: health ?? HealthDashboard.launchSource(), now: now)
        try zip.finish()

        var uploaded: String?
        if upload, AccountSession.shared.isSignedIn {
            uploaded = try await CloudSync.shared.uploadDataFile(file, folder: "exports", name: "\(day).zip")
        }
        return Result(file: file, uploadedPath: uploaded)
    }

    static func write(into zip: ZipWriter, health: any HealthSampleSource, now: Date) async throws {
        let user = AccountSession.shared.state.user?.id ?? "local"
        let calendar = Calendar.current
        let encoder = SupabaseServices.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        try zip.add("README.txt", data: Data(readme(now: now).utf8))

        let store = SomaProfileStore.shared
        try zip.add("profile.json", data: encoder.encode(ProfileRow.make(userID: user, profile: store.profile, avatarPath: nil, calendar: calendar)))
        if let photo = store.photo { try zip.add("profile.jpg", data: photo) }

        let track = TrackLogStore.shared
        let mind = MindStore.shared
        try zip.add("journal_days.json", data: encoder.encode(CloudSnapshots.journal(JournalStore().days, userID: user)))
        try zip.add("check_in_answers.json", data: encoder.encode(CloudSnapshots.checkIns(CheckInStore.shared.days, userID: user)))
        try zip.add("mood_logs.json", data: encoder.encode(CloudSnapshots.moods(mind: mind.moods, track: track.moods)))
        try zip.add("mind_check_ins.json", data: encoder.encode(CloudSnapshots.mindCheckIns(mind.checkIns)))
        try zip.add("track_logs.json", data: encoder.encode(CloudSnapshots.track(CloudSnapshots.TrackInput(
            drinks: track.drinks, meals: track.meals, supplements: track.supplements, doses: track.doses,
            fasts: track.fasts, practices: track.practices, measures: track.measures, wakeRatings: track.wakeRatings
        ), userID: user, calendar: calendar)))
        try zip.add("lab_results.json", data: encoder.encode(CloudSnapshots.labs(BloodPanelStore.shared.panels, calendar: calendar)))
        try zip.add("notification_inbox.json", data: encoder.encode(CloudSnapshots.inbox(SomaNotifications.shared.inbox, userID: user)))
        try zip.add("provider_connections.json", data: encoder.encode(CloudSnapshots.providers(ProviderConnections.shared.states, userID: user)))
        try zip.add("ask_conversations.json", data: encoder.encode(AskHistoryStore.shared.snapshot().map(AskExportedConversation.init)))

        if let anchored = health as? any HealthAnchoredSampleSource, health.isAvailable {
            try await writeHealth(anchored, into: zip)
        }
    }

    /// Every readable sample metric, one NDJSON file each, read from the start
    /// of the store in pages so memory holds one metric at a time.
    static func writeHealth(_ source: any HealthAnchoredSampleSource, into zip: ZipWriter) async throws {
        let line = JSONEncoder()
        line.dateEncodingStrategy = .iso8601
        line.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for metric in HealthMetricCatalog.all where metric.kind != .correlation && metric.kind != .characteristic {
            try Task.checkCancellation()
            var anchor: Data?
            var lines = Data()
            while true {
                let page: HealthSampleChanges
                do {
                    page = try await source.changes(metric, after: anchor, limit: 5000)
                } catch {
                    break
                }
                for record in page.added {
                    lines.append(try line.encode(ExportedSample(record)))
                    lines.append(0x0A)
                }
                anchor = page.anchor
                if !page.hasMore { break }
            }
            if !lines.isEmpty { try zip.add("health/\(metric.identifier).ndjson", data: lines) }
        }
    }

    nonisolated struct ExportedSample: Encodable {
        var uuid: String
        var metric: String
        var value: Double
        var unit: String
        var start: Date
        var end: Date
        var source: String?
        var sourceBundle: String?
        var device: String?
        var deviceModel: String?
        var wasUserEntered: Bool

        init(_ record: HealthSampleRecord) {
            let reading = record.reading
            uuid = record.uuid.uuidString.lowercased()
            metric = reading.metric
            value = reading.value
            unit = reading.unit.rawValue
            start = reading.start
            end = reading.end
            source = reading.source
            sourceBundle = reading.sourceBundle
            device = reading.device
            deviceModel = reading.deviceModel
            wasUserEntered = reading.wasUserEntered
        }

        enum CodingKeys: String, CodingKey {
            case uuid, metric, value, unit, start, end, source, device
            case sourceBundle = "source_bundle"
            case deviceModel = "device_model"
            case wasUserEntered = "was_user_entered"
        }
    }

    static func readme(now: Date) -> String {
        """
        Soma data export, \(SupabaseServices.timestamp(now))

        profile.json            what you told Soma about yourself
        profile.jpg             your profile photo, when you set one
        journal_days.json       your Journal: yes and no answers, and how you felt
        check_in_answers.json   your answers to Soma asks
        mood_logs.json          moods and emotions (valence -1 to 1)
        mind_check_ins.json     energy, mood and focus check-ins
        track_logs.json         drinks, meals, supplements, doses, fasts, practices, measures
        lab_results.json        blood panels and their markers
        notification_inbox.json what Soma sent you
        provider_connections.json which outside services you linked (never a password or token)
        ask_conversations.json  your conversations with Soma, each with its messages
        health/*.ndjson         Apple Health samples, one per line, by HealthKit type

        Dates are ISO 8601. Days are yyyy-MM-dd in your calendar.
        """
    }
}

/// One conversation in the export: its row and its messages, as the account
/// stores them.
nonisolated struct AskExportedConversation: Encodable, Sendable {
    var conversation: AskConversationRow
    var messages: [AskMessageRow]

    init(_ snapshot: AskConversationSnapshot) {
        conversation = AskHistoryMerge.row(snapshot)
        messages = snapshot.turns.flatMap { AskHistoryMerge.messages($0, in: snapshot.id) }
    }
}
