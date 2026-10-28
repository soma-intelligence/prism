//
//  PulseTrendsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

/// The Trends page is arithmetic over what Health returned: which aspect moved
/// most, the month's running total, the longest streak. A fixed calendar and
/// locale keep the words the same on every machine.
@Suite("Pulse trends")
@MainActor
struct PulseTrendsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")

    /// 16 September 2026, a Wednesday, at noon, or a day before or after it.
    func day(_ offset: Int = 0, hour: Int = 12) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func midnight(_ offset: Int) -> Date { calendar.startOfDay(for: day(offset)) }

    // MARK: Moved most

    @Test func movedMostPicksTheLargestShare() {
        let moved = PulseTrends.movedMost([
            .sleep: (now: 7.5, before: 7.0),     // +7%
            .mind: (now: 40, before: 50),         // -20%
            .activity: (now: 33, before: 30),     // +10%
        ])
        #expect(moved?.aspect == .mind)
        #expect(abs((moved?.share ?? 0) + 0.2) < 0.0001)
    }

    @Test func smallChangesReadAsSteady() {
        let moved = PulseTrends.movedMost([
            .sleep: (now: 7.05, before: 7.0),
            .mind: (now: 50.5, before: 50),
        ])
        #expect(moved == nil)
    }

    @Test func tiesGoToThePageOrder() {
        let moved = PulseTrends.movedMost([
            .activity: (now: 11, before: 10),
            .sleep: (now: 11, before: 10),
        ])
        #expect(moved?.aspect == .sleep)
    }

    @Test func headlineNamesTheMoverAndTheOneToWatch() {
        var inputs = PulseTrendsInputs(now: day())
        // HRV: 40 over the last 30 days, 50 over the 30 before.
        for offset in 0..<60 {
            let value: Double = offset < 30 ? 40 : 50
            let at = day(-offset, hour: 3)
            inputs.heartRateVariability.append(HealthReading(
                metric: PulseInputs.Metric.heartRateVariability, value: value, unit: .none, start: at, end: at))
        }
        // Exercise up a little, 33 against 30 minutes.
        for offset in 1...60 {
            inputs.exerciseByDay[midnight(-offset)] = offset <= 30 ? 33 : 30
        }
        let trends = PulseTrends.make(from: inputs, calendar: calendar, locale: locale)
        #expect(trends.headline == "Mind moved most this month.")
        #expect(trends.reason == "Your HRV fell 10 ms against the 30 days before. The other held or rose.")
        #expect(trends.rows.map(\.change) == ["No nights yet", "down 10 ms", "up 3m a day"])
        // The rows' numbers are scores, and none were passed.
        #expect(trends.rows[1].value == nil)
        #expect(trends.rows[0].value == nil)
    }

    @Test func emptyStoreSaysWhatFillsThePage() {
        let trends = PulseTrends.make(from: PulseTrendsInputs(now: day()), calendar: calendar, locale: locale)
        #expect(trends.headline == "Trends need two months of data.")
        #expect(trends.month.total == nil)
        #expect(trends.month.top == nil)
        #expect(trends.year.average == nil)
        #expect(trends.active.count == nil)
        #expect(trends.rows.allSatisfy { $0.value == nil })
    }

    // MARK: Cumulative month

    @Test func cumulativeRunsThroughMissingDays() {
        #expect(PulseTrends.cumulative([1000, nil, 500, 250]) == [1000, 1000, 1500, 1750])
        #expect(PulseTrends.cumulative([]) == [])
    }

    @Test func monthComparesTheSameDayOfLastMonth() {
        var inputs = PulseTrendsInputs(now: day())
        // September 1 to 16: 10,000 a day. August: 9,000 a day.
        for date in 1...16 {
            inputs.stepsByDay[calendar.date(from: DateComponents(year: 2026, month: 9, day: date))!] = 10_000
        }
        for date in 1...31 {
            inputs.stepsByDay[calendar.date(from: DateComponents(year: 2026, month: 8, day: date))!] = 9_000
        }
        let month = PulseTrends.make(from: inputs, calendar: calendar, locale: locale).month
        #expect(month.eyebrow == "September so far")
        #expect(month.total == "160,000")
        #expect(month.note == "16,000 ahead of August on the same day.")
        #expect(month.thisMonth.count == 16)
        #expect(month.lastMonth.count == 30)
        #expect(month.days == 30)
        #expect(month.top == 300_000)
    }

    @Test func niceTopAndAxisLabels() {
        #expect(PulseTrends.niceTop(270_000) == 300_000)
        #expect(PulseTrends.niceTop(129_412) == 200_000)
        #expect(PulseTrends.niceTop(0) == nil)
        #expect(PulseTrends.axisLabel(300_000) == "300k")
        #expect(PulseTrends.axisLabel(1_500) == "1.5k")
        #expect(PulseTrends.axisLabel(800) == "800")
    }

    // MARK: Streaks

    @Test func longestStreakFindsTheLongestRun() {
        var days: [Date: Double] = [:]
        for offset in [-20, -19, -18, -10, -9, -8, -7, -6, -2] { days[midnight(offset)] = 45 }
        days[midnight(-5)] = 10   // under the half hour: breaks the run
        let streak = PulseTrends.longestStreak(days, calendar: calendar)
        #expect(streak?.length == 5)
        #expect(streak?.start == midnight(-10))
        #expect(streak?.end == midnight(-6))
        #expect(PulseTrends.activeDays(days) == 9)
    }

    @Test func noActiveDayHasNoStreak() {
        #expect(PulseTrends.longestStreak([midnight(0): 12], calendar: calendar) == nil)
        #expect(PulseTrends.longestStreak([:], calendar: calendar) == nil)
    }

    @Test func activeDaysCardCountsThisYearOnly() {
        var inputs = PulseTrendsInputs(now: day())
        inputs.exerciseByDay[calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!] = 60
        for date in 1...23 {
            inputs.exerciseByDay[calendar.date(from: DateComponents(year: 2026, month: 6, day: date))!] = 40
        }
        let active = PulseTrends.make(from: inputs, calendar: calendar, locale: locale).active
        #expect(active.count == "23")
        #expect(active.note == "Longest streak: 23 days, in June.")
        #expect(active.grid.months.first?.label == "Jan")
        #expect(active.grid.months.count == 9)
        // 16 September 2026 is a Wednesday: the third row, Monday first.
        #expect(active.grid.todayRow == 2)
        #expect(active.grid.weeks.allSatisfy { $0.count == 7 })
        // 1 January 2026 is a Thursday: the first column opens on Monday
        // 29 December, and the three days before the year are not drawn.
        #expect(Array(active.grid.weeks[0].prefix(4)) == [.outside, .outside, .outside, .missing])
        #expect(active.streakColumns != nil)
    }

    // MARK: Explore

    @Test func exploreReasonsUseRealNumbers() {
        var inputs = PulseExploreInputs(now: day())
        for offset in 0..<14 {
            let at = day(-offset, hour: 3)
            inputs.heartRateVariability.append(HealthReading(
                metric: PulseInputs.Metric.heartRateVariability, value: offset < 7 ? 44 : 50, unit: .none, start: at, end: at))
        }
        let week = PulseExploreWeek.make(from: inputs, calendar: calendar, locale: locale)
        #expect(week.suggestions[0].reason == "Your HRV dipped to 44 this week.")
        #expect(week.suggestions[1].reason == "Why the first hours of the night matter most.")

        let empty = PulseExploreWeek.make(from: PulseExploreInputs(now: day()), calendar: calendar, locale: locale)
        #expect(empty.suggestions[0].reason == "What the number means, and why it swings.")
    }

    // MARK: Environment

    @Test func environmentUsualNeedsAWeek() {
        #expect(EnvironmentReport.usual([60, 70, 80], roundedTo: 5) == nil)
        #expect(EnvironmentReport.usual([40, 50, 70, 80, 90, 100, 120, 130], roundedTo: 5) == 70...120)
        #expect(EnvironmentReport.roundedUp(22, to: 5) == 25)
        #expect(EnvironmentReport.spelled(20) == "Twenty")
        #expect(EnvironmentReport.loudness(62) == "quiet")
        #expect(EnvironmentReport.loudness(85) == "loud")
    }

    @Test func environmentLeadNamesLowDaylight() {
        var inputs = EnvironmentInputs(now: day())
        inputs.daylightByDay[midnight(0)] = 48
        for offset in 1...30 { inputs.daylightByDay[midnight(-offset)] = offset % 2 == 0 ? 70 : 120 }
        let report = EnvironmentReport.make(from: inputs, calendar: calendar, locale: locale)
        #expect(report.headline == "Not much light today.")
        #expect(report.isDaylightLow)
        #expect(report.reason == "You got 48 minutes of daylight so far, against a usual 70 to 120. Twenty five more minutes outside would help tonight’s sleep.")
        #expect(report.daysOutside == "31")
    }

    @Test func environmentEmptyIsHonest() {
        let report = EnvironmentReport.make(from: EnvironmentInputs(now: day()), calendar: calendar, locale: locale)
        #expect(report.headline == "Nothing measured around you yet.")
        #expect(report.daylight == nil)
        #expect(report.sound == nil)
        #expect(report.daysOutside == nil)
    }
}
