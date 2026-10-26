//
//  EnvironmentInputsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Environment lens and the Around you card read daylight, sound and UV
/// out of Apple Health in one go. Daylight is totalled per day, over a month
/// for the card and over the whole year for the lens's grid.
@Suite("Environment inputs")
@MainActor
struct EnvironmentInputsTests {
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

    func midnight(_ day: Int) -> Date { calendar.startOfDay(for: at(12, day: day)) }

    var now: Date { at(15) }

    typealias Metric = EnvironmentInputs.Metric

    var readings: [HealthReading] {
        [
            .test(Metric.daylight, 10, at: at(9)),
            .test(Metric.daylight, 20, at: at(12)),
            .test(Metric.daylight, 30, at: at(12, day: -1)),
            .test(Metric.daylight, 15, at: at(12, day: -40)),
            .test(Metric.sound, 62, at: at(10, day: -5)),
            .test(Metric.sound, 70, at: at(10, day: -40)),
            .test(Metric.headphones, 78, at: at(18, day: -2)),
            .test(Metric.uv, 4, at: at(13)),
        ]
    }

    @Test("Every type the lens reads is one the Health catalog knows")
    func metricsAreInTheCatalog() {
        for identifier in EnvironmentInputs.metrics {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    @Test("For the card: today's stretches outside, a month of daily totals, a month of sound")
    func month() async {
        let inputs = await EnvironmentInputs.read(from: ScriptedHealthSource(readings), now: now, calendar: calendar, wholeYear: false)
        #expect(inputs.daylightToday.map(\.value).sorted() == [10, 20])
        #expect(inputs.daylightByDay == [midnight(0): 30, midnight(-1): 30])
        #expect(inputs.sound.map(\.value) == [62])
        #expect(inputs.headphones.map(\.value) == [78])
        #expect(inputs.uv.map(\.value) == [4])
        #expect(!inputs.isEmpty)
    }

    @Test("For the lens: daylight totals reach back to the first of January")
    func wholeYear() async {
        let inputs = await EnvironmentInputs.read(from: ScriptedHealthSource(readings), now: now, calendar: calendar, wholeYear: true)
        #expect(inputs.daylightByDay[midnight(-40)] == 15)
        #expect(inputs.daylightByDay.count == 3)
        #expect(inputs.sound.map(\.value) == [62])
    }

    @Test("A store that refuses every read leaves the lens empty")
    func refusedStore() async {
        let inputs = await EnvironmentInputs.read(from: ScriptedHealthSource(readings, fails: true), now: now, calendar: calendar, wholeYear: true)
        #expect(inputs.isEmpty)
    }
}
