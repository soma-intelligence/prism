//
//  TrackHealthWriter.swift
//  Prism
//

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Writes what a person logs in Track to Apple Health, where Health has a
/// type for it: body mass, height, waist, water, caffeine, the energy and the
/// three macronutrients of a meal, mindful minutes, and a state of mind.
///
/// Health asks for write access one type at a time, the first time Soma
/// saves that type, never at launch. Every call answers whether the sample
/// reached Health, so the sheet says "Saved to Apple Health" only when it
/// did. The entry itself is always kept in ``TrackLogStore`` first.
@MainActor
enum TrackHealthWriter {
    /// A quantity Health can hold, with the value in Health's own unit.
    enum Quantity: Sendable {
        case bodyMass(kilograms: Double)
        case height(centimetres: Double)
        case waist(centimetres: Double)
        case water(millilitres: Double)
        case caffeine(milligrams: Double)
        case energy(kilocalories: Double)
        case protein(grams: Double)
        case carbohydrates(grams: Double)
        case fat(grams: Double)
    }

    /// The state of mind a mood entry carries.
    struct Mood: Sendable {
        /// -1...1.
        var valence: Double
        var isDaily: Bool
        var words: [String]
        var contexts: [String]
    }

    /// Off in the empty Health mode UI tests launch with, and on a device
    /// without Health.
    static var isAvailable: Bool {
#if canImport(HealthKit)
        guard !UserDefaults.standard.bool(forKey: "health.empty") else { return false }
        guard Bundle.main.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil else { return false }
        return HKHealthStore.isHealthDataAvailable()
#else
        return false
#endif
    }

    /// Saves quantities taken at one moment. True when every one reached
    /// Health.
    @discardableResult
    static func save(_ quantities: [Quantity], at date: Date) async -> Bool {
#if canImport(HealthKit)
        guard isAvailable, !quantities.isEmpty else { return false }
        let samples = quantities.map { sample($0, at: date) }
        return await save(samples)
#else
        return false
#endif
    }

    /// Saves a logged drink: its water, and its caffeine when it has some.
    @discardableResult
    static func saveDrink(_ entry: TrackDrinkEntry) async -> Bool {
        var quantities: [Quantity] = []
        if entry.ml > 0 { quantities.append(.water(millilitres: entry.ml)) }
        if entry.caffeineMg > 0 { quantities.append(.caffeine(milligrams: entry.caffeineMg)) }
        return await save(quantities, at: entry.date)
    }

    /// Saves a mindful session of `minutes` ending at `end`.
    @discardableResult
    static func saveMindful(minutes: Double, endingAt end: Date) async -> Bool {
#if canImport(HealthKit)
        guard isAvailable, minutes > 0 else { return false }
        let sample = HKCategorySample(
            type: HKCategoryType(.mindfulSession),
            value: HKCategoryValue.notApplicable.rawValue,
            start: end.addingTimeInterval(-minutes * 60),
            end: end
        )
        return await save([sample])
#else
        return false
#endif
    }

    /// Saves a mood as a state of mind.
    @discardableResult
    static func saveMood(_ mood: Mood, at date: Date) async -> Bool {
#if canImport(HealthKit)
        guard isAvailable else { return false }
        let sample = HKStateOfMind(
            date: date,
            kind: mood.isDaily ? .dailyMood : .momentaryEmotion,
            valence: min(max(mood.valence, -1), 1),
            labels: mood.words.compactMap(label(for:)),
            associations: mood.contexts.compactMap(association(for:))
        )
        return await save([sample])
#else
        return false
#endif
    }

#if canImport(HealthKit)
    private static let store = HKHealthStore()

    private static func save(_ samples: [HKSample]) async -> Bool {
        let types = Set(samples.map(\.sampleType))
        do {
            try await store.requestAuthorization(toShare: types, read: [])
            guard types.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else { return false }
            try await store.save(samples)
            return true
        } catch {
            return false
        }
    }

    private static func sample(_ quantity: Quantity, at date: Date) -> HKQuantitySample {
        let (identifier, value, unit): (HKQuantityTypeIdentifier, Double, HKUnit) = switch quantity {
        case .bodyMass(let kilograms): (.bodyMass, kilograms, .gramUnit(with: .kilo))
        case .height(let centimetres): (.height, centimetres, .meterUnit(with: .centi))
        case .waist(let centimetres): (.waistCircumference, centimetres, .meterUnit(with: .centi))
        case .water(let millilitres): (.dietaryWater, millilitres, .literUnit(with: .milli))
        case .caffeine(let milligrams): (.dietaryCaffeine, milligrams, .gramUnit(with: .milli))
        case .energy(let kilocalories): (.dietaryEnergyConsumed, kilocalories, .kilocalorie())
        case .protein(let grams): (.dietaryProtein, grams, .gram())
        case .carbohydrates(let grams): (.dietaryCarbohydrates, grams, .gram())
        case .fat(let grams): (.dietaryFatTotal, grams, .gram())
        }
        return HKQuantitySample(
            type: HKQuantityType(identifier),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: date,
            end: date
        )
    }

    /// The Health label for one of the mood sheet's words.
    private static func label(for word: String) -> HKStateOfMind.Label? {
        switch word.lowercased() {
        case "calm": .calm
        case "content": .content
        case "grateful": .grateful
        case "hopeful": .hopeful
        case "tired": .drained
        case "happy": .happy
        case "stressed": .stressed
        case "anxious": .anxious
        case "irritated": .irritated
        case "sad": .sad
        case "excited": .excited
        case "confident": .confident
        case "peaceful": .peaceful
        case "overwhelmed": .overwhelmed
        case "lonely": .lonely
        case "proud": .proud
        default: nil
        }
    }

    /// The Health association for one of the mood sheet's contexts.
    private static func association(for context: String) -> HKStateOfMind.Association? {
        switch context.lowercased() {
        case "work": .work
        case "family": .family
        case "fitness": .fitness
        case "health": .health
        case "partner": .partner
        case "friends": .friends
        case "sleep": nil
        case "weather": .weather
        case "money": .money
        case "self care": .selfCare
        case "education": .education
        case "travel": .travel
        default: nil
        }
    }
#endif
}
