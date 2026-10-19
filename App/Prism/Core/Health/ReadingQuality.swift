//
//  ReadingQuality.swift
//  Prism
//

import Foundation
import HealthExportCore

/// How much weight one reading can bear, read off where it came from.
///
/// A grade of provenance, not of the value: it says what kind of instrument
/// took the reading, never whether the number is right. The rules run in
/// order and the first that matches decides:
///
/// 1. Typed in by a person: ``Level/manual``.
/// 2. A metric an algorithm works out rather than a sensor measures (VO2 max,
///    energy burned, BMI, walking steadiness): ``Level/estimated``, whatever
///    the device.
/// 3. A chest strap on a heart metric, or a cuff on blood pressure:
///    ``Level/reference``, the closest a wearable gets to the measurement a
///    clinic would take.
/// 4. A wrist, ring, chest strap off its heart metrics, scale or glucose
///    sensor: ``Level/sensor``.
/// 5. A phone, which infers from motion: ``Level/estimated``.
/// 6. Nothing recognised: ``Level/unknown``.
///
/// Matching is on lowercased words from the device name, the device model and
/// the source app, so a renamed watch still matches on its model.
struct ReadingQuality: Equatable, Sendable {
    enum Level: Int, Comparable, CaseIterable, Sendable {
        case unknown = 0
        case manual = 1
        case estimated = 2
        case sensor = 3
        case reference = 4

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        /// How many of the four marks it fills.
        var marks: Int { rawValue }

        var title: String {
            switch self {
            case .unknown: "Unknown"
            case .manual: "Manual"
            case .estimated: "Estimated"
            case .sensor: "Sensor"
            case .reference: "Reference"
            }
        }
    }

    let level: Level
    /// A few words on why: "Chest strap", "Entered by hand".
    let reason: String

    /// How many marks a grade is drawn with.
    static let scale = 4

    static func grade(_ reading: HealthReading) -> ReadingQuality {
        grade(
            metric: reading.metric,
            device: reading.device,
            deviceModel: reading.deviceModel,
            source: reading.source,
            wasUserEntered: reading.wasUserEntered
        )
    }

    static func grade(
        metric: String,
        device: String?,
        deviceModel: String?,
        source: String?,
        wasUserEntered: Bool
    ) -> ReadingQuality {
        if wasUserEntered {
            return ReadingQuality(level: .manual, reason: "Entered by hand")
        }
        if derived.contains(metric) {
            return ReadingQuality(level: .estimated, reason: "Worked out by an algorithm")
        }

        let hardware = [device, deviceModel]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let text = [hardware, source?.lowercased() ?? ""].joined(separator: " ")

        if matches(text, chestStraps) {
            return heartMetrics.contains(metric)
                ? ReadingQuality(level: .reference, reason: "Chest strap")
                : ReadingQuality(level: .sensor, reason: "Chest strap")
        }
        if matches(text, cuffs) {
            return pressureMetrics.contains(metric)
                ? ReadingQuality(level: .reference, reason: "Cuff")
                : ReadingQuality(level: .sensor, reason: "Cuff")
        }
        if matches(text, rings) {
            return ReadingQuality(level: .sensor, reason: "Ring")
        }
        if matches(text, glucoseSensors) {
            return ReadingQuality(level: .sensor, reason: "Glucose sensor")
        }
        if matches(text, scales) {
            return ReadingQuality(level: .sensor, reason: "Scale")
        }
        if matches(text, wrists) {
            return ReadingQuality(level: .sensor, reason: "Wrist sensor")
        }
        if matches(text, phones) {
            return ReadingQuality(level: .estimated, reason: "Phone motion")
        }
        return ReadingQuality(level: .unknown, reason: "Source not recognised")
    }

    private static func matches(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    // MARK: - Rule tables

    /// Read before the wrist list: "garmin hrm" would otherwise read as a
    /// Garmin watch.
    static let chestStraps = ["polar h", "h10", "hrm", "tickr", "chest strap", "movesense"]
    static let cuffs = ["omron", "bpm connect", "bpm core", "qardio", "cuff"]
    static let rings = ["oura", "ultrahuman", "ringconn", "galaxy ring", "circular"]
    static let glucoseSensors = ["dexcom", "libre", "stelo", "lingo"]
    static let scales = ["withings", "scale", "renpho", "eufy", "body+", "body comp", "qardiobase"]
    static let wrists = ["watch", "whoop", "garmin", "fitbit", "polar", "coros", "suunto", "amazfit", "band"]
    static let phones = ["iphone", "phone"]

    static let heartMetrics: Set<String> = [
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierRestingHeartRate",
        "HKQuantityTypeIdentifierWalkingHeartRateAverage",
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
    ]

    static let pressureMetrics: Set<String> = [
        "HKQuantityTypeIdentifierBloodPressureSystolic",
        "HKQuantityTypeIdentifierBloodPressureDiastolic",
    ]

    /// Metrics no sensor reads directly: each is a model's output.
    static let derived: Set<String> = [
        "HKQuantityTypeIdentifierVO2Max",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
        "HKQuantityTypeIdentifierBasalEnergyBurned",
        "HKQuantityTypeIdentifierBodyMassIndex",
        "HKQuantityTypeIdentifierAppleWalkingSteadiness",
        "HKQuantityTypeIdentifierPhysicalEffort",
    ]
}
