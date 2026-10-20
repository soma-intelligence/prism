//
//  PulseYearGrid.swift
//  Prism
//

import Foundation

/// The days of this year laid out as a grid: one column a week, one row a
/// weekday, Monday first whatever the locale's first weekday. Trends draws its
/// active days on it and Environment its days outside.
struct PulseYearGrid: Equatable, Codable {
    /// One cell of the grid.
    enum Cell: Equatable, Codable {
        /// Before the first of January or after today: not drawn.
        case outside
        /// A day of the year Health holds nothing for.
        case missing
        case value(Double)
    }

    struct MonthLabel: Equatable, Codable {
        var column: Int
        var label: String
    }

    /// One column a week, Monday first in each.
    var weeks: [[Cell]]
    var months: [MonthLabel]
    var todayColumn: Int
    var todayRow: Int
    /// The Monday the first column starts on.
    var firstMonday: Date

    /// The column `date` falls in.
    func column(of date: Date, calendar: Calendar) -> Int {
        (calendar.dateComponents([.day], from: firstMonday, to: calendar.startOfDay(for: date)).day ?? 0) / 7
    }

    /// The grid for the year of `now`, filled from one value per day keyed by
    /// the day's midnight.
    static func make(_ byDay: [Date: Double], now: Date, calendar: Calendar, locale: Locale) -> PulseYearGrid {
        let today = calendar.startOfDay(for: now)
        let january = calendar.dateInterval(of: .year, for: now)?.start ?? today

        func row(_ date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }
        let firstMonday = calendar.date(byAdding: .day, value: -row(january), to: january) ?? january
        let todayRow = row(today)
        let lastMonday = calendar.date(byAdding: .day, value: -todayRow, to: today) ?? today
        let weekCount = (calendar.dateComponents([.day], from: firstMonday, to: lastMonday).day ?? 0) / 7 + 1

        var weeks: [[Cell]] = []
        for column in 0..<weekCount {
            var cells: [Cell] = []
            for weekday in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: column * 7 + weekday, to: firstMonday),
                      date >= january, date <= today else {
                    cells.append(.outside)
                    continue
                }
                cells.append(byDay[date].map { .value($0) } ?? .missing)
            }
            weeks.append(cells)
        }

        var style = Date.FormatStyle().month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale

        var grid = PulseYearGrid(weeks: weeks, months: [], todayColumn: weekCount - 1, todayRow: todayRow,
                                 firstMonday: firstMonday)
        var first = january
        while first <= today {
            grid.months.append(MonthLabel(column: grid.column(of: first, calendar: calendar), label: first.formatted(style)))
            guard let next = calendar.date(byAdding: .month, value: 1, to: first) else { break }
            first = next
        }
        return grid
    }
}
