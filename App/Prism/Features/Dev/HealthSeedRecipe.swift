//
//  HealthSeedRecipe.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthExportCore

/// The shape of one metric's fabricated samples, in that metric's canonical
/// unit.
///
/// Values are the plausible range for one adult, not a distribution fitted to
/// anything. The point is a store that reads like a person's rather than a
/// store full of the number 42: a card showing 9,412 steps and 62 bpm tells you
/// whether the layout works, and one showing 1 and 1 does not.
struct HealthSeedRecipe: Sendable {
    /// Low end of the value. For a cumulative metric this is the day's total;
    /// for a discrete one it is a single reading.
    let low: Double
    /// High end of the same.
    let high: Double
    /// How many samples a seeded day is split into.
    let perDay: Int
    /// Share of the thirty days that get anything at all. A month of daily
    /// spirometry is not what a store looks like, and a gap is data too: it is
    /// what makes the dash on a card appear for the right reason.
    let chance: Double

    init(_ low: Double, _ high: Double, perDay: Int = 1, chance: Double = 1) {
        self.low = low
        self.high = high
        self.perDay = perDay
        self.chance = chance
    }
}

/// What to write for each metric in the catalog.
///
/// Keyed by the same HealthKit identifiers `HealthMetricCatalog` uses, so the
/// two cannot drift apart: a metric the catalog knows and this table does not
/// falls back to a range derived from its unit, which is dull but never absurd.
enum HealthSeedCatalog {

    /// Metrics handled by their own writer rather than by the generic pass.
    ///
    /// Sleep is stages through a night, blood pressure is a correlation of two
    /// quantities, and mindfulness is a session with a length: none of them is
    /// a number sprinkled over a day.
    static let specialCased: Set<String> = [
        "HKQuantityTypeIdentifierBloodPressureSystolic",
        "HKQuantityTypeIdentifierBloodPressureDiastolic",
        "HKCategoryTypeIdentifierSleepAnalysis",
        "HKCategoryTypeIdentifierMindfulSession",
    ]

    /// The recipe for a metric, or nil when it is not to be written.
    static func recipe(for metric: HealthMetric) -> HealthSeedRecipe? {
        if specialCased.contains(metric.identifier) { return nil }
        if let known = quantities[metric.identifier] { return known }
        if metric.kind == .category { return categories[metric.identifier] ?? defaultCategory }
        return fallback(for: metric)
    }

    /// The coded value a category sample carries.
    ///
    /// Zero is the default because it is valid almost everywhere: it is
    /// `unspecified` in `HKCategoryValueSeverity`, `present` in
    /// `HKCategoryValuePresence` and `notApplicable` for every type that carries
    /// no value at all. The enums that start at one are listed below, because
    /// for those zero is rejected.
    static func value(for identifier: String) -> Int {
        categoryValues[identifier] ?? 0
    }

    private static let defaultCategory = HealthSeedRecipe(1, 1, perDay: 1, chance: 0.08)

    // MARK: - Quantities

    private static let quantities: [String: HealthSeedRecipe] = q([
        // Movement.
        "StepCount": .init(4200, 13500, perDay: 14),
        "FlightsClimbed": .init(4, 22, perDay: 6),
        "ActiveEnergyBurned": .init(320, 820, perDay: 18),
        "BasalEnergyBurned": .init(1450, 1750, perDay: 12),
        "DistanceWalkingRunning": .init(3200, 10500, perDay: 14),
        "DistanceCycling": .init(4000, 18000, perDay: 4, chance: 0.35),
        "DistanceSwimming": .init(600, 1800, perDay: 3, chance: 0.15),
        "AppleExerciseTime": .init(22, 75, perDay: 6),
        "AppleMoveTime": .init(40, 120, perDay: 6),
        "AppleStandTime": .init(60, 240, perDay: 10),
        "TimeInDaylight": .init(25, 140, perDay: 5),

        // Heart and breath.
        "HeartRate": .init(48, 142, perDay: 28),
        "RestingHeartRate": .init(49, 61, perDay: 1),
        "WalkingHeartRateAverage": .init(88, 108, perDay: 1),
        "HeartRateVariabilitySDNN": .init(32, 88, perDay: 5),
        "HeartRateRecoveryOneMinute": .init(22, 42, perDay: 1, chance: 0.4),
        "OxygenSaturation": .init(0.94, 0.99, perDay: 6),
        "RespiratoryRate": .init(12, 18, perDay: 6),
        "PeripheralPerfusionIndex": .init(0.01, 0.06, perDay: 3, chance: 0.4),
        "AtrialFibrillationBurden": .init(0.0, 0.02, perDay: 1, chance: 0.1),

        // Body.
        "BodyMass": .init(71.5, 73.8, perDay: 1),
        "BodyFatPercentage": .init(0.15, 0.20, perDay: 1, chance: 0.5),
        "LeanBodyMass": .init(55, 58, perDay: 1, chance: 0.5),
        "BodyMassIndex": .init(21.8, 23.4, perDay: 1, chance: 0.5),
        "Height": .init(1.78, 1.78, perDay: 1, chance: 0.05),
        "WaistCircumference": .init(0.81, 0.87, perDay: 1, chance: 0.15),
        "BodyTemperature": .init(36.3, 37.0, perDay: 1, chance: 0.3),
        "AppleSleepingWristTemperature": .init(35.2, 36.4, perDay: 1),
        "BasalBodyTemperature": .init(36.2, 36.8, perDay: 1, chance: 0.5),

        // Fitness and gait.
        "VO2Max": .init(38, 47, perDay: 1, chance: 0.25),
        "WalkingSpeed": .init(1.05, 1.55, perDay: 6),
        "WalkingStepLength": .init(0.62, 0.78, perDay: 5),
        "WalkingAsymmetryPercentage": .init(0.0, 0.05, perDay: 4),
        "WalkingDoubleSupportPercentage": .init(0.22, 0.31, perDay: 4),
        "AppleWalkingSteadiness": .init(0.62, 0.92, perDay: 1, chance: 0.5),
        "StairAscentSpeed": .init(0.38, 0.62, perDay: 3),
        "StairDescentSpeed": .init(0.42, 0.68, perDay: 3),
        "SixMinuteWalkTestDistance": .init(520, 610, perDay: 1, chance: 0.1),
        "PhysicalEffort": .init(1.8, 7.5, perDay: 6),
        "RunningSpeed": .init(2.6, 3.8, perDay: 3, chance: 0.35),
        "RunningPower": .init(210, 330, perDay: 3, chance: 0.35),
        "RunningStrideLength": .init(0.95, 1.25, perDay: 3, chance: 0.35),
        "RunningVerticalOscillation": .init(7.2, 10.8, perDay: 3, chance: 0.35),
        "RunningGroundContactTime": .init(205, 275, perDay: 3, chance: 0.35),
        "CyclingSpeed": .init(4.2, 8.4, perDay: 3, chance: 0.35),
        "CyclingPower": .init(120, 260, perDay: 3, chance: 0.35),
        "CyclingCadence": .init(68, 96, perDay: 3, chance: 0.35),
        "CyclingFunctionalThresholdPower": .init(195, 255, perDay: 1, chance: 0.1),

        // Sports that happen now and then.
        "SwimmingStrokeCount": .init(240, 900, perDay: 3, chance: 0.15),
        "DistanceRowing": .init(2000, 8000, perDay: 2, chance: 0.12),
        "RowingSpeed": .init(2.2, 3.6, perDay: 2, chance: 0.12),
        "DistancePaddleSports": .init(1500, 6000, perDay: 2, chance: 0.08),
        "PaddleSportsSpeed": .init(1.4, 2.6, perDay: 2, chance: 0.08),
        "DistanceSkatingSports": .init(2000, 9000, perDay: 2, chance: 0.08),
        "DistanceDownhillSnowSports": .init(4000, 14000, perDay: 2, chance: 0.08),
        "DistanceCrossCountrySkiing": .init(3000, 12000, perDay: 2, chance: 0.05),
        "CrossCountrySkiingSpeed": .init(2.4, 4.2, perDay: 2, chance: 0.05),
        "NikeFuel": .init(1200, 3200, perDay: 4, chance: 0.3),
        "UnderwaterDepth": .init(1, 6, perDay: 2, chance: 0.08),
        "WaterTemperature": .init(23, 28, perDay: 2, chance: 0.12),

        // Wheelchair, which the same person does not also do. Rare on purpose:
        // present so the metric is exercised, thin so the activity reads as
        // walking.
        "DistanceWheelchair": .init(1200, 4000, perDay: 3, chance: 0.08),
        "PushCount": .init(200, 900, perDay: 3, chance: 0.08),

        // Hearing and environment.
        "EnvironmentalAudioExposure": .init(52, 82, perDay: 8),
        "HeadphoneAudioExposure": .init(58, 86, perDay: 6, chance: 0.7),
        "EnvironmentalSoundReduction": .init(12, 32, perDay: 4, chance: 0.4),
        "UVExposure": .init(1, 8, perDay: 2, chance: 0.6),

        // Clinical.
        "BloodGlucose": .init(82, 118, perDay: 3, chance: 0.4),
        "ElectrodermalActivity": .init(0.4, 4.5, perDay: 4, chance: 0.3),
        "BloodAlcoholContent": .init(0.0, 0.03, perDay: 1, chance: 0.1),
        "NumberOfAlcoholicBeverages": .init(1, 3, perDay: 2, chance: 0.25),
        "InhalerUsage": .init(1, 2, perDay: 2, chance: 0.1),
        "NumberOfTimesFallen": .init(1, 1, perDay: 1, chance: 0.03),
        "InsulinDelivery": .init(4, 12, perDay: 3, chance: 0.05),
        "ForcedExpiratoryVolume1": .init(3.2, 4.3, perDay: 1, chance: 0.1),
        "ForcedVitalCapacity": .init(4.1, 5.2, perDay: 1, chance: 0.1),
        "PeakExpiratoryFlowRate": .init(470, 620, perDay: 1, chance: 0.1),

        // Food, written as three meals on most days.
        "DietaryEnergyConsumed": .init(1850, 2650, perDay: 3, chance: 0.85),
        "DietaryWater": .init(1.4, 3.0, perDay: 6, chance: 0.85),
        "DietaryCarbohydrates": .init(180, 320, perDay: 3, chance: 0.85),
        "DietaryProtein": .init(85, 145, perDay: 3, chance: 0.85),
        "DietaryFatTotal": .init(55, 100, perDay: 3, chance: 0.85),
        "DietaryFatSaturated": .init(14, 30, perDay: 3, chance: 0.85),
        "DietaryFatMonounsaturated": .init(18, 38, perDay: 3, chance: 0.85),
        "DietaryFatPolyunsaturated": .init(9, 24, perDay: 3, chance: 0.85),
        "DietaryFiber": .init(18, 36, perDay: 3, chance: 0.85),
        "DietarySugar": .init(38, 95, perDay: 3, chance: 0.85),
        "DietaryCholesterol": .init(150, 350, perDay: 3, chance: 0.85),
        "DietarySodium": .init(1800, 3400, perDay: 3, chance: 0.85),
        "DietaryCalcium": .init(700, 1200, perDay: 3, chance: 0.85),
        "DietaryIron": .init(8, 18, perDay: 3, chance: 0.85),
        "DietaryPotassium": .init(2000, 3500, perDay: 3, chance: 0.85),
        "DietaryMagnesium": .init(250, 400, perDay: 3, chance: 0.85),
        "DietaryPhosphorus": .init(700, 1250, perDay: 3, chance: 0.85),
        "DietaryZinc": .init(8, 15, perDay: 3, chance: 0.85),
        "DietaryChloride": .init(2000, 3400, perDay: 3, chance: 0.85),
        "DietaryCopper": .init(0.8, 1.6, perDay: 3, chance: 0.85),
        "DietaryManganese": .init(1.8, 3.0, perDay: 3, chance: 0.85),
        "DietaryVitaminC": .init(50, 120, perDay: 3, chance: 0.85),
        "DietaryVitaminE": .init(8, 15, perDay: 3, chance: 0.85),
        "DietaryNiacin": .init(12, 25, perDay: 3, chance: 0.85),
        "DietaryPantothenicAcid": .init(4, 7, perDay: 3, chance: 0.85),
        "DietaryRiboflavin": .init(1.0, 2.0, perDay: 3, chance: 0.85),
        "DietaryThiamin": .init(1.0, 2.0, perDay: 3, chance: 0.85),
        "DietaryVitaminB6": .init(1.2, 2.2, perDay: 3, chance: 0.85),
        "DietaryCaffeine": .init(60, 250, perDay: 2, chance: 0.8),
        "DietaryBiotin": .init(25, 45, perDay: 3, chance: 0.85),
        "DietaryFolate": .init(300, 500, perDay: 3, chance: 0.85),
        "DietaryIodine": .init(100, 180, perDay: 3, chance: 0.85),
        "DietaryMolybdenum": .init(40, 70, perDay: 3, chance: 0.85),
        "DietarySelenium": .init(50, 90, perDay: 3, chance: 0.85),
        "DietaryChromium": .init(25, 45, perDay: 3, chance: 0.85),
        "DietaryVitaminA": .init(700, 1100, perDay: 3, chance: 0.85),
        "DietaryVitaminB12": .init(2.0, 5.0, perDay: 3, chance: 0.85),
        "DietaryVitaminD": .init(10, 25, perDay: 3, chance: 0.85),
        "DietaryVitaminK": .init(80, 140, perDay: 3, chance: 0.85),
    ])

    // MARK: - Categories

    private static let categories: [String: HealthSeedRecipe] = c([
        "AppleStandHour": .init(1, 1, perDay: 12),
        "ToothbrushingEvent": .init(1, 1, perDay: 2, chance: 0.9),
        "HandwashingEvent": .init(1, 1, perDay: 6, chance: 0.9),
        "SleepApneaEvent": .init(1, 1, perDay: 1, chance: 0.1),
        "HighHeartRateEvent": .init(1, 1, perDay: 1, chance: 0.05),
        "LowHeartRateEvent": .init(1, 1, perDay: 1, chance: 0.05),
        "IrregularHeartRhythmEvent": .init(1, 1, perDay: 1, chance: 0.04),
        "LowCardioFitnessEvent": .init(1, 1, perDay: 1, chance: 0.03),
        "AppleWalkingSteadinessEvent": .init(1, 1, perDay: 1, chance: 0.03),
        "EnvironmentalAudioExposureEvent": .init(1, 1, perDay: 1, chance: 0.08),
        "HeadphoneAudioExposureEvent": .init(1, 1, perDay: 1, chance: 0.05),
        "MenstrualFlow": .init(1, 1, perDay: 1, chance: 0.18),
        "CervicalMucusQuality": .init(1, 1, perDay: 1, chance: 0.2),
        "OvulationTestResult": .init(1, 1, perDay: 1, chance: 0.1),
        "SexualActivity": .init(1, 1, perDay: 1, chance: 0.15),
        "Contraceptive": .init(1, 1, perDay: 1, chance: 0.05),
        "PregnancyTestResult": .init(1, 1, perDay: 1, chance: 0.03),
        "ProgesteroneTestResult": .init(1, 1, perDay: 1, chance: 0.03),
    ])

    /// Coded values for the category enums that do not accept zero.
    ///
    /// Taken from `HKCategoryValues.h`: every one of these starts at one, so the
    /// zero that serves every other type is rejected here.
    private static let categoryValues: [String: Int] = c([
        "MenstrualFlow": 2,                      // light
        "CervicalMucusQuality": 3,               // creamy
        "OvulationTestResult": 1,                // negative
        "PregnancyTestResult": 1,                // negative
        "ProgesteroneTestResult": 1,             // negative
        "Contraceptive": 1,                      // unspecified
        "LowCardioFitnessEvent": 1,              // low fitness
        "AppleWalkingSteadinessEvent": 1,        // initial low
        "EnvironmentalAudioExposureEvent": 1,    // momentary limit
        "HeadphoneAudioExposureEvent": 1,        // seven day limit
    ])

    // MARK: - Fallback

    /// A range derived from the unit, for a metric the table above does not
    /// name. Dull but never absurd, and it means a metric added to the catalog
    /// still gets written without anyone editing this file.
    private static func fallback(for metric: HealthMetric) -> HealthSeedRecipe? {
        let cumulative = metric.aggregation == .cumulative
        switch metric.unit {
        case .count: return .init(1, cumulative ? 40 : 6, perDay: 2, chance: 0.4)
        case .countPerMinute: return .init(40, 120, perDay: 4, chance: 0.4)
        case .kilocalorie: return .init(60, 400, perDay: 3, chance: 0.4)
        case .kilocaloriePerKilogramHour: return .init(1.5, 7, perDay: 3, chance: 0.4)
        case .meter: return cumulative ? .init(800, 6000, perDay: 3, chance: 0.2) : .init(0.5, 2, perDay: 3, chance: 0.3)
        case .centimeter: return .init(5, 15, perDay: 2, chance: 0.3)
        case .minute: return .init(10, 60, perDay: 3, chance: 0.4)
        case .hour: return .init(1, 3, perDay: 1, chance: 0.3)
        case .second: return .init(30, 300, perDay: 2, chance: 0.3)
        case .millisecond: return .init(20, 250, perDay: 3, chance: 0.3)
        case .percent: return .init(0.2, 0.8, perDay: 2, chance: 0.3)
        case .millimeterOfMercury: return .init(70, 130, perDay: 1, chance: 0.3)
        case .kilogram: return .init(50, 80, perDay: 1, chance: 0.2)
        case .degreeCelsius: return .init(36, 37.2, perDay: 1, chance: 0.3)
        case .millilitrePerKilogramMinute: return .init(35, 50, perDay: 1, chance: 0.2)
        case .metrePerSecond: return .init(1, 4, perDay: 3, chance: 0.3)
        case .watt: return .init(100, 300, perDay: 3, chance: 0.3)
        case .milligramPerDecilitre: return .init(80, 120, perDay: 2, chance: 0.3)
        case .microsiemens: return .init(0.5, 4, perDay: 3, chance: 0.3)
        case .decibelASPL: return .init(50, 85, perDay: 4, chance: 0.4)
        case .decibelHearingLevel: return .init(5, 30, perDay: 1, chance: 0.1)
        case .litre: return .init(0.3, 3, perDay: 3, chance: 0.4)
        case .litrePerMinute: return .init(400, 600, perDay: 1, chance: 0.1)
        case .internationalUnit: return .init(2, 10, perDay: 2, chance: 0.1)
        case .gram: return .init(5, 60, perDay: 3, chance: 0.5)
        case .milligram: return .init(20, 400, perDay: 3, chance: 0.5)
        case .microgram: return .init(20, 300, perDay: 3, chance: 0.5)
        case .none: return nil
        }
    }

    // MARK: - Key shorthands

    private static func q<Value>(_ table: [String: Value]) -> [String: Value] {
        prefixed("HKQuantityTypeIdentifier", table)
    }

    private static func c<Value>(_ table: [String: Value]) -> [String: Value] {
        prefixed("HKCategoryTypeIdentifier", table)
    }

    private static func prefixed<Value>(_ prefix: String, _ table: [String: Value]) -> [String: Value] {
        Dictionary(uniqueKeysWithValues: table.map { (prefix + $0.key, $0.value) })
    }
}
#endif
