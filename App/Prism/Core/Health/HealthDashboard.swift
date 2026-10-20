//
//  HealthDashboard.swift
//  Prism
//

import Foundation
import Observation
import HealthExportCore
import HealthExportHealthKit
import HealthScoring
#if os(iOS)
import UIKit
#endif

/// What the pages read from.
///
/// One request, one load, one dictionary of readings keyed by HealthKit
/// identifier. The source is injected, so a preview or a test drives the same
/// pages from a fixture without a Health store.
@MainActor
@Observable
final class HealthDashboard {
    enum Status: Equatable {
        /// Nothing asked for yet.
        case idle
        case loading
        case ready
        /// No Health store on this device: a Mac, or a locked-down config.
        case unavailable
        /// The request or a read threw. The message is shown as-is rather than
        /// swallowed: a silent empty dashboard is indistinguishable from a bug.
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var readings: [String: HealthReading] = [:]
    private(set) var durations: [String: TimeInterval] = [:]
    /// Progress of a full catalog read, or nil when none has been asked for.
    private(set) var scan: HealthFullScan?
    /// The Pulse tab's Today page, worked out from the store. Nil until the
    /// first read.
    private(set) var today: PulseToday?
    /// When `today` was read, so a tab switch does not read it all again.
    private var todayReadAt: Date?
    /// Soma's 0 to 100 scores, worked out from ninety days of the store. Nil
    /// until the first read.
    private(set) var scores: SomaScores?
    /// When `scores` was read, under the same one-minute rule as `today`.
    private var scoresReadAt: Date?
    /// The read in flight, so the pages that appear together share one.
    private var scoresTask: Task<Void, Never>?
    /// When `loadLatest` or `load` last ran to the end, so the widgets can
    /// tell a reading that came back nil from one never read.
    @ObservationIgnored private var readingsReadAt: Date?
    /// When `load` last read every displayed metric, so `start` can keep a
    /// read under a minute old.
    @ObservationIgnored private var displayedReadAt: Date?

    /// Whether the scores were read in this process.
    var hasReadScores: Bool { scoresReadAt != nil }

    /// Whether the latest readings were read in this process.
    var hasReadReadings: Bool { readingsReadAt != nil }

    /// Whether Health can be read now. A locked iPhone closes the store, and
    /// a read then comes back empty: it must not replace what was read.
    static var isProtectedDataAvailable: Bool {
        #if os(iOS)
        UIApplication.shared.isProtectedDataAvailable
        #else
        true
        #endif
    }

    private let source: any HealthSampleSource
    private let calendar: Calendar

    /// The iPhone's own steps and movement, from Core Motion. Asked for in the
    /// same moment as Health, and merged into the day's counts below.
    let motion: PhoneMotion

    /// Health's own walking and running distance since midnight, before the
    /// phone's live count is weighed against it. See ``todayDistance``.
    private(set) var healthDistanceToday: HealthReading?

    /// Identifiers already put to the person, so a surface that opens twice
    /// does not ask twice. Empty again on the next launch, and that is right:
    /// Health keeps the durable record, this only spares the repeats inside a
    /// run. See ``request(_:)``.
    private var asked: Set<String> = []

    /// Requests in flight, keyed by the set they name. Two pages appearing
    /// together share one, rather than the second queueing behind the first
    /// and arriving after the answer.
    private var inFlight: [Set<String>: Task<Void, Error>] = [:]

    init(
        source: any HealthSampleSource = HealthKitSampleSource(),
        calendar: Calendar = .current,
        motion: PhoneMotion? = nil
    ) {
        self.source = source
        self.calendar = calendar
        self.motion = motion ?? PhoneMotion(calendar: calendar)
    }

    /// Metrics the dashboard pages actually show.
    ///
    /// The catalog holds all 192; asking for the whole of it at launch would put
    /// a permission sheet the length of an arm in front of someone who has seen
    /// three cards. These are what the pages read today. The last three are the
    /// Today page's: heart rate for last night's low, the stress peaks and the
    /// zones of a workout; the workouts themselves; and the date of birth, for
    /// those zones and for the age a fitness age is read against.
    static let displayed: [HealthMetric] = [
        "HKQuantityTypeIdentifierStepCount",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKQuantityTypeIdentifierAppleExerciseTime",
        "HKQuantityTypeIdentifierRestingHeartRate",
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKQuantityTypeIdentifierBodyMass",
        "HKQuantityTypeIdentifierVO2Max",
        "HKCategoryTypeIdentifierSleepAnalysis",
        "HKCategoryTypeIdentifierMindfulSession",
        "HKQuantityTypeIdentifierHeartRate",
        "HKWorkoutTypeIdentifier",
        "HKCharacteristicTypeIdentifierDateOfBirth",
    ].compactMap(HealthMetricCatalog.metric(for:))

    var isAvailable: Bool { source.isAvailable }

    /// The source, for the full scan in `HealthFullScan.swift`.
    var reader: any HealthSampleSource { source }

    // MARK: - State, written only here

    func setStatus(_ new: Status) { status = new }

    func setScan(_ new: HealthFullScan?) { scan = new }

    /// Everything the platform will let the app ask to read.
    ///
    /// `readable`, never `all`: naming a correlation in a read request raises
    /// NSInvalidArgumentException and terminates the app.
    func requestAuthorizationForWholeCatalog() async throws {
        try await request(HealthMetricCatalog.readable)
    }

    /// Asks for read access, once per set of metrics.
    ///
    /// Every path that needs permission goes through here. The pages call
    /// ``start()`` from `.task`, which runs again on every tab switch, and a
    /// category page calls ``loadLatest(_:)`` each time it opens: without this
    /// the app hands the same request back to Health on every appearance.
    ///
    /// A set that has already been answered returns immediately. On the real
    /// store the first request asks for everything at once, so nothing after
    /// it brings the sheet back.
    private func request(_ metrics: [HealthMetric]) async throws {
        let askable = metrics.filter(\.isReadAuthorizable)
        let identifiers = Set(askable.map(\.identifier))
        guard !identifiers.isEmpty, !identifiers.isSubset(of: asked) else { return }

        if let existing = inFlight[identifiers] {
            return try await existing.value
        }

        // The real store gets every type in one sheet, the first time
        // anything is asked: see `HealthAccess`. A fixture or the empty
        // source still answers for just what was named.
        let asksEverything = source is HealthKitSampleSource
        let task = Task { [source, motion] in
            if asksEverything {
                try await HealthAccess.requestEverything(motion: motion)
            } else {
                try await source.requestAuthorization(for: askable)
                await motion.requestAccess()
            }
        }
        inFlight[identifiers] = task
        // Cleared whichever way it ends: a request that threw was never
        // answered, so the next surface to ask is entitled to try again.
        defer { inFlight[identifiers] = nil }

        try await task.value
        asked.formUnion(identifiers)
        if asksEverything {
            asked.formUnion(HealthMetricCatalog.readable.filter(\.isReadAuthorizable).map(\.identifier))
        }
    }

    func recordChunk(_ results: [(String, Bool)]) {
        guard var current = scan else { return }
        current.scanned += results.count
        for (identifier, hasData) in results where hasData {
            current.withData += 1
            current.found.append(identifier)
        }
        scan = current
    }

    func finishScan() {
        scan?.isRunning = false
    }

    /// Asks for read access to the displayed metrics, then loads them.
    ///
    /// The three pages call this from `.task`, so it runs again on every tab
    /// switch. Only the first time does it ask: after that the request is a
    /// no-op and what is left is the read, which is why the page is not put
    /// back through `.loading` once it is ready.
    ///
    /// A read less than a minute old is kept, as `loadToday` keeps its own:
    /// read again on every tab switch, the ten metrics, one after the other,
    /// hold the page that has just appeared behind them for the store and the
    /// main thread.
    func start() async {
        guard source.isAvailable else {
            status = .unavailable
            return
        }

        if status == .idle { status = .loading }
        do {
            try await request(Self.displayed)
        } catch {
            status = .failed(String(describing: error))
            return
        }

        if let readAt = displayedReadAt, Date().timeIntervalSince(readAt) < 60 {
            status = .ready
            return
        }
        await load()
        status = .ready
    }

    /// Re-reads everything for today. Safe to call on a pull to refresh.
    func load() async {
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        // A night's sleep starts the previous evening, so it is read over a
        // window that reaches back past midnight rather than over the day.
        let nightStart = calendar.date(byAdding: .hour, value: -18, to: now) ?? dayStart

        for metric in Self.displayed {
            switch metric.identifier {
            case "HKCategoryTypeIdentifierSleepAnalysis":
                durations[metric.identifier] = try? await source.totalDuration(
                    metric, from: nightStart, to: now, codes: HealthCategoryValue.asleep
                )

            case "HKCategoryTypeIdentifierMindfulSession":
                durations[metric.identifier] = try? await source.totalDuration(
                    metric, from: dayStart, to: now
                )

            case "HKQuantityTypeIdentifierHeartRate",
                 "HKWorkoutTypeIdentifier",
                 "HKCharacteristicTypeIdentifierDateOfBirth":
                // Read by the Today page in `loadToday()`, as samples over a
                // window rather than as one value.
                continue

            case "HKQuantityTypeIdentifierBodyMass",
                 "HKQuantityTypeIdentifierVO2Max",
                 "HKQuantityTypeIdentifierRestingHeartRate",
                 "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
                // These are measured rarely; the last known value is the answer,
                // not today's average, which is usually missing.
                readings[metric.identifier] = try? await source.latest(metric)

            default:
                readings[metric.identifier] = try? await source.summary(
                    metric, from: dayStart, to: now
                )
            }
        }

        // Read without a request of its own: on the real store the one sheet
        // already named it, and `displayed` stays what the pages show.
        if let distance = HealthMetricCatalog.metric(for: Self.distanceIdentifier) {
            healthDistanceToday = try? await source.summary(distance, from: dayStart, to: now)
        }
        readingsReadAt = now
        displayedReadAt = now
        await motion.refresh()
    }

    // MARK: - The phone and Health, merged

    static let stepsIdentifier = "HKQuantityTypeIdentifierStepCount"
    static let distanceIdentifier = "HKQuantityTypeIdentifierDistanceWalkingRunning"

    /// Steps since midnight: Health's total or the phone's live count,
    /// whichever is higher (see `MotionMerge`). Nil when neither has any.
    var todaySteps: Double? {
        MotionMerge.preferred(health: readings[Self.stepsIdentifier]?.value, phone: motion.today?.steps)
    }

    /// Walking and running distance since midnight, in metres, under the same
    /// rule as ``todaySteps``.
    var todayDistance: Double? {
        MotionMerge.preferred(health: healthDistanceToday?.value, phone: motion.today?.distance)
    }

    /// Floors climbed since midnight, as the phone's barometer counted them.
    var todayFloors: Double? { motion.today?.floorsAscended }

    /// Today's activity from the phone as timeline events: walks, runs, rides
    /// and drives, each with a start and an end, stillness left out. Empty
    /// without the Motion & Fitness permission or a step counter.
    var phoneActivity: [MotionSegment] { motion.movingSegments }

    // MARK: - Reading out

    /// A formatted value, or nil when the store holds nothing.
    ///
    /// Nil is the honest answer. It renders as a dash, which says "not measured"
    /// rather than "zero".
    func value(_ identifier: String, decimals: Int = 0) -> String? {
        guard let value = shownValue(identifier) else { return nil }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// What a page shows for a metric: the stored reading, with today's steps
    /// merged with the phone's live count.
    private func shownValue(_ identifier: String) -> Double? {
        identifier == Self.stepsIdentifier ? todaySteps : readings[identifier]?.value
    }

    /// Minutes held as a duration, rounded.
    func minutes(_ identifier: String) -> String? {
        guard let seconds = durations[identifier], seconds > 0 else { return nil }
        return (seconds / 60).rounded().formatted(.number.precision(.fractionLength(0)))
    }

    /// Hours held as a duration, to one decimal.
    func hours(_ identifier: String) -> String? {
        guard let seconds = durations[identifier], seconds > 0 else { return nil }
        return (seconds / 3600).formatted(.number.precision(.fractionLength(1)))
    }

    /// The latest reading with its unit, or a dash when the store holds none.
    ///
    /// The dash is the point: it says "not measured" where a zero would say
    /// "measured, and it was nothing".
    func rowValue(for metric: HealthMetric) -> String {
        guard let value = shownValue(metric.identifier) else { return "-" }
        let decimals = value < 10 ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(decimals)))
        guard let unit = (readings[metric.identifier]?.unit ?? metric.unit).shortLabel else { return number }
        return "\(number) \(unit)"
    }

    /// Reads what the Today page needs and works the page out.
    ///
    /// The page calls this from `.task`, which runs again on every tab switch,
    /// so a read less than a minute old is kept. A pull to refresh passes
    /// `force` and reads again.
    func loadToday(force: Bool = false) async {
        guard source.isAvailable else {
            status = .unavailable
            return
        }
        if !force, let readAt = todayReadAt, Date().timeIntervalSince(readAt) < 60 { return }

        do {
            try await request(Self.displayed)
        } catch {
            status = .failed(String(describing: error))
            return
        }

        let now = Date()
        // The scores are read alongside the page's own inputs and fed into it:
        // the row under the orb and the energy card are scores.
        async let scoresRead: Void = loadScores(force: force)
        async let motionRead: Void = motion.refresh()
        var inputs = await PulseInputs.read(from: source, now: now, calendar: calendar)
        await scoresRead
        await motionRead
        // Health lags the phone through the day: the higher count wins.
        inputs.stepsToday = MotionMerge.preferred(health: inputs.stepsToday, phone: motion.today?.steps)
        today = PulseToday.make(from: inputs, scores: scores, calendar: calendar)
        todayReadAt = now
    }

    /// Reads ninety days of the store and works out Soma's scores.
    ///
    /// Today, Trends and Longevity's Mind all call this from `.task`, so a
    /// read less than a minute old is kept, and a read already running is
    /// joined rather than started again. A pull to refresh passes `force`.
    /// Everything read is already in ``displayed``: the request adds nothing.
    ///
    /// `requestAccess: false` reads without ever asking: a background wake
    /// must not raise a sheet, so what Health has not granted reads as empty.
    func loadScores(force: Bool = false, requestAccess: Bool = true) async {
        guard source.isAvailable else {
            status = .unavailable
            return
        }
        if let running = scoresTask {
            await running.value
            return
        }
        if !force, let readAt = scoresReadAt, Date().timeIntervalSince(readAt) < 60 { return }
        // A locked read finds nothing and would wipe the scores on screen.
        guard Self.isProtectedDataAvailable else { return }

        if requestAccess {
            do {
                try await request(Self.displayed)
            } catch {
                status = .failed(String(describing: error))
                return
            }
        }

        let task = Task { [source, calendar] in
            let now = Date()
            let inputs = await SomaScoresReader.read(from: source, now: now, calendar: calendar)
            let computed = await Self.compute(inputs)
            self.scores = computed
            self.scoresReadAt = now
        }
        scoresTask = task
        await task.value
        scoresTask = nil
    }

    /// The engine's arithmetic, off the main actor.
    @concurrent
    private nonisolated static func compute(_ inputs: ScoringInputs) async -> SomaScores {
        SomaScores.compute(inputs)
    }

    /// Asks for `metrics` and hands back the source to read them from.
    ///
    /// What a tab part calls from `.task` before it reads its own inputs: the
    /// request goes through the same once-per-set gate as every other, and a
    /// device without Health, or a request that threw, returns nil so the part
    /// renders its dashes and the status card says why.
    func prepare(_ metrics: [String]) async -> (any HealthSampleSource)? {
        guard source.isAvailable else {
            status = .unavailable
            return nil
        }
        let resolved = metrics.compactMap(HealthMetricCatalog.metric(for:))
        do {
            try await request(Self.displayed + resolved)
        } catch {
            status = .failed(String(describing: error))
            return nil
        }
        return source
    }

    /// Asks for these metrics, then reads the latest sample of each.
    ///
    /// What a surface calls when it opens on metrics outside ``displayed``. The
    /// launch request names none of the sensitive ones by construction, so a
    /// page that shows cycle tracking is the thing that asks for it, at the
    /// moment it is opened and not before.
    ///
    /// `requestAccess: false` only reads, for a background wake that must not
    /// raise a sheet.
    func loadLatest(_ metrics: [HealthMetric], requestAccess: Bool = true) async {
        guard source.isAvailable else {
            status = .unavailable
            return
        }

        let askable = metrics.filter(\.isReadAuthorizable)
        guard !askable.isEmpty, Self.isProtectedDataAvailable else { return }

        if requestAccess {
            do {
                try await request(askable)
            } catch {
                status = .failed(String(describing: error))
                return
            }
        }

        for metric in askable {
            readings[metric.identifier] = try? await source.latest(metric)
        }
        readingsReadAt = Date()
    }
}
