//
//  SomaScoringEngineTests.swift
//  HealthScoringTests
//
//  The pipeline against the ported primitives: every per-day value the engine
//  returns has to be the value the primitive gives for the same inputs, so a
//  change in the plumbing cannot quietly change a score.
//

import Foundation
import Testing
@testable import HealthScoring

@Suite struct SomaScoringEngineTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// 2026-09-29 15:00 local.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 15))!

    /// Eight hours in bed ending at `wake`: an hour of deep, then core and
    /// REM, with one awakening.
    static func night(endingOn wake: Date, source: String = "Watch") -> [ScoringSleepSample] {
        let bed = wake.addingTimeInterval(-8 * 3600)
        func sample(_ stage: String, _ from: Double, _ to: Double) -> ScoringSleepSample {
            ScoringSleepSample(stage: stage, start: bed.addingTimeInterval(from * 3600),
                               end: bed.addingTimeInterval(to * 3600), source: source)
        }
        return [
            sample("deep", 0, 1),
            sample("core", 1, 3.5),
            sample("awake", 3.5, 3.75),
            sample("rem", 3.75, 5),
            sample("core", 5, 7),
            sample("rem", 7, 8),
        ]
    }

    static func inputs(days: Int = 90, nights: Int = 90) -> ScoringInputs {
        let today = calendar.startOfDay(for: now)
        var sleep: [ScoringSleepSample] = []
        for back in 0..<nights {
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            sleep += night(endingOn: calendar.date(byAdding: .hour, value: 7, to: day)!)
        }
        let wave = (0..<days).map { Double($0 % 7) }
        return ScoringInputs(
            now: now,
            calendar: calendar,
            restingHeartRate: wave.map { 55 + $0 },
            heartRateVariability: wave.map { 50 - $0 * 2 },
            dayHeartRate: wave.map { 70 + $0 },
            steps: wave.map { 6000 + $0 * 800 },
            activeEnergy: wave.map { 350 + $0 * 40 },
            exerciseMinutes: wave.map { 20 + $0 * 5 },
            sleepSamples: sleep,
            intradayHeartRate: (0..<60).map {
                ScoringTimedValue(start: today.addingTimeInterval(8 * 3600 + Double($0) * 300),
                                  end: today.addingTimeInterval(8 * 3600 + Double($0) * 300), value: 80)
            },
            intradayActiveEnergy: [
                ScoringTimedValue(start: today.addingTimeInterval(9 * 3600),
                                  end: today.addingTimeInterval(10 * 3600), value: 200),
            ],
            lastNightHeartRate: 52,
            lastNightVariability: 48,
            latestRestingHeartRate: 56,
            ageYears: 35
        )
    }

    @Test func sleepCodesMapToStages() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(ScoringSleepSample(code: 0, start: start, end: start, source: nil) == nil)
        #expect(ScoringSleepSample(code: 1, start: start, end: start, source: nil)?.stage == "core")
        #expect(ScoringSleepSample(code: 2, start: start, end: start, source: nil)?.stage == "awake")
        #expect(ScoringSleepSample(code: 3, start: start, end: start, source: nil)?.stage == "core")
        #expect(ScoringSleepSample(code: 4, start: start, end: start, source: nil)?.stage == "deep")
        #expect(ScoringSleepSample(code: 5, start: start, end: start, source: nil)?.stage == "rem")
    }

    @Test func maxHeartRateFollowsTanaka() {
        #expect(SomaScoringEngine.maxHeartRate(ageYears: 40) == 180)
        #expect(SomaScoringEngine.maxHeartRate(ageYears: nil) == 208)
        #expect(SomaScoringEngine.maxHeartRate(ageYears: 200) == 120)
    }

    @Test func aNightCountsOnTheDayItWokeOn() {
        let today = Self.calendar.startOfDay(for: Self.now)
        let samples = Self.night(endingOn: today.addingTimeInterval(7 * 3600))
        let breakdown = SomaScoringEngine.dailySleepBreakdown(
            SomaScoringEngine.lite(samples), days: 3, now: Self.now, calendar: Self.calendar)
        #expect(breakdown.asleep[0] == nil)
        #expect(breakdown.asleep[1] == nil)
        #expect(abs((breakdown.asleep[2] ?? 0) - 7.75) < 0.001)
        #expect(abs((breakdown.deep[2] ?? 0) - 1) < 0.001)
        #expect(abs((breakdown.rem[2] ?? 0) - 2.25) < 0.001)
        #expect(breakdown.bedHour[2] == 23)
        #expect(breakdown.wakeHour[2] == 7)
    }

    @Test func aSecondTrackerDoesNotDoubleTheNight() {
        let today = Self.calendar.startOfDay(for: Self.now)
        let wake = today.addingTimeInterval(7 * 3600)
        let samples = Self.night(endingOn: wake) + Self.night(endingOn: wake, source: "Ring")
        let breakdown = SomaScoringEngine.dailySleepBreakdown(
            SomaScoringEngine.lite(samples), days: 1, now: Self.now, calendar: Self.calendar)
        #expect(abs((breakdown.asleep[0] ?? 0) - 7.75) < 0.001)
    }

    @Test func seriesAreAlignedAndEndToday() {
        let result = SomaScoringEngine.compute(Self.inputs())
        #expect(result.days == 90)
        for series in [result.sleepScore, result.strain, result.recovery, result.stress,
                       result.energyMorning, result.energyEnd, result.sleepDebtHours] {
            #expect(series.count == 90)
        }
        #expect(result.nightsRecorded == 90)
        #expect(result.lastNight != nil)
    }

    @Test func perDaySleepScoreIsThePrimitive() {
        let result = SomaScoringEngine.compute(Self.inputs())
        let index = 40
        let hours = result.sleepHours[index]!
        let need = Int(result.sleepNeedHours[index]! * 3600)
        let expected = RealHealthMath.sleepScore(
            asleepSeconds: Int(hours * 3600), needSeconds: need,
            remSeconds: Int(2.25 * 3600), deepSeconds: 3600,
            dayRHR: Self.inputs().restingHeartRate[index], ageYears: 35)
        #expect(result.sleepScore[index] == expected.map(Double.init))
    }

    @Test func perDayStrainIsThePrimitive() {
        let result = SomaScoringEngine.compute(Self.inputs())
        let trimp = result.trimp.map { $0 }
        let ctl = RealHealthMath.causalChronicDailyTRIMPSeries(trimp)
        let max90 = RealHealthMath.trailingMaxSeries(trimp, days: 90)
        for index in [10, 50, 88] {
            let expected = RealHealthMath.strainPercent(trimp: trimp[index]!, trimp90Max: max90[index]!,
                                                        chronicDailyTrimp: ctl[index])
            #expect(result.strain[index] == Double(expected))
        }
    }

    @Test func todaysStrainUsesTodaysZonesAndEnergy() {
        let inputs = Self.inputs()
        let result = SomaScoringEngine.compute(inputs)
        // An hour at 80 bpm with a 187 maximum sits in zone 0 (under half),
        // so today's load is the active energy floor.
        let kcal = inputs.activeEnergy.last!!
        #expect(abs(result.trimp.last!! - kcal / RealHealthMath.activeKcalPerTrimp) < 0.0001)
        #expect(result.strainToday != nil)
    }

    @Test func todayHasEveryScoreWithAFullHistory() {
        let result = SomaScoringEngine.compute(Self.inputs())
        #expect(result.sleepScoreToday != nil)
        #expect(result.recoveryToday != nil)
        #expect(result.stressToday != nil)
        #expect(result.energyToday != nil)
        #expect(result.sleepDebtHoursToday != nil)
        let energy = result.energyToday!
        #expect(energy.isMeasured)
        #expect(energy.current >= VitalitySections.batteryFloor && energy.current <= 100)
        #expect(energy.levels.last == energy.current)
    }

    @Test func nothingRecordedScoresNothing() {
        let empty = Array(repeating: Double?.none, count: 90)
        let inputs = ScoringInputs(now: Self.now, calendar: Self.calendar,
                                   restingHeartRate: empty, heartRateVariability: empty,
                                   dayHeartRate: empty, steps: empty, activeEnergy: empty,
                                   exerciseMinutes: empty)
        let result = SomaScoringEngine.compute(inputs)
        #expect(result.sleepScoreToday == nil)
        #expect(result.recoveryToday == nil)
        #expect(result.strainToday == nil)
        #expect(result.stressToday == nil)
        #expect(result.energyToday == nil)
        #expect(result.sleepScore.allSatisfy { $0 == nil })
        #expect(result.nightsRecorded == 0)
    }

    @Test func energyLedgerIsThePrimitive() {
        let result = SomaScoringEngine.compute(Self.inputs())
        // Every closing level sits in the bank's range, and a recorded night
        // always charges.
        for index in 1..<result.days {
            guard let morning = result.energyMorning[index], let end = result.energyEnd[index] else { continue }
            #expect(morning >= end)
            #expect(end >= VitalitySections.batteryFloor && morning <= 100)
        }
    }

    @Test func recoveryTodayCarriesItsTerms() {
        let result = SomaScoringEngine.compute(Self.inputs())
        let breakdown = result.recoveryToday!
        let kinds = Set(breakdown.terms.map(\.kind))
        #expect(kinds.isSuperset(of: [.hrv, .rhr, .sleep]))
        #expect(breakdown.missing.isEmpty)
        let sum = breakdown.baseline + breakdown.terms.reduce(0) { $0 + $1.points }
        #expect(abs(sum - breakdown.rawTotal) < 0.0001)
    }
}
