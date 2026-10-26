//
//  HealthDailyTotalsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Steps, exercise and daylight are charted one total a day, all through one
/// reader. Each day must hold what started on it, today must stop at now, and
/// a day the store holds nothing for must be missing rather than zero, or a
/// chart would draw a day without a step that the person never recorded.
@Suite("Health daily totals")
@MainActor
struct HealthDailyTotalsTests {
    let steps = "HKQuantityTypeIdentifierStepCount"

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    var now: Date { at(15) }

    var source: ScriptedHealthSource {
        ScriptedHealthSource([
            .test(steps, 1_200, at: at(8)),
            .test(steps, 800, at: at(13)),
            .test(steps, 700, at: at(18)),
            .test(steps, 5_000, at: at(10, day: -2)),
            .test(steps, 9_000, at: at(10, day: -3)),
        ])
    }

    @Test("Each day lands on its own midnight, today stops at now, and a day without readings is absent")
    func fromStart() async {
        let totals = await HealthDailyTotals.read(steps, from: at(9, day: -2), now: now, source: source, calendar: calendar)
        #expect(totals == [at(0): 2_000, at(0, day: -2): 5_000])
    }

    @Test("A count of days ends today and reaches back no further")
    func lastDays() async {
        let three = await HealthDailyTotals.read(steps, days: 3, now: now, source: source, calendar: calendar)
        #expect(three == [at(0): 2_000, at(0, day: -2): 5_000])

        let four = await HealthDailyTotals.read(steps, days: 4, now: now, source: source, calendar: calendar)
        #expect(four[at(0, day: -3)] == 9_000)

        let none = await HealthDailyTotals.read(steps, days: 0, now: now, source: source, calendar: calendar)
        #expect(none.isEmpty)
    }

    @Test("A metric outside the catalog, or a store that refuses, gives no days")
    func nothingToRead() async {
        let unknown = await HealthDailyTotals.read("HKQuantityTypeIdentifierNothing", days: 3, now: now,
                                                   source: source, calendar: calendar)
        let refused = await HealthDailyTotals.read(steps, days: 3, now: now,
                                                   source: ScriptedHealthSource([.test(steps, 1, at: at(8))], fails: true),
                                                   calendar: calendar)
        #expect(unknown.isEmpty)
        #expect(refused.isEmpty)
    }
}
