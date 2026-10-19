//
//  SomaProfile.swift
//  Prism
//

import Foundation

/// What a person picked as mattering most, on the onboarding Focus step.
///
/// Six areas. The order they were picked in is
/// kept, because the picks rank the tools two steps later.
nonisolated enum FocusArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case sleep
    case energy
    case stress
    case longevity
    case skin
    case routines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: String(localized: "Sleep")
        case .energy: String(localized: "Energy and performance")
        case .stress: String(localized: "Stress and nervous system")
        case .longevity: String(localized: "Longevity and recovery")
        case .skin: String(localized: "Skin and appearance")
        case .routines: String(localized: "Routines and challenges")
        }
    }
}

/// The answer to the biological sex question, which feeds biological age,
/// metabolism and maximum heart rate.
nonisolated enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male
    case female
    /// Other, or prefer not to say: the arithmetic that needs a sex then uses
    /// the average of the two.
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: String(localized: "Male")
        case .female: String(localized: "Female")
        case .other: String(localized: "Other, or prefer not to say")
        }
    }
}

/// What a person told Soma about themselves during onboarding.
///
/// Every field is optional: a step skipped leaves a gap, and whatever reads
/// the profile treats a gap as unknown rather than guessing.
nonisolated struct SomaProfile: Codable, Equatable, Sendable {
    /// The first name Soma calls them by.
    var name: String?
    /// Their date of birth, as a day.
    var birthday: Date?
    var sex: BiologicalSex?
    /// The focus areas in the order they were picked.
    var focus: [FocusArea] = []
    /// The five rMEQ answers, when the questionnaire was saved.
    var chronotype: RMEQAnswers?
    var chronotypeAnsweredAt: Date?
    /// The stable identifier Sign in with Apple hands back, when they used it.
    var appleUserID: String?
    /// The email Sign in with Apple shared, if it shared one.
    var email: String?
    /// When onboarding was finished. Nil until the last step.
    var onboardedAt: Date?

    /// The name trimmed, or nil when there is none.
    var firstName: String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whole years on `date`, or nil without a birthday.
    func age(on date: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let birthday else { return nil }
        return Self.age(born: birthday, on: date, calendar: calendar)
    }

    static func age(born: Date, on date: Date, calendar: Calendar = .current) -> Int? {
        let years = calendar.dateComponents([.year], from: calendar.startOfDay(for: born), to: calendar.startOfDay(for: date)).year
        guard let years, years >= 0 else { return nil }
        return years
    }

    /// The chronotype the answers place, or nil before the questionnaire.
    var chronotypeCategory: ChronotypeCategory? {
        guard let chronotype, chronotype.isComplete else { return nil }
        return chronotype.category
    }
}
