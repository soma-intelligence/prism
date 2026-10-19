//
//  HomeHealth.swift
//  Prism
//

import Foundation
import HealthExportCore

/// The Apple Health identifiers the pages Today opens read, beyond the ones
/// asked for at launch. Each page asks for its own when it opens, through
/// `HealthDashboard.prepare(_:)`.
enum HomeMetric {
    static let respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"
    static let wristTemperature = "HKQuantityTypeIdentifierAppleSleepingWristTemperature"
    static let standHour = "HKCategoryTypeIdentifierAppleStandHour"
    static let bloodGlucose = "HKQuantityTypeIdentifierBloodGlucose"
    static let menstrualFlow = "HKCategoryTypeIdentifierMenstrualFlow"
    static let height = "HKQuantityTypeIdentifierHeight"
    static let bodyMass = "HKQuantityTypeIdentifierBodyMass"
    static let leanBodyMass = "HKQuantityTypeIdentifierLeanBodyMass"
    static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
    static let biologicalSex = "HKCharacteristicTypeIdentifierBiologicalSex"
    static let bloodType = "HKCharacteristicTypeIdentifierBloodType"
    static let distance = "HKQuantityTypeIdentifierDistanceWalkingRunning"
    static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
}

extension HealthSampleSource {
    /// Every sample of `identifier` over the `days` days ending at `now`, or
    /// none when the read fails: a page renders its dashes rather than failing.
    func home(_ identifier: String, days: Int, now: Date, calendar: Calendar = .current) async -> [HealthReading] {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        return (try? await samples(metric, from: start, to: now, limit: 0)) ?? []
    }

    /// The latest sample of `identifier`, or nil.
    func homeLatest(_ identifier: String) async -> HealthReading? {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
        return try? await latest(metric)
    }
}
