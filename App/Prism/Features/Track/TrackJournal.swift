//
//  TrackJournal.swift
//  Prism
//

import Foundation
import SomaUI

/// The reading a tag is measured against.
enum TrackReading: Equatable, Sendable {
    /// Deep sleep on the night after: what caffeine and a bright screen cost.
    case deepSleep
    /// Heart rate variability the next morning: where alcohol shows.
    case nextMorningVariability
    /// The heart's average across the night after: where a late meal shows.
    case overnightHeart
    /// Heart rate variability on the day itself.
    case dayVariability

    /// Which reading a tag is set against. The starter tags each have the one
    /// their effect is known to land on; a tag of the person's own is read on
    /// the day's variability, the broadest single sign of load.
    static func forTag(_ tagID: String) -> TrackReading {
        switch tagID {
        case "coffee-late", "screens-in-bed", "sauna": .deepSleep
        case "alcohol", "hard-training", "travel": .nextMorningVariability
        case "late-meal": .overnightHeart
        default: .dayVariability
        }
    }

    var name: String {
        switch self {
        case .deepSleep: "Deep sleep"
        case .nextMorningVariability: "HRV next morning"
        case .overnightHeart: "Overnight heart rate"
        case .dayVariability: "HRV that day"
        }
    }

    var unit: String {
        switch self {
        case .deepSleep: "min"
        case .nextMorningVariability, .dayVariability: "ms"
        case .overnightHeart: "bpm"
        }
    }

    var better: EffectMath.Better {
        self == .overnightHeart ? .lower : .higher
    }

    /// The aspect whose hue fills the effect bar.
    var aspect: SomaAspect {
        switch self {
        case .deepSleep: .sleep
        case .nextMorningVariability, .dayVariability: .mind
        case .overnightHeart: .heart
        }
    }

    /// The move that fills the bar to its end.
    var fullScale: Double {
        switch self {
        case .deepSleep: 30
        case .nextMorningVariability, .dayVariability: 15
        case .overnightHeart: 6
        }
    }

    /// Whether the count after the reading's name says nights.
    var countsNights: Bool { self == .deepSleep }

    func series(in body: TrackBody) -> [Date: Double] {
        switch self {
        case .deepSleep: body.deepSleep
        case .nextMorningVariability: body.nextMorningVariability
        case .overnightHeart: body.overnightHeart
        case .dayVariability: body.dayVariability
        }
    }
}

/// One row of "What your tags do".
struct TrackTagEffect: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var reading: TrackReading
    var effect: EffectMath.Effect

    var isCost: Bool { effect.isCost(reading.better) }

    /// The move, signed, in the reading's unit: "−18 min", "+3 bpm". A dash
    /// until both sides hold enough days.
    var valueText: String {
        guard let delta = effect.delta else { return "-" }
        return TrackFormat.signed(delta, unit: reading.unit)
    }

    /// How often it went the way the delta says, out of the days it happened.
    var detailText: String {
        let noun = reading.countsNights ? " nights" : ""
        guard effect.delta != nil else {
            if effect.tries < EffectMath.minimumDays {
                return "\(reading.name), \(effect.tries) of \(EffectMath.minimumDays)\(noun) so far"
            }
            return "\(reading.name), needs more days without it"
        }
        let agreeing = isCost ? effect.tries - effect.held : effect.held
        return "\(reading.name), \(agreeing) of \(effect.tries)\(noun)"
    }

    /// The bar's reach in -1...1, rightwards for a rise.
    var fraction: Double? {
        effect.delta.map { $0 / reading.fullScale }
    }
}

/// One day on the feel and measure chart.
struct TrackFeelPoint: Equatable, Identifiable, Sendable {
    var id: Date { day }
    var day: Date
    /// Seven stops, 0 very unpleasant to 6 very pleasant.
    var feeling: Int
    /// The day's variability less the usual, in ms.
    var deviation: Double
    var agrees: Bool
}

/// The arithmetic of the Journal page, over plain values.
enum TrackJournal {
    /// Days the effects card looks back over.
    static let effectDays = 60
    /// Days the feel and measure chart looks back over.
    static let feelDays = 21
    /// Points before the chart draws anything.
    static let feelMinimum = 5

    static let feelingLabels = [
        "Very unpleasant", "Unpleasant", "Slightly unpleasant", "Neutral",
        "Slightly pleasant", "Pleasant", "Very pleasant",
    ]

    /// The effect of each tag with at least one logged day in the window,
    /// most telling first: stated deltas before the ones still gathering,
    /// larger moves before smaller.
    static func effects(
        tags: [JournalTag],
        days: [Date: JournalDay],
        body: TrackBody,
        today: Date,
        calendar: Calendar
    ) -> [TrackTagEffect] {
        let todayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -effectDays, to: todayStart) ?? todayStart
        let window = start..<todayStart.addingTimeInterval(1)

        return tags.compactMap { tag -> TrackTagEffect? in
            let causes = Set(days.filter { window.contains($0.key) && $0.value.tags.contains(tag.id) }.map(\.key))
            guard !causes.isEmpty else { return nil }
            let reading = TrackReading.forTag(tag.id)
            let outcome = reading.series(in: body).filter { window.contains($0.key) }
            let effect = EffectMath.effect(causeDays: causes, outcome: outcome, better: reading.better)
            guard effect.tries > 0 else { return nil }
            return TrackTagEffect(id: tag.id, title: tag.title, reading: reading, effect: effect)
        }
        .sorted { lhs, rhs in
            switch (lhs.fraction, rhs.fraction) {
            case let (l?, r?): abs(l) > abs(r)
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.effect.tries > rhs.effect.tries
            }
        }
    }

    /// Whether a feeling and the body's reading say the same thing: a
    /// pleasant day with variability above the usual, an unpleasant one below
    /// it, or a neutral one within a tenth of the usual either way.
    static func agrees(feeling: Int, deviation: Double, usual: Double) -> Bool {
        switch feeling {
        case ..<3: deviation < 0
        case 3: abs(deviation) <= usual * 0.1
        default: deviation > 0
        }
    }

    /// The days of the last three weeks that hold both a feeling and a
    /// variability reading, oldest first.
    static func feelPoints(days: [Date: JournalDay], body: TrackBody, today: Date, calendar: Calendar) -> [TrackFeelPoint] {
        guard let usual = body.usualVariability else { return [] }
        let todayStart = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -(feelDays - 1), to: todayStart) ?? todayStart
        return days.compactMap { day, entry -> TrackFeelPoint? in
            guard day >= start, day <= todayStart,
                  let feeling = entry.feeling,
                  let value = body.dayVariability[day] else { return nil }
            let deviation = value - usual
            return TrackFeelPoint(day: day, feeling: feeling, deviation: deviation,
                                  agrees: agrees(feeling: feeling, deviation: deviation, usual: usual))
        }
        .sorted { $0.day < $1.day }
    }

    /// The line under "k of N days agree".
    static func feelNote(_ points: [TrackFeelPoint]) -> String {
        let low = points.filter { $0.feeling < 3 }
        let good = points.filter { $0.feeling > 3 }
        if !low.isEmpty {
            let agreed = low.filter(\.agrees).count
            return agreed == low.count
                ? "When you felt low, your body agreed every time."
                : "When you felt low, your body agreed on \(agreed) of \(low.count) days."
        }
        if !good.isEmpty {
            let agreed = good.filter(\.agrees).count
            return agreed == good.count
                ? "When you felt good, your body agreed every time."
                : "When you felt good, your body agreed on \(agreed) of \(good.count) days."
        }
        return "Neutral days agree when the body sits near its usual."
    }

    /// The line under the feeling bar: what the body said on the same day.
    /// Nil parts are the reason there is nothing to compare yet.
    static func bodyLine(
        feeling: Int?,
        day: Date,
        body: TrackBody,
        points: [TrackFeelPoint]
    ) -> (lead: String, rest: String?) {
        guard let feeling else {
            return ("Tap how the day felt.", "Soma sets it beside what your body measured.")
        }
        guard let value = body.dayVariability[day], let usual = body.usualVariability else {
            return ("Nothing from your body for this day yet.",
                    "Heart rate variability from your watch fills this in.")
        }
        let deviation = value - usual
        let reading = "HRV is \(TrackFormat.whole(value)) ms, \(TrackFormat.whole(abs(deviation))) \(deviation < 0 ? "below" : "above") your usual."
        let parted = points.filter { !$0.agrees }.count
        if agrees(feeling: feeling, deviation: deviation, usual: usual) {
            return ("Your body agrees: \(reading)",
                    "On \(points.count - parted) of the last \(points.count) days the two matched.")
        }
        return ("Your body reads it differently: \(reading)",
                "On \(parted) of the last \(points.count) days the two parted like this.")
    }
}

/// Numbers as the Track pages set them.
enum TrackFormat {
    static func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    /// A signed whole number with its unit, with a true minus sign.
    static func signed(_ value: Double, unit: String) -> String {
        let rounded = Int(value.rounded())
        let sign = rounded > 0 ? "+" : rounded < 0 ? "\u{2212}" : ""
        return "\(sign)\(abs(rounded)) \(unit)"
    }

    static func hour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
