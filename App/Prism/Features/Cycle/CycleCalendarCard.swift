//
//  CycleCalendarCard.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The month on the cycle page: the days of flow Health holds filled, the
/// days the next period is expected outlined, a dot under a day with a
/// symptom logged, and a ring on today.
struct CycleCalendarCard: View {
    let month: Date
    let periodDays: Set<Date>
    let expectedDays: Set<Date>
    let symptomDays: Set<Date>
    var today: Date = .now
    var calendar: Calendar = .current

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let columns = Array(repeating: GridItem(.flexible(), spacing: metrics.spaceXS), count: 7)

        HomeRowsCard("This month", caption: LocalizedStringResource(stringLiteral: month.formatted(.dateTime.month(.wide).year()))) {
            VStack(alignment: .leading, spacing: metrics.spaceS) {
                LazyVGrid(columns: columns, spacing: metrics.spaceXS) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .accessibilityHidden(true)
                    }
                    ForEach(Array(Self.grid(month: month, calendar: calendar).enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day)
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }
                }
                HStack(spacing: metrics.spaceM) {
                    legend("Period", filled: true)
                    if !expectedDays.isEmpty { legend("Expected", filled: false) }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.heart].identity.color
        let isPeriod = periodDays.contains(day)
        let isExpected = !isPeriod && expectedDays.contains(day)
        let isToday = calendar.isDate(day, inSameDayAs: today)

        return VStack(spacing: metrics.spaceXS) {
            Text("\(calendar.component(.day, from: day))")
                .somaFont(theme.typography.caption)
                .foregroundStyle(isPeriod ? colors.canvas.color : colors.inkPrimary.color)
                .frame(width: metrics.cycleDayDiameter, height: metrics.cycleDayDiameter)
                .background {
                    if isPeriod {
                        Circle().fill(hue)
                    } else if isExpected {
                        Circle().strokeBorder(hue, lineWidth: metrics.cycleDayRing)
                    }
                }
                .overlay {
                    if isToday {
                        Circle().strokeBorder(colors.inkPrimary.color, lineWidth: metrics.cycleDayRing)
                    }
                }
            Circle()
                .fill(symptomDays.contains(day) ? colors.inkSecondary.color : .clear)
                .frame(width: metrics.chartPointDiameter, height: metrics.chartPointDiameter)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label(day, isPeriod: isPeriod, isExpected: isExpected)))
    }

    private func label(_ day: Date, isPeriod: Bool, isExpected: Bool) -> String {
        var parts = [day.formatted(.dateTime.day().month(.wide))]
        if isPeriod { parts.append("period") }
        if isExpected { parts.append("period expected") }
        if symptomDays.contains(day) { parts.append("symptom logged") }
        return parts.joined(separator: ", ")
    }

    private func legend(_ title: String, filled: Bool) -> some View {
        let metrics = theme.metrics
        let hue = theme.aspects[.heart].identity.color
        return HStack(spacing: metrics.spaceXS) {
            Group {
                if filled {
                    Circle().fill(hue)
                } else {
                    Circle().strokeBorder(hue, lineWidth: metrics.cycleDayRing)
                }
            }
            .frame(width: metrics.cycleLegendDiameter, height: metrics.cycleLegendDiameter)
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
    }

    /// The weekday initials, starting on the calendar's first weekday.
    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days, each at its start, behind the blanks that line the
    /// first one up under its weekday.
    static func grid(month: Date, calendar: Calendar) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        return Array(repeating: nil, count: lead) + days.map(Optional.some)
    }
}

#Preview("Cycle calendar") {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: .now)
    let days = { (offsets: ClosedRange<Int>) in Set(offsets.compactMap { calendar.date(byAdding: .day, value: $0, to: start) }) }
    return SomaPageScroll {
        CycleCalendarCard(month: .now, periodDays: days(-12...(-8)), expectedDays: days(14...18), symptomDays: days(-11...(-10)))
            .padding()
    }
}
