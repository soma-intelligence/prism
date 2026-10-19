//
//  LabReads.swift
//  Prism
//
//  What the lab pages read before they compute: who the person is (age from
//  Health, sex from Health or from their own answer) and the series the
//  biological age averages.
//

import Foundation
import HealthExportCore

nonisolated struct LabPerson: Sendable, Equatable {
    var age: Int?
    var sex: LabSex?
}

nonisolated enum LabReads {
    /// Everything the biological age reads from Health.
    static let bioAgeMetrics = [
        LabMetric.dateOfBirth, LabMetric.biologicalSex, LabMetric.vo2Max, LabMetric.bodyMass,
        LabMetric.height, LabMetric.bodyFat, LabMetric.systolic, LabMetric.diastolic,
    ]

    /// Health's half of the biological age inputs, the blood half from `panel`.
    static func bioAgeInputs(from source: any HealthSampleSource, person: LabPerson, panel: BloodPanel?,
                             panels: Int, now: Date, calendar: Calendar) async -> (inputs: BiologicalAge.Inputs?, daily: LabDaily) {
        let window = 180
        async let daily = LabHealth.daily(from: source, now: now, calendar: calendar)
        async let vo2 = LabHealth.points(LabMetric.vo2Max, days: 365, now: now, calendar: calendar, in: source)
        async let mass = LabHealth.points(LabMetric.bodyMass, days: 365, now: now, calendar: calendar, in: source)
        async let fat = LabHealth.points(LabMetric.bodyFat, days: 365, now: now, calendar: calendar, in: source)
        async let systolic = LabHealth.points(LabMetric.systolic, days: 365, now: now, calendar: calendar, in: source)
        async let height = LabHealth.points(LabMetric.height, days: 3650, now: now, calendar: calendar, in: source)

        let days = await daily
        guard let age = person.age ?? days.ageYears.map({ Int($0) }), let sex = person.sex else { return (nil, days) }
        let metres = await height.last?.value
        let bmi = await mass.compactMap { point in LabMath.bmi(kilograms: point.value, metres: metres).map { LabPoint(date: point.date, value: $0) } }

        var inputs = BiologicalAge.Inputs(chronologicalAge: age, sex: sex)
        inputs.restingHR = days.restingHeartRate.compactMap { $0 }
        inputs.hrv = days.heartRateVariability.compactMap { $0 }
        inputs.steps = days.steps.compactMap { $0 }.filter { $0 > 0 }
        inputs.sleepHours = days.sleepHours.compactMap { $0 }
        inputs.vo2Max = LabMath.forwardFilled(await vo2, days: window, now: now, calendar: calendar)
        inputs.bmi = LabMath.forwardFilled(bmi, days: window, now: now, calendar: calendar)
        // Health keeps body fat as a fraction; the model reads percent.
        inputs.bodyFatPercent = LabMath.forwardFilled(await fat, days: window, now: now, calendar: calendar).map { $0 * 100 }
        inputs.systolic = LabMath.forwardFilled(await systolic, days: window, now: now, calendar: calendar)
        if let panel {
            inputs.bloodMarkers = panel.phenoAgeValues
            inputs.extendedBloodMarkers = panel.extendedValues
        }
        inputs.bloodPanels = panels
        return (inputs, days)
    }
}
