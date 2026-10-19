//
//  MindUsual.swift
//  Prism
//
//  What is usual for a person: the middle half of their own days. Mind's
//  pages read every signal against it rather than against a population.
//

import Foundation
import HealthExportCore

nonisolated enum MindUsual {
    /// Days of history a usual range needs before it is stated.
    static let minimumDays = 5

    /// The value at `share` (0 to 1) of the sorted values, interpolated.
    static func percentile(_ values: [Double], _ share: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * min(max(share, 0), 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    /// The 25th to the 75th percentile of the daily values, nil under
    /// ``minimumDays``.
    static func range(_ daily: [Double]) -> ClosedRange<Double>? {
        guard daily.count >= minimumDays,
              let low = percentile(daily, 0.25),
              let high = percentile(daily, 0.75) else { return nil }
        return low...high
    }

    /// One value per day, reduced by `reduce`, keyed by the start of the day.
    static func daily(
        _ readings: [HealthReading],
        calendar: Calendar,
        reduce: ([Double]) -> Double?
    ) -> [Date: Double] {
        var byDay: [Date: [Double]] = [:]
        for reading in readings {
            byDay[calendar.startOfDay(for: reading.start), default: []].append(reading.value)
        }
        return byDay.compactMapValues(reduce)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Where a value sits against a range: under, inside or over it.
    enum Place: Equatable, Sendable {
        case under, inside, over
    }

    static func place(_ value: Double?, in range: ClosedRange<Double>?) -> Place? {
        guard let value, let range else { return nil }
        if value < range.lowerBound { return .under }
        if value > range.upperBound { return .over }
        return .inside
    }
}

/// One signal read against its usual range: a row of "What moved it".
nonisolated struct MindSignalRow: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case hrv, resting, breathing, peaks, sleep, lateMeals, sleepDebt, afternoonCalls, hardWeekday
    }

    var kind: Kind
    var title: String
    /// Under the title: the usual range, or when it happened.
    var detail: String?
    /// The value as the row shows it, with its unit. Nil renders a dash.
    var value: String?
    /// Whether the value is off in the direction that costs.
    var isCost: Bool
    /// The value and the usual range on one scale, for the track.
    var number: Double?
    var usual: ClosedRange<Double>?
    /// Ticks on the track instead of a dot: the clock hours of stress peaks.
    var marks: [Double] = []

    var id: Kind { kind }
}
