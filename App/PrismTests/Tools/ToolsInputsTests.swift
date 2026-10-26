//
//  ToolsInputsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import HealthScoring
#if canImport(HealthKit)
import HealthKit
#endif
@testable import Prism

/// Every tool page reads one set of inputs out of Apple Health. The part that
/// can go wrong quietly is the nights: stages from a watch and a phone have to
/// become one night per morning, counted once, with naps and short stretches
/// left out, or every body clock tool reads the wrong bedtime.
@Suite("Tools inputs")
@MainActor
struct ToolsInputsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    var now: Date { at(15) }

    func stage(_ stage: String, _ start: Date, _ end: Date, _ source: String = "Watch") -> ScoringSleepSample {
        ScoringSleepSample(stage: stage, start: start, end: end, source: source)
    }

    /// Last night on the watch: asleep 23:00 to 07:00, ten minutes awake.
    var watchNight: [ScoringSleepSample] {
        [
            stage("core", at(23, day: -1), at(1)),
            stage("deep", at(1), at(2)),
            stage("core", at(2), at(3)),
            stage("awake", at(3), at(3, 10)),
            stage("core", at(3, 10), at(4)),
            stage("rem", at(4), at(5)),
            stage("core", at(5), at(7)),
        ]
    }

    func night(bed: Date, wake: Date) -> ToolNight {
        ToolNight(wakeDay: calendar.startOfDay(for: wake), bed: bed, wake: wake,
                  asleep: wake.timeIntervalSince(bed) / 3600, deep: 0, rem: 0, core: 0, awake: 0, stages: [])
    }

    // MARK: Nights

    @Test("A night's stages add up, awake left out of asleep, on the day it ended")
    func oneNight() throws {
        let nights = ToolsInputs.nights(from: watchNight, calendar: calendar)
        let night = try #require(nights.first)
        #expect(nights.count == 1)
        #expect(night.wakeDay == calendar.startOfDay(for: at(7)))
        #expect(night.bed == at(23, day: -1))
        #expect(night.wake == at(7))
        #expect(abs(night.asleep - (7 + 50.0 / 60)) < 1e-9)
        #expect(abs(night.deep - 1) < 1e-9)
        #expect(abs(night.rem - 1) < 1e-9)
        #expect(abs(night.awake - 10.0 / 60) < 1e-9)
        #expect(night.stages.map(\.start) == night.stages.map(\.start).sorted())
    }

    @Test("A watch and a phone writing one night count it once, from the source that slept more")
    func twoSources() throws {
        let phone = [stage("core", at(23, 30, day: -1), at(6, 30), "iPhone")]
        let nights = ToolsInputs.nights(from: phone + watchNight, calendar: calendar)
        let night = try #require(nights.first)
        #expect(nights.count == 1)
        #expect(Set(night.stages.map(\.source)) == ["Watch"])
        #expect(abs(night.asleep - (7 + 50.0 / 60)) < 1e-9)
    }

    @Test("A nap is not a night, and of two sleeps ending one morning the longer is kept")
    func napsAndSplitNights() throws {
        let nap = [stage("core", at(14, day: -1), at(15, 30, day: -1))]
        let split = [
            stage("core", at(22, day: -3), at(2, day: -2)),
            stage("core", at(4, day: -2), at(7, 30, day: -2)),
        ]
        let nights = ToolsInputs.nights(from: nap + split + watchNight, calendar: calendar)
        #expect(nights.map(\.wakeDay) == [calendar.startOfDay(for: at(0, day: -2)), calendar.startOfDay(for: at(0))])
        let first = try #require(nights.first)
        #expect(first.bed == at(22, day: -3))
        #expect(abs(first.asleep - 4) < 1e-9)
    }

    @Test("Bed reads as a clock hour against the wake day, past 24 after midnight")
    func clockHours() {
        let early = night(bed: at(23, day: -1), wake: at(7))
        let late = night(bed: at(1), wake: at(8, 30))
        #expect(abs(early.bedHour(calendar: calendar) - 23) < 1e-9)
        #expect(abs(late.bedHour(calendar: calendar) - 25) < 1e-9)
        #expect(abs(late.wakeHour(calendar: calendar) - 8.5) < 1e-9)
    }

    @Test("Last night is the latest one, only when it ended today or yesterday")
    func lastNight() {
        let today = night(bed: at(23, day: -1), wake: at(7))
        let yesterday = night(bed: at(23, day: -2), wake: at(7, day: -1))
        let older = night(bed: at(23, day: -3), wake: at(7, day: -2))
        #expect(ToolsInputs(now: now, nights: [older, today]).lastNight(calendar: calendar) == today)
        #expect(ToolsInputs(now: now, nights: [older, yesterday]).lastNight(calendar: calendar) == yesterday)
        #expect(ToolsInputs(now: now, nights: [older]).lastNight(calendar: calendar) == nil)
        #expect(ToolsInputs(now: now).lastNight(calendar: calendar) == nil)
    }

    @Test("The bed and wake series hold one slot a day, ending today, empty where no night ended")
    func series() {
        let today = night(bed: at(23, day: -1), wake: at(7))
        let older = night(bed: at(1, day: -2), wake: at(9, day: -2))
        let series = ToolsInputs(now: now, nights: [older, today]).series(days: 4, calendar: calendar)
        #expect(series.bed.count == 4)
        #expect(series.bed[0] == nil)
        #expect(series.bed[1] == 25)
        #expect(series.bed[2] == nil)
        #expect(series.bed[3] == 23)
        #expect(series.wake == [nil, 9, nil, 7])
    }

    @Test("Readings average per day, oldest first, days without one left out")
    func dailyMeans() {
        let readings: [HealthReading] = [
            .test(ToolsInputs.Metric.restingHeartRate, 60, at: at(8, day: -1)),
            .test(ToolsInputs.Metric.restingHeartRate, 50, at: at(7, day: -3)),
            .test(ToolsInputs.Metric.restingHeartRate, 40, at: at(20, day: -3)),
        ]
        #expect(ToolsInputs.dailyMeans(readings, calendar: calendar) == [45, 60])
        #expect(ToolsInputs.dailyMeans(readings, through: at(0, day: -2), calendar: calendar) == [45])
    }

    // MARK: Reading

    @Test("Every type the tools read is one the Health catalog knows")
    func metricsAreInTheCatalog() {
        for identifier in ToolsInputs.metrics {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    #if canImport(HealthKit)
    @Test("The strength codes are HealthKit's own strength workouts")
    func strengthCodes() {
        let strength: [HKWorkoutActivityType] = [.functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining]
        #expect(Set(strength.map { Int($0.rawValue) }) == ToolsInputs.strengthCodes)
    }
    #endif

    @Test("One read gathers the nights, the caffeine, today's daylight and the latest body readings")
    func read() async {
        let sleep: [HealthReading] = [
            .test(ToolsInputs.Metric.sleep, 0, from: at(22, 40, day: -1), to: at(7, 5)),
            .test(ToolsInputs.Metric.sleep, 3, from: at(23, day: -1), to: at(3)),
            .test(ToolsInputs.Metric.sleep, 4, from: at(3), to: at(4)),
            .test(ToolsInputs.Metric.sleep, 5, from: at(4), to: at(7)),
        ]
        let rest: [HealthReading] = [
            .test(ToolsInputs.Metric.caffeine, 95, at: at(8)),
            .test(ToolsInputs.Metric.caffeine, 63, at: at(13)),
            .test(ToolsInputs.Metric.caffeine, 80, at: at(9, day: -40)),
            .test(ToolsInputs.Metric.daylight, 12, at: at(9)),
            .test(ToolsInputs.Metric.daylight, 20, at: at(12)),
            .test(ToolsInputs.Metric.daylight, 30, at: at(12, day: -1)),
            .test(ToolsInputs.Metric.leanMass, 55, at: at(8, day: -20)),
            .test(ToolsInputs.Metric.leanMass, 56, at: at(8, day: -2)),
            .test(ToolsInputs.Metric.dateOfBirth, 41, at: at(0, day: -900)),
        ]
        let inputs = await ToolsInputs.read(from: ScriptedHealthSource(sleep + rest), now: now, calendar: calendar)
        #expect(inputs.nights.count == 1)
        #expect(inputs.nights.first?.bed == at(23, day: -1))
        #expect(abs((inputs.nights.first?.asleep ?? 0) - 8) < 1e-9)
        #expect(inputs.caffeine.map(\.value).sorted() == [63, 95])
        #expect(inputs.daylightToday == 32)
        #expect(inputs.leanMass?.value == 56)
        #expect(inputs.ageYears == 41)
    }

    @Test("A store that refuses every read leaves every input empty")
    func refusedStore() async {
        let inputs = await ToolsInputs.read(from: ScriptedHealthSource(fails: true), now: now, calendar: calendar)
        #expect(inputs == ToolsInputs(now: now))
        #expect(!inputs.hasNights)
    }
}
