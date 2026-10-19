//
//  LinkMath.swift
//  Prism
//

import Foundation

/// Whether one thing a person did, or one reading, goes with a change in
/// another reading on their own days.
///
/// Two daily series, each keyed by the start of a day, are paired (the same
/// day, or the outcome on the day after), split into high and low driver days
/// (or tagged and untagged days), and the outcome's mean on each side is
/// compared. A link is stated only when both sides hold enough days and the
/// difference stands clear of the outcome's day to day noise; anything else is
/// held back, never drawn as a guess.
///
/// Plain arithmetic over dictionaries, so a test states every rule without a
/// Health store.
nonisolated enum LinkMath {
    /// Where the outcome sits against the driver's day.
    enum Lag: Int, Sendable, Equatable {
        /// The outcome on the driver's own day.
        case sameDay = 0
        /// The outcome on the day after: yesterday's strain, today's recovery.
        case nextDay = 1
    }

    /// The bar a link has to clear before it is shown.
    struct Gate: Sendable, Equatable {
        /// The fewest days on each side.
        var minimumDays: Int
        /// How many standard errors of the difference the effect must exceed.
        /// Two is roughly the 95% line.
        var noiseMultiple: Double = 2

        /// Continuous drivers: a third of three weeks on each side.
        static let level = Gate(minimumDays: 7)
        /// Journal tags: rarer days, so fewer on the tagged side.
        static let tag = Gate(minimumDays: 5)
    }

    /// Which way the outcome moves on high (or tagged) days.
    enum Direction: Sendable, Equatable {
        case rises
        case falls
    }

    /// Why a link is held back, or that it is not.
    enum Verdict: Sendable, Equatable {
        case shown
        /// A side holds fewer days than the gate asks.
        case notEnoughDays
        /// Enough days, but the difference is inside the outcome's noise.
        case withinNoise
    }

    /// Where a paired day fell in the split.
    enum Side: Sendable, Equatable {
        /// A high (or tagged) day.
        case high
        /// A low (or untagged) day.
        case low
        /// The middle third of a level split: measured, compared with neither.
        case between
    }

    /// One paired day as the comparison read it, for drawing it in time.
    struct Day: Sendable, Equatable {
        /// The driver's day: the evening of the drink, the day of the strain.
        /// The outcome sits `lag` days later.
        var day: Date
        var outcome: Double
        var side: Side
    }

    /// One comparison: the outcome on high days against low days.
    struct Result: Sendable, Equatable {
        /// The outcome on each high (or tagged) day, and each low one.
        var high: [Double]
        var low: [Double]
        /// Mean on high days less mean on low days. Nil when a side is empty.
        var delta: Double?
        /// The outcome's standard deviation over every paired day.
        var spread: Double?
        /// The smallest difference that counts: the gate's multiple of the
        /// difference's standard error, from that spread.
        var noise: Double?
        var verdict: Verdict
        /// Every paired day with its side, oldest first. Empty when the
        /// result was built from bare values.
        var days: [Day] = []

        var highDays: Int { high.count }
        var lowDays: Int { low.count }
        var isShown: Bool { verdict == .shown }

        var direction: Direction? {
            guard let delta, delta != 0 else { return nil }
            return delta > 0 ? .rises : .falls
        }

        /// The effect in standard deviations of the outcome, for ranking links
        /// measured in different units. Zero when it cannot be stated.
        var strength: Double {
            guard let delta, let spread, spread > 0 else { return 0 }
            return abs(delta) / spread
        }
    }

    // MARK: Pairing

    /// One day where both series hold a value.
    struct Pair: Sendable, Equatable {
        var day: Date
        var driver: Double
        var outcome: Double
    }

    /// Driver days with the outcome `lag` days later, oldest first.
    static func pairs(driver: [Date: Double], outcome: [Date: Double], lag: Lag, calendar: Calendar) -> [Pair] {
        driver.compactMap { day, value -> Pair? in
            guard let target = shift(day, by: lag.rawValue, calendar: calendar),
                  let result = outcome[target] else { return nil }
            return Pair(day: day, driver: value, outcome: result)
        }
        .sorted { $0.day < $1.day }
    }

    /// A series moved `days` later: the value of day d keyed by day d + days.
    static func shifted(_ series: [Date: Double], by days: Int, calendar: Calendar) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for (day, value) in series {
            if let key = shift(day, by: days, calendar: calendar) { out[key] = value }
        }
        return out
    }

    static func shift(_ day: Date, by days: Int, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        return days == 0 ? start : calendar.date(byAdding: .day, value: days, to: start)
    }

    // MARK: Comparing

    /// A continuous driver: its top third of days against its bottom third.
    ///
    /// Thirds rather than halves so the two sides are days that differ, not
    /// days either side of a median by a hair. Ties are ordered by day, and a
    /// split whose two sides share a driver value has no contrast to speak of.
    static func byLevel(_ pairs: [Pair], gate: Gate = .level) -> Result {
        let sorted = pairs.sorted { ($0.driver, $0.day) < ($1.driver, $1.day) }
        let third = sorted.count / 3
        let low = Array(sorted.prefix(third))
        let high = Array(sorted.suffix(third))
        let all = pairs.map(\.outcome)
        let days = sorted.enumerated().map { index, pair in
            let side: Side = index < third ? .low : index >= sorted.count - third ? .high : .between
            return Day(day: pair.day, outcome: pair.outcome, side: side)
        }
        .sorted { $0.day < $1.day }
        if let lowTop = low.last?.driver, let highBottom = high.first?.driver, lowTop >= highBottom {
            return Result(high: high.map(\.outcome), low: low.map(\.outcome), delta: nil,
                          spread: standardDeviation(all), noise: nil, verdict: .notEnoughDays, days: days)
        }
        var result = compare(high: high.map(\.outcome), low: low.map(\.outcome), all: all, gate: gate)
        result.days = days
        return result
    }

    /// A tag: the outcome after the days it was logged against every other
    /// day from `since` on (the day the person started logging), `lag` later.
    static func byTag(
        days tagged: Set<Date>,
        outcome: [Date: Double],
        lag: Lag,
        since: Date?,
        calendar: Calendar,
        gate: Gate = .tag
    ) -> Result {
        let marks = Set(tagged.map { calendar.startOfDay(for: $0) })
        var days: [Day] = []
        for (day, value) in outcome {
            guard let driverDay = shift(day, by: -lag.rawValue, calendar: calendar) else { continue }
            if let since, driverDay < calendar.startOfDay(for: since) { continue }
            days.append(Day(day: driverDay, outcome: value, side: marks.contains(driverDay) ? .high : .low))
        }
        days.sort { $0.day < $1.day }
        let high = days.filter { $0.side == .high }.map(\.outcome)
        let low = days.filter { $0.side == .low }.map(\.outcome)
        var result = compare(high: high, low: low, all: high + low, gate: gate)
        result.days = days
        return result
    }

    /// The gate itself: enough days on each side, and a difference larger
    /// than `noiseMultiple` standard errors, the error read from the spread
    /// of `all` (the outcome's day to day noise) and the two sides' sizes.
    static func compare(high: [Double], low: [Double], all: [Double], gate: Gate) -> Result {
        let spread = standardDeviation(all)
        guard let highMean = mean(high), let lowMean = mean(low) else {
            return Result(high: high, low: low, delta: nil, spread: spread, noise: nil, verdict: .notEnoughDays)
        }
        let delta = highMean - lowMean
        guard high.count >= gate.minimumDays, low.count >= gate.minimumDays, let spread else {
            return Result(high: high, low: low, delta: delta, spread: spread, noise: nil, verdict: .notEnoughDays)
        }
        let noise = gate.noiseMultiple * spread * (1 / Double(high.count) + 1 / Double(low.count)).squareRoot()
        let clear = delta != 0 && abs(delta) > noise
        return Result(high: high, low: low, delta: delta, spread: spread, noise: noise,
                      verdict: clear ? .shown : .withinNoise)
    }

    // MARK: Arithmetic

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The sample standard deviation. Nil under two values.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let mean = mean(values) else { return nil }
        let squares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (squares / Double(values.count - 1)).squareRoot()
    }
}
