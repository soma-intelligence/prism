//
//  LinkDetail.swift
//  Prism
//

import Foundation
import SomaUI

extension CauseLink {
    /// Where the outcome sits against the driver's day, from the same tables
    /// ``CauseLinks/compute(_:calendar:)`` reads.
    var lag: LinkMath.Lag {
        if case .tag = driver { return CauseLinks.tagLag }
        return CauseLinks.levels.first { $0.0 == driver && $0.1 == outcome }?.2 ?? .nextDay
    }

    /// The bar this link has to clear.
    var gate: LinkMath.Gate {
        if case .tag = driver { return .tag }
        return .level
    }

    var isTag: Bool {
        if case .tag = driver { return true }
        return false
    }
}

extension LinkOutcome {
    /// The aspect whose colour the outcome's line wears.
    var aspect: SomaAspect {
        switch self {
        case .sleepScore, .sleepOnset: .sleep
        case .hrv, .restingHeart: .heart
        case .energy, .recovery: .body
        }
    }

    /// When the outcome is read, as the plural a takeaway opens with.
    var moments: String {
        switch self {
        case .sleepScore, .sleepOnset: "Nights"
        case .hrv, .energy: "Mornings"
        case .recovery, .restingHeart: "Days"
        }
    }
}

/// Everything a link's detail sheet shows, worked out from the link alone:
/// the two sides, the outcome in time with the driver days marked, the facts
/// row, one takeaway, and for a link still held back how far it is from its
/// gate.
struct LinkDetail: Sendable, Equatable {
    /// One day of the outcome in time, keyed by the outcome's own day.
    struct Day: Sendable, Equatable {
        var date: Date
        /// The outcome in the shown unit; nil when the day was not paired.
        var value: Double?
        /// The side the comparison put the day on; nil when not paired.
        var side: LinkMath.Side?
    }

    /// How far a held link is toward showing.
    struct Progress: Sendable, Equatable {
        /// 0 to 1.
        var fraction: Double
        /// "3 of 5 nights with Sauna".
        var label: String
    }

    /// Days drawn in time, ending today.
    static let window = 90
    /// The strength (effect over the outcome's spread) each meter bar needs:
    /// the usual small, medium and large lines, and one past large.
    static let strengthSteps: [Double] = [0.2, 0.5, 0.8, 1.2]

    var link: CauseLink
    /// `window` days, oldest first, the last one today.
    var timeline: [Day]
    /// The outcome on each side, in the shown unit.
    var high: [Double]
    var low: [Double]
    /// The two rows' names: "With" and "Without", "Long" and "Short".
    var highLabel: String
    var lowLabel: String
    /// The gap as the headline states it: "−11 pts".
    var differenceText: String
    /// The smallest gap that counts: "±5 pts". Nil when it cannot be stated.
    var noiseText: String?
    /// "9 vs 41".
    var daysText: String
    /// Meter bars filled, out of `strengthSteps.count`.
    var strengthLevel: Int
    /// "Same night", "Next morning".
    var lagText: String
    /// "Nights after alcohol: 11 pts lower". Nil until the link is shown.
    var takeaway: String?
    /// Nil once the link is shown.
    var progress: Progress?

    init(link: CauseLink, today: Date, calendar: Calendar) {
        self.link = link
        let result = link.result
        let scale = link.outcome.scale
        let unit = link.outcome.unit

        high = result.high.map { $0 * scale }
        low = result.low.map { $0 * scale }
        if let sides = link.driver.sides {
            highLabel = sides.high.capitalized
            lowLabel = sides.low.capitalized
        } else {
            highLabel = "With"
            lowLabel = "Without"
        }
        differenceText = link.effect == nil ? "-" : "\(link.valueText) \(unit)"
        noiseText = result.noise.map { "\u{00B1}\(link.magnitudeText($0 * scale)) \(unit)" }
        daysText = "\(result.highDays) vs \(result.lowDays)"
        strengthLevel = Self.strengthSteps.filter { result.strength >= $0 }.count
        lagText = Self.lagText(link)
        takeaway = Self.takeaway(link)
        progress = Self.progress(link)
        timeline = Self.timeline(link, today: today, calendar: calendar)
    }

    // MARK: Derivations

    static func lagText(_ link: CauseLink) -> String {
        switch link.outcome {
        case .sleepScore, .sleepOnset: "Same night"
        case .hrv, .energy: link.lag == .sameDay ? "Same morning" : "Next morning"
        case .recovery, .restingHeart: link.lag == .sameDay ? "Same day" : "Next day"
        }
    }

    /// One phrase from the numbers, for a shown link only.
    static func takeaway(_ link: CauseLink) -> String? {
        guard link.result.isShown, let effect = link.effect, effect != 0 else { return nil }
        let word: String = if link.outcome == .sleepOnset {
            effect > 0 ? "later" : "earlier"
        } else {
            effect > 0 ? "higher" : "lower"
        }
        let amount = "\(link.magnitudeText(effect)) \(link.outcome.unit) \(word)"
        if let sides = link.driver.sides {
            return "After \(sides.high) \(link.driver.noun): \(amount)"
        }
        return "\(link.outcome.moments) after \(link.driver.name.lowercased()): \(amount)"
    }

    /// How far a held link is from its gate, in the terms it is held on:
    /// tagged days, paired days, or the gap against the noise.
    static func progress(_ link: CauseLink) -> Progress? {
        let result = link.result
        let need = link.gate.minimumDays
        let noun = link.driver.noun
        let name = link.driver.name
        switch result.verdict {
        case .shown:
            return nil
        case .notEnoughDays:
            if link.isTag {
                if result.highDays < need {
                    return Progress(fraction: Double(result.highDays) / Double(need),
                                    label: "\(result.highDays) of \(need) \(noun) with \(name)")
                }
                return Progress(fraction: Double(min(result.lowDays, need)) / Double(need),
                                label: "\(min(result.lowDays, need)) of \(need) \(noun) without \(name)")
            }
            // A level split needs a third of the paired days on each side.
            let total = need * 3
            let have = result.days.count
            if have < total {
                return Progress(fraction: Double(have) / Double(total), label: "\(have) of \(total) \(noun) measured")
            }
            // Enough days, but the driver barely moved across them.
            return Progress(fraction: 1, label: "\(name) too steady to compare")
        case .withinNoise:
            guard let delta = result.delta, let noise = result.noise, noise > 0 else {
                return Progress(fraction: 0, label: "Inside the noise")
            }
            let scale = link.outcome.scale
            return Progress(
                fraction: abs(delta) / noise,
                label: "Inside the noise: \(link.magnitudeText(delta * scale)) of \(link.magnitudeText(noise * scale)) \(link.outcome.unit)"
            )
        }
    }

    /// The last `window` days, each with the outcome on its own day and the
    /// side its driver day fell on.
    static func timeline(_ link: CauseLink, today: Date, calendar: Calendar) -> [Day] {
        var byDay: [Date: LinkMath.Day] = [:]
        for day in link.result.days {
            guard let outcomeDay = LinkMath.shift(day.day, by: link.lag.rawValue, calendar: calendar) else { continue }
            byDay[outcomeDay] = day
        }
        let end = calendar.startOfDay(for: today)
        return (0..<window).compactMap { index -> Day? in
            guard let date = calendar.date(byAdding: .day, value: index - (window - 1), to: end) else { return nil }
            let paired = byDay[date]
            return Day(date: date, value: paired.map { $0.outcome * link.outcome.scale }, side: paired?.side)
        }
    }
}
