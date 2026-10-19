//
//  TrackWeek.swift
//  Prism
//

import Foundation

/// The week strip at the head of the Journal: Monday to Sunday of the week
/// that holds the selected day.
///
/// Monday first whatever the locale, because the design draws M to S, and a
/// strip whose first letter moves with the region reads as a different screen.
enum TrackWeek {
    /// The seven day starts of the week holding `date`, Monday first.
    static func days(containing date: Date, calendar: Calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        // Gregorian weekday: 1 is Sunday, 2 is Monday.
        let weekday = calendar.component(.weekday, from: day)
        let sinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -sinceMonday, to: day) else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// The same weekday a week earlier or later, never past today.
    static func shift(_ date: Date, weeks: Int, today: Date, calendar: Calendar) -> Date {
        let moved = calendar.date(byAdding: .day, value: 7 * weeks, to: calendar.startOfDay(for: date)) ?? date
        let todayStart = calendar.startOfDay(for: today)
        return min(moved, todayStart)
    }

    /// Whether the day is still to come, which the strip draws disabled.
    static func isFuture(_ date: Date, today: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: today)
    }

    /// The day's initial as the strip sets it: M T W T F S S.
    static func letter(_ date: Date, calendar: Calendar) -> String {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return letters[(calendar.component(.weekday, from: date) - 1) % 7]
    }
}
