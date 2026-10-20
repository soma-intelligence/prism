//
//  InsightMetric.swift
//  Prism
//
//  The metrics the interpretation engine reads. How each one is judged
//  (which way is better, how wide a usual band can shrink, how far a month
//  has to move before it counts) lives in the one table, ``MetricProfile``.
//

import Foundation

/// Which way a metric is better.
enum InsightPreference: Sendable, Equatable, Codable {
    /// More is better: HRV, VO2 max, steps.
    case higher
    /// Less is better: resting heart rate, body fat.
    case lower
    /// Neither: being near the usual is what matters (wrist temperature,
    /// breathing, weight).
    case steady
}

/// How one metric is judged. Every value is in the unit the metric is shown
/// in (ms, bpm, %, kg, hours).
struct InsightPolicy: Sendable, Equatable {
    var preference: InsightPreference
    /// The narrowest half width the usual band may have, in the shown unit:
    /// a run of identical readings would otherwise make the smallest change
    /// look out of range.
    var minimumSpread: Double
    /// The same floor as a share of the usual, for metrics whose scale
    /// varies from person to person (steps). The larger floor wins.
    var minimumShare: Double = 0
    /// The change over thirty days that counts as rising or falling.
    var trendStep: Double
    /// How much this metric weighs when ranking what moved.
    var weight: Double = 1
    /// The day's total keeps growing until midnight (steps), so today is left
    /// out of the reading until it is over.
    var partialToday: Bool = false

    /// A score from 0 to 100 where higher is better: Sleep, Mind.
    static let score = InsightPolicy(preference: .higher, minimumSpread: 5, trendStep: 6)
    /// A score from 0 to 100 that is neither good nor bad by itself: Activity.
    static let load = InsightPolicy(preference: .steady, minimumSpread: 6, trendStep: 8)
}

/// The sixteen metrics Soma interprets.
enum InsightMetric: String, CaseIterable, Sendable, Identifiable {
    case heartRateVariability, restingHeartRate, respiratoryRate, bloodOxygen, wristTemperature,
         vo2Max, heartRateRecovery, steps, walkingSpeed, sleepDuration,
         weight, bodyFat, leanMass, bodyMassIndex, bloodPressure, bloodGlucose

    var id: String { rawValue }

    /// The HealthKit identifier its records live under.
    var identifier: String {
        switch self {
        case .heartRateVariability: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        case .restingHeartRate: "HKQuantityTypeIdentifierRestingHeartRate"
        case .respiratoryRate: "HKQuantityTypeIdentifierRespiratoryRate"
        case .bloodOxygen: "HKQuantityTypeIdentifierOxygenSaturation"
        case .wristTemperature: "HKQuantityTypeIdentifierAppleSleepingWristTemperature"
        case .vo2Max: "HKQuantityTypeIdentifierVO2Max"
        case .heartRateRecovery: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
        case .steps: "HKQuantityTypeIdentifierStepCount"
        case .walkingSpeed: "HKQuantityTypeIdentifierWalkingSpeed"
        case .sleepDuration: "HKCategoryTypeIdentifierSleepAnalysis"
        case .weight: "HKQuantityTypeIdentifierBodyMass"
        case .bodyFat: "HKQuantityTypeIdentifierBodyFatPercentage"
        case .leanMass: "HKQuantityTypeIdentifierLeanBodyMass"
        case .bodyMassIndex: "HKQuantityTypeIdentifierBodyMassIndex"
        case .bloodPressure: "HKQuantityTypeIdentifierBloodPressureSystolic"
        case .bloodGlucose: "HKQuantityTypeIdentifierBloodGlucose"
        }
    }

    /// The metric whose records live under `identifier`, if Soma interprets it.
    static func metric(for identifier: String) -> InsightMetric? {
        allCases.first { $0.identifier == identifier }
    }

    /// How the engine judges it, from the one table in ``MetricProfile``.
    var policy: InsightPolicy {
        MetricProfile.of(identifier).policy ?? InsightPolicy(preference: .steady, minimumSpread: 0, trendStep: 0)
    }

    /// The short name a ranked row reads under.
    var title: String {
        switch self {
        case .heartRateVariability: "HRV"
        case .restingHeartRate: "Resting heart rate"
        case .respiratoryRate: "Respiratory rate"
        case .bloodOxygen: "Blood oxygen"
        case .wristTemperature: "Wrist temperature"
        case .vo2Max: "VO2 max"
        case .heartRateRecovery: "Heart rate recovery"
        case .steps: "Steps"
        case .walkingSpeed: "Walking speed"
        case .sleepDuration: "Sleep"
        case .weight: "Weight"
        case .bodyFat: "Body fat"
        case .leanMass: "Lean body mass"
        case .bodyMassIndex: "BMI"
        case .bloodPressure: "Blood pressure"
        case .bloodGlucose: "Blood glucose"
        }
    }
}
