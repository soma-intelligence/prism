//
//  BodyCatalog.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// One data type as a browse list shows it: the catalog entry plus the name a
/// person reads.
struct BodyDataType: Identifiable, Hashable {
    let metric: HealthMetric
    let title: String

    var id: String { metric.identifier }

    init(_ metric: HealthMetric) {
        self.metric = metric
        self.title = metric.displayName
    }
}

/// A group of data types, the way Apple Health groups them.
struct BodyCategory: Identifiable, Hashable {
    let title: String
    let symbol: String
    let types: [BodyDataType]

    var id: String { title }

    var metrics: [HealthMetric] { types.map(\.metric) }

    /// True when anything in here is scoped away from the launch request.
    ///
    /// The page that opens on it asks for it then, which is the whole point of
    /// the scoping: the first permission sheet never sweeps in reproductive
    /// health nobody went looking for.
    var isSensitive: Bool { types.contains { $0.metric.sensitivity == .sensitive } }

    init(_ title: String, symbol: String, _ identifiers: [String]) {
        self.title = title
        self.symbol = symbol
        self.types = identifiers
            .compactMap(HealthMetricCatalog.metric(for:))
            .map(BodyDataType.init)
    }
}

/// What the Body tab browses.
///
/// The catalog itself is flat: 192 entries keyed by HealthKit identifier, with
/// no grouping, because HealthKit has none. The grouping is a reading of it, so
/// it lives here at the surface rather than in the package.
///
/// An identifier that the catalog does not carry drops out silently, the same
/// way the catalog itself lets an older OS skip a type it has never heard of.
enum BodyCatalog {
    /// How many measures the categories list: every count of measures the app
    /// shows (the Vault's head, the search on Today's All categories) reads
    /// this one. It is fewer than the Health catalog's entries, which also
    /// hold the characteristics, correlations and kinds no category browses.
    static var measureCount: Int {
        categories.reduce(0) { $0 + $1.types.count }
    }

    static let categories: [BodyCategory] = [
        BodyCategory("Activity", symbol: "flame.fill", [
            "HKQuantityTypeIdentifierStepCount",
            "HKQuantityTypeIdentifierActiveEnergyBurned",
            "HKQuantityTypeIdentifierBasalEnergyBurned",
            "HKQuantityTypeIdentifierAppleExerciseTime",
            "HKQuantityTypeIdentifierAppleMoveTime",
            "HKQuantityTypeIdentifierAppleStandTime",
            "HKQuantityTypeIdentifierFlightsClimbed",
            "HKQuantityTypeIdentifierDistanceWalkingRunning",
            "HKQuantityTypeIdentifierDistanceCycling",
            "HKQuantityTypeIdentifierDistanceSwimming",
            "HKQuantityTypeIdentifierSwimmingStrokeCount",
            "HKQuantityTypeIdentifierPhysicalEffort",
            "HKQuantityTypeIdentifierDistanceWheelchair",
            "HKQuantityTypeIdentifierPushCount",
            "HKCategoryTypeIdentifierAppleStandHour",
        ]),
        BodyCategory("Body Measurements", symbol: "figure.arms.open", [
            "HKQuantityTypeIdentifierBodyMass",
            "HKQuantityTypeIdentifierBodyMassIndex",
            "HKQuantityTypeIdentifierBodyFatPercentage",
            "HKQuantityTypeIdentifierLeanBodyMass",
            "HKQuantityTypeIdentifierHeight",
            "HKQuantityTypeIdentifierWaistCircumference",
        ]),
        BodyCategory("Cycle Tracking", symbol: "drop.fill", [
            "HKCategoryTypeIdentifierMenstrualFlow",
            "HKCategoryTypeIdentifierIntermenstrualBleeding",
            "HKCategoryTypeIdentifierCervicalMucusQuality",
            "HKCategoryTypeIdentifierOvulationTestResult",
            "HKCategoryTypeIdentifierProgesteroneTestResult",
            "HKCategoryTypeIdentifierSexualActivity",
            "HKQuantityTypeIdentifierBasalBodyTemperature",
        ]),
        BodyCategory("Hearing", symbol: "ear.fill", [
            "HKQuantityTypeIdentifierEnvironmentalAudioExposure",
            "HKQuantityTypeIdentifierHeadphoneAudioExposure",
            "HKQuantityTypeIdentifierEnvironmentalSoundReduction",
            "HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent",
            "HKCategoryTypeIdentifierHeadphoneAudioExposureEvent",
        ]),
        BodyCategory("Heart", symbol: "heart.fill", [
            "HKQuantityTypeIdentifierHeartRate",
            "HKQuantityTypeIdentifierRestingHeartRate",
            "HKQuantityTypeIdentifierWalkingHeartRateAverage",
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
            "HKQuantityTypeIdentifierVO2Max",
            "HKQuantityTypeIdentifierAtrialFibrillationBurden",
            "HKQuantityTypeIdentifierPeripheralPerfusionIndex",
            "HKCategoryTypeIdentifierHighHeartRateEvent",
            "HKCategoryTypeIdentifierLowHeartRateEvent",
            "HKCategoryTypeIdentifierIrregularHeartRhythmEvent",
            "HKCategoryTypeIdentifierLowCardioFitnessEvent",
        ]),
        BodyCategory("Medications", symbol: "pills.fill", [
            "HKQuantityTypeIdentifierInhalerUsage",
            "HKQuantityTypeIdentifierInsulinDelivery",
        ]),
        BodyCategory("Mental Wellbeing", symbol: "brain.head.profile", [
            "HKCategoryTypeIdentifierMindfulSession",
            "HKQuantityTypeIdentifierTimeInDaylight",
            "HKCategoryTypeIdentifierMoodChanges",
            "HKQuantityTypeIdentifierElectrodermalActivity",
        ]),
        BodyCategory("Mobility", symbol: "figure.walk.motion", [
            "HKQuantityTypeIdentifierWalkingSpeed",
            "HKQuantityTypeIdentifierWalkingStepLength",
            "HKQuantityTypeIdentifierWalkingAsymmetryPercentage",
            "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage",
            "HKQuantityTypeIdentifierAppleWalkingSteadiness",
            "HKQuantityTypeIdentifierSixMinuteWalkTestDistance",
            "HKQuantityTypeIdentifierStairAscentSpeed",
            "HKQuantityTypeIdentifierStairDescentSpeed",
            "HKQuantityTypeIdentifierRunningSpeed",
            "HKQuantityTypeIdentifierRunningStrideLength",
            "HKQuantityTypeIdentifierRunningVerticalOscillation",
            "HKQuantityTypeIdentifierRunningGroundContactTime",
            "HKQuantityTypeIdentifierRunningPower",
            "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent",
            "HKQuantityTypeIdentifierNumberOfTimesFallen",
        ]),
        BodyCategory("Nutrition", symbol: "carrot.fill", [
            "HKQuantityTypeIdentifierDietaryEnergyConsumed",
            "HKQuantityTypeIdentifierDietaryWater",
            "HKQuantityTypeIdentifierDietaryCarbohydrates",
            "HKQuantityTypeIdentifierDietaryProtein",
            "HKQuantityTypeIdentifierDietaryFatTotal",
            "HKQuantityTypeIdentifierDietaryFiber",
            "HKQuantityTypeIdentifierDietarySugar",
            "HKQuantityTypeIdentifierDietarySodium",
            "HKQuantityTypeIdentifierDietaryCaffeine",
            "HKQuantityTypeIdentifierDietaryCholesterol",
            "HKQuantityTypeIdentifierDietaryIron",
            "HKQuantityTypeIdentifierDietaryCalcium",
        ]),
        BodyCategory("Respiratory", symbol: "lungs.fill", [
            "HKQuantityTypeIdentifierRespiratoryRate",
            "HKQuantityTypeIdentifierOxygenSaturation",
            "HKQuantityTypeIdentifierForcedVitalCapacity",
            "HKQuantityTypeIdentifierForcedExpiratoryVolume1",
            "HKQuantityTypeIdentifierPeakExpiratoryFlowRate",
            "HKCategoryTypeIdentifierShortnessOfBreath",
            "HKCategoryTypeIdentifierWheezing",
        ]),
        BodyCategory("Sleep", symbol: "bed.double.fill", [
            "HKCategoryTypeIdentifierSleepAnalysis",
            "HKQuantityTypeIdentifierAppleSleepingWristTemperature",
            "HKCategoryTypeIdentifierSleepApneaEvent",
            "HKCategoryTypeIdentifierSleepChanges",
        ]),
        BodyCategory("Symptoms", symbol: "stethoscope", [
            "HKCategoryTypeIdentifierHeadache",
            "HKCategoryTypeIdentifierFatigue",
            "HKCategoryTypeIdentifierFever",
            "HKCategoryTypeIdentifierChestTightnessOrPain",
            "HKCategoryTypeIdentifierDizziness",
            "HKCategoryTypeIdentifierNausea",
            "HKCategoryTypeIdentifierCoughing",
            "HKCategoryTypeIdentifierSoreThroat",
            "HKCategoryTypeIdentifierLowerBackPain",
            "HKCategoryTypeIdentifierGeneralizedBodyAche",
            "HKCategoryTypeIdentifierNightSweats",
            "HKCategoryTypeIdentifierMemoryLapse",
        ]),
        BodyCategory("Vitals", symbol: "waveform.path.ecg", [
            "HKQuantityTypeIdentifierHeartRate",
            "HKQuantityTypeIdentifierBloodPressureSystolic",
            "HKQuantityTypeIdentifierBloodPressureDiastolic",
            "HKQuantityTypeIdentifierBodyTemperature",
            "HKQuantityTypeIdentifierRespiratoryRate",
            "HKQuantityTypeIdentifierOxygenSaturation",
            "HKQuantityTypeIdentifierBloodGlucose",
        ]),
        BodyCategory("Other Data", symbol: "ellipsis.circle.fill", [
            "HKQuantityTypeIdentifierUVExposure",
            "HKQuantityTypeIdentifierBloodAlcoholContent",
            "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages",
            "HKQuantityTypeIdentifierWaterTemperature",
            "HKQuantityTypeIdentifierUnderwaterDepth",
            "HKCategoryTypeIdentifierToothbrushingEvent",
            "HKCategoryTypeIdentifierHandwashingEvent",
        ]),
    ]

    /// Every data type the browse list can reach, each named once.
    ///
    /// Deduplicated on purpose: heart rate is both a heart reading and a vital,
    /// and a search that answered with it twice would read as a bug. The first
    /// category that claims a type keeps it.
    static let allTypes: [BodyDataType] = {
        var seen: Set<String> = []
        return categories.flatMap(\.types).filter { seen.insert($0.id).inserted }
    }()

    /// Data types whose name carries the query, in catalog order.
    static func search(_ query: String) -> [BodyDataType] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return allTypes.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Categories whose name carries the query.
    static func searchCategories(_ query: String) -> [BodyCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return categories.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

extension HealthMetric {
    /// The identifier as a person reads it.
    ///
    /// Derived rather than tabulated. A table of 192 names is 192 chances for a
    /// name to drift away from the identifier beside it, and the identifiers
    /// already spell the words out: the only work is telling where one word
    /// ends and the next starts.
    var displayName: String {
        let stripped = identifier
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCharacteristicTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCorrelationTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKWorkoutTypeIdentifier", with: "Workout")

        let characters = Array(stripped)
        var words = ""

        for (index, character) in characters.enumerated() {
            guard index > 0 else {
                words.append(character)
                continue
            }
            let previous = characters[index - 1]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            // A capital opens a word when it follows a lowercase letter, and
            // when it ends a run of capitals that is turning back into a word:
            // so VO2Max splits once and SDNN not at all.
            let opensWord: Bool
            if character.isUppercase {
                opensWord = previous.isLowercase
                    || previous.isNumber
                    || (previous.isUppercase && (next?.isLowercase ?? false))
            } else if character.isNumber {
                opensWord = previous.isLowercase
            } else {
                opensWord = false
            }

            if opensWord { words.append(" ") }
            words.append(character)
        }

        return words
    }
}

extension HealthUnit {
    /// The unit as it is written beside a value.
    var shortLabel: String? {
        switch self {
        case .count: nil
        case .countPerMinute: "bpm"
        case .kilocalorie: "kcal"
        case .kilocaloriePerKilogramHour: "kcal/kg·h"
        case .meter: "m"
        case .centimeter: "cm"
        case .minute: "min"
        case .hour: "h"
        case .second: "s"
        case .millisecond: "ms"
        case .percent: "%"
        case .millimeterOfMercury: "mmHg"
        case .kilogram: "kg"
        case .degreeCelsius: "°C"
        case .millilitrePerKilogramMinute: "ml/kg·min"
        case .metrePerSecond: "m/s"
        case .watt: "W"
        case .milligramPerDecilitre: "mg/dL"
        case .microsiemens: "µS"
        case .decibelASPL: "dB"
        case .decibelHearingLevel: "dB"
        case .litre: "L"
        case .litrePerMinute: "L/min"
        case .internationalUnit: "IU"
        case .gram: "g"
        case .milligram: "mg"
        case .microgram: "µg"
        case .none: nil
        }
    }
}

extension BodyCategory {
    /// The category's colour, as Apple Health paints it.
    var hue: SomaHealthHue {
        switch title {
        case "Activity": .activity
        case "Body Measurements": .body
        case "Cycle Tracking": .cycle
        case "Hearing": .hearing
        case "Heart": .heart
        case "Medications": .medications
        case "Mental Wellbeing": .mind
        case "Mobility": .mobility
        case "Nutrition": .nutrition
        case "Respiratory": .respiratory
        case "Sleep": .sleep
        case "Symptoms": .symptoms
        case "Vitals": .vitals
        default: .other
        }
    }

    /// The category a data type is listed under, for its hue on its own page.
    static func containing(_ type: BodyDataType) -> BodyCategory? {
        BodyCatalog.categories.first { $0.types.contains(type) }
    }
}
