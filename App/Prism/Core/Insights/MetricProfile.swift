//
//  MetricProfile.swift
//  Prism
//
//  The one table of how each metric is read: its fixed reference band where
//  one exists, which way is good news, how its chart is drawn, the span its
//  page opens on, whether it is projected forward, and how the insight engine
//  judges it. Keyed by HealthKit identifier.
//

import Foundation
import HealthExportCore

struct MetricProfile: Sendable, Equatable {
    /// How a data type page draws its chart.
    enum Chart: Sendable, Equatable {
        /// A line with hollow dots: a reading taken at a moment.
        case line
        /// Thin bars: a daily total, or a night's sleep.
        case bars
        /// Dots and a moving average: a sparse body reading (weight).
        case points
        /// Systolic over diastolic, one pill per bucket.
        case bloodPressure
    }

    /// The healthy zone in the unit the page shows, nil when the person's
    /// own rolling band is the better yardstick (HRV, body composition).
    var referenceBand: ClosedRange<Double>?
    /// Whether a rising series is good news. Nil is deliberate: a band
    /// metric (temperature, glucose, pressure) or one a person may move
    /// either way on purpose (weight) has no universal good way.
    var risingIsGood: Bool?
    var chart: Chart
    /// Measured now and then rather than daily: drawn as dots with a moving
    /// average.
    var sparse = false
    /// The span its page opens on.
    var period: VaultPeriod = .month
    /// Projected 7, 30 and 90 days ahead (body composition).
    var projects = false
    /// A daily total that keeps growing until midnight.
    var accumulates = false
    /// How the insight engine judges it; nil for a metric it does not read.
    var policy: InsightPolicy?
    /// A physical ceiling the axis never climbs past (100 percent oxygen).
    var ceiling: Double?

    /// The profile for a HealthKit identifier: the table's entry, or one
    /// worked out from the catalog's kind and aggregation.
    static func of(_ identifier: String) -> MetricProfile {
        if let known = table[identifier] { return known }
        let metric = HealthMetricCatalog.metric(for: identifier)
        if metric?.kind == .quantity, metric?.aggregation == .cumulative {
            return MetricProfile(risingIsGood: nil, chart: .bars, accumulates: true)
        }
        if metric?.kind == .category { return MetricProfile(risingIsGood: nil, chart: .bars) }
        return MetricProfile(risingIsGood: nil, chart: .line)
    }

    static func of(_ metric: InsightMetric) -> MetricProfile { of(metric.identifier) }

    /// Systolic and diastolic draw together, whichever one opened the page.
    static let systolic = "HKQuantityTypeIdentifierBloodPressureSystolic"
    static let diastolic = "HKQuantityTypeIdentifierBloodPressureDiastolic"
    static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"

    // MARK: - The table

    private static func entry(
        _ rising: Bool?,
        band: ClosedRange<Double>? = nil,
        chart: Chart = .line,
        sparse: Bool = false,
        period: VaultPeriod = .month,
        projects: Bool = false,
        accumulates: Bool = false,
        ceiling: Double? = nil,
        spread: Double,
        share: Double = 0,
        step: Double,
        weight: Double = 1
    ) -> MetricProfile {
        let preference: InsightPreference = switch rising {
        case true: .higher
        case false: .lower
        default: .steady
        }
        return MetricProfile(
            referenceBand: band, risingIsGood: rising, chart: chart, sparse: sparse, period: period,
            projects: projects, accumulates: accumulates,
            policy: InsightPolicy(
                preference: preference, minimumSpread: spread, minimumShare: share, trendStep: step,
                weight: weight, partialToday: accumulates
            ),
            ceiling: ceiling
        )
    }

    static let table: [String: MetricProfile] = [
        // Nightly vitals.
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": entry(true, spread: 4, share: 0.08, step: 5),
        "HKQuantityTypeIdentifierRestingHeartRate": entry(false, band: 50...70, spread: 2, step: 2),
        "HKQuantityTypeIdentifierRespiratoryRate": entry(nil, band: 12...20, spread: 0.6, step: 0.6, weight: 0.8),
        "HKQuantityTypeIdentifierOxygenSaturation": entry(true, band: 95...100, ceiling: 100, spread: 1, step: 1, weight: 0.8),
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature": entry(nil, spread: 0.3, step: 0.3, weight: 0.9),
        // Fitness.
        "HKQuantityTypeIdentifierVO2Max": entry(true, chart: .points, sparse: true, period: .sixMonths, spread: 1, step: 1, weight: 0.8),
        "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute": entry(true, chart: .points, sparse: true, period: .threeMonths, spread: 3, step: 3, weight: 0.7),
        "HKQuantityTypeIdentifierStepCount": entry(true, chart: .bars, accumulates: true, spread: 1000, share: 0.2, step: 1000, weight: 0.7),
        "HKQuantityTypeIdentifierWalkingSpeed": entry(true, spread: 0.2, step: 0.2, weight: 0.6),
        // Sleep, as hours asleep a night.
        sleep: entry(true, band: 7...9, chart: .bars, spread: 0.4, step: 0.3),
        // Body composition: sparse, projected.
        "HKQuantityTypeIdentifierBodyMass": entry(nil, chart: .points, sparse: true, period: .threeMonths, projects: true, spread: 0.8, share: 0.01, step: 0.7, weight: 0.8),
        "HKQuantityTypeIdentifierBodyFatPercentage": entry(false, chart: .points, sparse: true, period: .threeMonths, projects: true, spread: 0.8, step: 0.7, weight: 0.7),
        "HKQuantityTypeIdentifierLeanBodyMass": entry(true, chart: .points, sparse: true, period: .threeMonths, projects: true, spread: 0.6, step: 0.5, weight: 0.7),
        "HKQuantityTypeIdentifierBodyMassIndex": entry(nil, chart: .points, sparse: true, period: .threeMonths, spread: 0.3, step: 0.25, weight: 0.5),
        // Metabolic.
        systolic: entry(nil, chart: .bloodPressure, sparse: true, period: .threeMonths, spread: 5, step: 4, weight: 0.9),
        diastolic: MetricProfile(risingIsGood: nil, chart: .bloodPressure, sparse: true, period: .threeMonths),
        "HKQuantityTypeIdentifierBloodGlucose": entry(nil, band: 70...99, spread: 8, step: 5, weight: 0.9),
        // Soma's scores and what the engine reads off a night (ScoreMetric).
        "soma.score.sleepScore": MetricProfile(referenceBand: 75...100, risingIsGood: true, chart: .line, ceiling: 100),
        "soma.score.recovery": MetricProfile(referenceBand: 67...100, risingIsGood: true, chart: .line, ceiling: 100),
        "soma.score.strain": MetricProfile(risingIsGood: nil, chart: .line, ceiling: 100),
        "soma.score.stress": MetricProfile(referenceBand: 0...33, risingIsGood: false, chart: .line, ceiling: 100),
        "soma.score.energy": MetricProfile(referenceBand: 67...100, risingIsGood: true, chart: .bars, ceiling: 100),
        "soma.score.remHours": MetricProfile(risingIsGood: true, chart: .line),
        "soma.score.deepHours": MetricProfile(risingIsGood: true, chart: .line),
        "soma.score.sleepDebt": MetricProfile(risingIsGood: false, chart: .bars),
        "soma.score.bedtime": MetricProfile(risingIsGood: nil, chart: .line),
        "soma.score.wakeTime": MetricProfile(risingIsGood: nil, chart: .line),
        // Daily totals.
        "HKQuantityTypeIdentifierActiveEnergyBurned": MetricProfile(risingIsGood: true, chart: .bars, accumulates: true),
        "HKQuantityTypeIdentifierAppleExerciseTime": MetricProfile(risingIsGood: true, chart: .bars, accumulates: true),
        "HKQuantityTypeIdentifierAppleStandTime": MetricProfile(risingIsGood: true, chart: .bars, accumulates: true),
    ]
}
