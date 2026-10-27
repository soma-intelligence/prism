//
//  LongevityCache.swift
//  Prism
//

import Foundation
import Observation
import HealthExportCore
import HealthScoring
import SomaUI

/// What the Body lens draws, read in one go: the three numbers, every tile
/// and row, and the muscle map.
struct LongevityBodyState: Equatable, Codable {
    var overview: BodyOverview
    var markers: [BodyBiomarkerSpec: BodyBiomarker]
    var muscles: [SomaMuscle: SomaMuscleState]

    private enum CodingKeys: String, CodingKey { case overview, markers, muscles }

    init(overview: BodyOverview, markers: [BodyBiomarkerSpec: BodyBiomarker], muscles: [SomaMuscle: SomaMuscleState]) {
        self.overview = overview
        self.markers = markers
        self.muscles = muscles
    }

    // The muscle map's states live in the design system, which does not make
    // them Codable: they are kept by name.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decode(BodyOverview.self, forKey: .overview)
        markers = try container.decode([BodyBiomarkerSpec: BodyBiomarker].self, forKey: .markers)
        let names = try container.decode([String: String].self, forKey: .muscles)
        var muscles: [SomaMuscle: SomaMuscleState] = [:]
        for (muscle, state) in names {
            guard let muscle = SomaMuscle(rawValue: muscle), let state = Self.state(named: state) else { continue }
            muscles[muscle] = state
        }
        self.muscles = muscles
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overview, forKey: .overview)
        try container.encode(markers, forKey: .markers)
        var names: [String: String] = [:]
        for (muscle, state) in muscles { names[muscle.rawValue] = Self.name(of: state) }
        try container.encode(names, forKey: .muscles)
    }

    private static func name(of state: SomaMuscleState) -> String {
        switch state {
        case .recovered: "recovered"
        case .fatigued: "fatigued"
        case .depleted: "depleted"
        case .none: "none"
        }
    }

    private static func state(named name: String) -> SomaMuscleState? {
        switch name {
        case "recovered": .recovered
        case "fatigued": .fatigued
        case "depleted": .depleted
        case "none": SomaMuscleState.none
        default: nil
        }
    }

    /// Every reading empty: what the lens draws before anything is known.
    static func empty(now: Date, calendar: Calendar) -> LongevityBodyState {
        var markers: [BodyBiomarkerSpec: BodyBiomarker] = [:]
        for spec in BodyBiomarkerSpec.allCases {
            markers[spec] = BodyBiomarkers.make(spec, readings: [], now: now, calendar: calendar)
        }
        return LongevityBodyState(
            overview: BodyOverview.make(from: BodyOverviewInputs(now: now), calendar: calendar),
            markers: markers,
            muscles: MuscleFreshness.map([:])
        )
    }
}

/// What the Mind lens is worked out from. Kept in memory only: the scores and
/// the Journal it is read against change under it, so the lens works its
/// model out again on every draw, as it always has.
struct LongevityMindParts {
    var inputs: MindInputs
    var stress: [MindStressDay]
    var today: ScoreDetailInputs?
    var moods: [MindMoodEntry]

    /// What Pulse's stress page and the lens's day line share.
    static let todayParts: Set<ScoreDetailInputs.Part> = [.heart, .today, .nights]

    static func empty(now: Date) -> LongevityMindParts {
        LongevityMindParts(inputs: MindInputs(now: now), stress: [], today: nil, moods: [])
    }

    func model(scores: SomaScores?, moods: [MindMoodEntry]? = nil, journal: JournalStore?, calendar: Calendar) -> MindLensModel {
        let inner = MindInnerSpace.make(from: inputs, scores: scores, calendar: calendar)
        return MindLensModel.make(
            inner: inner,
            stress: today.map { ScorePages.stress(scores, $0, calendar: calendar) },
            heatmap: MindHeatmap.make(stress, calendar: calendar),
            moods: moods ?? self.moods,
            feelings: Self.feelings(journal, calendar: calendar),
            now: inputs.now,
            calendar: calendar
        )
    }

    /// The Journal's evening feeling, by day.
    static func feelings(_ journal: JournalStore?, calendar: Calendar) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for entry in journal?.loggedDays ?? [] {
            if let feeling = entry.day.feeling { result[calendar.startOfDay(for: entry.date)] = feeling }
        }
        return result
    }
}

/// What the Longevity lenses showed last time, kept on the device so the
/// next launch opens the tab full rather than empty and filling.
///
/// The owner asked for the Longevity charts to arrive "all at the same time,
/// already preloaded, with a cache" (2026-10-24), as Pulse already does with
/// ``HealthSnapshot``.
struct LongevitySnapshot: Equatable, Codable {
    /// Bumped when a cached type changes shape; an older file is dropped.
    static let version = 1

    var version = Self.version
    var savedAt: Date
    var body: LongevityBodyState?
    /// The Mind lens as it was last drawn.
    var mind: MindLensModel?
    var environment: EnvironmentReport?
    /// The weather where you were, laid into the Environment lens.
    var outside: EnvironmentConditions?
}

/// Reads and writes the one Longevity file, the same way
/// ``HealthSnapshotStore`` keeps Pulse's: Application Support, the system's
/// default data protection, an atomic write, and every failure (a missing
/// file, an older shape, a corrupt write) read as no snapshot, never a crash.
nonisolated struct LongevitySnapshotStore: Sendable {
    let url: URL

    /// The app's own file, beside Pulse's.
    static let shared = LongevitySnapshotStore(
        url: HealthSnapshotStore.shared.url.deletingLastPathComponent().appendingPathComponent("longevity-snapshot.json")
    )

    /// How old a snapshot may be and still be shown.
    static let maximumAge: TimeInterval = HealthSnapshotStore.maximumAge

    /// The snapshot, trimmed to what still holds at `now`. On another day
    /// Mind and Environment go, since both are drawn round today (today's
    /// stress line, today's daylight), and so does the Body lens's step
    /// count, which is a day's total: a yesterday shown as today is wrong.
    /// The long readings stay, and the first read of the day replaces them.
    @MainActor
    func load(now: Date = Date(), calendar: Calendar = .current) -> LongevitySnapshot? {
        guard let data = try? Data(contentsOf: url),
              var snapshot = try? JSONDecoder().decode(LongevitySnapshot.self, from: data),
              snapshot.version == LongevitySnapshot.version,
              snapshot.savedAt <= now.addingTimeInterval(60),
              now.timeIntervalSince(snapshot.savedAt) < Self.maximumAge
        else { return nil }
        if !calendar.isDate(snapshot.savedAt, inSameDayAs: now) {
            snapshot.mind = nil
            snapshot.environment = nil
            snapshot.outside = nil
            for spec in BodyBiomarkerSpec.allCases where spec.sumsPerDay {
                snapshot.body?.markers[spec] = BodyBiomarkers.make(spec, readings: [], now: now, calendar: calendar)
            }
        }
        return snapshot
    }

    @MainActor
    func save(_ snapshot: LongevitySnapshot) throws {
        try write(try JSONEncoder().encode(snapshot))
    }

    /// Writes encoded bytes atomically, so a crash mid-write leaves the old
    /// file whole rather than half of a new one.
    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    /// Removes the file, for a reset or an account deletion.
    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Drops the Mind lens from the file and keeps the rest, for when Mind's
    /// own record is erased.
    func clearMind() {
        guard let data = try? Data(contentsOf: url),
              var snapshot = try? JSONDecoder().decode(LongevitySnapshot.self, from: data),
              snapshot.mind != nil
        else { return }
        snapshot.mind = nil
        if let encoded = try? JSONEncoder().encode(snapshot) { try? write(encoded) }
    }
}

/// The last read of each Longevity lens, shared by the lenses and the
/// launch preload.
///
/// A lens draws what is here at once, from this launch's read or the last
/// launch's file, and its read lands as one write per lens, so every tile and
/// chart of a lens changes in the same transaction rather than one by one.
/// A read already running (the preload, say) is joined, never started twice.
@MainActor
@Observable
final class LongevityCache {
    static let shared = LongevityCache()

    enum Lens: Hashable, CaseIterable { case body, mind, environment }

    /// How long a read stands before a visit reads again, as the score
    /// pages keep theirs (``ScoreInputsCache/freshFor``).
    static let freshFor: TimeInterval = 5 * 60

    private(set) var body: LongevityBodyState?
    /// The Mind lens as last drawn: what a launch shows before this launch's
    /// read lands in ``mindParts``.
    private(set) var mind: MindLensModel?
    private(set) var mindParts: LongevityMindParts?
    private(set) var environment: EnvironmentReport?
    private(set) var outside: EnvironmentConditions?
    /// When the file the lenses opened on was written, while nothing of this
    /// launch has replaced it.
    private(set) var cachedAt: Date?

    @ObservationIgnored private var readAt: [Lens: Date] = [:]
    @ObservationIgnored private var running: [Lens: Task<Void, Never>] = [:]
    @ObservationIgnored private var store: LongevitySnapshotStore?
    @ObservationIgnored private var hasPreloaded = false
    /// The last write handed off the main actor; the next one waits for it.
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    init(store: LongevitySnapshotStore? = nil, now: Date = Date(), calendar: Calendar = .current) {
        attach(store, now: now, calendar: calendar)
    }

    /// Where the lenses are kept between launches, and what it held. Read
    /// synchronously: the file is small, and a lens that draws before it
    /// would show the very emptiness it is here to stop.
    func attach(_ store: LongevitySnapshotStore?, now: Date = Date(), calendar: Calendar = .current) {
        self.store = store
        guard let snapshot = store?.load(now: now, calendar: calendar) else { return }
        body = snapshot.body
        mind = snapshot.mind
        environment = snapshot.environment
        outside = snapshot.outside
        cachedAt = snapshot.savedAt
    }

    func isFresh(_ lens: Lens, now: Date = Date()) -> Bool {
        guard let read = readAt[lens] else { return false }
        return now.timeIntervalSince(read) < Self.freshFor
    }

    /// Forgets every lens, here and on disk: an account deletion.
    func clear() {
        for task in running.values { task.cancel() }
        running = [:]
        readAt = [:]
        body = nil
        mind = nil
        mindParts = nil
        environment = nil
        outside = nil
        cachedAt = nil
        hasPreloaded = false
        store?.clear()
    }

    // MARK: - Writes, one per lens

    func setBody(_ state: LongevityBodyState, now: Date = Date()) {
        if state != body { body = state }
        readAt[.body] = now
        persist(now: now)
    }

    func setMind(_ parts: LongevityMindParts, model: MindLensModel, now: Date = Date()) {
        mindParts = parts
        if model != mind { mind = model }
        readAt[.mind] = now
        persist(now: now)
    }

    func setEnvironment(_ report: EnvironmentReport, now: Date = Date()) {
        var report = report
        report.outside = nil
        if report != environment { environment = report }
        readAt[.environment] = now
        persist(now: now)
    }

    func setOutside(_ conditions: EnvironmentConditions?, now: Date = Date()) {
        guard conditions != outside else { return }
        outside = conditions
        persist(now: now)
    }

    /// Writes what the lenses show for the next launch: encoded here, written
    /// off the main actor, one write after the other. Two detached writes
    /// could land in either order, and an older snapshot written last would
    /// put back a lens the file had already lost.
    private func persist(now: Date) {
        if readAt.count == Lens.allCases.count { cachedAt = nil }
        guard let store else { return }
        let snapshot = LongevitySnapshot(savedAt: now, body: body, mind: mind, environment: environment, outside: outside)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let previous = lastWrite
        lastWrite = Task.detached(priority: .utility) {
            await previous?.value
            try? store.write(data)
        }
    }

    // MARK: - Reads

    /// Runs `read` for `lens` unless a read of it is fresh, joining one
    /// already running.
    private func run(_ lens: Lens, force: Bool, _ read: @escaping @MainActor () async -> Void) async {
        if let task = running[lens] {
            await task.value
            if !force { return }
        }
        if !force, isFresh(lens) { return }
        let task = Task { await read() }
        running[lens] = task
        await task.value
        if running[lens] == task { running[lens] = nil }
    }

    func loadBody(_ health: HealthDashboard, force: Bool = false) async {
        await run(.body, force: force) { [weak self] in
            guard let state = await LongevityLoad.body(health) else { return }
            self?.setBody(state)
        }
    }

    func loadMind(_ health: HealthDashboard, journal: JournalStore?, force: Bool = false) async {
        await run(.mind, force: force) { [weak self] in
            let parts = await LongevityLoad.mind(health)
            let model = parts.model(scores: health.scores, journal: journal, calendar: .current)
            self?.setMind(parts, model: model)
        }
    }

    func loadEnvironment(_ health: HealthDashboard, force: Bool = false) async {
        await run(.environment, force: force) { [weak self] in
            guard let report = await LongevityLoad.environment(health) else { return }
            self?.setEnvironment(report)
        }
    }

    /// Reads every lens once, after Pulse's first read, so the first visit
    /// to Longevity opens full even with no file from a last launch. One
    /// lens after another, at low priority: Today has the reader first.
    func preload(_ health: HealthDashboard, journal: JournalStore?) async {
        guard !hasPreloaded else { return }
        hasPreloaded = true
        // Each lens's arithmetic runs on the main actor: a yield between
        // them hands the main thread back, so a tap made while the preload
        // runs gets its transition's frames rather than waiting behind it.
        await loadBody(health)
        await Task.yield()
        await loadMind(health, journal: journal)
        await Task.yield()
        await loadEnvironment(health)
        await Task.yield()
        await LongevityLoad.environmentExtras(health, into: self)
    }
}

/// The reads behind each lens, each finished before anything is written.
@MainActor
enum LongevityLoad {
    /// The overview, every biomarker (a year for the sparse ones) and the
    /// muscle map. Nil without Health, so the lens keeps what it shows.
    static func body(_ health: HealthDashboard, now: Date = Date(), calendar: Calendar = .current) async -> LongevityBodyState? {
        let metrics = BodyOverviewInputs.metrics + BodyBiomarkers.metrics + FitnessHistory.metrics
        guard let source = await health.prepare(metrics) else { return nil }
        async let overviewRead = BodyOverviewInputs.read(from: source, now: now, calendar: calendar)
        async let readingsRead = BodyBiomarkers.read(from: source, now: now, calendar: calendar)
        async let historyRead = FitnessHistory.read(from: source, days: Int(MuscleFreshness.days), now: now, calendar: calendar)

        var overview = await overviewRead
        let profile = SomaProfileStore.shared.profile
        // The profile's answer first; "other" stays unknown rather than
        // falling back to Health.
        overview.sex = BodyFitnessAge.Sex(profile.sex.map { LabSex($0) } ?? LabHealth.biologicalSex())
        if overview.age == nil { overview.age = profile.age(on: now, calendar: calendar) }

        let all = await readingsRead
        var built: [BodyBiomarkerSpec: BodyBiomarker] = [:]
        for spec in BodyBiomarkerSpec.allCases {
            built[spec] = BodyBiomarkers.make(spec, readings: all[spec] ?? [], now: now, calendar: calendar)
            // One marker at a time on the main actor, never all of them in
            // one block, so a frame can be drawn between two of them.
            await Task.yield()
        }
        let markers = await BodyBiomarkers.filledSparse(built, from: source, now: now, calendar: calendar)
        let history = await historyRead
        return LongevityBodyState(
            overview: BodyOverview.make(from: overview, calendar: calendar),
            markers: markers,
            muscles: MuscleFreshness.map(MuscleFreshness.states(history.workouts, now: now))
        )
    }

    /// Sixty days of readings, today's stress line, sixty days of stress and
    /// the moods, with the scores they are read against.
    static func mind(_ health: HealthDashboard, now: Date = Date(), calendar: Calendar = .current) async -> LongevityMindParts {
        let parts = LongevityMindParts.todayParts
        let moodStart = calendar.date(byAdding: .day, value: -MindLensModel.moodDays, to: calendar.startOfDay(for: now)) ?? now
        async let scoresRead: Void = health.loadScores()
        async let moodsRead = MindJourneyLoad.moods(since: moodStart, store: .shared)
        let inputs = await MindLoad.inputs(health, now: now, calendar: calendar)
        var today = ScoreInputsCache.shared.value(for: parts)
        if !ScoreInputsCache.shared.isFresh(parts),
           let source = await health.prepare(ScoreDetailInputs.metrics(for: parts)) {
            let read = await ScoreDetailInputs.read(parts, from: source, now: now, calendar: calendar)
            today = read
            ScoreInputsCache.shared.store(read, for: parts)
        }
        let stress = await MindLoad.stress(health, inputs: inputs, calendar: calendar)
        await scoresRead
        return LongevityMindParts(inputs: inputs, stress: stress, today: today, moods: await moodsRead)
    }

    /// A year of daylight, thirty days of UV and sound. Nil without Health.
    static func environment(_ health: HealthDashboard, now: Date = Date(), calendar: Calendar = .current) async -> EnvironmentReport? {
#if DEBUG
        if EnvironmentReport.usesPreview { return EnvironmentReport.preview }
#endif
        guard let source = await health.prepare(EnvironmentInputs.metrics) else { return nil }
        let inputs = await EnvironmentInputs.read(from: source, now: now, calendar: calendar, wholeYear: true)
        return EnvironmentReport.make(from: inputs, calendar: calendar)
    }

    /// What the Environment lens lays over the report: the weather where you
    /// are and last night's sleep inputs for the bedroom card. Only for the
    /// preload: the lens reads both itself when it opens.
    static func environmentExtras(_ health: HealthDashboard, into cache: LongevityCache) async {
        let parts: Set<ScoreDetailInputs.Part> = [.nights, .sound]
        if !ScoreInputsCache.shared.isFresh(parts), let source = await health.prepare(ScoreDetailInputs.metrics(for: parts)) {
            ScoreInputsCache.shared.store(await ScoreDetailInputs.read(parts, from: source, now: Date(), calendar: .current), for: parts)
        }
        let location = EnvironmentLocation.shared
        await location.refresh()
        guard let place = location.place,
              let conditions = await EnvironmentWeatherClient.shared.conditions(latitude: place.latitude, longitude: place.longitude)
        else { return }
        cache.setOutside(conditions)
    }
}
