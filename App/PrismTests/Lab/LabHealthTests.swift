//
//  LabHealthTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Body lab's reads out of Health, and the half of the biological age
/// they feed: a sparse weight, body fat or VO2 max carried day by day, body
/// fat turned from Health's fraction into percent, BMI from the latest
/// height, and no estimate at all without an age and a sex.
@Suite("Lab Health reads")
@MainActor
struct LabHealthTests {
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

    // MARK: Points

    @Test("A metric's samples come oldest first, dated when they ended, inside the window")
    func points() async {
        let readings: [HealthReading] = [
            .test(LabMetric.bodyMass, 70, from: at(9, day: -1), to: at(9, 5, day: -1)),
            .test(LabMetric.bodyMass, 71, from: at(8, day: -5), to: at(8, 30, day: -5)),
            .test(LabMetric.bodyMass, 75, at: at(8, day: -400)),
        ]
        let points = await LabHealth.points(LabMetric.bodyMass, days: 365, now: now, calendar: calendar,
                                            in: ScriptedHealthSource(readings))
        #expect(points == [LabPoint(date: at(8, 30, day: -5), value: 71), LabPoint(date: at(9, 5, day: -1), value: 70)])
    }

    @Test("An identifier outside the catalog, or a store that refuses, gives no points")
    func noPoints() async {
        let readings: [HealthReading] = [.test(LabMetric.bodyMass, 70, at: at(9))]
        let refused = await LabHealth.points(LabMetric.bodyMass, days: 30, now: now, calendar: calendar,
                                             in: ScriptedHealthSource(readings, fails: true))
        let unknown = await LabHealth.points("HKQuantityTypeIdentifierNothing", days: 30, now: now, calendar: calendar,
                                             in: ScriptedHealthSource(readings))
        #expect(refused.isEmpty)
        #expect(unknown.isEmpty)
    }

    @Test("Cuff readings pair within two minutes, the nearest diastolic winning, and a lone systolic is dropped")
    func pressures() async {
        let readings: [HealthReading] = [
            .test(LabMetric.systolic, 118, at: at(8, day: -2)),
            .test(LabMetric.diastolic, 76, at: at(8, day: -2)),
            .test(LabMetric.systolic, 131, at: at(20, day: -1)),
            .test(LabMetric.diastolic, 88, at: at(20, day: -1).addingTimeInterval(30)),
            .test(LabMetric.diastolic, 95, at: at(20, day: -1).addingTimeInterval(100)),
            .test(LabMetric.systolic, 140, at: at(9)),
        ]
        let pairs = await LabHealth.pressures(days: 30, now: now, calendar: calendar, in: ScriptedHealthSource(readings))
        #expect(pairs == [
            PressureReading(date: at(8, 1, day: -2), systolic: 118, diastolic: 76),
            PressureReading(date: at(20, 1, day: -1), systolic: 131, diastolic: 88),
        ])
    }

    @Test("Age is read from the date of birth, and is unknown without one")
    func age() async {
        let known = await LabHealth.age(in: ScriptedHealthSource([.test(LabMetric.dateOfBirth, 41, at: at(0, day: -400))]))
        let unknown = await LabHealth.age(in: ScriptedHealthSource())
        #expect(known == 41)
        #expect(unknown == nil)
    }

    // MARK: Biological age inputs

    /// A weight and a body fat ten days ago, a height taken years back (and an
    /// older one it replaces), a VO2 max, a cuff reading and a date of birth.
    var body: [HealthReading] {
        [
            .test(LabMetric.bodyMass, 70, at: at(8, day: -10)),
            .test(LabMetric.bodyFat, 0.22, at: at(8, day: -10)),
            .test(LabMetric.height, 1.65, at: at(8, day: -3_000)),
            .test(LabMetric.height, 1.70, at: at(8, day: -1_000)),
            .test(LabMetric.vo2Max, 41, at: at(18, day: -20)),
            .test(LabMetric.systolic, 118, at: at(8, day: -5)),
            .test(LabMetric.dateOfBirth, 44, at: at(0, day: -400)),
        ]
    }

    func bioAge(_ person: LabPerson, _ readings: [HealthReading]) async -> (inputs: BiologicalAge.Inputs?, daily: LabDaily) {
        await LabReads.bioAgeInputs(from: ScriptedHealthSource(readings), person: person, panel: nil, panels: 2,
                                    now: now, calendar: calendar)
    }

    @Test("Without a sex there is no estimate, and the daily series still come back")
    func noSex() async {
        let result = await bioAge(LabPerson(age: 50, sex: nil), body)
        #expect(result.inputs == nil)
        #expect(result.daily.ageYears == 44)
    }

    @Test("Without an age, from the person or from Health, there is no estimate")
    func noAge() async {
        let result = await bioAge(LabPerson(age: nil, sex: .female), body.filter { $0.metric != LabMetric.dateOfBirth })
        #expect(result.inputs == nil)
    }

    @Test("The age the person gave wins over Health's, and Health's stands in without one")
    func ageWins() async {
        let given = await bioAge(LabPerson(age: 50, sex: .female), body)
        let read = await bioAge(LabPerson(age: nil, sex: .male), body)
        #expect(given.inputs?.chronologicalAge == 50)
        #expect(given.inputs?.sex == .female)
        #expect(read.inputs?.chronologicalAge == 44)
        #expect(read.inputs?.sex == .male)
    }

    @Test("Sparse readings are carried day by day, body fat as percent and BMI from the latest height")
    func series() async throws {
        let result = await bioAge(LabPerson(age: 50, sex: .female), body)
        let inputs = try #require(result.inputs)
        #expect(inputs.vo2Max == Array(repeating: 41, count: 21))
        #expect(inputs.systolic == Array(repeating: 118, count: 6))
        #expect(inputs.bodyFatPercent.count == 11)
        #expect(inputs.bodyFatPercent.allSatisfy { abs($0 - 22) < 1e-9 })
        #expect(inputs.bmi.count == 11)
        #expect(inputs.bmi.allSatisfy { abs($0 - 70 / (1.70 * 1.70)) < 1e-9 })
        #expect(inputs.bloodMarkers.isEmpty)
        #expect(inputs.bloodPanels == 2)
    }
}
