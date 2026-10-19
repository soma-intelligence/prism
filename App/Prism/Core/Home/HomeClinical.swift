//
//  HomeClinical.swift
//  Prism
//

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// What Apple Health knows about the person that is not a sample: date of
/// birth, sex and blood type, the three the medical card leads with.
///
/// The source Soma reads through answers only the date of birth, as an age,
/// so the card reads these facts from the Health store itself, after
/// `HealthDashboard.prepare(_:)` has asked for them.
struct HomeClinical: Equatable, Sendable {
    var birth: DateComponents?
    var sex: String?
    var bloodType: String?

    static let characteristics = [HomeMetric.dateOfBirth, HomeMetric.biologicalSex, HomeMetric.bloodType]

    /// Reads the three facts, or nothing where Health is absent.
    static func read() -> HomeClinical {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return HomeClinical() }
        let store = HKHealthStore()
        var clinical = HomeClinical()
        clinical.birth = try? store.dateOfBirthComponents()
        if let sex = try? store.biologicalSex().biologicalSex {
            clinical.sex = switch sex {
            case .female: "Female"
            case .male: "Male"
            case .other: "Other"
            default: nil
            }
        }
        if let type = try? store.bloodType().bloodType {
            clinical.bloodType = Self.name(type)
        }
        return clinical
#else
        return HomeClinical()
#endif
    }

#if canImport(HealthKit)
    static func name(_ type: HKBloodType) -> String? {
        switch type {
        case .aPositive: "A positive"
        case .aNegative: "A negative"
        case .bPositive: "B positive"
        case .bNegative: "B negative"
        case .abPositive: "AB positive"
        case .abNegative: "AB negative"
        case .oPositive: "O positive"
        case .oNegative: "O negative"
        default: nil
        }
    }
#endif
}
