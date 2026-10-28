//
//  TrackFasting.swift
//  Prism
//
//  A fast is one
//  start date and an objective, and everything shown is derived from the
//  start date, never from a counter, so it stays right across a relaunch.
//

import Foundation
import SomaUI

/// A fast being timed, or one that has ended. At most one runs at a time.
nonisolated struct TrackFast: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var start: Date
    /// The length aimed for, in hours. Nil is an open fast with no arc to fill.
    var objectiveHours: Double?
    /// When it ended. Nil while it runs.
    var end: Date?

    /// Seconds since the fast began, to its end or to `now`, never negative.
    func elapsed(at now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    /// 0...1 of the objective, or nil for an open fast.
    func fraction(at now: Date) -> Double? {
        guard let objectiveHours, objectiveHours > 0 else { return nil }
        return min(1, elapsed(at: now) / (objectiveHours * 3600))
    }

    /// Seconds left to the objective, negative once passed, nil when open.
    func remaining(at now: Date) -> TimeInterval? {
        guard let objectiveHours, objectiveHours > 0 else { return nil }
        return objectiveHours * 3600 - elapsed(at: now)
    }

    /// When the objective is reached.
    var goalEnd: Date? {
        objectiveHours.map { start.addingTimeInterval($0 * 3600) }
    }
}

/// The arithmetic of the fasting sheet.
nonisolated enum TrackFasting {
    /// The lengths offered under the clock, in hours.
    static let presets: [Double] = [12, 14, 16, 18]
    /// The shortest and longest fast the clock lets a person draw.
    static let lengthRange: ClosedRange<Double> = 1...23.5
    /// The grid a dragged start or end snaps to, in hours: a quarter hour.
    static let snap: Double = 0.25

    /// A clock hour snapped to the quarter hour and wrapped into 0..<24.
    static func snapped(_ hour: Double) -> Double {
        wrap((hour / snap).rounded() * snap)
    }

    static func wrap(_ hour: Double) -> Double {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }

    /// The clock hour of a date, with minutes as a fraction.
    static func clockHour(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// The next moment at `hour` from `now` on: today if it is still ahead,
    /// or within the last half hour (a fast started "at 20:00" at 20:10 means
    /// the one just begun), otherwise tomorrow.
    static func nextStart(at hour: Double, from now: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: now)
        let today = day.addingTimeInterval(hour * 3600)
        if today >= now.addingTimeInterval(-30 * 60) { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// How many seconds of `start..<start + hours` fall inside the nightly
    /// window `from`...`to` (clock hours, the window may cross midnight).
    static func overlap(start: Date, hours: Double, window: (from: Double, to: Double), calendar: Calendar) -> TimeInterval {
        let end = start.addingTimeInterval(hours * 3600)
        let windowLength = wrap(window.to - window.from)
        guard windowLength > 0, end > start else { return 0 }
        var total: TimeInterval = 0
        // Every night the fast could touch: the one before its start to the
        // one after its end.
        let firstDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
        var night = firstDay
        while night <= end {
            let opens = night.addingTimeInterval(window.from * 3600)
            let closes = opens.addingTimeInterval(windowLength * 3600)
            let lower = max(opens, start)
            let upper = min(closes, end)
            if upper > lower { total += upper.timeIntervalSince(lower) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: night) else { break }
            night = next
        }
        return total
    }

    /// "7h 45m", "14h", "40m": a length the way every duration in the app
    /// is written, through ``SomaFormat``.
    static func length(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        SomaFormat.duration(seconds, locale: locale)
    }

    /// The usual night's sleep window, as clock hours: the median time of
    /// falling asleep and of waking over the nights given. Nil under three
    /// nights.
    static func usualWindow(asleep: [Date], woke: [Date], calendar: Calendar) -> (from: Double, to: Double)? {
        guard asleep.count >= 3, woke.count >= 3 else { return nil }
        // Evening hours are read past midnight (01:00 is 25) so a median of
        // 23:30 and 00:30 lands at midnight, not at noon.
        let fell = asleep.map { hour -> Double in
            let value = clockHour(hour, calendar: calendar)
            return value < 12 ? value + 24 : value
        }
        let rose = woke.map { clockHour($0, calendar: calendar) }
        guard let from = median(fell), let to = median(rose) else { return nil }
        return (wrap(from), wrap(to))
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
