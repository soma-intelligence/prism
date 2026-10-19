//
//  PhoneMotionTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// A Health store that holds one value per metric for today, and records how
/// often it was asked.
private struct TodayHealthSource: HealthSampleSource {
    let values: [String: Double]

    var isAvailable: Bool { true }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? { reading(metric) }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { reading(metric) }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { reading(metric) }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] { [] }

    private func reading(_ metric: HealthMetric) -> HealthReading? {
        guard let value = values[metric.identifier] else { return nil }
        let now = Date()
        return HealthReading(metric: metric.identifier, value: value, unit: metric.unit, start: now, end: now)
    }
}

@Suite("Phone motion: merge rule")
struct PhoneMotionMergeTests {
    @Test("The higher of the two counts wins")
    func higherWins() {
        #expect(MotionMerge.preferred(health: 4_000, phone: 5_200) == 5_200)
        #expect(MotionMerge.preferred(health: 9_000, phone: 5_200) == 9_000)
    }

    @Test("One present is the answer; none is nil, a dash")
    func missingSides() {
        #expect(MotionMerge.preferred(health: nil, phone: 1_200) == 1_200)
        #expect(MotionMerge.preferred(health: 800, phone: nil) == 800)
        #expect(MotionMerge.preferred(health: nil, phone: nil) == nil)
    }
}

@Suite("Phone motion: timeline segments")
struct PhoneMotionSegmentTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    private func sample(_ minutes: Double, _ kind: MotionActivityKind?, _ confidence: MotionConfidence = .high) -> MotionActivitySample {
        MotionActivitySample(start: at(minutes), kind: kind, confidence: confidence)
    }

    @Test("Each sample lasts until the next; the last until the end")
    func spans() {
        let segments = MotionSegmenter.segments(
            from: [sample(0, .stationary), sample(10, .walking), sample(40, .automotive)],
            until: at(70)
        )
        #expect(segments.map(\.kind) == [.stationary, .walking, .automotive])
        #expect(segments.map(\.start) == [at(0), at(10), at(40)])
        #expect(segments.map(\.end) == [at(10), at(40), at(70)])
    }

    @Test("Repeated samples of one kind join into one segment")
    func joinsEqualNeighbours() {
        let segments = MotionSegmenter.segments(
            from: [sample(0, .walking, .medium), sample(5, .walking, .high), sample(20, .stationary)],
            until: at(30)
        )
        #expect(segments.count == 2)
        #expect(segments[0] == MotionSegment(kind: .walking, start: at(0), end: at(20), confidence: .high))
    }

    @Test("Unknown and unsure samples continue what was going on")
    func unsureCarriesForward() {
        let segments = MotionSegmenter.segments(
            from: [sample(0, .walking), sample(10, nil), sample(15, .running, .low), sample(25, .stationary)],
            until: at(40)
        )
        #expect(segments.map(\.kind) == [.walking, .stationary])
        #expect(segments[0].end == at(25))
    }

    @Test("Time before the first sure sample is left out")
    func leadingUnknownSkipped() {
        let segments = MotionSegmenter.segments(
            from: [sample(0, nil), sample(10, .cycling)],
            until: at(30)
        )
        #expect(segments == [MotionSegment(kind: .cycling, start: at(10), end: at(30), confidence: .high)])
    }

    @Test("A blip is dropped and the walk it split joins across it")
    func blipJoinsSameKind() {
        let segments = MotionSegmenter.segments(
            from: [sample(0, .walking), sample(10, .stationary), sample(11, .walking), sample(30, .stationary)],
            until: at(45)
        )
        #expect(segments.map(\.kind) == [.walking, .stationary])
        #expect(segments[0].start == at(0))
        #expect(segments[0].end == at(30))
    }

    @Test("A blip between two different kinds leaves a gap")
    func blipBetweenKindsLeavesGap() {
        let segments = MotionSegmenter.segments(
            from: [sample(0, .walking), sample(10, .running), sample(11, .automotive)],
            until: at(40)
        )
        #expect(segments.map(\.kind) == [.walking, .automotive])
        #expect(segments[0].end == at(10))
        #expect(segments[1].start == at(11))
    }

    @Test("Samples arrive in any order and past the end are ignored")
    func orderAndEnd() {
        let segments = MotionSegmenter.segments(
            from: [sample(20, .stationary), sample(0, .walking), sample(90, .running)],
            until: at(60)
        )
        #expect(segments.map(\.kind) == [.walking, .stationary])
        #expect(segments.last?.end == at(60))
    }

    @Test("A car at a red light reads as driving")
    func mostSpecificFlag() {
        #expect(MotionActivityKind.from(stationary: true, walking: false, running: false, cycling: false, automotive: true) == .automotive)
        #expect(MotionActivityKind.from(stationary: false, walking: true, running: true, cycling: false, automotive: false) == .running)
        #expect(MotionActivityKind.from(stationary: false, walking: false, running: false, cycling: false, automotive: false) == nil)
    }
}

@Suite("Phone motion: reader and dashboard")
@MainActor
struct PhoneMotionReaderTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func fixture(
        authorization: MotionAuthorization = .authorized,
        steps: Double,
        distance: Double? = nil,
        now: Date = .now
    ) -> PhoneMotionFixtureSource {
        let midnight = calendar.startOfDay(for: now)
        let today = PedometerDay(start: midnight, end: now, steps: steps, distance: distance, floorsAscended: 3)
        let samples = [
            MotionActivitySample(start: midnight, kind: .stationary, confidence: .high),
            MotionActivitySample(start: midnight.addingTimeInterval(60), kind: .walking, confidence: .high),
        ]
        return PhoneMotionFixtureSource(authorization: authorization, days: [today], samples: samples)
    }

    @Test("Nothing is read before the question has an answer")
    func noReadBeforeAnswer() async {
        let source = fixture(authorization: .notDetermined, steps: 900)
        let motion = PhoneMotion(source: source, calendar: calendar)

        await motion.refresh()

        #expect(motion.today == nil)
        #expect(source.accessRequests == 0)
    }

    @Test("The Health request puts the motion question once, then reads")
    func askedWithHealth() async {
        let source = fixture(authorization: .notDetermined, steps: 900)
        let motion = PhoneMotion(source: source, calendar: calendar)
        let dashboard = HealthDashboard(source: TodayHealthSource(values: [:]), calendar: calendar, motion: motion)

        await dashboard.start()
        await dashboard.start()

        #expect(source.accessRequests == 1)
        #expect(motion.authorization == .authorized)
        #expect(motion.today?.steps == 900)
        #expect(motion.timeline.first?.kind == .walking)
    }

    @Test("Today's steps and distance take the phone's count when Health lags")
    func phoneAheadOfHealth() async {
        let health = TodayHealthSource(values: [
            HealthDashboard.stepsIdentifier: 4_000,
            HealthDashboard.distanceIdentifier: 2_900,
        ])
        let motion = PhoneMotion(source: fixture(steps: 5_250, distance: 3_800), calendar: calendar)
        let dashboard = HealthDashboard(source: health, calendar: calendar, motion: motion)

        await dashboard.start()

        #expect(dashboard.todaySteps == 5_250)
        #expect(dashboard.todayDistance == 3_800)
        #expect(dashboard.value(HealthDashboard.stepsIdentifier) == 5_250.formatted(.number.precision(.fractionLength(0))))
        #expect(dashboard.todayFloors == 3)
        #expect(dashboard.phoneActivity.map(\.kind) == [.walking])
    }

    @Test("Health's count stands when it is ahead, the watch's steps included")
    func healthAheadOfPhone() async {
        let health = TodayHealthSource(values: [HealthDashboard.stepsIdentifier: 7_100])
        let motion = PhoneMotion(source: fixture(steps: 5_250), calendar: calendar)
        let dashboard = HealthDashboard(source: health, calendar: calendar, motion: motion)

        await dashboard.start()

        #expect(dashboard.todaySteps == 7_100)
        #expect(dashboard.todayDistance == nil)
    }

    @Test("Without the phone the dashboard reads Health alone")
    func withoutPhone() async {
        let health = TodayHealthSource(values: [HealthDashboard.stepsIdentifier: 2_000])
        let dashboard = HealthDashboard(source: health, calendar: calendar)

        await dashboard.start()

        #expect(dashboard.todaySteps == 2_000)
        #expect(dashboard.motion.authorization == .unavailable)
        #expect(dashboard.phoneActivity.isEmpty)
    }

    @Test("The read set holds what the iPhone writes to Health about walking")
    func iPhoneMobilityInReadSet() {
        let readable = Set(HealthMetricCatalog.readable.map(\.identifier))
        let phoneWritten = [
            "stepCount", "distanceWalkingRunning", "flightsClimbed", "walkingSpeed",
            "walkingStepLength", "walkingAsymmetryPercentage", "walkingDoubleSupportPercentage",
            "appleWalkingSteadiness", "sixMinuteWalkTestDistance", "stairAscentSpeed", "stairDescentSpeed",
        ].map { "HKQuantityTypeIdentifier" + $0.prefix(1).uppercased() + $0.dropFirst() }
        for identifier in phoneWritten {
            #expect(readable.contains(identifier), "\(identifier) is missing from the read set")
        }
        #expect(readable.contains("HKCategoryTypeIdentifierAppleWalkingSteadinessEvent"))
    }
}
