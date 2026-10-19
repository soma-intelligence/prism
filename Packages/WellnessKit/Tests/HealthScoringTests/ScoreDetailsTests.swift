//
//  ScoreDetailsTests.swift
//  HealthScoringTests
//
//  The score pages' detail: a score taken apart must add back up to the
//  score, and every derived reading must say nothing rather than something
//  invented when its inputs are thin.
//

import Foundation
import Testing
@testable import HealthScoring

@Suite struct ScoreDetailsTests {
    static let calendar = SomaScoringEngineTests.calendar
    static let now = SomaScoringEngineTests.now

    // MARK: Sleep score parts

    @Test func sleepPartsSumToTheScore() {
        let result = SomaScoringEngine.compute(SomaScoringEngineTests.inputs())
        let parts = result.sleepPartsToday
        #expect(!parts.isEmpty)
        let shares = parts.reduce(0) { $0 + $1.share }
        #expect(abs(shares - 100) < 0.0001)
        let points = parts.reduce(0) { $0 + $1.points }
        #expect(Int(points.rounded()) == result.sleepScoreToday)
    }

    @Test func termsMatchTheScoreTheyExplain() {
        let hypnogram: [(stage: String, seconds: Int)] = [
            ("deep", 3600), ("core", 9000), ("awake", 900), ("rem", 4500), ("core", 7200), ("rem", 3600),
        ]
        let score = RealHealthMath.sleepScore(hypnogram: hypnogram, needSeconds: 8 * 3600,
                                              nightHR: 52, dayRHR: 58, ageYears: 40)
        let parts = ScoringSleepPart.parts(hypnogram: hypnogram, needSeconds: 8 * 3600,
                                           nightHR: 52, dayRHR: 58, ageYears: 40)
        #expect(parts.count == 6)
        #expect(Int(parts.reduce(0) { $0 + $1.points }.rounded()) == score)
    }

    @Test func aNightWithoutWakeDropsEfficiencyAndContinuity() {
        let parts = ScoringSleepPart.parts(hypnogram: [("core", 20_000), ("deep", 4000)], needSeconds: 28_800,
                                           nightHR: nil, dayRHR: nil, ageYears: nil)
        let kinds = Set(parts.map(\.kind))
        #expect(!kinds.contains(.efficiency))
        #expect(!kinds.contains(.continuity))
        #expect(!kinds.contains(.dip))
    }

    // MARK: Stages and nights

    @Test func lastNightStagesFillTheNight() {
        let result = SomaScoringEngine.compute(SomaScoringEngineTests.inputs())
        let runs = result.lastNightStages
        #expect(!runs.isEmpty)
        for (a, b) in zip(runs, runs.dropFirst()) {
            #expect(a.end <= b.start.addingTimeInterval(1))
        }
        #expect(runs.contains { $0.stage == "deep" })
    }

    @Test func nightWindowsLandOnTheirWakeDay() {
        let inputs = SomaScoringEngineTests.inputs(days: 30, nights: 10)
        let windows = SomaScoringEngine.nightWindows(from: inputs.sleepSamples, days: 30, now: Self.now,
                                                     calendar: Self.calendar)
        #expect(windows.count == 30)
        #expect(windows.compactMap { $0 }.count == 10)
        #expect(windows.last??.end != nil)
        #expect(windows.first! == nil)
    }

    // MARK: Night dip

    @Test func dipNeedsTenBeatsAndABaseline() {
        let start = Self.now
        let beats = (0..<12).map { ScoringTimedValue(start: start.addingTimeInterval(Double($0) * 600),
                                                     end: start, value: 50 + Double($0 % 3)) }
        #expect(ScoringNightDip.reading(samples: Array(beats.prefix(9)), restingHR: 58) == nil)
        #expect(ScoringNightDip.reading(samples: beats, restingHR: nil) == nil)
        let reading = ScoringNightDip.reading(samples: beats, restingHR: 58)
        #expect(reading != nil)
        #expect(reading!.lowest == 50)
        let expected = (58 - reading!.meanSleepingHR) / 58 * 100
        #expect(abs(reading!.percent - expected) < 0.0001)
    }

    @Test func dipBandsFollowTheConvention() {
        #expect(ScoringNightDip.Band(percent: 4.9) == .flat)
        #expect(ScoringNightDip.Band(percent: 5) == .shallow)
        #expect(ScoringNightDip.Band(percent: 12) == .healthy)
        #expect(ScoringNightDip.Band(percent: 20) == .deep)
    }

    // MARK: Usual band

    @Test func usualBandNeedsSevenValues() {
        #expect(ScoringUsual.of([14, 15, 14.5, nil, 15, 14], spreadFloor: 0.5) == nil)
        let usual = ScoringUsual.of([14, 15, 14.5, 14.8, 15, 14, 14.4], spreadFloor: 0.5)
        #expect(usual != nil)
        #expect(usual!.center == 14.5)
        #expect(usual!.high - usual!.center >= 0.5)
        #expect(usual!.contains(14.5))
    }

    // MARK: Stress through the day

    @Test func stressLineSkipsSleepAndEmptyHalfHours() {
        let dayStart = Self.calendar.startOfDay(for: Self.now)
        let readings = (0..<(15 * 4)).map { quarter in
            ScoringTimedValue(start: dayStart.addingTimeInterval(Double(quarter) * 900),
                              end: dayStart, value: quarter < 40 ? 55 : 95)
        }
        let sleep = ScoringNightWindow(start: dayStart.addingTimeInterval(-3600), end: dayStart.addingTimeInterval(7 * 3600))
        let line = ScoringIntradayStress.line(heartRate: readings, dayStart: dayStart, now: Self.now,
                                              excluded: [sleep], hrv: 40, hrvBaseline: 50, restingHR: 55,
                                              maxHR: 180)
        #expect(line.allSatisfy { $0.start >= dayStart.addingTimeInterval(7 * 3600) })
        #expect(line.first!.value < line.last!.value)
        #expect(line.allSatisfy { (0...100).contains($0.value) })
    }

    // MARK: Peak window

    static func nights(_ count: Int, bed: Int = 23, wake: Int = 7) -> [ScoringNightWindow] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            let end = calendar.date(byAdding: .hour, value: wake, to: day)!
            let start = calendar.date(byAdding: .hour, value: bed - 24, to: day)!
            return ScoringNightWindow(start: start, end: end)
        }
    }

    @Test func peakDayWaitsForThreeNights() {
        #expect(ScoringPeakDay.resolve(nights: Self.nights(2), now: Self.now, calendar: Self.calendar) == nil)
        #expect(ScoringPeakDay.resolve(nights: Self.nights(3), now: Self.now, calendar: Self.calendar) != nil)
    }

    @Test func peakDayReadsAWellRestedDay() {
        let day = ScoringPeakDay.resolve(nights: Self.nights(14), now: Self.now, calendar: Self.calendar)!
        #expect(abs(day.bedHour - 23) < 0.01)
        #expect(abs(day.wakeHour - 7) < 0.01)
        #expect(abs(day.windDownHour - 22) < 0.01)
        #expect(day.now != nil)
        let peak = day.peakHour!
        #expect(peak > 7 && peak < 23)
        #expect(day.curve.allSatisfy { (0...100).contains($0.level) })
        // 100 mg to 25 mg at a five hour half life is ten hours before bed.
        #expect(abs(day.caffeineCutoffHour - 13) < 0.01)
        #expect(day.chronotype != nil)
    }
}
