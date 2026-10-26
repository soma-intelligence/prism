//
//  ScreeningCalendarView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The screening year at a glance: twelve months, the five behind and the
/// six ahead of this one, one line per screening with something in them.
///
/// A filled dot in the danger colour sits on this month for what is due now,
/// an accent dot on the month a screening comes due soon, a ring on a month
/// further out, and a grey dot on the month one was done. Still: nothing here
/// moves, so there is nothing to settle under Reduce Motion.
struct ScreeningCalendarView: View {
    let dues: [SomaTools.ScreeningDue]
    let now: Date
    var calendar: Calendar = .current

    @Environment(\.somaTheme) private var theme

    /// Months shown before the current one.
    static let monthsBack = 5
    static let monthCount = 12

    /// What a dot says, in the order the legend reads.
    enum Mark: CaseIterable {
        case due, soon, later, done
    }

    struct Line: Identifiable {
        let id: String
        let title: String
        /// Column to mark, 0 to 11.
        let marks: [Int: Mark]
        let summary: String
    }

    var body: some View {
        let lines = Self.lines(dues, now: now, calendar: calendar)
        let columns = Self.columns(now: now, calendar: calendar)
        let metrics = theme.metrics

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                HStack(spacing: metrics.spaceXS) {
                    Color.clear.frame(maxWidth: .infinity)
                    monthRow(columns)
                }
                .accessibilityHidden(true)
                if lines.isEmpty {
                    Text("Nothing comes due in the months around this one.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                } else {
                    ForEach(lines) { line in
                        ToolHairline()
                        HStack(spacing: metrics.spaceXS) {
                            Text(line.title)
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 0) {
                                ForEach(0..<Self.monthCount, id: \.self) { column in
                                    dot(line.marks[column])
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(line.title), \(line.summary)")
                    }
                }
                ToolHairline()
                legend
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func monthRow(_ columns: [Date]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, month in
                Text(Self.initial(month, calendar: calendar))
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(index == Self.monthsBack ? theme.colors.inkPrimary.color : theme.colors.inkSecondary.color)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dot(_ mark: Mark?) -> some View {
        let side = theme.metrics.chartDotDiameter
        switch mark {
        case .later:
            Circle()
                .strokeBorder(theme.colors.inkSecondary.color, lineWidth: theme.metrics.chartLineWidth)
                .frame(width: side, height: side)
        case .some(let mark):
            Circle()
                .fill(color(mark))
                .frame(width: side, height: side)
        case nil:
            Color.clear.frame(width: side, height: side)
        }
    }

    private func color(_ mark: Mark) -> Color {
        switch mark {
        case .due: theme.colors.danger.color
        case .soon: theme.colors.accent.color
        case .later: theme.colors.inkSecondary.color
        case .done: theme.colors.inkSecondary.color
        }
    }

    private var legend: some View {
        HStack(spacing: theme.metrics.moveRowGap) {
            ForEach(Mark.allCases, id: \.self) { mark in
                HStack(spacing: theme.metrics.spaceXS) {
                    dot(mark)
                    Text(Self.word(mark))
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Derivations

    static func word(_ mark: Mark) -> String {
        switch mark {
        case .due: String(localized: "Due now")
        case .soon: String(localized: "Soon")
        case .later: String(localized: "Later")
        case .done: String(localized: "Done")
        }
    }

    /// The first day of each month shown.
    static func columns(now: Date, calendar: Calendar) -> [Date] {
        let start = firstMonth(now: now, calendar: calendar)
        return (0..<monthCount).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }

    static func firstMonth(now: Date, calendar: Calendar) -> Date {
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return calendar.date(byAdding: .month, value: -monthsBack, to: month) ?? month
    }

    /// The column a date falls in, or nil outside the twelve months.
    static func column(of date: Date, now: Date, calendar: Calendar) -> Int? {
        let start = firstMonth(now: now, calendar: calendar)
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        guard let index = calendar.dateComponents([.month], from: start, to: month).month,
              (0..<monthCount).contains(index) else { return nil }
        return index
    }

    static func initial(_ month: Date, calendar: Calendar) -> String {
        let symbols = calendar.veryShortStandaloneMonthSymbols
        let index = calendar.component(.month, from: month) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    /// One line per screening with something in the twelve months: what is
    /// due sits on this month, what comes due on its month, and the last time
    /// it was done on that month.
    static func lines(_ dues: [SomaTools.ScreeningDue], now: Date, calendar: Calendar) -> [Line] {
        var style = Date.FormatStyle().month(.wide).year()
        style.timeZone = calendar.timeZone
        return dues.compactMap { due in
            var marks: [Int: Mark] = [:]
            if let last = due.lastDone, let column = column(of: last, now: now, calendar: calendar) {
                marks[column] = .done
            }
            switch due.state {
            case .overdue:
                marks[monthsBack] = .due
            case .soon, .later, .done:
                if let date = due.dueDate, let column = column(of: date, now: now, calendar: calendar) {
                    marks[column] = due.state == .soon ? .soon : .later
                }
            }
            guard !marks.isEmpty else { return nil }
            let summary: String = switch due.state {
            case .overdue: String(localized: "due now")
            case .soon, .later: due.dueDate.map { String(localized: "due \($0.formatted(style))") } ?? ""
            case .done: due.lastDone.map { String(localized: "done \($0.formatted(style))") } ?? String(localized: "done")
            }
            return Line(id: due.id, title: due.item.title, marks: marks, summary: summary)
        }
    }
}

#Preview("Screening calendar") {
    let now = Date()
    let catalog = SomaTools.ScreeningCatalog.self
    let dues = [
        SomaTools.ScreeningDue(item: catalog.item(id: "colorectal")!, dueDate: now, state: .overdue, lastDone: nil),
        SomaTools.ScreeningDue(item: catalog.item(id: "bloodPressure")!, dueDate: Calendar.current.date(byAdding: .month, value: 2, to: now),
                               state: .soon, lastDone: Calendar.current.date(byAdding: .month, value: -10, to: now)),
        SomaTools.ScreeningDue(item: catalog.item(id: "lipids")!, dueDate: Calendar.current.date(byAdding: .month, value: 5, to: now),
                               state: .later, lastDone: nil),
        SomaTools.ScreeningDue(item: catalog.item(id: "hepatitisC")!, dueDate: nil, state: .done,
                               lastDone: Calendar.current.date(byAdding: .month, value: -3, to: now)),
    ]
    ScreeningCalendarView(dues: dues, now: now)
        .padding()
}
