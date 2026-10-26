//
//  SomaScoresTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import HealthScoring
import SomaUI
@testable import Prism

/// The adapter between Apple Health and the score engine is arithmetic too:
/// readings bucketed into days, Soma's gates over the engine's result, and the
/// pages' numbers read off the scores. Plain inputs in, plain values out.
@Suite("Soma scores")
@MainActor
struct SomaScoresTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")

    /// 29 September 2026 at 15:00.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 15))! }
    var today: Date { calendar.startOfDay(for: now) }

    func day(_ offset: Int, hour: Int = 0) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: today)!)!
    }

    func reading(_ value: Double, at date: Date) -> HealthReading {
        HealthReading(metric: "m", value: value, unit: .none, start: date, end: date)
    }

    /// Eight hours in bed from 23:00, with an hour of deep and an hour and a
    /// half of REM, woken on the day `offset` from today.
    func night(wokeOn offset: Int) -> [ScoringSleepSample] {
        let bed = day(offset - 1, hour: 23)
        func sample(_ stage: String, _ from: Double, _ to: Double) -> ScoringSleepSample {
            ScoringSleepSample(stage: stage, start: bed.addingTimeInterval(from * 3600),
                               end: bed.addingTimeInterval(to * 3600), source: "Watch")
        }
        return [sample("deep", 0, 1), sample("core", 1, 4), sample("rem", 4, 5.5), sample("core", 5.5, 8)]
    }

    /// Ninety days of steady readings with a night on each of the last
    /// `nights` days.
    func inputs(nights: Int) -> ScoringInputs {
        let days = SomaScoresReader.days
        let steady: (Double) -> [Double?] = { value in Array(repeating: value, count: days) }
        return ScoringInputs(
            now: now,
            calendar: calendar,
            restingHeartRate: steady(56),
            heartRateVariability: steady(48),
            dayHeartRate: steady(72),
            steps: steady(8000),
            activeEnergy: steady(420),
            exerciseMinutes: steady(30),
            sleepSamples: (0..<nights).flatMap { night(wokeOn: -$0) },
            lastNightHeartRate: 52,
            latestRestingHeartRate: 56,
            ageYears: 36
        )
    }

    // MARK: - Reading

    @Test("Days run oldest first and end today")
    func dayStartsEndToday() {
        let starts = SomaScoresReader.dayStarts(days: 90, now: now, calendar: calendar)
        #expect(starts.count == 90)
        #expect(starts.last == today)
        #expect(starts.first == day(-89))
    }

    @Test("Readings average into the day they started on, and a day with none is missing, not zero")
    func dailyMeansBucketByDay() {
        let starts = SomaScoresReader.dayStarts(days: 3, now: now, calendar: calendar)
        let readings = [
            reading(40, at: day(-2, hour: 3)),
            reading(50, at: day(-2, hour: 22)),
            reading(60, at: day(0, hour: 4)),
        ]
        #expect(SomaScoresReader.dailyMeans(readings, dayStarts: starts, calendar: calendar) == [45, nil, 60])
    }

    @Test("A night's HRV is the mean of the readings inside it")
    func meanInsideTheNight() {
        let window = ScoringNightWindow(start: day(-1, hour: 23), end: day(0, hour: 7))
        let readings = [reading(30, at: day(-1, hour: 20)), reading(40, at: day(0, hour: 2)), reading(50, at: day(0, hour: 6))]
        #expect(SomaScoresReader.mean(readings, in: window) == 45)
    }

    @Test("The reader turns a store into aligned daily series")
    func readerAlignsSeries() async {
        let source = FixedSource(now: now, calendar: calendar)
        let read = await SomaScoresReader.read(from: source, now: now, calendar: calendar)
        #expect(read.steps.count == SomaScoresReader.days)
        #expect(read.steps.allSatisfy { $0 == 1000 })
        #expect(read.dayHeartRate.last == 70)
        #expect(read.restingHeartRate.last == 55)
        #expect(read.heartRateVariability.suffix(2) == [nil, 42])
        #expect(read.latestRestingHeartRate == 55)
        #expect(read.ageYears == 40)
        #expect(read.sleepSamples.map(\.stage) == ["deep", "core"])
    }

    // MARK: - Gates

    @Test("Before seven nights there is no sleep score and no recovery")
    func gateBeforeSevenNights() {
        let scores = SomaScores.compute(inputs(nights: 6))
        #expect(scores.nightsRecorded == 6)
        #expect(scores.sleep == nil)
        #expect(scores.recovery == nil)
        #expect(scores.sleepSeries.allSatisfy { $0 == nil })
        // Activity needs no nights.
        #expect(scores.strain != nil)
    }

    @Test("From seven nights the scores appear, and only from the day the gate opened")
    func gateOpensAtSevenNights() {
        let scores = SomaScores.compute(inputs(nights: 7))
        #expect(scores.sleep != nil)
        #expect(scores.recovery != nil)
        #expect(scores.energy != nil)
        #expect(scores.sleepSeries.compactMap { $0 }.count == 1)
        #expect(scores.sleepSeries.last != nil)
        #expect(scores.recoveryTerms.contains { $0.kind == .sleep })
    }

    @Test("Every score is 0 to 100")
    func scoresStayInRange() {
        let scores = SomaScores.compute(inputs(nights: 30))
        for value in [scores.sleep, scores.recovery, scores.strain, scores.stress, scores.energy] {
            #expect(value.map { (0...100).contains($0) } ?? false)
        }
        #expect(scores.sleepSeries.count == SomaScores.seriesDays)
        #expect(scores.energyCurve.last.map { Int($0.level.rounded()) } == scores.energy)
    }

    @Test("An empty store scores nothing")
    func emptyStoreScoresNothing() {
        let empty = Array(repeating: Double?.none, count: SomaScoresReader.days)
        let scores = SomaScores.compute(ScoringInputs(
            now: now, calendar: calendar, restingHeartRate: empty, heartRateVariability: empty,
            dayHeartRate: empty, steps: empty, activeEnergy: empty, exerciseMinutes: empty))
        #expect(scores.sleep == nil)
        #expect(scores.mind == nil)
        #expect(scores.strain == nil)
        #expect(scores.energy == nil)
        #expect(scores.energyCurve.isEmpty)
    }

    @Test("Masking keeps a day only once the count had reached seven by then")
    func maskingArithmetic() {
        let counts = SomaScores.runningCount([true, false, true, true, true, true, true, true])
        #expect(counts == [1, 1, 2, 3, 4, 5, 6, 7])
        #expect(SomaScores.masked([1, 2, 3, 4, 5, 6, 7, 8], open: counts) == [nil, nil, nil, nil, nil, nil, nil, 8])
        #expect(SomaScores.tail([1, 2]).count == SomaScores.seriesDays)
        #expect(SomaScores.tail([1, 2]).suffix(2) == [1, 2])
    }

    // MARK: - Mind

    @Test("Mind is recovery, or 100 minus stress when recovery is missing")
    func mindFallsBackOnCalm() {
        var scores = SomaScores.compute(inputs(nights: 30))
        scores.recovery = 71
        scores.recoveryTrend = .up
        #expect(scores.mind == 71)
        #expect(scores.mindTrend == .up)

        scores.recovery = nil
        scores.stress = 30
        scores.stressTrend = .up
        #expect(scores.mind == 70)
        #expect(scores.mindTrend == .down)

        scores.recoverySeries = [nil, 60]
        scores.stressSeries = [25, 40]
        #expect(scores.mindSeries == [75, 60])
    }

    // MARK: - Pages

    @Test("The row under the orb and the energy card read the scores")
    func todayReadsScores() {
        var scores = SomaScores.compute(inputs(nights: 30))
        scores.sleep = 82
        scores.sleepTrend = .up
        scores.recovery = 64
        scores.strain = 37
        scores.energy = 58
        let today = PulseToday.make(from: PulseInputs(now: now), scores: scores, calendar: calendar, locale: locale)
        #expect(today.sleep.value == "82")
        #expect(today.sleep.trend == .up)
        #expect(today.mind.value == "64")
        #expect(today.activity.value == "37")
        #expect(today.energyLevel == 0.58)
    }

    @Test("Without scores the row reads dashes rather than raw values")
    func todayWithoutScores() {
        let today = PulseToday.make(from: PulseInputs(now: now), calendar: calendar, locale: locale)
        #expect(today.sleep.value == nil)
        #expect(today.mind.value == nil)
        #expect(today.activity.value == nil)
        #expect(today.energyLevel == nil)
    }

    @Test("The three trend rows draw the score series and today's score")
    func trendsReadScores() {
        let scores = SomaScores.compute(inputs(nights: 30))
        let trends = PulseTrends.make(from: PulseTrendsInputs(now: now), scores: scores, calendar: calendar, locale: locale)
        #expect(trends.rows[0].series == scores.sleepSeries)
        #expect(trends.rows[0].value == scores.sleep.map { "\($0)" })
        #expect(trends.rows[1].series == scores.mindSeries)
        #expect(trends.rows[2].series == scores.strainSeries)
        #expect(trends.rows.allSatisfy { $0.unit == "of 100" })
    }

    @Test("Mind's energy line keeps today only")
    func mindEnergyLine() {
        var scores = SomaScores.compute(inputs(nights: 30))
        scores.energy = 60
        scores.energyCurve = [
            .init(date: day(-1, hour: 23), level: 40),
            .init(date: day(0, hour: 6), level: 80),
            .init(date: day(0, hour: 12), level: 60),
        ]
        let model = MindInnerSpace.make(from: MindInputs(now: now), scores: scores, calendar: calendar, locale: locale)
        #expect(model.energy == 60)
        #expect(model.energyCurve == [
            MindEnergyPoint(dayFraction: 0.25, level: 80),
            MindEnergyPoint(dayFraction: 0.5, level: 60),
        ])
    }
}

/// A store holding one fixed reading per metric: 1,000 steps a day, a mean
/// heart rate of 70, a resting rate of 55 every day, an HRV of 42 today only,
/// a date of birth reading 40 and part of one night.
private struct FixedSource: HealthSampleSource {
    let now: Date
    let calendar: Calendar

    var isAvailable: Bool { true }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        switch metric.identifier {
        case "HKQuantityTypeIdentifierRestingHeartRate": value(metric, 55, at: now)
        case "HKCharacteristicTypeIdentifierDateOfBirth": value(metric, 40, at: now)
        default: nil
        }
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        metric.identifier == "HKQuantityTypeIdentifierStepCount" ? value(metric, 1000, at: from) : nil
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        metric.identifier == "HKQuantityTypeIdentifierHeartRate" ? value(metric, 70, at: from) : nil
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        let today = calendar.startOfDay(for: now)
        switch metric.identifier {
        case "HKQuantityTypeIdentifierRestingHeartRate":
            var day = calendar.startOfDay(for: from)
            var found: [HealthReading] = []
            while day <= to {
                found.append(value(metric, 55, at: day.addingTimeInterval(8 * 3600)))
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            return found
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            return [value(metric, 42, at: today.addingTimeInterval(3 * 3600))]
        case "HKCategoryTypeIdentifierSleepAnalysis":
            let bed = today.addingTimeInterval(-3600)
            return [
                HealthReading(metric: metric.identifier, value: 0, unit: .none, start: bed, end: bed.addingTimeInterval(8 * 3600)),
                HealthReading(metric: metric.identifier, value: 4, unit: .none, start: bed, end: bed.addingTimeInterval(3600)),
                HealthReading(metric: metric.identifier, value: 3, unit: .none,
                              start: bed.addingTimeInterval(3600), end: bed.addingTimeInterval(8 * 3600)),
            ]
        default:
            return []
        }
    }

    private func value(_ metric: HealthMetric, _ number: Double, at date: Date) -> HealthReading {
        HealthReading(metric: metric.identifier, value: number, unit: .none, start: date, end: date)
    }
}
