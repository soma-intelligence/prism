//
//  Chronotype.swift
//  Prism
//

import Foundation

/// Where a person's body clock sits: early, late, or between the two.
///
/// The cutoffs are the published
/// boundaries of the reduced Morningness-Eveningness Questionnaire (Adan and
/// Almirall 1991); a measured estimate from logged nights replaces this seed
/// once there are enough of them, which is why the onboarding step says sleep
/// can tell you later.
nonisolated enum ChronotypeCategory: String, Codable, Sendable, CaseIterable {
    case morning
    case intermediate
    case evening

    /// The name every surface prints, so there is one spelling of each.
    var title: String {
        switch self {
        case .morning: String(localized: "Morning type")
        case .intermediate: String(localized: "Intermediate type")
        case .evening: String(localized: "Evening type")
        }
    }
}

/// The five rMEQ answers, each already mapped to its published point value.
///
/// Totals run from 4 to 25: 4 to 11 is evening, 12 to 17 intermediate, 18 to
/// 25 morning. The total and the category are derived, never stored, so they
/// cannot drift from the cutoffs.
nonisolated struct RMEQAnswers: Codable, Sendable, Equatable {
    /// The five per-item point values, in question order.
    var items: [Int]

    var total: Int { items.reduce(0, +) }
    var isComplete: Bool { items.count == RMEQCatalog.items.count }

    var category: ChronotypeCategory {
        switch total {
        case ...11: .evening
        case 12...17: .intermediate
        default: .morning
        }
    }
}

/// One answer on the questionnaire and what it scores.
nonisolated struct RMEQOption: Hashable, Sendable {
    let text: String
    let points: Int
}

/// One question and its answers, earliest first.
nonisolated struct RMEQItem: Hashable, Sendable {
    let prompt: String
    let options: [RMEQOption]
}

/// The reduced MEQ: items 1, 7, 10, 18 and 19 of the full questionnaire, with
/// its published point values and the shorter wording the Soma sheet prints.
nonisolated enum RMEQCatalog {
    static let items: [RMEQItem] = [
        RMEQItem(prompt: String(localized: "Free to plan your day, when would you get up?"), options: [
            RMEQOption(text: String(localized: "5:00 to 6:30"), points: 5),
            RMEQOption(text: String(localized: "6:30 to 7:45"), points: 4),
            RMEQOption(text: String(localized: "7:45 to 9:45"), points: 3),
            RMEQOption(text: String(localized: "9:45 to 11:00"), points: 2),
            RMEQOption(text: String(localized: "11:00 to 12:00"), points: 1),
        ]),
        RMEQItem(prompt: String(localized: "In the first half hour awake, how tired are you?"), options: [
            RMEQOption(text: String(localized: "Very tired"), points: 1),
            RMEQOption(text: String(localized: "Fairly tired"), points: 2),
            RMEQOption(text: String(localized: "Fairly refreshed"), points: 3),
            RMEQOption(text: String(localized: "Very refreshed"), points: 4),
        ]),
        RMEQItem(prompt: String(localized: "When in the evening do you feel ready for sleep?"), options: [
            RMEQOption(text: String(localized: "20:00 to 21:00"), points: 5),
            RMEQOption(text: String(localized: "21:00 to 22:15"), points: 4),
            RMEQOption(text: String(localized: "22:15 to 00:30"), points: 3),
            RMEQOption(text: String(localized: "00:30 to 01:45"), points: 2),
            RMEQOption(text: String(localized: "01:45 to 03:00"), points: 1),
        ]),
        RMEQItem(prompt: String(localized: "When in the day do you feel at your best?"), options: [
            RMEQOption(text: String(localized: "5:00 to 8:00"), points: 5),
            RMEQOption(text: String(localized: "8:00 to 10:00"), points: 4),
            RMEQOption(text: String(localized: "10:00 to 17:00"), points: 3),
            RMEQOption(text: String(localized: "17:00 to 22:00"), points: 2),
            RMEQOption(text: String(localized: "22:00 to 5:00"), points: 1),
        ]),
        RMEQItem(prompt: String(localized: "Morning or evening: which are you?"), options: [
            RMEQOption(text: String(localized: "Definitely morning"), points: 6),
            RMEQOption(text: String(localized: "More morning than evening"), points: 4),
            RMEQOption(text: String(localized: "More evening than morning"), points: 2),
            RMEQOption(text: String(localized: "Definitely evening"), points: 0),
        ]),
    ]
}
