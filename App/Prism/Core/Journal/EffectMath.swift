//
//  EffectMath.swift
//  Prism
//

import Foundation

/// How much something a person did moved a reading, measured on their own
/// days: the days it happened against the days it did not.
///
/// Plain arithmetic over dictionaries keyed by the start of a day, so the Mind
/// and Track pages share one rule and a test states it without a Health store.
enum EffectMath {
    /// Which way a reading improves.
    enum Better: Sendable {
        case higher
        case lower
    }

    struct Effect: Equatable, Sendable {
        /// The median on the days it happened, less the median on the days it
        /// did not. Nil until both sides hold enough days.
        var delta: Double?
        /// On how many of those days the reading beat the usual.
        var held: Int
        /// How many days it happened with a reading to compare.
        var tries: Int

        /// Whether the move is for the worse.
        func isCost(_ better: Better) -> Bool {
            guard let delta else { return false }
            return better == .higher ? delta < 0 : delta > 0
        }
    }

    /// The fewest days on each side before a delta is stated.
    static let minimumDays = 3

    /// - Parameters:
    ///   - causeDays: the start of each day it happened.
    ///   - outcome: the reading, keyed by the start of the day it belongs to.
    ///     For a next morning reading, key it by the day before.
    ///   - better: which way the reading improves, for `held`.
    static func effect(causeDays: Set<Date>, outcome: [Date: Double], better: Better) -> Effect {
        let with = outcome.filter { causeDays.contains($0.key) }.map(\.value)
        let without = outcome.filter { !causeDays.contains($0.key) }.map(\.value)
        guard !with.isEmpty else { return Effect(delta: nil, held: 0, tries: 0) }
        guard without.count >= minimumDays, let usual = median(without) else {
            return Effect(delta: nil, held: 0, tries: with.count)
        }
        let held = with.filter { better == .higher ? $0 > usual : $0 < usual }.count
        let delta = with.count >= minimumDays ? median(with).map { $0 - usual } : nil
        return Effect(delta: delta, held: held, tries: with.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
