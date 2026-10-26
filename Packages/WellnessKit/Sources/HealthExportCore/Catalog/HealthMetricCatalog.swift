//
//  HealthMetricCatalog.swift
//  HealthExportCore
//

import Foundation

/// Every metric Apple Health can hand over, named by its HealthKit identifier.
///
/// Identifiers are strings rather than SDK symbols on purpose. A catalog built
/// from symbols stops compiling the moment it names a type the current SDK does
/// not have; this one names them all and lets the platform resolve what it
/// knows at runtime, so a newer metric costs one line here and an older OS
/// simply skips it.
///
/// 117 quantity types, 70 category types, the correlations, the workout
/// type and the characteristics.
public enum HealthMetricCatalog {

    // MARK: - Everything

    /// The whole catalog, in read order: priority first, then normal, then slow.
    public static let all: [HealthMetric] =
        quantities + categories + correlations + [workout] + characteristics

    /// Every metric that may be named in a read authorization request.
    ///
    /// This is what to pass to `requestAuthorization`, never ``all``: the
    /// correlations in the catalog exist so a caller can reason about them, but
    /// asking to read one terminates the app.
    public static let readable: [HealthMetric] = all.filter(\.isReadAuthorizable)

    /// Metrics the first permission sheet may ask for.
    ///
    /// Sensitive metrics are absent by construction. A surface that genuinely
    /// needs cycle tracking asks for it itself, when the person opens it: so
    /// the launch sheet never sweeps in reproductive health nobody requested.
    public static let launchRequest: [HealthMetric] =
        readable.filter { $0.sensitivity == .standard }

    /// Metrics that are only ever requested by the surface that needs them.
    public static let onDemand: [HealthMetric] =
        readable.filter { $0.sensitivity == .sensitive }

    /// Look one up by its HealthKit identifier.
    public static func metric(for identifier: String) -> HealthMetric? {
        index[identifier]
    }

    /// Everything in one tier, in catalog order.
    public static func metrics(in tier: HealthTier) -> [HealthMetric] {
        all.filter { $0.tier == tier }
    }

    private static let index: [String: HealthMetric] =
        Dictionary(all.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })

    // MARK: - Quantities

    public static let quantities: [HealthMetric] = [
        q("stepCount", .count, .cumulative, .priority),
        q("flightsClimbed", .count, .cumulative, .priority),
        q("activeEnergyBurned", .kilocalorie, .cumulative, .priority),
        q("basalEnergyBurned", .kilocalorie, .cumulative, .priority),
        q("distanceWalkingRunning", .meter, .cumulative, .priority),
        q("distanceCycling", .meter, .cumulative, .priority),
        q("distanceSwimming", .meter, .cumulative, .priority),
        q("appleExerciseTime", .minute, .cumulative, .priority),
        q("appleMoveTime", .minute, .cumulative, .priority),
        q("appleStandTime", .minute, .cumulative, .priority),
        q("heartRate", .countPerMinute, .discrete, .priority),
        q("restingHeartRate", .countPerMinute, .discrete, .priority),
        q("walkingHeartRateAverage", .countPerMinute, .discrete, .priority),
        q("heartRateVariabilitySDNN", .millisecond, .discrete, .priority),
        q("oxygenSaturation", .percent, .discrete, .priority),
        q("respiratoryRate", .countPerMinute, .discrete, .priority),
        q("bloodPressureSystolic", .millimeterOfMercury, .discrete, .priority),
        q("bloodPressureDiastolic", .millimeterOfMercury, .discrete, .priority),
        q("bodyMass", .kilogram, .discrete, .priority),
        q("bodyFatPercentage", .percent, .discrete, .priority),
        q("bodyTemperature", .degreeCelsius, .discrete, .priority),
        q("VO2Max", .millilitrePerKilogramMinute, .discrete, .priority),
        q("walkingSpeed", .metrePerSecond, .discrete, .priority),
        q("runningSpeed", .metrePerSecond, .discrete, .priority),
        q("runningPower", .watt, .discrete, .priority),
        q("cyclingPower", .watt, .discrete, .priority),
        q("bodyMassIndex", .count, .discrete, .normal),
        q("height", .meter, .discrete, .normal),
        q("waistCircumference", .meter, .discrete, .normal),
        q("leanBodyMass", .kilogram, .discrete, .normal),
        q("appleSleepingWristTemperature", .degreeCelsius, .discrete, .normal),
        q("bloodGlucose", .milligramPerDecilitre, .discrete, .normal),
        q("electrodermalActivity", .microsiemens, .discrete, .normal),
        q("UVExposure", .count, .discrete, .normal),
        q("bloodAlcoholContent", .percent, .discrete, .normal),
        q("peripheralPerfusionIndex", .percent, .discrete, .normal),
        q("atrialFibrillationBurden", .percent, .discrete, .normal),
        q("heartRateRecoveryOneMinute", .countPerMinute, .discrete, .normal),
        q("numberOfAlcoholicBeverages", .count, .cumulative, .normal),
        q("inhalerUsage", .count, .cumulative, .normal),
        q("numberOfTimesFallen", .count, .cumulative, .normal),
        q("swimmingStrokeCount", .count, .cumulative, .normal),
        q("environmentalAudioExposure", .decibelASPL, .discrete, .normal),
        q("headphoneAudioExposure", .decibelASPL, .discrete, .normal),
        q("environmentalSoundReduction", .decibelASPL, .discrete, .normal),
        q("waterTemperature", .degreeCelsius, .discrete, .normal),
        q("underwaterDepth", .meter, .discrete, .normal),
        q("timeInDaylight", .minute, .cumulative, .normal),
        q("runningStrideLength", .meter, .discrete, .normal),
        q("walkingStepLength", .meter, .discrete, .normal),
        q("sixMinuteWalkTestDistance", .meter, .discrete, .normal),
        q("runningVerticalOscillation", .centimeter, .discrete, .normal),
        q("runningGroundContactTime", .millisecond, .discrete, .normal),
        q("walkingAsymmetryPercentage", .percent, .discrete, .normal),
        q("walkingDoubleSupportPercentage", .percent, .discrete, .normal),
        q("appleWalkingSteadiness", .percent, .discrete, .normal),
        q("stairAscentSpeed", .metrePerSecond, .discrete, .normal),
        q("stairDescentSpeed", .metrePerSecond, .discrete, .normal),
        q("physicalEffort", .kilocaloriePerKilogramHour, .discrete, .normal),
        q("distanceWheelchair", .meter, .cumulative, .normal),
        q("distanceDownhillSnowSports", .meter, .cumulative, .normal),
        q("distanceRowing", .meter, .cumulative, .normal),
        q("distancePaddleSports", .meter, .cumulative, .normal),
        q("distanceSkatingSports", .meter, .cumulative, .normal),
        q("distanceCrossCountrySkiing", .meter, .cumulative, .normal),
        q("pushCount", .count, .cumulative, .normal),
        q("nikeFuel", .count, .cumulative, .normal),
        q("cyclingSpeed", .metrePerSecond, .discrete, .normal),
        q("rowingSpeed", .metrePerSecond, .discrete, .normal),
        q("paddleSportsSpeed", .metrePerSecond, .discrete, .normal),
        q("crossCountrySkiingSpeed", .metrePerSecond, .discrete, .normal),
        q("cyclingCadence", .countPerMinute, .discrete, .normal),
        q("cyclingFunctionalThresholdPower", .watt, .discrete, .normal),
        q("forcedExpiratoryVolume1", .litre, .discrete, .slow),
        q("forcedVitalCapacity", .litre, .discrete, .slow),
        q("peakExpiratoryFlowRate", .litrePerMinute, .discrete, .slow),
        q("insulinDelivery", .internationalUnit, .cumulative, .slow),
        q("basalBodyTemperature", .degreeCelsius, .discrete, .normal, sensitivity: .sensitive),
        q("dietaryCarbohydrates", .gram, .cumulative, .slow),
        q("dietaryFatTotal", .gram, .cumulative, .slow),
        q("dietaryFatSaturated", .gram, .cumulative, .slow),
        q("dietaryFatMonounsaturated", .gram, .cumulative, .slow),
        q("dietaryFatPolyunsaturated", .gram, .cumulative, .slow),
        q("dietaryProtein", .gram, .cumulative, .slow),
        q("dietaryFiber", .gram, .cumulative, .slow),
        q("dietarySugar", .gram, .cumulative, .slow),
        q("dietaryCholesterol", .milligram, .cumulative, .slow),
        q("dietarySodium", .milligram, .cumulative, .slow),
        q("dietaryCalcium", .milligram, .cumulative, .slow),
        q("dietaryIron", .milligram, .cumulative, .slow),
        q("dietaryPotassium", .milligram, .cumulative, .slow),
        q("dietaryMagnesium", .milligram, .cumulative, .slow),
        q("dietaryPhosphorus", .milligram, .cumulative, .slow),
        q("dietaryZinc", .milligram, .cumulative, .slow),
        q("dietaryVitaminC", .milligram, .cumulative, .slow),
        q("dietaryVitaminE", .milligram, .cumulative, .slow),
        q("dietaryNiacin", .milligram, .cumulative, .slow),
        q("dietaryPantothenicAcid", .milligram, .cumulative, .slow),
        q("dietaryRiboflavin", .milligram, .cumulative, .slow),
        q("dietaryThiamin", .milligram, .cumulative, .slow),
        q("dietaryVitaminB6", .milligram, .cumulative, .slow),
        q("dietaryChloride", .milligram, .cumulative, .slow),
        q("dietaryCopper", .milligram, .cumulative, .slow),
        q("dietaryManganese", .milligram, .cumulative, .slow),
        q("dietaryCaffeine", .milligram, .cumulative, .slow),
        q("dietaryBiotin", .microgram, .cumulative, .slow),
        q("dietaryFolate", .microgram, .cumulative, .slow),
        q("dietaryIodine", .microgram, .cumulative, .slow),
        q("dietaryMolybdenum", .microgram, .cumulative, .slow),
        q("dietarySelenium", .microgram, .cumulative, .slow),
        q("dietaryChromium", .microgram, .cumulative, .slow),
        q("dietaryVitaminA", .microgram, .cumulative, .slow),
        q("dietaryVitaminB12", .microgram, .cumulative, .slow),
        q("dietaryVitaminD", .microgram, .cumulative, .slow),
        q("dietaryVitaminK", .microgram, .cumulative, .slow),
        q("dietaryEnergyConsumed", .kilocalorie, .cumulative, .slow),
        q("dietaryWater", .litre, .cumulative, .slow),
    ]

    // MARK: - Categories

    public static let categories: [HealthMetric] = [
        c("sleepAnalysis", .priority),
        c("mindfulSession", .priority),
        c("highHeartRateEvent", .priority),
        c("lowHeartRateEvent", .priority),
        c("irregularHeartRhythmEvent", .priority),
        c("skippedHeartbeat", .priority),
        c("rapidPoundingOrFlutteringHeartbeat", .priority),
        c("lowCardioFitnessEvent", .priority),
        c("appleStandHour", .normal),
        c("sleepApneaEvent", .normal),
        c("appleWalkingSteadinessEvent", .normal),
        c("toothbrushingEvent", .normal),
        c("handwashingEvent", .normal),
        c("audioExposureEvent", .normal),
        c("headphoneAudioExposureEvent", .normal),
        // The symptoms the cycle log writes (cramps, bloating, headache, hot
        // flashes, mood, night sweats, sleep) are sensitive: logged against a
        // cycle they say as much as the flow does, so the cycle page asks for
        // them when it opens and the launch sheet never names them.
        c("abdominalCramps", .normal, sensitivity: .sensitive),
        c("acne", .normal),
        c("appetiteChanges", .normal),
        c("bladderIncontinence", .normal),
        c("bloating", .normal, sensitivity: .sensitive),
        c("chestTightnessOrPain", .normal),
        c("chills", .normal),
        c("constipation", .normal),
        c("coughing", .normal),
        c("diarrhea", .normal),
        c("dizziness", .normal),
        c("drySkin", .normal),
        c("fainting", .normal),
        c("fatigue", .normal),
        c("fever", .normal),
        c("generalizedBodyAche", .normal),
        c("hairLoss", .normal),
        c("headache", .normal, sensitivity: .sensitive),
        c("heartburn", .normal),
        c("hotFlashes", .normal, sensitivity: .sensitive),
        c("lossOfSmell", .normal),
        c("lossOfTaste", .normal),
        c("lowerBackPain", .normal),
        c("memoryLapse", .normal),
        c("moodChanges", .normal, sensitivity: .sensitive),
        c("nausea", .normal),
        c("nightSweats", .normal, sensitivity: .sensitive),
        c("runnyNose", .normal),
        c("shortnessOfBreath", .normal),
        c("sinusCongestion", .normal),
        c("sleepChanges", .normal, sensitivity: .sensitive),
        c("soreThroat", .normal),
        c("vomiting", .normal),
        c("wheezing", .normal),
        c("menstrualFlow", .normal, sensitivity: .sensitive),
        c("cervicalMucusQuality", .normal, sensitivity: .sensitive),
        c("ovulationTestResult", .normal, sensitivity: .sensitive),
        c("intermenstrualBleeding", .normal, sensitivity: .sensitive),
        c("sexualActivity", .normal, sensitivity: .sensitive),
        c("pregnancy", .normal, sensitivity: .sensitive),
        c("lactation", .normal, sensitivity: .sensitive),
        c("contraceptive", .normal, sensitivity: .sensitive),
        c("pregnancyTestResult", .normal, sensitivity: .sensitive),
        c("progesteroneTestResult", .normal, sensitivity: .sensitive),
        c("persistentIntermenstrualBleeding", .normal, sensitivity: .sensitive),
        c("prolongedMenstrualPeriods", .normal, sensitivity: .sensitive),
        c("irregularMenstrualCycles", .normal, sensitivity: .sensitive),
        c("infrequentMenstrualCycles", .normal, sensitivity: .sensitive),
        c("pelvicPain", .normal, sensitivity: .sensitive),
        c("vaginalDryness", .normal, sensitivity: .sensitive),
        c("breastPain", .normal, sensitivity: .sensitive),
        c("bleedingAfterPregnancy", .normal, sensitivity: .sensitive),
        c("bleedingDuringPregnancy", .normal, sensitivity: .sensitive),
        // iOS 27: an older OS resolves these to nil and skips them.
        c("bleedingAfterMenopause", .normal, sensitivity: .sensitive),
        c("menopausalState", .normal, sensitivity: .sensitive),
    ]

    // MARK: - Everything else

    public static let correlations: [HealthMetric] = [
        HealthMetric(identifier: "HKCorrelationTypeIdentifierBloodPressure", kind: .correlation, tier: .priority),
        HealthMetric(identifier: "HKCorrelationTypeIdentifierFood", kind: .correlation, tier: .slow),
    ]

    public static let workout = HealthMetric(
        identifier: "HKWorkoutTypeIdentifier",
        kind: .workout,
        tier: .priority
    )

    public static let characteristics: [HealthMetric] = [
        "HKCharacteristicTypeIdentifierBiologicalSex",
        "HKCharacteristicTypeIdentifierBloodType",
        "HKCharacteristicTypeIdentifierDateOfBirth",
        "HKCharacteristicTypeIdentifierFitzpatrickSkinType",
        "HKCharacteristicTypeIdentifierWheelchairUse",
        "HKCharacteristicTypeIdentifierActivityMoveMode",
    ].map { HealthMetric(identifier: $0, kind: .characteristic) }

    // MARK: - Shorthands used by the tables above

    private static func q(
        _ name: String,
        _ unit: HealthUnit,
        _ aggregation: HealthAggregation,
        _ tier: HealthTier,
        sensitivity: HealthSensitivity = .standard
    ) -> HealthMetric {
        HealthMetric(
            identifier: "HKQuantityTypeIdentifier" + name.prefixUppercased,
            kind: .quantity,
            unit: unit,
            aggregation: aggregation,
            tier: tier,
            sensitivity: sensitivity
        )
    }

    private static func c(
        _ name: String,
        _ tier: HealthTier,
        sensitivity: HealthSensitivity = .standard
    ) -> HealthMetric {
        HealthMetric(
            identifier: "HKCategoryTypeIdentifier" + name.prefixUppercased,
            kind: .category,
            tier: tier,
            sensitivity: sensitivity
        )
    }
}

private extension String {
    /// HealthKit identifiers are the Swift member name with a capital first
    /// letter, behind a fixed prefix: except where Apple keeps an acronym in
    /// caps (`VO2Max`, `UVExposure`), which the tables above spell out already.
    /// Uppercasing a first letter that is already uppercase is a no-op, so both
    /// spellings go through the same rule.
    var prefixUppercased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
