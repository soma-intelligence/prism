//
//  CauseLinks.swift
//  Prism
//

import Foundation
import SomaUI

/// The daily series the links are read from, each keyed by the start of a day.
///
/// Night readings are keyed by the morning the night ended on (the wake day),
/// the way the score engine attributes them. Everything here comes from Apple
/// Health, the score engine's own daily series, or the Journal.
struct LinkSeries: Sendable, Equatable {
    /// Hours asleep in the night that ended on the day.
    var sleepHours: [Date: Double] = [:]
    /// The sleep score of the night that ended on the day.
    var sleepScore: [Date: Double] = [:]
    /// When that night's sleep began, in clock hours (above 24 after midnight).
    var sleepOnset: [Date: Double] = [:]
    /// The median HRV measured before noon on the day, in ms.
    var morningHRV: [Date: Double] = [:]
    /// The day's recovery score.
    var recovery: [Date: Double] = [:]
    /// The energy bank on waking, 0 to 100.
    var energy: [Date: Double] = [:]
    /// The day's resting heart rate, in bpm.
    var restingHeart: [Date: Double] = [:]
    /// The day's strain score.
    var strain: [Date: Double] = [:]
    /// The day's step count.
    var steps: [Date: Double] = [:]
    /// Minutes spent in daylight on the day.
    var daylight: [Date: Double] = [:]
    /// The days each Journal tag was logged on, by tag id.
    var tagDays: [String: Set<Date>] = [:]
    /// The first day anything was logged in the Journal: untagged days before
    /// it say nothing about the tag.
    var firstJournalDay: Date?
}

/// What a link is driven by.
enum LinkDriver: Sendable, Hashable {
    case sleepLength
    case strain
    case steps
    case daylight
    /// A Journal tag, by id.
    case tag(String)

    /// The Journal tags measured, with the short name a card uses.
    static let tags: [(id: String, name: String)] = [
        ("alcohol", "Alcohol"),
        ("late-meal", "Late meal"),
        ("coffee-late", "Late coffee"),
        ("screens-in-bed", "Screens in bed"),
        ("sauna", "Sauna"),
        ("meditation", "Meditation"),
        ("hard-training", "Hard training"),
    ]

    var name: String {
        switch self {
        case .sleepLength: "Sleep"
        case .strain: "Strain"
        case .steps: "Steps"
        case .daylight: "Daylight"
        case let .tag(id): Self.tags.first { $0.id == id }?.name ?? id
        }
    }

    /// The words for the two sides in the caption: "long" and "short"
    /// nights. A tag's sides go unnamed: "6 vs 40 nights".
    var sides: (high: String, low: String)? {
        switch self {
        case .sleepLength: ("long", "short")
        case .strain: ("hard", "easy")
        case .steps: ("active", "quiet")
        case .daylight: ("bright", "dim")
        case .tag: nil
        }
    }

    var noun: String {
        switch self {
        case .sleepLength, .tag: "nights"
        case .strain, .steps, .daylight: "days"
        }
    }
}

/// What a link is measured on.
enum LinkOutcome: Sendable, Hashable {
    case sleepScore
    case hrv
    case energy
    case recovery
    case restingHeart
    case sleepOnset

    var name: String {
        switch self {
        case .sleepScore: "Sleep"
        case .hrv: "HRV"
        case .energy: "Energy"
        case .recovery: "Recovery"
        case .restingHeart: "Resting HR"
        case .sleepOnset: "Bedtime"
        }
    }

    /// Which way is better. Nil for a reading with no better side: an earlier
    /// bedtime is neither good nor bad on its own.
    var better: EffectMath.Better? {
        switch self {
        case .sleepScore, .hrv, .energy, .recovery: .higher
        case .restingHeart: .lower
        case .sleepOnset: nil
        }
    }

    /// From the series' unit to the one shown: onset is in hours, shown in
    /// minutes.
    var scale: Double { self == .sleepOnset ? 60 : 1 }

    func series(in series: LinkSeries) -> [Date: Double] {
        switch self {
        case .sleepScore: series.sleepScore
        case .hrv: series.morningHRV
        case .energy: series.energy
        case .recovery: series.recovery
        case .restingHeart: series.restingHeart
        case .sleepOnset: series.sleepOnset
        }
    }
}

/// One driver set against one outcome, with its comparison.
struct CauseLink: Identifiable, Sendable, Equatable {
    var driver: LinkDriver
    var outcome: LinkOutcome
    var result: LinkMath.Result

    var id: String { "\(driver.name)>\(outcome.name)" }

    /// The effect in the shown unit, signed. Nil when a side is empty.
    var effect: Double? { result.delta.map { $0 * outcome.scale } }

    /// The effect, signed with a true minus: "\u{2212}11", "+0.8". A dash
    /// when there is none.
    var valueText: String {
        guard let effect else { return "-" }
        let magnitude = magnitudeText(effect)
        let isZero = Double(magnitude) == 0
        let sign = isZero ? "" : effect > 0 ? "+" : "\u{2212}"
        return sign + magnitude
    }

    /// A size in the shown unit, unsigned, with a decimal for a small move
    /// (and for resting heart rate under ten): "11", "2.4".
    func magnitudeText(_ value: Double) -> String {
        let decimals = (outcome == .restingHeart && abs(value) < 9.95) || abs(value) < 0.95 ? 1 : 0
        return String(format: "%.\(decimals)f", abs(value))
    }

    /// The day counts: "20 long vs 20 short nights", "6 vs 40 nights".
    var caption: String {
        let high = result.highDays
        let low = result.lowDays
        if let sides = driver.sides {
            return "\(high) \(sides.high) vs \(low) \(sides.low) \(driver.noun)"
        }
        return "\(high) vs \(low) \(driver.noun)"
    }

    /// In the outcome's favour, against it, or neither.
    var tone: SomaLinkTone {
        guard let better = outcome.better, let direction = result.direction else { return .neutral }
        switch (better, direction) {
        case (.higher, .rises), (.lower, .falls): return .good
        default: return .cost
        }
    }
}

/// The links the Trends page shows, worked out from ``LinkSeries``.
enum CauseLinks {
    /// Every link the app can read, split by the gate.
    struct Output: Sendable, Equatable {
        /// Links that cleared the gate, strongest first.
        var shown: [CauseLink]
        /// Links held back: too few days, or inside the noise.
        var pending: [CauseLink]

        /// The held links' plain names, once each, for the "Still learning"
        /// row: "Hard days and recovery".
        var pendingNames: [String] {
            var seen: Set<String> = []
            return pending.map(\.plainTitle).filter { seen.insert($0).inserted }
        }
    }

    /// The level links: a continuous driver and its outcome.
    static let levels: [(LinkDriver, LinkOutcome, LinkMath.Lag)] = [
        // Last night's sleep against this morning's HRV and energy: both are
        // keyed by the wake day, so the same day.
        (.sleepLength, .hrv, .sameDay),
        (.sleepLength, .energy, .sameDay),
        // Yesterday's strain against today's recovery and resting heart.
        (.strain, .recovery, .nextDay),
        (.strain, .restingHeart, .nextDay),
        // A day's steps against the night after it, which ends the next day.
        (.steps, .sleepScore, .nextDay),
        // A day's daylight against when the following night's sleep began.
        (.daylight, .sleepOnset, .nextDay),
    ]

    /// What each tag is set against: the night after it, and the morning
    /// after that night.
    static let tagOutcomes: [LinkOutcome] = [.sleepScore, .hrv]

    /// Both tag outcomes are keyed by the wake day: the night after a tagged
    /// day ends the next morning.
    static let tagLag: LinkMath.Lag = .nextDay

    static func compute(_ series: LinkSeries, calendar: Calendar) -> Output {
        var links: [CauseLink] = []

        for (driver, outcome, lag) in levels {
            let pairs = LinkMath.pairs(
                driver: driverSeries(driver, in: series),
                outcome: outcome.series(in: series),
                lag: lag,
                calendar: calendar
            )
            links.append(CauseLink(driver: driver, outcome: outcome, result: LinkMath.byLevel(pairs)))
        }

        // A tag never logged has nothing to wait for, so it is left out
        // rather than listed as needing days.
        for tag in LinkDriver.tags {
            guard let days = series.tagDays[tag.id], !days.isEmpty else { continue }
            for outcome in tagOutcomes {
                let result = LinkMath.byTag(days: days, outcome: outcome.series(in: series), lag: tagLag,
                                            since: series.firstJournalDay, calendar: calendar)
                links.append(CauseLink(driver: .tag(tag.id), outcome: outcome, result: result))
            }
        }

        let shown = links.filter(\.result.isShown)
            .sorted { $0.result.strength > $1.result.strength }
        let pending = links.filter { !$0.result.isShown }
        return Output(shown: shown, pending: pending)
    }

    static func driverSeries(_ driver: LinkDriver, in series: LinkSeries) -> [Date: Double] {
        switch driver {
        case .sleepLength: series.sleepHours
        case .strain: series.strain
        case .steps: series.steps
        case .daylight: series.daylight
        case .tag: [:]
        }
    }
}
