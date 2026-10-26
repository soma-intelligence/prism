//
//  MindInnerMapPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The inner map, last eight weeks: the feelings named week by week, felt
/// against measured, and what pulls on a person.
///
/// Feelings are Apple Health's State of Mind entries and the ones kept on
/// the phone (`MindInnerMap`); measured is the day's HRV against the usual.
struct MindInnerMapPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var moods: [MindMoodEntry] = []
    @State private var inputs: MindInputs?
    @State private var isLogging = false

    var body: some View {
        let calendar = Calendar.current
        let words = PulseWording(calendar: calendar, locale: .current)
        let base = inputs ?? MindInputs(now: Date())
        let hrvByDay = MindUsual.daily(base.heartRateVariability, calendar: calendar, reduce: MindUsual.mean)
        let usual = MindUsual.percentile(Array(hrvByDay.values), 0.5)
        let map = MindInnerMap.make(
            moods: moods, notes: MindStore.shared.notes, hrvByDay: hrvByDay,
            usualHRV: hrvByDay.count >= MindUsual.minimumDays ? usual : nil,
            now: Date(), calendar: calendar
        )

        MindPage(
            navigationTitle: "Inner map",
            title: map.headline
        ) {
            SomaChartCard(
                eyebrow: "Feelings by week",
                value: "\(map.checkIns)",
                unit: "check-ins in 8 weeks",
                note: map.rows.isEmpty ? "Each feeling you name lands here, week by week." : "Bigger means more often that week."
            ) {
                if !map.rows.isEmpty {
                    MindFeelingGrid(rows: map.rows, weekStarts: map.weekStarts)
                }
            }

            SomaChartCard(
                eyebrow: "Feel and measure",
                value: map.points.isEmpty ? nil : "\(map.agreeing) of \(map.points.count)",
                unit: "days agree",
                note: map.points.isEmpty
                    ? "Once a feeling and an HRV reading share a day, the two are set side by side here."
                    : "Across: how you felt. Up: HRV against your usual. A day agrees when both sit on the same side."
            ) {
                if !map.points.isEmpty {
                    MindFeelMeasureChart(points: map.points)
                }
            }

            if !map.pulls.isEmpty {
                MindRowsCard(title: "What pulls on you", caption: "People, places and themes", rows: map.pulls) { pull in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pull.title)
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                            Text("a \(pull.kind.rawValue) · held \(pull.held) of \(pull.mentions) times")
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: theme.metrics.spaceS) {
                            Text(pull.lifts ? "lifts" : "weighs")
                                .somaFont(theme.typography.rowValue)
                                .foregroundStyle(pull.lifts ? theme.colors.inkPrimary.color : theme.colors.danger.color)
                            SomaEffectBar(fraction: Double(pull.held) / Double(max(pull.mentions, 1)) * (pull.lifts ? 1 : -1), aspect: .mind, isCost: !pull.lifts)
                                .frame(width: theme.metrics.aspectChartWidth)
                        }
                    }
                    .padding(.vertical, theme.metrics.browseRowVerticalPadding)
                    .accessibilityElement(children: .combine)
                }
            }

            SomaActionCard(
                eyebrow: "Right now",
                title: "Name how you feel",
                detail: "One word a day is enough for the map to fill in.",
                actionTitle: "Check in",
                action: { isLogging = true }
            ) {
                SomaObjectIcon(aspect: .mind, size: .row)
            }
        }
        .task { await load() }
        .sheet(isPresented: $isLogging, onDismiss: { Task { await load() } }) {
            MindEntryGate { MindEmotionLogSheet() }
        }
    }

    private func load() async {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -MindInnerMap.weeks, to: Date()) ?? Date()
        moods = await MindJourneyLoad.moods(since: start, store: .shared)
        if inputs == nil { inputs = await MindLoad.inputs(health) }
    }
}

/// Feelings by week: one row per feeling, a dot per week sized by count.
struct MindFeelingGrid: View {
    let rows: [MindInnerMap.Row]
    let weekStarts: [Date]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let type = theme.typography
        let hue = theme.aspects[.mind].identity.color
        let most = max(rows.flatMap(\.counts).max() ?? 1, 1)
        let largest = theme.metrics.chartEstimateDiameter * 1.6

        VStack(spacing: 8) {
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    Text(row.feeling.title)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(width: theme.metrics.aspectChartWidth * 0.75, alignment: .leading)
                    ForEach(Array(row.counts.enumerated()), id: \.offset) { _, count in
                        Circle()
                            .fill(row.feeling.isPleasant ? hue : colors.danger.color)
                            .frame(width: count == 0 ? 2 : largest * CGFloat(0.35 + 0.65 * Double(count) / Double(most)))
                            .frame(maxWidth: .infinity, minHeight: largest)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.feeling.title)
                .accessibilityValue("\(row.total) times in 8 weeks")
            }
            HStack {
                Color.clear.frame(width: theme.metrics.aspectChartWidth * 0.75, height: 1)
                if let first = weekStarts.first { Text(first.formatted(.dateTime.day().month(.abbreviated))) }
                Spacer()
                if let last = weekStarts.last { Text(last.formatted(.dateTime.day().month(.abbreviated))) }
            }
            .somaFont(type.captionValue)
            .foregroundStyle(colors.inkSecondary.color)
        }
    }
}

/// Felt across, measured up: one dot per day in four quadrants, on hairline
/// axes. A day where the two agree is filled, one where they part hollow.
struct MindFeelMeasureChart: View {
    let points: [MindInnerMap.Point]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.mind].identity.color
        let reach = max(points.map { abs($0.measured) }.max() ?? 1, 1) * 1.15
        let points = points
        let pen = SomaPen(theme)
        Canvas { context, size in
            let inset = pen.point
            let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            pen.gridline(context, y: plot.midY, from: 0, to: size.width)
            pen.vertical(context, x: plot.midX, height: size.height)
            for share in [0.0, 1.0] {
                pen.gridline(context, y: share == 0 ? 0.25 : size.height - 0.25, to: size.width)
            }
            for point in points {
                let x = plot.minX + plot.width * CGFloat((point.felt + 1) / 2)
                let y = plot.midY - CGFloat(point.measured / reach) * plot.height / 2
                pen.dot(context, at: CGPoint(x: x, y: y), color: hue, filled: point.agrees)
            }
        }
        .frame(height: theme.metrics.chartPlotHeight)
        .overlay(alignment: .bottomLeading) { label("Felt low").padding(theme.metrics.spaceXS) }
        .overlay(alignment: .bottomTrailing) { label("Felt great").padding(theme.metrics.spaceXS) }
        .overlay(alignment: .topLeading) { label("Body above usual").padding(theme.metrics.spaceXS) }
        .accessibilityElement()
        .accessibilityLabel("Felt against measured")
        .accessibilityValue("\(points.filter(\.agrees).count) of \(points.count) days agree")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
    }
}
