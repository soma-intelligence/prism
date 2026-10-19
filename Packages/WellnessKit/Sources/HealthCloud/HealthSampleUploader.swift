import Foundation
import HealthExportCore
import SyncCore

/// What one upload run may touch.
public struct HealthUploadConfiguration: Sendable {
    /// The metrics to upload, in this order. Correlations and characteristics
    /// are dropped: neither is a sample with an identity.
    public var metrics: [HealthMetric]
    /// Samples per page read and per request sent.
    public var batchSize: Int
    /// Daily rows are worked out for days this recent only, so the first run
    /// over years of history does not ask Health for thousands of days.
    public var dailyWindowDays: Int
    /// Names this phone in `health_sync_state`: anchors belong to one Health
    /// store, so two phones keep two rows.
    public var installationID: String
    public var calendar: Calendar

    public init(metrics: [HealthMetric], batchSize: Int = 500, dailyWindowDays: Int = 120, installationID: String, calendar: Calendar = .current) {
        self.metrics = metrics.filter { $0.kind != .correlation && $0.kind != .characteristic }
        self.batchSize = max(1, batchSize)
        self.dailyWindowDays = max(0, dailyWindowDays)
        self.installationID = installationID
        self.calendar = calendar
    }

    /// Every sample metric of the catalog, the priority tier first. The
    /// sensitive ones (cycle tracking and the like) stay on the phone unless
    /// `includingSensitive` says otherwise.
    public static func catalogMetrics(includingSensitive: Bool = false) -> [HealthMetric] {
        HealthMetricCatalog.all
            .filter { includingSensitive || $0.sensitivity == .standard }
            .sorted { $0.tier < $1.tier }
    }
}

/// Why a run ended before the last metric.
public enum HealthUploadStop: Error, Sendable, Hashable {
    /// A previous failure asked for a pause that has not run out.
    case backingOff(until: Date)
    case offline
    /// The session is gone or was refused: the person has to sign in.
    case authRequired
    /// The server is unwell; the pause before the next run is recorded.
    case transient(String)
    /// The device has no Health store.
    case sourceUnavailable
    case cancelled
    /// The anchors could not be written; nothing after that point is trusted.
    case storage(String)
}

public struct HealthUploadReport: Sendable, Hashable {
    public var uploadedSamples = 0
    public var deletedSamples = 0
    public var dailyRows = 0
    public var metricsVisited = 0
    /// Metrics passed over this run, with the reason: unknown on this OS, or
    /// refused by the server.
    public var skipped: [String: String] = [:]
    public var stoppedBy: HealthUploadStop?

    public init() {}
}

/// Sends new Health samples to `health_samples`, one metric at a time, from
/// the anchor of the last confirmed page.
///
/// The order of each page is what makes it safe: read changes after the
/// anchor, upsert the added samples on `(user_id, hk_uuid)`, delete the
/// removed ones, and only then store the new anchor. A crash between the two
/// sends the page again, and the upsert absorbs it. The daily rows of the
/// days a page touched are kept as pending in the same write as the anchor,
/// so they survive a failure too.
///
/// One run at a time: a second call while one runs waits for it and returns
/// its report. A failure that could pass (a 503, a timeout) records a pause
/// from the retry policy, and runs inside that pause return at once.
public actor HealthSampleUploader {
    private let source: any HealthAnchoredSampleSource
    private let writer: any HealthCloudWriter
    private let anchors: any HealthAnchorStore
    private let userID: UserID
    private let configuration: HealthUploadConfiguration
    private let policy: RetryPolicy
    private let clock: any SyncClock
    private let random: any RandomSource
    private let aggregator: HealthDailyAggregator
    private var current: Task<HealthUploadReport, Never>?

    public init(
        source: any HealthAnchoredSampleSource,
        writer: any HealthCloudWriter,
        anchors: any HealthAnchorStore,
        userID: UserID,
        configuration: HealthUploadConfiguration,
        policy: RetryPolicy = .standard,
        clock: any SyncClock = SystemClock(),
        random: any RandomSource = SystemRandomSource()
    ) {
        self.source = source
        self.writer = writer
        self.anchors = anchors
        self.userID = userID
        self.configuration = configuration
        self.policy = policy
        self.clock = clock
        self.random = random
        self.aggregator = HealthDailyAggregator(calendar: configuration.calendar)
    }

    /// Runs an upload, or joins the one already running.
    @discardableResult
    public func run() async -> HealthUploadReport {
        if let current { return await current.value }
        let task = Task { await self.perform() }
        current = task
        let report = await task.value
        current = nil
        return report
    }

    // MARK: The run

    private func perform() async -> HealthUploadReport {
        var report = HealthUploadReport()
        let now = clock.now().date
        let pause = await anchors.backoff()
        if let until = pause.nextAttemptAt, until > now {
            report.stoppedBy = .backingOff(until: until)
            return report
        }
        guard source.isAvailable else {
            report.stoppedBy = .sourceUnavailable
            return report
        }

        for metric in configuration.metrics {
            if Task.isCancelled {
                report.stoppedBy = .cancelled
                return report
            }
            report.metricsVisited += 1
            do {
                try await upload(metric, report: &report)
            } catch let stop as HealthUploadStop {
                report.stoppedBy = stop
                await recordFailure(stop)
                return report
            } catch {
                report.stoppedBy = .storage(String(describing: error))
                return report
            }
        }

        if pause.attempts > 0 || pause.nextAttemptAt != nil {
            do {
                try await anchors.setBackoff(HealthUploadBackoff())
            } catch {
                report.stoppedBy = .storage(String(describing: error))
            }
        }
        return report
    }

    /// Every page of one metric, then its pending daily rows, then its sync
    /// state row. Throws `HealthUploadStop` to end the run; a problem that
    /// concerns this metric alone is written into `report.skipped` instead.
    private func upload(_ metric: HealthMetric, report: inout HealthUploadReport) async throws {
        var state = await anchors.state(for: metric.identifier)
        let windowStart = configuration.calendar.date(
            byAdding: .day,
            value: -configuration.dailyWindowDays,
            to: configuration.calendar.startOfDay(for: clock.now().date)
        ) ?? .distantPast
        var touchedThisRun = false

        while true {
            if Task.isCancelled { throw HealthUploadStop.cancelled }
            let changes: HealthSampleChanges
            do {
                changes = try await source.changes(metric, after: state.anchor, limit: configuration.batchSize)
            } catch HealthReadError.unavailable {
                throw HealthUploadStop.sourceUnavailable
            } catch is CancellationError {
                throw HealthUploadStop.cancelled
            } catch {
                // Unknown on this OS, not readable this way, or a Health
                // error for this one type: the others still go.
                report.skipped[metric.identifier] = String(describing: error)
                return
            }

            if !changes.added.isEmpty {
                let rows = changes.added.map { HealthSampleRow(userID: userID, record: $0, kind: metric.kind) }
                guard try await send(metric, report: &report, { () async throws(AuthorizedCallError) in try await self.writer.upsertSamples(rows) }) else { return }
                report.uploadedSamples += rows.count
                state.uploaded += rows.count
                if let latest = changes.added.map(\.reading.end).max() {
                    state.lastSampleEnd = max(state.lastSampleEnd ?? latest, latest)
                }
                for record in changes.added where record.reading.end >= windowStart {
                    state.pendingDays.formUnion(aggregator.days(touchedBy: record.reading).filter { day in
                        (aggregator.interval(of: day)?.end ?? .distantPast) > windowStart
                    })
                }
            }
            if !changes.deleted.isEmpty {
                let deleted = changes.deleted
                guard try await send(metric, report: &report, { () async throws(AuthorizedCallError) in try await self.writer.deleteSamples(deleted) }) else { return }
                report.deletedSamples += deleted.count
            }

            state.anchor = changes.anchor ?? state.anchor
            state.lastError = nil
            try await anchors.save(state, for: metric.identifier)
            touchedThisRun = touchedThisRun || !changes.isEmpty
            if !changes.hasMore { break }
        }

        if !state.pendingDays.isEmpty {
            var rows: [HealthDailyRow] = []
            var unfinished: Set<String> = []
            for day in state.pendingDays.sorted() {
                do {
                    if let row = try await aggregator.row(for: metric, day: day, userID: userID, source: source) {
                        rows.append(row)
                    }
                } catch {
                    // The samples are up; a day Health cannot total now is
                    // tried again on the next run.
                    unfinished.insert(day)
                }
            }
            let built = rows
            guard try await send(metric, report: &report, { () async throws(AuthorizedCallError) in try await self.writer.upsertDaily(built) }) else { return }
            report.dailyRows += built.count
            // A day Health had nothing for is done as well: there is no row to send.
            state.pendingDays = unfinished
            try await anchors.save(state, for: metric.identifier)
        }

        if touchedThisRun {
            let row = HealthSyncStateRow(
                userID: userID,
                installationID: configuration.installationID,
                metric: metric.identifier,
                anchor: state.anchor,
                lastSyncedAt: clock.now().date,
                samplesUploaded: state.uploaded,
                lastSampleEnd: state.lastSampleEnd,
                lastError: nil
            )
            _ = try await send(metric, report: &report, { () async throws(AuthorizedCallError) in try await self.writer.upsertSyncState([row]) })
        }
    }

    /// Runs one write. True when it went through; false when the server
    /// refused this metric's rows for good (the metric is skipped this run);
    /// throws `HealthUploadStop` when the whole run has to stop.
    private func send(
        _ metric: HealthMetric,
        report: inout HealthUploadReport,
        _ write: () async throws(AuthorizedCallError) -> Void
    ) async throws(HealthUploadStop) -> Bool {
        do {
            try await write()
            return true
        } catch {
            switch error {
            case .interrupted(let interruption):
                switch interruption {
                case .offline: throw .offline
                case .authRequired, .authMismatch: throw .authRequired
                case .circuitOpen: throw .transient("circuit open")
                case .cancelled: throw .cancelled
                }
            case .remote(let remote):
                switch remote {
                case .offline: throw .offline
                case .unauthorized: throw .authRequired
                case .cancelled: throw .cancelled
                case .timeout, .transient, .malformedResponse, .cursorExpired:
                    throw .transient(String(describing: remote))
                case .forbidden, .rejected:
                    report.skipped[metric.identifier] = String(describing: remote)
                    return false
                }
            }
        }
    }

    private func recordFailure(_ stop: HealthUploadStop) async {
        guard case .transient = stop else { return }
        var pause = await anchors.backoff()
        pause.attempts += 1
        let delay = policy.delay(forAttempt: pause.attempts, retryAfter: nil, random: random)
        pause.nextAttemptAt = clock.now().adding(delay).date
        do {
            try await anchors.setBackoff(pause)
        } catch {
            // The pause is advice, not state: losing it costs one early retry
            // after a transient failure.
        }
    }
}
