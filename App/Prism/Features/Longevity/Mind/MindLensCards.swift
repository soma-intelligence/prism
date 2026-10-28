//
//  MindLensCards.swift
//  Prism
//

import SwiftUI
import SomaUI

// MARK: - Section

/// A titled group on the Mind lens, headed the way the Body lens heads its
/// own, with an optional way into the page behind it.
struct MindSection<Content: View, Route: Hashable>: View {
    let title: LocalizedStringResource
    let route: Route?
    let content: Content

    @Environment(\.somaTheme) private var theme

    init(_ title: LocalizedStringResource, route: Route?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.route = route
        self.content = content()
    }

    var body: some View {
        let colors = theme.colors

        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            if let route {
                NavigationLink(value: route) {
                    HStack(spacing: theme.metrics.trendMarkSpacing * 2) {
                        heading
                        Image(systemName: "chevron.forward")
                            .somaFont(theme.typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(colors.inkSecondary.color)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                // No zoom source here: the zoom clips its source to its
                // bounds, which cut the title's first letter (owner,
                // 2026-10-25). The page opens with the standard push.
                .buttonStyle(.plain)
            } else {
                heading
            }
            content
        }
    }

    private var heading: some View {
        Text(title)
            .somaFont(theme.typography.headline)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .accessibilityAddTraits(.isHeader)
    }
}

extension MindSection where Route == MindRoute {
    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.init(title, route: nil, content: content)
    }
}

// MARK: - Mindful minutes

/// Today's mindful minutes as a ring that closes at the day's goal, beside
/// the week as bars in the mind hue: full where the goal was met, lighter
/// where it was not. Tapping a bar sets that day in the ring.
struct MindMindfulCard: View {
    let week: [MindBar]
    let goal: Double

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Date?

    var body: some View {
        let metrics = theme.metrics
        let chosen = week.first { $0.id == selection } ?? week.last

        SomaCard {
            HStack(alignment: .center, spacing: metrics.spaceL) {
                ring(chosen)
                bars(selected: chosen?.id)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func ring(_ bar: MindBar?) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = SomaHealthHue.mind
        let diameter = metrics.miniOrbDiameter * 2
        let width = metrics.chartThinBarWidth * 1.6
        let progress = min((bar?.minutes ?? 0) / goal, 1)

        return ZStack {
            Circle()
                .stroke(hue.color.opacity(metrics.chartBandOpacity), lineWidth: width)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(hue.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : theme.motion.selection, value: progress)
            VStack(spacing: 0) {
                SomaNumber(bar?.minutes.map(MindLensFormat.whole), theme.typography.metric)
                    .foregroundStyle(colors.inkPrimary.color)
                    .contentTransition(.numericText())
                Text(bar?.isToday == false ? bar.map { $0.day.formatted(.dateTime.weekday(.abbreviated)) } ?? "" : "of \(MindLensFormat.whole(goal))")
                    .somaFont(theme.typography.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .frame(width: diameter, height: diameter)
        .padding(width / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mindful minutes")
        .accessibilityValue(bar?.minutes.map { "\(MindLensFormat.whole($0)) of \(MindLensFormat.whole(goal))" } ?? SomaFormat.notMeasured)
    }

    private func bars(selected: Date?) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = SomaHealthHue.mind
        let highest = max(week.compactMap(\.minutes).max() ?? 0, goal)
        let height = metrics.chartCompactPlotHeight * 0.8

        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(week) { bar in
                let minutes = bar.minutes ?? 0
                let isChosen = bar.id == selected
                Button {
                    selection = bar.id
                } label: {
                    VStack(spacing: metrics.chartLabelGap) {
                        ZStack(alignment: .bottom) {
                            Capsule()
                                .fill(colors.inkPrimary.color.opacity(metrics.chartGridOpacity * 0.6))
                            Capsule()
                                .fill(hue.color.opacity(minutes >= goal ? 1 : metrics.chartContextBarOpacity + 0.15))
                                .frame(height: bar.minutes == nil ? 0 : max(height * minutes / highest, metrics.chartThinBarWidth))
                        }
                        .frame(width: metrics.chartThinBarWidth * 1.8, height: height)
                        .overlay(alignment: .bottom) {
                            // The goal, a hairline across every bar at the same height.
                            Rectangle()
                                .fill(colors.inkSecondary.color.opacity(0.6))
                                .frame(width: metrics.chartThinBarWidth * 2.6, height: 1)
                                .offset(y: -height * goal / highest)
                        }
                        Text(verbatim: bar.letter)
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(isChosen ? colors.inkPrimary.color : colors.inkSecondary.color)
                    }
                    .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPressDim)
                .accessibilityLabel(Text(bar.day, format: .dateTime.weekday(.wide)))
                .accessibilityValue(bar.minutes.map { "\(MindLensFormat.whole($0)) min" } ?? SomaFormat.notMeasured)
            }
        }
    }
}

// MARK: - Breathe

/// The way into a breathing session: the mind orb breathing in four seconds
/// and out six, the length, and a play glyph. Still under Reduce Motion.
struct MindBreatheCard: View {
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let side = metrics.miniOrbDiameter * 1.4

        Button(action: action) {
            HStack(spacing: metrics.cardSpacing + 4) {
                // One thin ring that breathes with the pace the sheet uses,
                // over a still ring at rest size: the card shows the breath,
                // it does not decorate it.
                MindBreathRing(aspect: .mind)
                    .frame(width: side, height: side)

                VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                    Text("Breathe")
                        .somaFont(theme.typography.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Text("In with the ring, out as it falls")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("Start")
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(colors.onAccent.color)
                    .padding(.horizontal, metrics.spaceM + 2)
                    .padding(.vertical, metrics.spaceS)
                    .background(colors.accent.color, in: .capsule)
            }
            .padding(metrics.cardPadding)
            .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel("Breathe")
        .accessibilityHint("Starts a guided breath")
    }
}

/// One thin ring that breathes at the pace the Breathe sheet uses, over a
/// still ring at rest size, in the aspect's colour: it shows the breath, it
/// does not decorate it. Still with Reduce Motion, off screen and in Low
/// Power Mode.
struct MindBreathRing: View {
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = true
    private var power = SomaPowerState.shared

    init(aspect: SomaAspect) {
        self.aspect = aspect
    }

    var body: some View {
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isOnScreen || power.isLowPower)) { context in
            let scale = reduceMotion ? 0.8 : MindBreatheSheet.breath(at: context.date.timeIntervalSinceReferenceDate).scale
            ZStack {
                Circle()
                    .stroke(colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity), lineWidth: 1)
                Circle()
                    .fill(hue.opacity(0.14))
                    .scaleEffect(scale * 0.86)
                Circle()
                    .stroke(hue, lineWidth: 1.5)
                    .scaleEffect(scale * 0.86)
            }
        }
        .somaOnScreen($isOnScreen)
        .accessibilityHidden(true)
    }
}

// MARK: - Heat map

/// Sixty days of stress by weekday and two hour block, coloured along the
/// zone ramp: teal where little was raised, through amber, to red where the
/// most was. Tapping a block reads it in the header; the busiest is read
/// until then.
struct MindHeatmapCard: View {
    let heatmap: MindHeatmap

    @Environment(\.somaTheme) private var theme
    @State private var selection: Cell?

    struct Cell: Hashable {
        var row: Int
        var column: Int
    }

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let letters = Calendar.current.shortStandaloneWeekdaySymbols
        let shown = selection ?? busiest

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.trendMarkSpacing * 2) {
                    if let shown {
                        let minutes = heatmap.minutes[shown.row][shown.column]
                        Text(MindLensFormat.whole(minutes))
                            .somaFont(theme.typography.metric)
                            .foregroundStyle(colors.inkPrimary.color)
                            .contentTransition(.numericText())
                        Text("min")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                        Spacer(minLength: 0)
                        Text(verbatim: "\(letters[(shown.row + 1) % 7]) · \(Self.hours(shown.column))")
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(color(share(shown)))
                    } else {
                        SomaMissingValue(theme.typography.metric)
                        Spacer(minLength: 0)
                    }
                }
                grid(selected: shown)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var busiest: Cell? {
        guard !heatmap.isEmpty else { return nil }
        var best = Cell(row: 0, column: 0)
        for row in 0..<7 {
            for column in 0..<MindHeatmap.columns where heatmap.minutes[row][column] > heatmap.minutes[best.row][best.column] {
                best = Cell(row: row, column: column)
            }
        }
        return best
    }

    private func grid(selected: Cell?) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let letters = Calendar.current.veryShortStandaloneWeekdaySymbols
        let gap = metrics.chartBarCornerRadius + 1
        let labelWidth = metrics.miniOrbDiameter / 2
        let cellHeight = metrics.chartBarWidth * 1.9

        return VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: gap) {
                    Text(verbatim: letters[(row + 1) % 7])
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<MindHeatmap.columns, id: \.self) { column in
                        let cell = Cell(row: row, column: column)
                        let share = share(cell)
                        let isChosen = cell == selected
                        // A button, so the cell answers the finger as it lands
                        // (a dim), and the card's selection tick follows.
                        Button { selection = cell } label: {
                            RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius, style: .continuous)
                                .fill(share > 0 ? AnyShapeStyle(color(share)) : AnyShapeStyle(colors.surfaceRecessed.color))
                                .overlay {
                                    if isChosen {
                                        RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius, style: .continuous)
                                            .strokeBorder(colors.inkPrimary.color, lineWidth: metrics.chartStroke)
                                    }
                                }
                                .frame(height: cellHeight)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.somaGlassPressDim)
                        .accessibilityLabel(Text(verbatim: "\(Calendar.current.standaloneWeekdaySymbols[(row + 1) % 7]), \(Self.hours(column))"))
                        .accessibilityValue("\(MindLensFormat.whole(heatmap.minutes[row][column])) min")
                    }
                }
            }
            HStack(spacing: gap) {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(0..<MindHeatmap.columns, id: \.self) { column in
                    Text(verbatim: column.isMultiple(of: 2) ? "\(MindHeatmap.firstHour + column * MindHeatmap.blockHours)" : "")
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, gap)
        }
    }

    private func share(_ cell: Cell) -> Double {
        let highest = heatmap.highest
        return highest > 0 ? heatmap.minutes[cell.row][cell.column] / highest : 0
    }

    /// Along the zone ramp, faint at the low end so an empty week stays calm.
    private func color(_ share: Double) -> Color {
        guard share > 0 else { return theme.colors.inkSecondary.color }
        let low = MindZone.low.color
        let medium = MindZone.medium.color
        let high = MindZone.high.color
        let hue = share < 0.5 ? low.mix(with: medium, by: share * 2) : medium.mix(with: high, by: (share - 0.5) * 2)
        return hue.opacity(0.35 + 0.65 * share)
    }

    static func hours(_ column: Int) -> String {
        let start = MindHeatmap.firstHour + column * MindHeatmap.blockHours
        return String(format: "%02d to %02d", start, start + MindHeatmap.blockHours)
    }
}

// MARK: - Deeper pages

/// One way into a deeper Mind page: a glyph in its colour and a short name.
struct MindGlyphTile: View {
    let route: MindRoute
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let hue: SomaHealthHue

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        TileLink(value: route) {
            VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.journalTileGlyph, weight: .light))
                        .foregroundStyle(colors.inkPrimary.color)
                        .frame(height: metrics.journalTileGlyph * 1.2, alignment: .leading)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Spacer(minLength: metrics.spaceS)
                Text(title)
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                Text(detail)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        }
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(detail))
    }
}

/// Every deeper Mind page as a tile, two to a row: an ink glyph, the page's
/// name and a line on what it holds. Colour stays out: eight gradient
/// squircles read as a template, not as Soma.
struct MindGlyphGrid: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let spacing = theme.metrics.cardSpacing

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 2), spacing: spacing) {
            MindGlyphTile(route: .hrv, symbol: "waveform.path.ecg", title: "HRV", detail: "Variability and its trend", hue: .heart)
            MindGlyphTile(route: .stressRadar, symbol: "scope", title: "Radar", detail: "What raised your stress", hue: .vitals)
            MindGlyphTile(route: .moodForecast, symbol: "cloud.sun", title: "Forecast", detail: "Tomorrow\u{2019}s mood, from today", hue: .mobility)
            MindGlyphTile(route: .innerMap, symbol: "circle.hexagongrid", title: "Inner map", detail: "Feelings and what drove them", hue: .symptoms)
            MindGlyphTile(route: .detail, symbol: "brain.head.profile", title: "Score", detail: "How your Mind score is built", hue: .mind)
            MindGlyphTile(route: .insights, symbol: "square.grid.3x3", title: "Insights", detail: "Patterns across your weeks", hue: .cycle)
            MindGlyphTile(route: .meetings, symbol: "calendar", title: "Meetings", detail: "Calendar load against stress", hue: .hearing)
            MindGlyphTile(route: .habits(.recovery), symbol: "leaf", title: "Habits", detail: "What helps you recover", hue: .nutrition)
            MindGlyphTile(route: .assessments, symbol: "list.clipboard", title: "Questionnaires",
                          detail: LocalizedStringResource(stringLiteral: MindGlyphGrid.assessmentLine(MindStore.shared.latest(.phq9))), hue: .mind)
            MindGlyphTile(route: .connection, symbol: "person.2", title: "Connection",
                          detail: LocalizedStringResource(stringLiteral: MindGlyphGrid.assessmentLine(MindStore.shared.latest(.ucla3), invitation: "Time with people, and how it feels")), hue: .heart)
        }
    }

    /// The questionnaires tile's line: the last PHQ-9 with its band and its
    /// day, never the number alone, or the invitation when there is none.
    static func assessmentLine(_ latest: MindAssessment?, invitation: String = "Take a 2 minute check") -> String {
        guard let latest, let reading = latest.reading else { return invitation }
        return "\(latest.instrument.title) \(reading.value), \(reading.word.localizedLowercase), \(MindAssessmentFormat.day(latest.date))"
    }
}

#if DEBUG
#Preview("Mind lens cards") {
    NavigationStack {
        SomaPageScroll {
            VStack(spacing: 16) {
                MindMindfulCard(week: MindLensModel.preview.week, goal: MindLensModel.mindfulGoal)
                MindBreatheCard {}
                MindHeatmapCard(heatmap: MindLensModel.preview.heatmap)
                MindGlyphGrid()
            }
            .padding()
        }
        .softScrollEdges()
    }
    .somaTheme(.standard)
}
#endif
