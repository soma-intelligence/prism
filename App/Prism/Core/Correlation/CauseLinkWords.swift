//
//  CauseLinkWords.swift
//  Prism
//

import Foundation

/// The words the Trends cards say a link in: a headline that tells what
/// happens ("After a long night, your morning energy is higher"), one line
/// with its size and the days it rests on, and the two sides by name.
///
/// Plain on purpose (owner, 2026-10-19: Trends read too scientific): no
/// arrows, no "pts", one number per card.
extension LinkDriver {
    /// The high side as the start of a sentence: "After a long night".
    var after: String {
        switch self {
        case .sleepLength: "After a long night"
        case .strain: "After a hard day"
        case .steps: "After an active day"
        case .daylight: "After a bright day"
        case let .tag(id):
            switch id {
            case "alcohol": "After drinking"
            case "late-meal": "After a late meal"
            case "coffee-late": "After a late coffee"
            case "screens-in-bed": "After screens in bed"
            case "sauna": "After a sauna"
            case "meditation": "After meditating"
            case "hard-training": "After hard training"
            default: "After \(name.lowercased())"
            }
        }
    }

    /// The driver as a short noun for a list: "Long nights", "Alcohol".
    var plainName: String {
        switch self {
        case .sleepLength: "Long nights"
        case .strain: "Hard days"
        case .steps: "Active days"
        case .daylight: "Daylight"
        case .tag: name
        }
    }

    /// The two sides as the track under a card names them.
    var sideLabels: (high: String, low: String) {
        guard let sides else { return (name, "Without") }
        return ("\(sides.high.capitalized) \(noun)", "\(sides.low.capitalized) \(noun)")
    }
}

extension LinkOutcome {
    /// The outcome as the subject of a sentence.
    var subject: String {
        switch self {
        case .sleepScore: "your sleep score"
        case .hrv: "your morning HRV"
        case .energy: "your morning energy"
        case .recovery: "your recovery"
        case .restingHeart: "your resting heart rate"
        case .sleepOnset: "you"
        }
    }

    /// The outcome in a short list name: "Hard days and recovery".
    var plainName: String {
        switch self {
        case .sleepScore: "sleep"
        case .hrv: "HRV"
        case .energy: "energy"
        case .recovery: "recovery"
        case .restingHeart: "resting heart rate"
        case .sleepOnset: "bedtime"
        }
    }

    /// The unit spelled out where it reads better: "points", "minutes".
    var unitWords: String {
        switch self {
        case .sleepScore, .energy, .recovery: "points"
        case .hrv: "ms"
        case .restingHeart: "bpm"
        case .sleepOnset: "minutes"
        }
    }
}

extension CauseLink {
    /// What happens, in one sentence. A link with no difference yet is named
    /// rather than stated.
    var headline: String {
        guard let effect, effect != 0 else { return plainTitle }
        if outcome == .sleepOnset {
            return "\(driver.after), you fall asleep \(effect > 0 ? "later" : "earlier")"
        }
        return "\(driver.after), \(outcome.subject) is \(effect > 0 ? "higher" : "lower")"
    }

    /// The size and the days it rests on: "About 5 points, across 60 nights".
    var plainDetail: String {
        let days = result.highDays + result.lowDays
        guard let effect else { return "\(days) \(driver.noun) so far" }
        return "About \(magnitudeText(effect)) \(outcome.unitWords), across \(days) \(driver.noun)"
    }

    /// The link as a short name, for the list of those still learning:
    /// "Hard days and recovery".
    var plainTitle: String {
        "\(driver.plainName) and \(outcome.plainName)"
    }
}
