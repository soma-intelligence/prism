//
//  BodyPartsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

/// The Body tab's parts are arithmetic over what Health returned: trends
/// against eight weeks ago, heart rate zones and sessions counted by week. A
/// fixed calendar and locale keep every date and number the same on every
/// machine.
@Suite("Body parts")
@MainActor
struct BodyPartsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()
    let locale = Locale(identifier: "en_US")

    /// Tuesday 29 September 2026 at noon.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))! }

    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func reading(_ metric: String, _ value: Double, at date: Date, lasting seconds: TimeInterval = 0) -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .none, start: date, end: date.addingTimeInterval(seconds))
    }

    func workout(_ type: Int, at date: Date, minutes: Double = 40) -> HealthReading {
        reading(BodyMetric.workout, Double(type), at: date, lasting: minutes * 60)
    }

    // MARK: - Trends

    @Test("A change compares the latest reading with the newest one at least eight weeks old")
    func changeAgainstEightWeeks() {
        let readings = [
            reading(BodyMetric.leanBodyMass, 51.0, at: daysAgo(80)),
            reading(BodyMetric.leanBodyMass, 52.1, at: daysAgo(60)),
            reading(BodyMetric.leanBodyMass, 53.0, at: daysAgo(30)),
            reading(BodyMetric.leanBodyMass, 53.6, at: daysAgo(1)),
        ]
        let change = BodyMath.change(readings, now: now, calendar: calendar)
        #expect(change?.latest == 53.6)
        #expect(change?.earlier == 52.1)
        #expect(abs((change?.delta ?? 0) - 1.5) < 0.0001)
    }

    @Test("Without a reading eight weeks old there is a value but no trend")
    func changeWithoutHistory() {
        let readings = [reading(BodyMetric.vo2Max, 44, at: daysAgo(3))]
        let change = BodyMath.change(readings, now: now, calendar: calendar)
        #expect(change?.latest == 44)
        #expect(change?.delta == nil)
        #expect(BodyMath.trend(change?.delta, tolerance: 0.5) == nil)
        #expect(BodyMath.change([], now: now, calendar: calendar) == nil)
    }

    @Test("A change smaller than the tolerance holds steady")
    func trendTolerance() {
        #expect(BodyMath.trend(1.5, tolerance: 0.1) == .up)
        #expect(BodyMath.trend(-0.4, tolerance: 0.1) == .down)
        #expect(BodyMath.trend(0.05, tolerance: 0.1) == nil)
    }

    @Test("The Overview says what fills it when Health has nothing")
    func overviewEmpty() {
        let page = BodyOverview.make(from: BodyOverviewInputs(now: now), calendar: calendar, locale: locale)
        #expect(page.leanMass == nil)
        #expect(page.vo2Max == nil)
        #expect(page.headline == "Your body composition.")
    }

    @Test("The Overview headline follows lean mass when it moved")
    func overviewLeanHeadline() {
        let inputs = BodyOverviewInputs(
            now: now,
            leanMass: [reading(BodyMetric.leanBodyMass, 52.1, at: daysAgo(60)), reading(BodyMetric.leanBodyMass, 53.6, at: daysAgo(1))],
            vo2Max: [reading(BodyMetric.vo2Max, 41, at: daysAgo(70)), reading(BodyMetric.vo2Max, 44, at: daysAgo(2))],
            age: 46
        )
        let page = BodyOverview.make(from: inputs, calendar: calendar, locale: locale)
        #expect(page.leanMass == "53.6")
        #expect(page.leanTrend == .up)
        #expect(page.vo2Max == "44")
        #expect(page.vo2Trend == .up)
        #expect(page.reason.hasPrefix("Lean mass rose 1.5 kg in eight weeks, to 53.6 kg."))
    }

    // MARK: - Zones

    @Test("Zones are cut from 220 less the age")
    func zoneBounds() {
        #expect(BodyMath.maxHeartRate(age: 40) == 180)
        #expect(BodyMath.maxHeartRate(age: nil) == nil)
        #expect(BodyMath.zone(for: 89, maxHeartRate: 180) == nil)
        #expect(BodyMath.zone(for: 90, maxHeartRate: 180) == .one)
        #expect(BodyMath.zone(for: 115, maxHeartRate: 180) == .two)
        #expect(BodyMath.zone(for: 130, maxHeartRate: 180) == .three)
        #expect(BodyMath.zone(for: 150, maxHeartRate: 180) == .four)
        #expect(BodyMath.zone(for: 175, maxHeartRate: 180) == .five)
    }

    @Test("Each sample holds until the next, capped at a minute, inside its workout only")
    func zoneMinutes() {
        let start = daysAgo(1)
        let session = workout(37, at: start, minutes: 10)
        let heart = [
            reading(BodyMetric.heartRate, 115, at: start),                          // zone 2, 60 s to the next
            reading(BodyMetric.heartRate, 115, at: start.addingTimeInterval(60)),   // zone 2, gap of 5 min capped at 60 s
            reading(BodyMetric.heartRate, 150, at: start.addingTimeInterval(360)),  // zone 4, 4 min to the end, capped at 60 s
            reading(BodyMetric.heartRate, 150, at: start.addingTimeInterval(900)),  // after the workout, ignored
        ]
        let minutes = BodyMath.zoneMinutes(heartRate: heart, workouts: [session], maxHeartRate: 180)
        #expect(minutes[.two] == 2)
        #expect(minutes[.four] == 1)
        #expect(minutes[.one] == nil)
    }

    @Test("The usual zone 2 span is the least and the most over weeks that held a workout")
    func usualZoneTwo() {
        func week(_ daysBack: Double, zoneTwoMinutes: Int) -> (HealthReading, [HealthReading]) {
            let start = daysAgo(daysBack)
            let session = workout(37, at: start, minutes: Double(zoneTwoMinutes) + 1)
            let heart = (0...zoneTwoMinutes).map { reading(BodyMetric.heartRate, 115, at: start.addingTimeInterval(Double($0) * 60)) }
            return (session, heart)
        }
        let weeks = [week(10, zoneTwoMinutes: 30), week(17, zoneTwoMinutes: 50), week(24, zoneTwoMinutes: 40)]
        let usual = BodyMath.usualZoneTwo(
            heartRate: weeks.flatMap(\.1), workouts: weeks.map(\.0), maxHeartRate: 180, now: now
        )
        #expect(usual == 31...51)

        let single = BodyMath.usualZoneTwo(heartRate: weeks[0].1, workouts: [weeks[0].0], maxHeartRate: 180, now: now)
        #expect(single == nil)
    }

    @Test("Cardio zones say what fills them without an age")
    func cardioZonesWithoutAge() {
        let inputs = BodyCardioInputs(
            now: now,
            workouts: [workout(37, at: daysAgo(1))],
            workoutHeartRate: [reading(BodyMetric.heartRate, 130, at: daysAgo(1))]
        )
        let page = BodyCardio.make(from: inputs, calendar: calendar, locale: locale)
        #expect(page.zones.minutes == nil)
        #expect(page.zones.zoneTwo == nil)
        #expect(page.zones.value(.two) == nil)
    }

    @Test("A run reads its distance, time and pace")
    func runSummary() {
        let start = daysAgo(1)
        let run = workout(37, at: start, minutes: 50)
        let inputs = BodyCardioInputs(now: now, workouts: [run], runDistance: 10_000, age: 40)
        let summary = BodyCardio.make(from: inputs, calendar: calendar, locale: locale).run
        #expect(summary?.title == "Run")
        #expect(summary?.distance == "10.0")
        #expect(summary?.duration == "50:00")
        #expect(summary?.note.hasPrefix("Average 5:00 a km.") == true)
        #expect(BodyMath.clock(3912) == "1:05:12")
    }

    // MARK: - Sessions

    @Test("Sessions count by calendar week, the last one the week in progress")
    func weeklyCounts() {
        let workouts = [
            workout(50, at: daysAgo(0.5)),   // this week (Monday 28 September onwards)
            workout(20, at: daysAgo(3)),     // last week
            workout(50, at: daysAgo(4)),     // last week
            workout(37, at: daysAgo(5)),     // a run, not counted
            workout(50, at: daysAgo(48)),    // eight weeks back, the first column
            workout(50, at: daysAgo(70)),    // before the window
        ]
        let counts = BodyMath.weeklyCounts(workouts, types: BodyStrength.strengthTypes, now: now, calendar: calendar)
        #expect(counts == [1, 0, 0, 0, 0, 0, 2, 1])
    }

    @Test("The weekly average leaves out the week in progress")
    func averagePerWeek() {
        #expect(BodyMath.averagePerWeek([2, 2, 1, 2, 3, 2, 2, 9]) == 2)
        #expect(BodyMath.averagePerWeek([1]) == nil)
        #expect(BodyMath.formatCount(2.0, locale: locale) == "2")
        #expect(BodyMath.formatCount(10.0 / 7, locale: locale) == "1.4")
    }

    @Test("No workouts at all is a dash, not zero sessions")
    func sessionsWithoutWorkouts() {
        let empty = BodyStrength.make(from: BodyStrengthInputs(now: now), calendar: calendar, locale: locale)
        #expect(empty.sessionsPerWeek == nil)
        #expect(empty.weeks.isEmpty)

        let runsOnly = BodyStrength.make(
            from: BodyStrengthInputs(now: now, workouts: [workout(37, at: daysAgo(10))]),
            calendar: calendar, locale: locale
        )
        #expect(runsOnly.sessionsPerWeek == "0")
        #expect(runsOnly.headline == "No strength work yet.")
    }
}
