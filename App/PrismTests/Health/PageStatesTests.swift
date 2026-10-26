//
//  PageStatesTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaWidgetKit
@testable import Prism

/// The states a page passes through: the Today page drawn before the scores,
/// a failed Health request that a "Try again" recovers from, and the line a
/// save leaves behind.
@Suite("Page states")
@MainActor
struct PageStatesTests {

    @Test("Today is drawn and the status is ready once the page's own read is in")
    func todayComesUpReady() async {
        let dashboard = HealthDashboard(source: EmptyHealthSource())

        await dashboard.loadToday()

        #expect(dashboard.status == .ready)
        #expect(dashboard.today != nil)
        #expect(!dashboard.isReadingScores)
        #expect(dashboard.hasReadScores)
    }

    @Test("A request that failed reads again on retry, and the page comes back ready")
    func retryRecoversFromAFailedRequest() async {
        let source = RefusesOnce()
        let dashboard = HealthDashboard(source: source)

        await dashboard.start()
        guard case .failed = dashboard.status else {
            Issue.record("expected the first request to fail, got \(dashboard.status)")
            return
        }

        await dashboard.retry()

        #expect(dashboard.status == .ready)
        #expect(dashboard.today != nil)
    }

    @Test("Today's widget snapshot draws the scores before the first read")
    func lastKnownFromToday() throws {
        let now = Date()
        let snapshot = SomaWidgetSnapshot(
            generatedAt: now.addingTimeInterval(-60),
            hasData: true,
            sleep: .init(value: 82, series7: [70, 75, nil, 80, 81, 79, 82]),
            recovery: .init(value: 64.4),
            strain: .init(value: 11)
        )

        let known = try #require(SomaScores.lastKnown(from: snapshot, now: now, calendar: .current))

        #expect(known.sleep == 82)
        #expect(known.recovery == 64)
        #expect(known.strain == 11)
        #expect(known.stress == nil)
        #expect(known.sleepSeries.count == SomaScores.seriesDays)
        #expect(known.sleepSeries.last == 82)
        #expect(known.nightsRecorded == SomaScores.minimumNights)
    }

    @Test("Yesterday's snapshot, or one without a sleep score, is not used")
    func lastKnownOnlyWhenItHolds() {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let old = SomaWidgetSnapshot(generatedAt: yesterday, hasData: true, sleep: .init(value: 82))
        let gated = SomaWidgetSnapshot(generatedAt: now, hasData: true, strain: .init(value: 9))

        #expect(SomaScores.lastKnown(from: old, now: now, calendar: calendar) == nil)
        #expect(SomaScores.lastKnown(from: gated, now: now, calendar: calendar) == nil)
        #expect(SomaScores.lastKnown(from: nil, now: now, calendar: calendar) == nil)
    }

    @Test("Last known scores do not count as a read")
    func lastKnownIsNotARead() {
        let dashboard = HealthDashboard(source: EmptyHealthSource())
        let snapshot = SomaWidgetSnapshot(generatedAt: .now, hasData: true, sleep: .init(value: 82))

        dashboard.adoptLastKnownScores(snapshot)

        #expect(dashboard.scores?.sleep == 82)
        #expect(!dashboard.hasReadScores)
    }

    @Test("A log that reached Health is confirmed as done")
    func loggedAndReached() {
        let confirmations = Confirmations()

        confirmations.logged("Water", reachedHealth: true)

        #expect(confirmations.current?.kind == .done)
        #expect(confirmations.current?.text == "Water logged")
    }

    @Test("A notice replaces what was showing, and clearing an old one leaves it")
    func newestWins() throws {
        let confirmations = Confirmations()
        confirmations.done("Weight logged")
        let first = try #require(confirmations.current)

        confirmations.notice("Water saved in Soma, not in Apple Health.")
        confirmations.clear(first)

        #expect(confirmations.current?.kind == .notice)
    }
}

/// A store whose first permission request throws and whose second succeeds,
/// as a request interrupted by a locked phone does.
private final class RefusesOnce: HealthSampleSource, @unchecked Sendable {
    private var asked = 0

    struct Refused: Error {}

    var isAvailable: Bool { true }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {
        asked += 1
        if asked == 1 { throw Refused() }
    }

    func latest(_ metric: HealthMetric) async throws -> HealthReading? { nil }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] { [] }
}
