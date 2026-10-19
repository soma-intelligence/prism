//
//  StepsMath.swift
//  Prism
//

import Foundation

/// Steps by day, by week and by month, over daily totals.
nonisolated enum StepsMath {
    /// One calendar week of steps: its first and last day inside the window,
    /// the mean a day, and whether it is the week in progress.
    struct Week: Equatable, Sendable, Identifiable {
        var start: Date
        var end: Date
        var perDay: Double
        var isCurrent: Bool
        var id: Date { start }
    }

    /// The last `count` calendar weeks, newest first. `totals` is steps per
    /// day keyed by the day's midnight. A day missing from `totals` is left
    /// out of the mean rather than counted as zero.
    static func weeks(_ totals: [Date: Double], count: Int, now: Date, calendar: Calendar) -> [Week] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<count).compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -7 * back, to: thisWeek.start) else { return nil }
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.filter { $0 <= today }
            let values = days.compactMap { totals[$0] }
            guard !values.isEmpty, let last = days.last else { return nil }
            return Week(start: start, end: last, perDay: values.reduce(0, +) / Double(values.count), isCurrent: back == 0)
        }
    }

    /// Steps so far this month, day by day from the first, cumulative.
    static func monthToDate(_ totals: [Date: Double], now: Date, calendar: Calendar) -> [Double] {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        var running = 0.0
        var result: [Double] = []
        var day = month.start
        while day <= today {
            running += totals[day] ?? 0
            result.append(running)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Steps last month up to the same day of the month as today. Nil when
    /// last month holds no day at all.
    static func lastMonthToSameDay(_ totals: [Date: Double], now: Date, calendar: Calendar) -> Double? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let lastStart = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) else { return nil }
        let dayOfMonth = calendar.component(.day, from: now)
        let days = (0..<dayOfMonth).compactMap { calendar.date(byAdding: .day, value: $0, to: lastStart) }
            .filter { $0 < thisMonth.start }
        let values = days.compactMap { totals[$0] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    /// The largest day in the month so far, and when.
    static func biggestDay(_ totals: [Date: Double], now: Date, calendar: Calendar) -> (day: Date, steps: Double)? {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        return totals.filter { month.contains($0.key) }.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    /// A step count in thousands as a row writes it: 9.1k.
    static func thousands(_ value: Double, locale: Locale) -> String {
        (value / 1000).formatted(.number.precision(.fractionLength(1)).locale(locale)) + "k"
    }
}
