//
//  CalendarMonth.swift
//  Prism
//

import Foundation

/// One month laid out as weeks, each day carrying the score it had.
///
/// A ring a day, filled with that day's score for
/// the chosen aspect, and dots for what happened. Scores come from the thirty
/// day series `SomaScores` keeps (oldest first, ending today); a day outside
/// that window, or a day with no score, has an empty ring, never a zero.
nonisolated struct CalendarMonth: Equatable, Sendable {
    nonisolated struct Day: Equatable, Identifiable, Sendable {
        var date: Date
        var number: Int
        /// False for the leading and trailing days of the neighbouring months.
        var isInMonth: Bool
        var isToday: Bool
        var isFuture: Bool
        var score: Int?
        /// The journal holds an entry for the day.
        var hasJournal: Bool
        /// The day was read under a status other than Training.
        var status: ActivityStatus?
        var id: Date { date }
    }

    var month: Date
    var weeks: [[Day]]

    /// - Parameters:
    ///   - series: scores oldest first, the last one today's.
    ///   - journalDays: the start of each day the journal holds.
    ///   - status: the status in force on a day.
    static func make(
        month: Date,
        today: Date,
        series: [Double?],
        journalDays: Set<Date>,
        status: (Date) -> ActivityStatus,
        calendar: Calendar
    ) -> CalendarMonth {
        let todayStart = calendar.startOfDay(for: today)
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return CalendarMonth(month: month, weeks: [])
        }
        let first = interval.start
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let cells = Int((Double(leading + dayCount) / 7).rounded(.up)) * 7

        var days: [Day] = []
        for offset in 0..<cells {
            guard let date = calendar.date(byAdding: .day, value: offset - leading, to: first) else { continue }
            let start = calendar.startOfDay(for: date)
            let inMonth = offset >= leading && offset < leading + dayCount
            let back = calendar.dateComponents([.day], from: start, to: todayStart).day ?? Int.max
            var score: Int?
            if back >= 0, back < series.count, let value = series[series.count - 1 - back] {
                score = Int(value.rounded())
            }
            let isFuture = start > todayStart
            let dayStatus = isFuture ? nil : status(start)
            days.append(Day(
                date: start,
                number: calendar.component(.day, from: start),
                isInMonth: inMonth,
                isToday: start == todayStart,
                isFuture: isFuture,
                score: inMonth ? score : nil,
                hasJournal: inMonth && journalDays.contains(start),
                status: inMonth && (dayStatus?.marksCalendar ?? false) ? dayStatus : nil
            ))
        }
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return CalendarMonth(month: first, weeks: weeks)
    }

    /// The short weekday names in the calendar's order: Mon, Tue, ...
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
