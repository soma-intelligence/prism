//
//  GlucoseMetricsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// A continuous monitor's fortnight read the way the 2019 international
/// consensus reads it: the shares of time in each range, the mean, GMI and
/// the variation, what a meal did over the two hours after it, and the
/// difference between a monitor and a few finger sticks.
@Suite("Glucose metrics")
struct GlucoseMetricsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func reading(_ value: Double, _ date: Date) -> HealthReading {
        HealthReading(metric: LabMetric.glucose, value: value, unit: .milligramPerDecilitre, start: date, end: date,
                      source: "Dexcom")
    }

    /// One reading every five minutes from `start`, a value each.
    func trace(_ values: [Double], from start: Date) -> [HealthReading] {
        values.enumerated().map { reading($0.element, start.addingTimeInterval(Double($0.offset) * 300)) }
    }

    @Test("Time in each range is the share of readings in it, below 70 counting below 54")
    func timeInRangeShares() throws {
        let values = Array(repeating: 120.0, count: 70) + Array(repeating: 60, count: 3) + [50]
            + Array(repeating: 200, count: 20) + Array(repeating: 260, count: 6)
        let summary = GlucoseSummary.make(samples: trace(values, from: at(0)), meals: [], unit: .milligrams,
                                          now: at(23), calendar: calendar)
        #expect(summary.isContinuous)
        #expect(abs(try #require(summary.timeInRange) - 0.70) < 1e-9)
        #expect(abs(try #require(summary.timeBelow70) - 0.04) < 1e-9)
        #expect(abs(try #require(summary.timeBelow54) - 0.01) < 1e-9)
        #expect(abs(try #require(summary.timeAbove180) - 0.26) < 1e-9)
        #expect(abs(try #require(summary.timeAbove250) - 0.06) < 1e-9)
    }

    @Test("GMI is 3.31 plus 0.02392 times the mean: 154 mg/dL reads 7.0 %")
    func gmiFormula() throws {
        // Alternating 134 and 174 averages 154 with a standard deviation of 20.
        let values = (0..<288).map { $0 % 2 == 0 ? 134.0 : 174.0 }
        let summary = GlucoseSummary.make(samples: trace(values, from: at(0)), meals: [], unit: .milligrams,
                                          now: at(0, day: 1), calendar: calendar)
        #expect(abs(try #require(summary.averageMilligrams) - 154) < 1e-9)
        #expect(abs(try #require(summary.gmi) - 7.0) < 0.05)
        let cv = try #require(summary.cv)
        #expect(abs(cv - 20.0 / 154 * 100) < 0.2)
    }

    @Test("mmol/L converts at the read, and the page's numbers follow the setting")
    func mmolConversion() throws {
        let values = Array(repeating: 180.0, count: 48)
        let samples = trace(values, from: at(8))
        let mg = GlucoseSummary.make(samples: samples, meals: [], unit: .milligrams, now: at(23), calendar: calendar)
        let mmol = GlucoseSummary.make(samples: samples, meals: [], unit: .millimoles, now: at(23), calendar: calendar)
        #expect(abs(try #require(mg.average) - 180) < 1e-9)
        #expect(abs(try #require(mmol.average) - 180 / 18.016) < 1e-6)
        #expect(GlucoseUnit.millimoles.text(milligrams: 180) == "10.0")
        #expect(GlucoseUnit.millimoles.text(milligrams: 70) == "3.9")
        #expect(GlucoseUnit.millimoles.text(milligrams: 54) == "3.0")
        #expect(GlucoseUnit.milligrams.text(milligrams: 70) == "70")
        #expect(GlucoseUnit.millimoles.text(milligrams: nil) == "-")
        // The time shares do not depend on the unit they are shown in.
        #expect(mg.timeInRange == mmol.timeInRange)
        #expect(mg.gmi == mmol.gmi)
    }

    @Test("Three finger sticks a day are not a monitor: no time in range, no CGM page")
    func sparseFingerSticksNotCGM() {
        var samples: [HealthReading] = []
        for day in 0..<14 {
            samples += [reading(95, at(7, day: -day)), reading(140, at(13, day: -day)), reading(120, at(20, day: -day))]
        }
        let summary = GlucoseSummary.make(samples: samples, meals: [], unit: .milligrams, now: at(22), calendar: calendar)
        #expect(!summary.isContinuous)
        #expect(summary.timeInRange == nil)
        #expect(summary.gmi == nil)
        #expect(summary.cv == nil)
        #expect(summary.profile.isEmpty)

        // A monitor's trace with a few finger sticks beside it still reads as a monitor.
        let monitor = trace(Array(repeating: 110, count: 288), from: at(0, day: -1)) + samples.prefix(6)
        #expect(GlucoseSummary.make(samples: monitor, meals: [], unit: .milligrams, now: at(22), calendar: calendar).isContinuous)
    }

    @Test("Nothing in Health: every number is missing, nothing reads as zero")
    func emptyState() {
        let summary = GlucoseSummary.make(samples: [], meals: [], unit: .milligrams, now: at(12), calendar: calendar)
        #expect(!summary.isContinuous)
        #expect(summary.average == nil)
        #expect(summary.timeInRange == nil)
        #expect(summary.urgentNote == nil)
        #expect(summary.meals.isEmpty)
    }

    @Test("A reading under 54 brings the urgent note, in the person's unit, with or without a monitor")
    func below54IsUrgentNote() throws {
        let calm = GlucoseSummary.make(samples: trace(Array(repeating: 110, count: 60), from: at(8)), meals: [],
                                       unit: .milligrams, now: at(23), calendar: calendar)
        #expect(calm.urgentNote == nil)

        var values = Array(repeating: 110.0, count: 60)
        values[30] = 50
        let low = GlucoseSummary.make(samples: trace(values, from: at(8)), meals: [], unit: .milligrams,
                                      now: at(23), calendar: calendar)
        let note = try #require(low.urgentNote)
        #expect(note.contains("54 mg/dL"))
        #expect(note.contains("doctor"))

        // The latest reading, minutes old, under 54: what to do now comes first.
        let now = GlucoseSummary.make(samples: [reading(110, at(11)), reading(48, at(11, 55))], meals: [],
                                      unit: .millimoles, now: at(12), calendar: calendar)
        let urgent = try #require(now.urgentNote)
        #expect(urgent.contains("3.0 mmol/L"))
        #expect(urgent.contains("15 g"))
        #expect(!now.isContinuous)
    }

    @Test("A meal's peak and return are read over the two hours after it, never after")
    func mealPeakWithin2h() throws {
        // Flat at 100 from 11:30, up to 170 at 12:45, back to 100 by 13:40,
        // flat again, then a second rise to 220 at 14:30 that is not this meal's.
        var values: [Double] = []
        for step in 0...42 {
            let minutes = Double(step * 5 - 30)
            switch minutes {
            case ...0: values.append(100)
            case ...45: values.append(100 + 70 * minutes / 45)
            case ...100: values.append(170 - 70 * (minutes - 45) / 55)
            case ...150: values.append(100)
            default: values.append(220)
            }
        }
        let lunch = TrackMealEntry(name: "Pasta", meal: .lunch, protein: 20, carbs: 80, fat: 15, portions: 1, date: at(12))
        let untracked = TrackMealEntry(name: "Toast", meal: .breakfast, protein: 5, carbs: 30, fat: 5, portions: 1, date: at(7))
        let summary = GlucoseSummary.make(samples: trace(values, from: at(11, 30)), meals: [lunch, untracked],
                                          unit: .milligrams, now: at(16), calendar: calendar)
        #expect(summary.meals.count == 1)
        let response = try #require(summary.meals.first)
        #expect(response.mealID == lunch.id)
        #expect(abs(response.baseline - 100) < 1e-9)
        #expect(abs(response.peak - 170) < 1e-9)
        #expect(abs(response.rise - 70) < 1e-9)
        #expect(response.peakMinutes == 45)
        #expect(response.returnMinutes == 100)
    }

    @Test("The ambulatory profile has the median and the spread for each hour worn")
    func ambulatoryProfile() throws {
        var samples: [HealthReading] = []
        for day in 0..<14 {
            samples += trace((0..<288).map { 100 + Double(day) + ($0 / 12 == 13 ? 60 : 0) }, from: at(0, day: -day - 1))
        }
        let summary = GlucoseSummary.make(samples: samples, meals: [], unit: .milligrams, now: at(0), calendar: calendar)
        #expect(summary.profile.count == 24)
        let one = try #require(summary.profile.first { $0.hour == 13 })
        let night = try #require(summary.profile.first { $0.hour == 3 })
        #expect(one.median > night.median + 50)
        #expect(night.p10 <= night.p25 && night.p25 <= night.median && night.median <= night.p75 && night.p75 <= night.p90)
    }
}
