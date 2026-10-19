//
//  ShareCard.swift
//  Prism
//

import Foundation
import SomaUI

/// A card the Share studio can hand over, built from today's real scores.
///
/// Every gallery card comes with a skin, a size and a switch for exact numbers,
/// over the scores `SomaScores` works out; a card whose score the store does not hold
/// is not offered, rather than drawn with a dash on it.
nonisolated struct ShareCard: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: String, CaseIterable, Identifiable, Sendable {
        case sleep, mind, activity, energy
        var id: String { rawValue }

        var eyebrow: String {
            switch self {
            case .sleep: String(localized: "Last night")
            case .mind: String(localized: "Mind")
            case .activity: String(localized: "Activity")
            case .energy: String(localized: "Energy")
            }
        }

        var aspect: SomaAspect {
            switch self {
            case .sleep: .sleep
            case .mind: .mind
            case .activity: .activity
            case .energy: .body
            }
        }
    }

    var kind: Kind
    var score: Int
    var trend: SomaTrend?
    /// The last days of the score, oldest first, for the card's small chart.
    var series: [Double?]
    /// A line under the number, when there is one: "7:12 asleep".
    var detail: String?

    var id: Kind { kind }

    /// The number, or with exact numbers off, only which way it went.
    func headline(exact: Bool) -> String {
        if exact { return "\(score)" }
        switch trend {
        case .up: return String(localized: "Better than usual")
        case .down: return String(localized: "Lower than usual")
        case nil: return String(localized: "About usual")
        }
    }

    /// The cards today's scores allow, in the studio's order.
    static func cards(from scores: SomaScores?, sleepClock: String?) -> [ShareCard] {
        guard let scores else { return [] }
        var cards: [ShareCard] = []
        if let sleep = scores.sleep {
            cards.append(ShareCard(kind: .sleep, score: sleep, trend: scores.sleepTrend,
                                   series: scores.sleepSeries, detail: sleepClock.map { String(localized: "\($0) asleep") }))
        }
        if let mind = scores.mind {
            cards.append(ShareCard(kind: .mind, score: mind, trend: scores.mindTrend, series: scores.mindSeries, detail: nil))
        }
        if let strain = scores.strain {
            cards.append(ShareCard(kind: .activity, score: strain, trend: scores.strainTrend, series: scores.strainSeries, detail: nil))
        }
        if let energy = scores.energy {
            cards.append(ShareCard(kind: .energy, score: energy, trend: scores.energyTrend, series: scores.energySeries, detail: nil))
        }
        return cards
    }
}

/// How the chosen card is dressed before it leaves the phone.
nonisolated struct ShareStyle: Equatable, Sendable {
    nonisolated enum Background: String, CaseIterable, Identifiable, Sendable {
        case orb, plain, clear
        var id: String { rawValue }
        var title: String {
            switch self {
            case .orb: String(localized: "Orb")
            case .plain: String(localized: "Plain")
            case .clear: String(localized: "Clear")
            }
        }
    }

    nonisolated enum Size: String, CaseIterable, Identifiable, Sendable {
        case story, post, square
        var id: String { rawValue }
        var title: String {
            switch self {
            case .story: String(localized: "Story")
            case .post: String(localized: "Post")
            case .square: String(localized: "Square")
            }
        }
        /// Width over height.
        var aspectRatio: Double {
            switch self {
            case .story: 9.0 / 16.0
            case .post: 4.0 / 5.0
            case .square: 1
            }
        }
        /// The exported image's width in points, rendered at 3x.
        static let exportWidth: Double = 360
    }

    var background: Background = .orb
    var size: Size = .story
    var exactNumbers = true
    var showsDate = true
}
