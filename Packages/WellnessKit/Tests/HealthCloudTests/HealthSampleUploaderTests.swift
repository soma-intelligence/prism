import Foundation
import Testing
import HealthExportCore
import SyncCore
import SyncTesting
@testable import HealthCloud

// MARK: - Doubles

/// A Health store as an append-only log: an anchor is the index of the next
/// change to hand out, which is exactly how HealthKit's anchors behave.
actor FakeAnchoredSource: HealthAnchoredSampleSource {
    enum Change: Sendable {
        case added(HealthSampleRecord)
        case deleted(UUID)
    }

    nonisolated let isAvailable: Bool
    private var log: [String: [Change]] = [:]
    private(set) var reads: [(metric: String, anchor: Int?)] = []
    private var failures: [String: HealthReadError] = [:]

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func add(_ metric: String, _ changes: [Change]) {
        log[metric, default: []].append(contentsOf: changes)
    }

    func fail(_ metric: String, with error: HealthReadError) {
        failures[metric] = error
    }

    static func position(_ anchor: Data?) -> Int? {
        anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
    }

    func changes(_ metric: HealthMetric, after anchor: Data?, limit: Int) async throws -> HealthSampleChanges {
        if let failure = failures[metric.identifier] { throw failure }
        let start = Self.position(anchor) ?? 0
        reads.append((metric.identifier, Self.position(anchor)))
        let all = log[metric.identifier] ?? []
        let end = limit > 0 ? min(all.count, start + limit) : all.count
        let page = start < end ? Array(all[start..<end]) : []
        var added: [HealthSampleRecord] = []
        var deleted: [UUID] = []
        for change in page {
            switch change {
            case .added(let record): added.append(record)
            case .deleted(let id): deleted.append(id)
            }
        }
        return HealthSampleChanges(added: added, deleted: deleted, anchor: Data(String(end).utf8), hasMore: end < all.count)
    }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}
    func latest(_ metric: HealthMetric) async throws -> HealthReading? { nil }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        let values = live(metric.identifier).filter { $0.reading.start >= from && $0.reading.start < to }.map(\.reading.value)
        guard !values.isEmpty else { return nil }
        return HealthReading(metric: metric.identifier, value: values.reduce(0, +), unit: metric.unit, start: from, end: to)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        live(metric.identifier).map(\.reading).filter { $0.end > from && $0.start < to }
    }

    private func live(_ metric: String) -> [HealthSampleRecord] {
        var records: [UUID: HealthSampleRecord] = [:]
        for change in log[metric] ?? [] {
            switch change {
            case .added(let record): records[record.uuid] = record
            case .deleted(let id): records[id] = nil
            }
        }
        return Array(records.values)
    }
}

/// A server that keeps what it is sent, and fails when told to.
actor FakeHealthWriter: HealthCloudWriter {
    private(set) var samples: [String: HealthSampleRow] = [:]
    private(set) var daily: [String: HealthDailyRow] = [:]
    private(set) var syncStates: [HealthSyncStateRow] = []
    private(set) var sampleRequests: [Int] = []
    private var failures: [AuthorizedCallError] = []

    func failNext(_ errors: [AuthorizedCallError]) {
        failures.append(contentsOf: errors)
    }

    private func check() throws(AuthorizedCallError) {
        if !failures.isEmpty { throw failures.removeFirst() }
    }

    func upsertSamples(_ rows: [HealthSampleRow]) async throws(AuthorizedCallError) {
        try check()
        sampleRequests.append(rows.count)
        for row in rows { samples["\(row.userID)/\(row.hkUUID)"] = row }
    }

    func deleteSamples(_ uuids: [UUID]) async throws(AuthorizedCallError) {
        try check()
        let ids = Set(uuids.map { $0.uuidString.lowercased() })
        samples = samples.filter { !ids.contains($0.value.hkUUID) }
    }

    func upsertDaily(_ rows: [HealthDailyRow]) async throws(AuthorizedCallError) {
        try check()
        for row in rows { daily["\(row.metric)/\(row.day)"] = row }
    }

    func upsertSyncState(_ rows: [HealthSyncStateRow]) async throws(AuthorizedCallError) {
        try check()
        syncStates.append(contentsOf: rows)
    }
}

// MARK: - Tests

@Suite struct HealthSampleUploaderTests {
    static let steps = HealthMetric(identifier: "HKQuantityTypeIdentifierStepCount", kind: .quantity, unit: .count, aggregation: .cumulative, tier: .priority)
    static let heart = HealthMetric(identifier: "HKQuantityTypeIdentifierHeartRate", kind: .quantity, unit: .countPerMinute, aggregation: .discrete, tier: .priority)
    static let user = UserID("0f8fad5b-d9cb-469f-a165-70867728950e")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// The fixed "now" every test starts at.
    static let start = Instant(millisecondsSinceEpoch: 1_800_000_000_000)
    /// One clock per test: Swift Testing makes a suite instance per test, and
    /// tests run in parallel.
    let clock = ManualClock(now: HealthSampleUploaderTests.start)

    static func record(_ metric: HealthMetric, _ value: Double, minutesAgo: Double) -> FakeAnchoredSource.Change {
        let end = start.date.addingTimeInterval(-minutesAgo * 60)
        return .added(HealthSampleRecord(
            uuid: UUID(),
            reading: HealthReading(metric: metric.identifier, value: value, unit: metric.unit, start: end.addingTimeInterval(-60), end: end, source: "Watch", device: "Apple Watch")
        ))
    }

    func uploader(_ source: FakeAnchoredSource, _ writer: FakeHealthWriter, _ anchors: any HealthAnchorStore, metrics: [HealthMetric] = [steps, heart], batch: Int = 3) -> HealthSampleUploader {
        HealthSampleUploader(
            source: source,
            writer: writer,
            anchors: anchors,
            userID: Self.user,
            configuration: HealthUploadConfiguration(metrics: metrics, batchSize: batch, installationID: "phone-1", calendar: Self.calendar),
            clock: clock,
            random: FixedRandom(0.5)
        )
    }

    @Test func pagesInBatchesAndAdvancesTheAnchorPerPage() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, (0..<7).map { Self.record(Self.steps, Double($0), minutesAgo: Double(10 + $0)) })
        let writer = FakeHealthWriter()
        let anchors = MemoryHealthAnchorStore()

        let report = await uploader(source, writer, anchors).run()

        #expect(report.stoppedBy == nil)
        #expect(report.uploadedSamples == 7)
        #expect(await writer.sampleRequests == [3, 3, 1])
        #expect(await writer.samples.count == 7)
        #expect(FakeAnchoredSource.position(await anchors.state(for: Self.steps.identifier).anchor) == 7)
        #expect(await source.reads.map(\.anchor) == [nil, 3, 6, nil])
    }

    @Test func aSecondRunStartsFromTheStoredAnchorAndSendsOnlyTheNew() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 1, minutesAgo: 5)])
        let writer = FakeHealthWriter()
        let anchors = MemoryHealthAnchorStore()
        let upload = uploader(source, writer, anchors, metrics: [Self.steps])

        await upload.run()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 2, minutesAgo: 1)])
        let second = await upload.run()

        #expect(second.uploadedSamples == 1)
        #expect(await writer.sampleRequests == [1, 1])
    }

    @Test func aFailedWriteKeepsTheAnchorSoThePageIsSentAgain() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, (0..<2).map { Self.record(Self.steps, Double($0), minutesAgo: Double($0 + 1)) })
        let writer = FakeHealthWriter()
        await writer.failNext([.remote(.transient(status: 503, retryAfter: nil))])
        let anchors = MemoryHealthAnchorStore()
        let upload = uploader(source, writer, anchors, metrics: [Self.steps])

        let first = await upload.run()

        #expect(first.stoppedBy == .transient("transient(status: Optional(503), retryAfter: nil)"))
        #expect(await anchors.state(for: Self.steps.identifier).anchor == nil)
        let pause = await anchors.backoff()
        #expect(pause.attempts == 1)
        #expect(pause.nextAttemptAt != nil)

        // Inside the pause nothing is read.
        let paused = await upload.run()
        if case .backingOff = paused.stoppedBy {} else { Issue.record("expected a pause, got \(String(describing: paused.stoppedBy))") }

        clock.advance(by: .seconds(3600))
        let retried = await upload.run()
        #expect(retried.stoppedBy == nil)
        #expect(retried.uploadedSamples == 2)
        #expect(await anchors.backoff() == HealthUploadBackoff())
    }

    @Test func offlineStopsWithoutAPause() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 1, minutesAgo: 1)])
        let writer = FakeHealthWriter()
        await writer.failNext([.remote(.offline)])
        let anchors = MemoryHealthAnchorStore()

        let report = await uploader(source, writer, anchors).run()

        #expect(report.stoppedBy == .offline)
        #expect(await anchors.backoff().attempts == 0)
    }

    @Test func aRefusedSessionStopsTheRunAsAuthRequired() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 1, minutesAgo: 1)])
        let writer = FakeHealthWriter()
        await writer.failNext([.interrupted(.authRequired)])

        let report = await uploader(source, writer, MemoryHealthAnchorStore()).run()

        #expect(report.stoppedBy == .authRequired)
    }

    @Test func aRejectedMetricIsSkippedAndTheOthersStillGo() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 1, minutesAgo: 1)])
        await source.add(Self.heart.identifier, [Self.record(Self.heart, 60, minutesAgo: 1)])
        let writer = FakeHealthWriter()
        await writer.failNext([.remote(.rejected(status: 400, reason: "bad row"))])

        let report = await uploader(source, writer, MemoryHealthAnchorStore()).run()

        #expect(report.stoppedBy == nil)
        #expect(report.skipped[Self.steps.identifier] != nil)
        #expect(report.uploadedSamples == 1)
    }

    @Test func anUnknownMetricIsSkipped() async throws {
        let source = FakeAnchoredSource()
        await source.fail(Self.steps.identifier, with: .unknownMetric(Self.steps.identifier))
        await source.add(Self.heart.identifier, [Self.record(Self.heart, 60, minutesAgo: 1)])

        let report = await uploader(source, FakeHealthWriter(), MemoryHealthAnchorStore()).run()

        #expect(report.skipped.keys.contains(Self.steps.identifier))
        #expect(report.uploadedSamples == 1)
    }

    @Test func deletionsReachTheServer() async throws {
        let source = FakeAnchoredSource()
        let first = Self.record(Self.steps, 1, minutesAgo: 2)
        await source.add(Self.steps.identifier, [first])
        let writer = FakeHealthWriter()
        let upload = uploader(source, writer, MemoryHealthAnchorStore(), metrics: [Self.steps])
        await upload.run()
        guard case .added(let record) = first else { return }

        await source.add(Self.steps.identifier, [.deleted(record.uuid)])
        let report = await upload.run()

        #expect(report.deletedSamples == 1)
        #expect(await writer.samples.isEmpty)
    }

    @Test func dailyRowsSumCumulativeAndSpreadDiscrete() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 100, minutesAgo: 30), Self.record(Self.steps, 50, minutesAgo: 20)])
        await source.add(Self.heart.identifier, [Self.record(Self.heart, 50, minutesAgo: 30), Self.record(Self.heart, 70, minutesAgo: 20)])
        let writer = FakeHealthWriter()
        let anchors = MemoryHealthAnchorStore()

        let report = await uploader(source, writer, anchors).run()

        let day = HealthDailyAggregator(calendar: Self.calendar).dayKey(Self.start.date)
        let steps = try #require(await writer.daily["\(Self.steps.identifier)/\(day)"])
        #expect(steps.sum == 150)
        #expect(steps.avg == nil)
        let heart = try #require(await writer.daily["\(Self.heart.identifier)/\(day)"])
        #expect(heart.avg == 60)
        #expect(heart.min == 50)
        #expect(heart.max == 70)
        #expect(heart.count == 2)
        #expect(report.dailyRows == 2)
        #expect(await anchors.state(for: Self.steps.identifier).pendingDays.isEmpty)
    }

    @Test func pendingDaysSurviveAFailedDailyWrite() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 100, minutesAgo: 30)])
        let writer = FakeHealthWriter()
        // The samples go, the daily row fails.
        let anchors = MemoryHealthAnchorStore()
        let upload = uploader(source, writer, anchors, metrics: [Self.steps])
        let gate = FailingDailyWriter(inner: writer)
        let failing = HealthSampleUploader(
            source: source, writer: gate, anchors: anchors, userID: Self.user,
            configuration: HealthUploadConfiguration(metrics: [Self.steps], installationID: "phone-1", calendar: Self.calendar),
            clock: clock, random: FixedRandom(0)
        )

        let first = await failing.run()
        #expect(first.uploadedSamples == 1)
        #expect(await anchors.state(for: Self.steps.identifier).pendingDays.count == 1)
        await anchors.setBackoff(HealthUploadBackoff())

        // Nothing new in Health, yet the day is sent.
        let second = await upload.run()
        #expect(second.dailyRows == 1)
        #expect(await anchors.state(for: Self.steps.identifier).pendingDays.isEmpty)
    }

    @Test func syncStateCarriesTheInstallationAndTheAnchor() async throws {
        let source = FakeAnchoredSource()
        await source.add(Self.steps.identifier, [Self.record(Self.steps, 1, minutesAgo: 1)])
        let writer = FakeHealthWriter()

        await uploader(source, writer, MemoryHealthAnchorStore(), metrics: [Self.steps]).run()

        let state = try #require(await writer.syncStates.first)
        #expect(state.installationID == "phone-1")
        #expect(state.metric == Self.steps.identifier)
        #expect(state.anchor == Data("1".utf8).base64EncodedString())
        #expect(state.samplesUploaded == 1)
    }

    @Test func anUnavailableStoreDoesNothing() async {
        let report = await uploader(FakeAnchoredSource(isAvailable: false), FakeHealthWriter(), MemoryHealthAnchorStore()).run()
        #expect(report.stoppedBy == .sourceUnavailable)
    }

    @Test func catalogMetricsLeaveOutSensitiveCorrelationsAndCharacteristics() {
        let metrics = HealthUploadConfiguration(metrics: HealthUploadConfiguration.catalogMetrics(), installationID: "x").metrics
        #expect(!metrics.isEmpty)
        #expect(metrics.allSatisfy { $0.sensitivity == .standard })
        #expect(metrics.allSatisfy { $0.kind != .correlation && $0.kind != .characteristic })
        #expect(metrics.first?.tier == .priority)
    }

    @Test func fileAnchorsPersistAcrossInstances() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let url = directory.url.appending(path: "anchors.json")
        let first = FileHealthAnchorStore(url: url)
        try await first.save(HealthMetricUploadState(anchor: Data([1, 2]), pendingDays: ["2027-01-15"], uploaded: 4), for: "m")

        let second = FileHealthAnchorStore(url: url)
        let state = await second.state(for: "m")
        #expect(state.anchor == Data([1, 2]))
        #expect(state.pendingDays == ["2027-01-15"])
        #expect(state.uploaded == 4)

        try await second.reset()
        #expect(await FileHealthAnchorStore(url: url).state(for: "m") == HealthMetricUploadState())
    }
}

/// Passes everything through except the daily rows, which fail as a 503.
struct FailingDailyWriter: HealthCloudWriter {
    let inner: FakeHealthWriter
    func upsertSamples(_ rows: [HealthSampleRow]) async throws(AuthorizedCallError) { try await inner.upsertSamples(rows) }
    func deleteSamples(_ uuids: [UUID]) async throws(AuthorizedCallError) { try await inner.deleteSamples(uuids) }
    func upsertDaily(_ rows: [HealthDailyRow]) async throws(AuthorizedCallError) { throw .remote(.transient(status: 503, retryAfter: nil)) }
    func upsertSyncState(_ rows: [HealthSyncStateRow]) async throws(AuthorizedCallError) { try await inner.upsertSyncState(rows) }
}

@Suite struct HealthCloudRowTests {
    @Test func sampleRowsEncodeSnakeCaseWithIdentity() throws {
        let uuid = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let reading = HealthReading(metric: "HKQuantityTypeIdentifierHeartRate", value: 61, unit: .countPerMinute,
                                    start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60),
                                    source: "Watch", sourceBundle: "com.apple.health", device: "Apple Watch", deviceModel: "Watch Apple Inc.", wasUserEntered: false)
        let row = HealthSampleRow(userID: UserID("ABC"), record: HealthSampleRecord(uuid: uuid, reading: reading), kind: .quantity)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        #expect(json["hk_uuid"] as? String == "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")
        #expect(json["user_id"] as? String == "abc")
        #expect(json["unit"] as? String == "countPerMinute")
        #expect(json["device_model"] as? String == "Watch Apple Inc.")
        #expect(json["was_user_entered"] as? Bool == false)
    }

    @Test func aSampleSpanningMidnightTouchesBothDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let aggregator = HealthDailyAggregator(calendar: calendar)
        let start = Date(timeIntervalSince1970: 86_400 - 3600)
        let reading = HealthReading(metric: "sleep", value: 3, unit: .none, start: start, end: start.addingTimeInterval(7200))
        #expect(aggregator.days(touchedBy: reading) == ["1970-01-01", "1970-01-02"])
    }
}
