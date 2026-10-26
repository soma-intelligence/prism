//
//  EnvironmentWeekTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Environment lens's week is arithmetic over what Health and Open-Meteo
/// returned: daylight against its target, loud days, the headphone dose the
/// WHO sets, the UV and air of seven days, and today's pollen. A fixed
/// calendar keeps the days the same on every machine.
@Suite("Environment week")
struct EnvironmentWeekTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 16 September 2026, a Wednesday, or a day before it, at `hour`.
    func day(_ offset: Int = 0, hour: Int = 12) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func midnight(_ offset: Int) -> Date { calendar.startOfDay(for: day(offset)) }

    func reading(_ metric: String, _ value: Double, at start: Date, hours: Double) -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .none, start: start, end: start.addingTimeInterval(hours * 3600))
    }

    // MARK: Headphones

    /// WHO-ITU H.870: 80 dBA for 40 hours a week is the whole allowance, and
    /// every 3 dB more halves the time.
    @Test func whoHeadphoneDose() {
        var inputs = EnvironmentInputs(now: day())
        inputs.headphones = (0..<5).map { reading(EnvironmentInputs.Metric.headphones, 80, at: day(-$0, hour: 8), hours: 8) }
        let week = EnvironmentWeek.make(inputs: [inputs], now: day(), calendar: calendar)
        #expect(abs((week.headphoneDoseShare ?? 0) - 1) < 0.0001)

        var louder = EnvironmentInputs(now: day())
        louder.headphones = [reading(EnvironmentInputs.Metric.headphones, 83, at: day(-1, hour: 8), hours: 20)]
        #expect(abs((EnvironmentWeek.make(inputs: [louder], now: day(), calendar: calendar).headphoneDoseShare ?? 0) - 1) < 0.01)

        // Listening older than the week does not count, and no listening is a
        // dash, not 0 %.
        var old = EnvironmentInputs(now: day())
        old.headphones = [reading(EnvironmentInputs.Metric.headphones, 90, at: day(-9, hour: 8), hours: 10)]
        #expect(EnvironmentWeek.make(inputs: [old], now: day(), calendar: calendar).headphoneDoseShare == nil)
        #expect(EnvironmentWeek.make(inputs: [EnvironmentInputs(now: day())], now: day(), calendar: calendar).headphoneDoseShare == nil)
    }

    @Test func loudDaysCountTheDaysThatReached80() {
        var inputs = EnvironmentInputs(now: day())
        inputs.sound = [
            reading(EnvironmentInputs.Metric.sound, 82, at: day(0, hour: 9), hours: 0.5),
            reading(EnvironmentInputs.Metric.sound, 60, at: day(0, hour: 10), hours: 0.5),
            reading(EnvironmentInputs.Metric.sound, 79, at: day(-1, hour: 9), hours: 0.5),
            reading(EnvironmentInputs.Metric.sound, 85, at: day(-3, hour: 9), hours: 0.5),
            reading(EnvironmentInputs.Metric.sound, 95, at: day(-8, hour: 9), hours: 0.5),
        ]
        let week = EnvironmentWeek.make(inputs: [inputs], now: day(), calendar: calendar)
        #expect(week.loudDays == 2)
        #expect(EnvironmentWeek.make(inputs: [EnvironmentInputs(now: day())], now: day(), calendar: calendar).loudDays == nil)
    }

    // MARK: Daylight

    @Test func daylightTarget() {
        #expect(EnvironmentWeek.daylightTarget == 30...120)
        var inputs = EnvironmentInputs(now: day())
        inputs.daylightByDay = [midnight(-6): 10, midnight(-5): 30, midnight(-4): 60, midnight(-3): 150, midnight(-9): 200]
        inputs.daylightToday = [reading(EnvironmentInputs.Metric.daylight, 45, at: day(0, hour: 9), hours: 0.75)]
        let week = EnvironmentWeek.make(inputs: [inputs], now: day(), calendar: calendar)

        // Seven days, oldest first, today last; a day with nothing is nil.
        #expect(week.daylightMinutes == [10, 30, 60, 150, nil, nil, 45])
        #expect(week.daylightDaysReached == 4)
        #expect(week.daylightTotal == 295)
        #expect(EnvironmentWeek.make(inputs: [EnvironmentInputs(now: day())], now: day(), calendar: calendar).daylightTotal == nil)
    }

    /// Several reads fold into one week, one per day as a test writes them.
    @Test func readsFoldTogether() {
        var first = EnvironmentInputs(now: day())
        first.daylightByDay = [midnight(-1): 40]
        var second = EnvironmentInputs(now: day())
        second.daylightByDay = [midnight(-2): 20]
        let week = EnvironmentWeek.make(inputs: [first, second], now: day(), calendar: calendar)
        #expect(week.daylightMinutes.suffix(3) == [20, 40, nil])
    }

    // MARK: UV and air

    @Test func uvAndAirOverTheWeek() {
        var inputs = EnvironmentInputs(now: day())
        inputs.uv = [
            reading(EnvironmentInputs.Metric.uv, 3, at: day(0, hour: 11), hours: 0),
            reading(EnvironmentInputs.Metric.uv, 5, at: day(0, hour: 10), hours: 0),
            reading(EnvironmentInputs.Metric.uv, 4, at: day(-2, hour: 13), hours: 0),
        ]
        var outside = EnvironmentConditions()
        outside.aqiDays = [300, 20, 40, 120, 60, 150, 30, 45]
        let week = EnvironmentWeek.make(inputs: [inputs], outside: outside, now: day(), calendar: calendar)
        #expect(week.uvTotal == 9)
        #expect(week.unhealthyAirDays == 2)
        #expect(week.airPeak == 150)

        // Without UV in Health the forecast's daily peaks stand in.
        var forecast = EnvironmentConditions()
        forecast.uvDays = [9, 1, 2, 3, 4, 5, 6, 7]
        #expect(EnvironmentWeek.make(inputs: [EnvironmentInputs(now: day())], outside: forecast, now: day(), calendar: calendar).uvTotal == 28)
    }

    // MARK: Pollen

    /// The National Allergy Bureau's counts, grains per cubic metre, read
    /// per group: trees, grass and weeds each have their own steps.
    @Test func pollenLevels() {
        #expect(PollenLevel.level(.grass, grains: 0) == PollenLevel.none)
        #expect(PollenLevel.level(.grass, grains: 3) == .low)
        #expect(PollenLevel.level(.grass, grains: 5) == .moderate)
        #expect(PollenLevel.level(.grass, grains: 20) == .high)
        #expect(PollenLevel.level(.grass, grains: 200) == .veryHigh)
        #expect(PollenLevel.level(.birch, grains: 14) == .low)
        #expect(PollenLevel.level(.birch, grains: 89) == .moderate)
        #expect(PollenLevel.level(.olive, grains: 90) == .high)
        #expect(PollenLevel.level(.alder, grains: 1500) == .veryHigh)
        #expect(PollenLevel.level(.ragweed, grains: 10) == .moderate)
        #expect(PollenLevel.level(.mugwort, grains: 50) == .high)

        var outside = EnvironmentConditions()
        outside.pollen = [.grass: 12, .birch: 120, .ragweed: 0]
        let peak = EnvironmentWeek.make(inputs: [EnvironmentInputs(now: day())], outside: outside, now: day(), calendar: calendar).pollenPeak
        #expect(peak?.kind == .birch)
        #expect(peak?.level == .high)
        #expect(peak?.grains == 120)
    }

    /// No place, no forecast, no pollen: a dash and a sentence, never "none".
    @Test func noLocationNoPollen() {
        let week = EnvironmentWeek.make(inputs: [EnvironmentInputs(now: day())], outside: nil, now: day(), calendar: calendar)
        #expect(week.pollenPeak == nil)
        #expect(week.unhealthyAirDays == nil)

        // A place outside the forecast's map returns nulls: still no pollen.
        let parsed = EnvironmentWeatherClient.parse(forecast: nil, air: [
            "hourly": ["time": ["2026-09-16T09:00"], "us_aqi": [40], "grass_pollen": [NSNull()], "birch_pollen": [NSNull()]],
        ])
        #expect(parsed.pollen == nil)
        #expect(EnvironmentWeek.make(inputs: [EnvironmentInputs(now: day())], outside: parsed, now: day(), calendar: calendar).pollenPeak == nil)
    }

    /// Today's pollen is the highest hour of the last day the service sent.
    @Test func pollenParsedFromTheLastDay() {
        let parsed = EnvironmentWeatherClient.parse(forecast: nil, air: [
            "hourly": [
                "time": ["2026-09-15T12:00", "2026-09-16T08:00", "2026-09-16T14:00"],
                "us_aqi": [40, 30, 35],
                "grass_pollen": [300, 8, 25],
                "birch_pollen": [0, 0, 1],
                "olive_pollen": [NSNull(), NSNull(), NSNull()],
            ],
        ])
        #expect(parsed.pollen?[.grass] == 25)
        #expect(parsed.pollen?[.birch] == 1)
        #expect(parsed.pollen?[.olive] == nil)
    }

    // MARK: Pollen alert

    /// Opt in only, in the morning only, high pollen only, once a day.
    @Test func pollenAlertInTheMorningWhenOptedIn() {
        let high = PollenPeak(kind: .grass, grains: 60, level: .high)
        var schedule = NotificationSchedule()
        #expect(schedule.pollenAlerts == false)
        #expect(DataAlertRules.pollenMorning(peak: high, schedule: schedule, prefs: NotificationPreferences(), now: day(0, hour: 8), calendar: calendar) == nil)

        schedule.pollenAlerts = true
        let alert = DataAlertRules.pollenMorning(peak: high, schedule: schedule, prefs: NotificationPreferences(), now: day(0, hour: 8), calendar: calendar)
        #expect(alert?.kind == .dataAlert)
        #expect(alert.map { SomaNotificationKind.kind(forIdentifier: $0.id) } == .dataAlert)
        let again = DataAlertRules.pollenMorning(peak: high, schedule: schedule, prefs: NotificationPreferences(), now: day(0, hour: 10), calendar: calendar)
        #expect(again?.id == alert?.id)
        let tomorrow = DataAlertRules.pollenMorning(peak: high, schedule: schedule, prefs: NotificationPreferences(), now: day(1, hour: 8), calendar: calendar)
        #expect(tomorrow?.id != alert?.id)

        #expect(DataAlertRules.pollenMorning(peak: high, schedule: schedule, prefs: NotificationPreferences(), now: day(0, hour: 15), calendar: calendar) == nil)
        let moderate = PollenPeak(kind: .grass, grains: 10, level: .moderate)
        #expect(DataAlertRules.pollenMorning(peak: moderate, schedule: schedule, prefs: NotificationPreferences(), now: day(0, hour: 8), calendar: calendar) == nil)
        #expect(DataAlertRules.pollenMorning(peak: nil, schedule: schedule, prefs: NotificationPreferences(), now: day(0, hour: 8), calendar: calendar) == nil)
    }

    @Test func pollenSwitchDecodesFromAnOlderFile() throws {
        let old = try JSONDecoder().decode(NotificationSchedule.self, from: Data(#"{"dataAlerts":false}"#.utf8))
        #expect(old.pollenAlerts == false)
        var on = NotificationSchedule()
        on.pollenAlerts = true
        let back = try JSONDecoder().decode(NotificationSchedule.self, from: JSONEncoder().encode(on))
        #expect(back.pollenAlerts)
    }
}
