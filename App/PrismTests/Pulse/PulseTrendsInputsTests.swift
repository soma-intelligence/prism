//
//  PulseTrendsInputsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Trends page reads a year of sleep, two months of HRV and daily totals of
/// steps and exercise. Each window has its own start, and a day Health holds
/// nothing for is absent rather than zero.
@Suite("Pulse trends inputs")
@MainActor
struct PulseTrendsInputsTests {
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

    func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func midnight(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    typealias Metric = PulseInputs.Metric

    @Test("Every type the page reads is one the Health catalog knows")
    func metricsAreInTheCatalog() {
        for identifier in PulseTrendsInputs.metrics {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    @Test("Steps from the first of last month, exercise from January, HRV for sixty days, sleep for a year")
    func windows() async {
        let readings: [HealthReading] = [
            .test(Metric.steps, 3_000, at: at(9)),
            .test(Metric.steps, 2_000, at: at(13)),
            .test(Metric.steps, 1_000, at: date(9, 1)),
            .test(Metric.steps, 500, at: date(8, 31)),
            .test(Metric.exercise, 30, at: date(1, 2)),
            .test(Metric.heartRateVariability, 50, at: at(7, day: -59)),
            .test(Metric.heartRateVariability, 40, at: at(7, day: -61)),
            .test(Metric.sleep, 3, from: at(23, day: -300), to: at(7, day: -299)),
            .test(Metric.sleep, 3, from: at(23, day: -400), to: at(7, day: -399)),
        ]
        let inputs = await PulseTrendsInputs.read(from: ScriptedHealthSource(readings), now: at(15), calendar: calendar)
        #expect(inputs.stepsByDay == [midnight(at(15)): 5_000, midnight(date(9, 1)): 1_000])
        #expect(inputs.exerciseByDay == [midnight(date(1, 2)): 30])
        #expect(inputs.heartRateVariability.map(\.value) == [50])
        #expect(inputs.sleep.count == 1)
        #expect(!inputs.isEmpty)
    }

    @Test("A store that refuses every read leaves the page empty")
    func refusedStore() async {
        let inputs = await PulseTrendsInputs.read(from: ScriptedHealthSource(fails: true), now: at(15), calendar: calendar)
        #expect(inputs.isEmpty)
    }
}
