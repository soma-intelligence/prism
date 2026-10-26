//
//  RobustnessTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import HealthScoring
@testable import Prism

/// Apple Health is written by any app on the phone, so the store can hold
/// anything: a NaN from a broken integration, an infinite or negative value,
/// a sample that ends before it starts, one dated next year, a thousand
/// readings at the same instant. None of it may bring the app down. Each test
/// drives the real readers and the real arithmetic with such a store, or
/// with nothing at all, and asks only that the work finishes and gives
/// numbers a page can draw.
@Suite("Robustness")
@MainActor
struct RobustnessTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// 24 October 2026 at 09:00, a few days before the clocks change.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9))! }

    /// A store that answers every question with the worst it can.
    struct HostileSource: HealthSampleSource {
        let now: Date
        var isAvailable: Bool { true }

        static let values: [Double] = [.nan, .infinity, -.infinity, -1, 0, 1e12, -1e12, .ulpOfOne, 72, 0.5]

        func requestAuthorization(for metrics: [HealthMetric]) async throws {}

        func latest(_ metric: HealthMetric) async throws -> HealthReading? {
            reading(metric, value: .nan, start: now.addingTimeInterval(86_400 * 365), end: now)
        }

        func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
            reading(metric, value: .infinity, start: to, end: from)
        }

        func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
            reading(metric, value: -.infinity, start: from, end: to)
        }

        func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
            var out: [HealthReading] = []
            let span = max(to.timeIntervalSince(from), 1)
            for index in 0..<400 {
                let value = Self.values[index % Self.values.count]
                let start = from.addingTimeInterval(span * Double(index) / 400)
                // Every kind of interval: normal, zero length, reversed, far
                // future, and many at one instant.
                let end: Date = switch index % 5 {
                case 0: start.addingTimeInterval(1_800)
                case 1: start
                case 2: start.addingTimeInterval(-3_600)
                case 3: start.addingTimeInterval(86_400 * 400)
                default: from
                }
                out.append(reading(metric, value: value, start: start, end: end))
            }
            // Sleep stage codes outside the known range.
            if metric.identifier == "HKCategoryTypeIdentifierSleepAnalysis" {
                out += [-1, 99, 3, 4, 5, 2].map { reading(metric, value: $0, start: from, end: to) }
            }
            return out
        }

        private func reading(_ metric: HealthMetric, value: Double, start: Date, end: Date) -> HealthReading {
            HealthReading(metric: metric.identifier, value: value, unit: metric.unit, start: start, end: end,
                          source: "Hostile", device: "", deviceModel: nil)
        }
    }

    /// A store that throws on every read.
    struct FailingSource: HealthSampleSource {
        var isAvailable: Bool { true }
        func requestAuthorization(for metrics: [HealthMetric]) async throws {}
        func latest(_ metric: HealthMetric) async throws -> HealthReading? { throw HealthReadError.underlying("x") }
        func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { throw HealthReadError.underlying("x") }
        func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { throw HealthReadError.underlying("x") }
        func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] { throw HealthReadError.underlying("x") }
    }

    private var sources: [(String, any HealthSampleSource)] {
        [("empty", EmptyHealthSource()), ("hostile", HostileSource(now: now)), ("failing", FailingSource()),
         ("fixture", FixtureHealthSource(now: now, calendar: calendar))]
    }

    // MARK: - Scores and the pages built on them

    @Test("Scores compute from any store, and every score stays within 0 to 100")
    func scoresFromAnyStore() async {
        for (name, source) in sources {
            let inputs = await SomaScoresReader.read(from: source, now: now, calendar: calendar)
            let scores = SomaScores.compute(inputs)
            for value in [scores.sleep, scores.recovery, scores.strain, scores.stress, scores.energy].compactMap({ $0 }) {
                #expect((0...100).contains(value), "\(name): \(value)")
            }
            for series in [scores.sleepSeries, scores.recoverySeries, scores.strainSeries, scores.stressSeries] {
                let finite = series.compactMap { $0 }.allSatisfy { $0.isFinite }
                #expect(finite, "\(name)")
            }
            // Every score page builds from them.
            for inputs in [nil, await ScoreDetailInputs.read(Set(ScoreDetailInputs.Part.allCases), from: source, now: now, calendar: calendar)] {
                _ = ScorePages.sleep(scores, inputs, calendar: calendar)
                _ = ScorePages.recovery(scores, inputs)
                _ = ScorePages.strain(scores, inputs, calendar: calendar)
                _ = ScorePages.stress(scores, inputs, calendar: calendar)
            }
            _ = ScorePages.energy(scores, calendar: calendar)
        }
    }

    @Test("Score pages build with no scores at all")
    func scorePagesWithNothing() {
        _ = ScorePages.sleep(nil, nil, calendar: calendar)
        _ = ScorePages.recovery(nil, nil)
        _ = ScorePages.strain(nil, nil, calendar: calendar)
        _ = ScorePages.stress(nil, nil, calendar: calendar)
        _ = ScorePages.energy(nil, calendar: calendar)
        #expect(SleepNightSummary.make(scoring: [], inBedStart: nil, parts: []) == nil)
    }

    @Test("The Today page builds from any store")
    func todayFromAnyStore() async {
        for (_, source) in sources {
            let inputs = await PulseInputs.read(from: source, now: now, calendar: calendar)
            let scores = SomaScores.compute(await SomaScoresReader.read(from: source, now: now, calendar: calendar))
            _ = PulseToday.make(from: inputs, scores: scores, calendar: calendar)
            _ = PulseToday.make(from: inputs, scores: nil, calendar: calendar)
        }
    }

    @Test("Every Body reading builds from no readings, one, or hostile ones")
    func biomarkers() async {
        let hostile = HostileSource(now: now)
        for spec in BodyBiomarkerSpec.allCases {
            _ = BodyBiomarkers.make(spec, readings: [], now: now, calendar: calendar)
            guard let metric = HealthMetricCatalog.metric(for: spec.identifier) else { continue }
            let readings = (try? await hostile.samples(metric, from: now.addingTimeInterval(-90 * 86_400), to: now, limit: 0)) ?? []
            let marker = BodyBiomarkers.make(spec, readings: readings, now: now, calendar: calendar)
            _ = BodyBiomarkers.make(spec, readings: Array(readings.prefix(1)), now: now, calendar: calendar)
            #expect(marker.days.count <= BodyBiomarkers.days)
        }
    }

    // MARK: - The dashboard

    @Test("The dashboard starts, loads and refreshes on any store, twice over at once")
    func dashboardOnAnyStore() async {
        for (_, source) in sources {
            let dashboard = HealthDashboard(source: source, calendar: calendar)
            // Pages appearing together call these at the same moment.
            async let start: Void = dashboard.start()
            async let today: Void = dashboard.loadToday(force: true)
            async let scores: Void = dashboard.loadScores(force: true)
            async let scoresAgain: Void = dashboard.loadScores(force: true)
            _ = await (start, today, scores, scoresAgain)
            await dashboard.load()
            for metric in HealthDashboard.displayed {
                _ = dashboard.rowValue(for: metric)
                _ = dashboard.value(metric.identifier)
                _ = dashboard.minutes(metric.identifier)
                _ = dashboard.hours(metric.identifier)
            }
        }
    }

    // MARK: - Charts and spans

    @Test("Chart spans and buckets hold for every period, including backwards and empty runs")
    func periodsAndBuckets() {
        let master = MetricMaster(today: calendar.startOfDay(for: now), days: Array(repeating: nil, count: MetricMaster.length))
        for period in VaultPeriod.allCases {
            let span = period.interval(endingAt: now, calendar: calendar)
            #expect(span.duration > 0)
            #expect(!period.buckets(endingAt: now, calendar: calendar).isEmpty)
            #expect(period.buckets(from: now, through: now.addingTimeInterval(-86_400 * 30), calendar: calendar).isEmpty)
            let year = period.buckets(from: master.date(at: 0, calendar: calendar), through: now, calendar: calendar)
            #expect(!year.isEmpty)
            let buckets = MetricDetailMath.buckets(master, band: nil, intervals: year, calendar: calendar)
            #expect(buckets.allSatisfy { $0.value == nil })
            #expect(MetricDetailMath.stats(buckets.map(\.value)) == nil)
            _ = period.shifted(now, by: 5, calendar: calendar)
            _ = period.shifted(now, by: -5, calendar: calendar)
        }
    }

    @Test("A night of one stage, or of overlapping and backwards runs, draws")
    func oddNights() {
        let start = now.addingTimeInterval(-8 * 3_600)
        let runs = [
            ScoringStageRun(stage: "deep", start: start, end: start.addingTimeInterval(3_600)),
            ScoringStageRun(stage: "rem", start: start.addingTimeInterval(1_800), end: start.addingTimeInterval(600)),
            ScoringStageRun(stage: "unknown", start: start, end: start),
            ScoringStageRun(stage: "core", start: start.addingTimeInterval(7_200), end: start.addingTimeInterval(7_200 + 60)),
        ]
        _ = SleepNightSummary.make(scoring: runs, inBedStart: nil, parts: [])
        _ = SleepNightSummary.make(scoring: Array(runs.prefix(1)), inBedStart: start.addingTimeInterval(3_600), parts: [])
    }
}
