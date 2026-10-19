//
//  CalendarPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A month of days, each with a ring filled by that day's score, the journal
/// and the status marked under it, and today's three scores below.
///
/// The Calendar ring sheet. The scores are `SomaScores`' thirty day
/// series, so a ring older than a month, or a day without a score, stays empty.
/// The info button opens the statuses legend.
struct CalendarPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var month = Date()
    @State private var aspect: SomaAspect = .sleep
    @State private var statuses = ActivityStatusStore.shared
    @State private var sheet: GlobalRoute?

    static let aspects: [SomaAspect] = [.sleep, .mind, .activity]

    var body: some View {
        let calendar = Self.calendar
        let layout = CalendarMonth.make(
            month: month, today: Date(), series: series,
            journalDays: Set(journal.loggedDays.map { calendar.startOfDay(for: $0.date) }),
            status: { statuses.status(on: $0) }, calendar: calendar
        )

        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.browseSectionSpacing) {
                header
                aspectPicker
                CalendarGrid(layout: layout, aspect: aspect, calendar: calendar)
                legend
                todayBlock
            }
            .padding(theme.metrics.pagePadding)
            .frame(maxWidth: theme.metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { sheet = .activityLegend } label: {
                    Image(systemName: "info")
                        .foregroundStyle(theme.colors.inkPrimary.color)
                }
                .accessibilityLabel("What statuses change")
            }
        }
        .task { await health.loadScores() }
        .sheet(item: $sheet) { route in
            GlobalSheet { route.page }
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = GlobalSettings.shared.units.weekStart.rawValue
        return calendar
    }

    private var series: [Double?] {
        guard let scores = health.scores else { return [] }
        switch aspect {
        case .mind: return scores.mindSeries
        case .activity: return scores.strainSeries
        default: return scores.sleepSeries
        }
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                Text("Calendar")
                    .somaFont(theme.typography.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .somaFont(theme.typography.display)
                    .foregroundStyle(theme.colors.inkPrimary.color)
            }
            Spacer()
            SomaIconButton(symbol: "chevron.left", style: .plain, accessibilityLabel: "Previous month") { step(-1) }
            SomaIconButton(symbol: "chevron.right", style: .plain, accessibilityLabel: "Next month") { step(1) }
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? theme.metrics.hairlineOpacity * 3 : 1)
        }
    }

    private func step(_ months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(theme.motion.selection) { month = next }
    }

    private var aspectPicker: some View {
        SomaSegmentedControl(
            segments: Self.aspects.map { SomaSegment(id: $0, title: $0.title) },
            selection: $aspect
        )
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing * 2) {
            HStack(spacing: theme.metrics.cardSpacing) {
                legendDot(theme.colors.inkPrimary.color, "Journal")
                HStack(spacing: theme.metrics.scoreLabelSpacing) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: theme.metrics.browseChevronSize))
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    Text("A status")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            Text(legendLine)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legendLine: String {
        switch aspect {
        case .mind: String(localized: "Each ring fills with that day\u{2019}s Mind score. Days ahead stay empty until they happen.")
        case .activity: String(localized: "Each ring fills with that day\u{2019}s Activity score. Days ahead stay empty until they happen.")
        default: String(localized: "Each ring fills with that night\u{2019}s Sleep score. Days ahead stay empty until they happen.")
        }
    }

    private func legendDot(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: theme.metrics.scoreLabelSpacing) {
            Circle().fill(color).frame(width: theme.metrics.timelineDotDiameter, height: theme.metrics.timelineDotDiameter)
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
    }

    private var todayBlock: some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            Text("Today \u{00B7} \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .somaFont(theme.typography.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.inkSecondary.color)

            SomaScoreRow([
                SomaScore(aspect: .sleep, value: health.scores?.sleep.map { "\($0)" }, trend: health.scores?.sleepTrend),
                SomaScore(aspect: .mind, value: health.scores?.mind.map { "\($0)" }, trend: health.scores?.mindTrend),
                SomaScore(aspect: .activity, value: health.scores?.strain.map { "\($0)" }, trend: health.scores?.strainTrend),
            ]) { aspect = $0 }

            SomaBrowseGroup([SettingsItem(id: "status")]) { _ in
                SomaBrowseRow(
                    symbol: statuses.current.symbol,
                    title: String(localized: "Activity status"),
                    detail: statuses.current.title
                ) { sheet = .activityStatus }
            }
        }
    }
}

/// The month itself: weekday names, then a row of rings a week.
private struct CalendarGrid: View {
    let layout: CalendarMonth
    let aspect: SomaAspect
    let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: theme.metrics.scoreLabelSpacing), count: 7)
        LazyVGrid(columns: columns, spacing: theme.metrics.cardSpacing) {
            ForEach(CalendarMonth.weekdaySymbols(calendar: calendar), id: \.self) { name in
                Text(name)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
            }
            ForEach(layout.weeks.flatMap { $0 }) { day in
                CalendarDayCell(day: day, aspect: aspect)
            }
        }
    }
}

private struct CalendarDayCell: View {
    let day: CalendarMonth.Day
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color
        let side = theme.metrics.minimumTapTarget * 0.9

        VStack(spacing: theme.metrics.scoreLabelSpacing) {
            if day.isInMonth {
                ZStack {
                    Circle()
                        .stroke(colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity * 2), lineWidth: theme.metrics.chartLineWidth)
                    if let score = day.score {
                        Circle()
                            .trim(from: 0, to: Double(score) / 100)
                            .stroke(hue, style: StrokeStyle(lineWidth: theme.metrics.chartLineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(score)")
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(colors.inkPrimary.color)
                    } else {
                        Text("\(day.number)")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(day.isFuture ? colors.inkSecondary.color : colors.inkPrimary.color)
                    }
                }
                .frame(width: side, height: side)
                .background(
                    Circle().fill(day.isToday ? colors.surface.color : .clear)
                )

                HStack(spacing: theme.metrics.scoreLabelSpacing) {
                    if day.hasJournal {
                        Circle().fill(colors.inkPrimary.color)
                            .frame(width: theme.metrics.timelineDotDiameter * 0.7, height: theme.metrics.timelineDotDiameter * 0.7)
                    }
                    if let status = day.status {
                        Image(systemName: status.symbol)
                            .font(.system(size: theme.metrics.browseChevronSize * 0.7))
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
                .frame(height: theme.metrics.timelineDotDiameter)
            } else {
                Color.clear.frame(width: side, height: side + theme.metrics.timelineDotDiameter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        var parts = [day.date.formatted(.dateTime.day().month(.wide))]
        if let score = day.score { parts.append(String(localized: "score \(score)")) }
        if day.hasJournal { parts.append(String(localized: "journal logged")) }
        if let status = day.status { parts.append(status.title) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Calendar") {
    GlobalSheet { CalendarPage() }
        .environment(HealthDashboard())
        .environment(JournalStore(url: nil))
}
