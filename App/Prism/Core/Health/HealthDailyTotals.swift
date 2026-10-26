//
//  HealthDailyTotals.swift
//  Prism
//

import Foundation
import HealthExportCore

/// One total a day out of Health, the way every page that charts days reads
/// it: steps, exercise minutes, time in daylight.
///
/// Each day is its own total query from midnight to the next midnight, and
/// today stops at `now`. A day the store holds nothing for is absent from the
/// result, never zero, so a page draws a gap rather than a day of no steps.
nonisolated enum HealthDailyTotals {
    /// Days read at once.
    static let inFlight = 12

    /// From the day `start` falls on through today, keyed by each day's midnight.
    static func read(
        _ identifier: String,
        from start: Date,
        now: Date,
        source: any HealthSampleSource,
        calendar: Calendar
    ) async -> [Date: Double] {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [:] }
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day <= now {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return await withTaskGroup(of: (Date, Double?).self) { group in
            var result: [Date: Double] = [:]
            var pending = days.makeIterator()

            func add(_ day: Date) {
                let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? now, now)
                group.addTask { (day, (try? await source.total(metric, from: day, to: end))?.value) }
            }

            for _ in 0..<inFlight {
                guard let next = pending.next() else { break }
                add(next)
            }
            for await (day, value) in group {
                if let value { result[day] = value }
                if let next = pending.next() { add(next) }
            }
            return result
        }
    }

    /// The `days` days ending today, keyed by each day's midnight.
    static func read(
        _ identifier: String,
        days: Int,
        now: Date,
        source: any HealthSampleSource,
        calendar: Calendar
    ) async -> [Date: Double] {
        let today = calendar.startOfDay(for: now)
        guard days > 0, let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [:] }
        return await read(identifier, from: start, now: now, source: source, calendar: calendar)
    }
}
