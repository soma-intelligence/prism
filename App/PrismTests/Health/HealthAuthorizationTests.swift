//
//  HealthAuthorizationTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Every request the dashboard made, in order.
private actor RequestLog {
    private(set) var requests: [Set<String>] = []

    func record(_ identifiers: Set<String>) { requests.append(identifiers) }

    var count: Int { requests.count }
}

/// A source that records what it was asked for and hands back nothing.
///
/// Nothing is the honest fixture here: the question under test is how often
/// permission is asked for, not what comes back once it is granted.
private struct RecordingSource: HealthSampleSource {
    let log: RequestLog
    /// Errors to throw, one per call, front first. Empty means every call
    /// succeeds.
    let failures: FailureQueue

    var isAvailable: Bool { true }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {
        await log.record(Set(metrics.map(\.identifier)))
        if await failures.next() { throw HealthReadError.unavailable }
    }

    func latest(_ metric: HealthMetric) async throws -> HealthReading? { nil }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] { [] }
}

/// How many of the first calls throw.
private actor FailureQueue {
    private var remaining: Int

    init(_ remaining: Int = 0) { self.remaining = remaining }

    func next() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}

/// The permission sheet is a question, and a question that has an answer is
/// not asked again. The pages call `start()` from `.task`, which SwiftUI runs
/// afresh on every tab switch, so "ask on appear" means "ask on every
/// appear" unless something upstream remembers.
@Suite("Health authorization")
@MainActor
struct HealthAuthorizationTests {

    private func sensitiveMetric() throws -> HealthMetric {
        let metric = HealthMetricCatalog.onDemand.first { $0.isReadAuthorizable }
        return try #require(metric)
    }

    @Test("Three page appearances ask once")
    func startAsksOnce() async throws {
        let log = RequestLog()
        let dashboard = HealthDashboard(source: RecordingSource(log: log, failures: FailureQueue()))

        await dashboard.start()
        await dashboard.start()
        await dashboard.start()

        #expect(await log.count == 1)
        #expect(dashboard.status == .ready)
    }

    @Test("A surface opening on a metric never asked for still asks")
    func newMetricStillAsks() async throws {
        let log = RequestLog()
        let dashboard = HealthDashboard(source: RecordingSource(log: log, failures: FailureQueue()))
        let sensitive = try sensitiveMetric()

        await dashboard.start()
        await dashboard.loadLatest([sensitive])
        await dashboard.loadLatest([sensitive])

        let requests = await log.requests
        #expect(requests.count == 2)
        #expect(requests.last == [sensitive.identifier])
    }

    @Test("A request that threw was never answered, so it is asked again")
    func failedRequestIsRetried() async throws {
        let log = RequestLog()
        let dashboard = HealthDashboard(source: RecordingSource(log: log, failures: FailureQueue(1)))

        await dashboard.start()
        #expect(dashboard.status == .failed(String(describing: HealthReadError.unavailable)))

        await dashboard.start()

        #expect(await log.count == 2)
        #expect(dashboard.status == .ready)
    }

    @Test("Two pages appearing together share one request")
    func concurrentAppearancesShareOneRequest() async throws {
        let log = RequestLog()
        let dashboard = HealthDashboard(source: RecordingSource(log: log, failures: FailureQueue()))

        async let first: Void = dashboard.start()
        async let second: Void = dashboard.start()
        _ = await (first, second)

        #expect(await log.count == 1)
    }
}
