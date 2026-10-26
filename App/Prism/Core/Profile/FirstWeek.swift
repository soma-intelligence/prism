//
//  FirstWeek.swift
//  Prism
//

import Foundation

/// The days before Soma knows a person's usual.
///
/// A score needs seven nights (`SomaScores.minimumNights`): before that there
/// is no band to read today against, and the pages show dashes. This is what
/// the Today page says about that stretch instead of pretending it is not
/// there.
nonisolated struct FirstWeek: Equatable, Sendable {
    /// Nights with sleep recorded, clamped to the week.
    let nights: Int
    static let length = 7

    init(nightsRecorded: Int) {
        nights = min(max(nightsRecorded, 0), Self.length)
    }

    /// Whether the week is still running.
    var isLearning: Bool { nights < Self.length }

    var toGo: Int { Self.length - nights }

    /// "Two nights in, five to go." The count written as a word, the way a
    /// sentence says it.
    var headline: String {
        switch nights {
        case 0: String(localized: "Your first night is tonight.")
        case 6: String(localized: "Six nights in, one to go.")
        default: String(localized: "\(Self.capitalized(Self.word(nights))) \(Self.nightsWord(nights)) in, \(Self.word(toGo)) to go.")
        }
    }

    static let reason = String(localized: "Soma learns your usual range from 7 nights with your watch. Until then, a reading without a usual shows as a dash.")

    static func word(_ number: Int) -> String {
        switch number {
        case 0: String(localized: "no")
        case 1: String(localized: "one")
        case 2: String(localized: "two")
        case 3: String(localized: "three")
        case 4: String(localized: "four")
        case 5: String(localized: "five")
        case 6: String(localized: "six")
        case 7: String(localized: "seven")
        default: number.formatted()
        }
    }

    static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    static func nightsWord(_ number: Int) -> String {
        number == 1 ? String(localized: "night") : String(localized: "nights")
    }
}
