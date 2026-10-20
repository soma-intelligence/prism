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
            HStack(alignment: .center, spacing: metrics.cardSpacing * 1.5) {
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
                .stroke(
                    AngularGradient(colors: [hue.end.color, hue.start.color], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.01))),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : theme.motion.selection, value: progress)
            VStack(spacing: 0) {
                Text(bar?.minutes.map(MindLensFormat.whole) ?? "-")
                    .somaFont(theme.typography.metric)
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
        .accessibilityValue(bar?.minutes.map { "\(MindLensFormat.whole($0)) of \(MindLensFormat.whole(goal))" } ?? "-")
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
                                .fill(
                                    LinearGradient(colors: [hue.end.color, hue.start.color], startPoint: .top, endPoint: .bottom)
                                        .opacity(minutes >= goal ? 1 : metrics.chartContextBarOpacity + 0.15)
                                )
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
                .buttonStyle(.plain)
                .accessibilityLabel(Text(bar.day, format: .dateTime.weekday(.wide)))
                .accessibilityValue(bar.minutes.map { "\(MindLensFormat.whole($0)) min" } ?? "-")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = SomaHealthHue.mind

        Button(action: action) {
            HStack(spacing: metrics.cardSpacing) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let scale = reduceMotion ? 1 : MindBreatheSheet.breath(at: context.date.timeIntervalSinceReferenceDate).scale
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [hue.end.color.opacity(0.45), .clear],
                                                 center: .center, startRadius: 0, endRadius: metrics.miniOrbDiameter * 0.9))
                            .scaleEffect(scale * 1.15)
                        SomaOrb(aspect: .mind, scale: .mini)
                            .scaleEffect(scale)
                    }
                }
                .frame(width: metrics.miniOrbDiameter * 1.5, height: metrics.miniOrbDiameter * 1.5)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                    Text("Breathe")
                        .somaFont(theme.typography.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Text(verbatim: "4 · 6 · 10 min")
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(SomaHealthHue.ink.color)
                    .frame(width: metrics.minimumTapTarget, height: metrics.minimumTapTarget)
                    .background(
                        LinearGradient(colors: [hue.end.color, hue.start.color], startPoint: .top, endPoint: .bottom),
                        in: .circle
                    )
            }
            .padding(metrics.cardPadding)
            .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityLabel("Breathe, 10 min")
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
                        Text(verbatim: "-")
                            .somaFont(theme.typography.metric)
                            .foregroundStyle(colors.inkSecondary.color)
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
                            .onTapGesture { selection = cell }
                            .accessibilityElement()
                            .accessibilityLabel(Text(verbatim: "\(Calendar.current.standaloneWeekdaySymbols[(row + 1) % 7]), \(Self.hours(column))"))
                            .accessibilityValue("\(MindLensFormat.whole(heatmap.minutes[row][column])) min")
                            .accessibilityAddTraits(.isButton)
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

/// A deeper Mind page as a tile: its line glyph on the Mind badge, drawn
/// like the aspect glyphs, and its name under it.
struct MindGlyphTile: View {
    let route: MindRoute
    let glyph: SomaMindGlyph.Kind
    let title: LocalizedStringResource

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        TileLink(value: route) {
            VStack(spacing: metrics.cardHeaderSpacing + 4) {
                SomaMindGlyph(glyph)
                Text(title)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.cardPadding)
            .background(theme.colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
            )
        }
        .accessibilityLabel(Text(title))
    }
}

/// Every deeper Mind page as a glyph tile, four to a row.
struct MindGlyphGrid: View {
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let spacing = theme.metrics.cardSpacing * 0.75

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 4), spacing: spacing) {
            MindGlyphTile(route: .hrv, glyph: .hrv, title: "HRV")
            MindGlyphTile(route: .stressRadar, glyph: .radar, title: "Radar")
            MindGlyphTile(route: .moodForecast, glyph: .forecast, title: "Forecast")
            MindGlyphTile(route: .innerMap, glyph: .innerMap, title: "Inner map")
            MindGlyphTile(route: .detail, glyph: .score, title: "Score")
            MindGlyphTile(route: .insights, glyph: .insights, title: "Insights")
            MindGlyphTile(route: .meetings, glyph: .meetings, title: "Meetings")
            MindGlyphTile(route: .habits(.recovery), glyph: .habits, title: "Habits")
        }
    }
}

#if DEBUG
#Preview("Mind lens cards") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                MindMindfulCard(week: MindLensModel.preview.week, goal: MindLensModel.mindfulGoal)
                MindBreatheCard {}
                MindHeatmapCard(heatmap: MindLensModel.preview.heatmap)
                MindGlyphGrid()
            }
            .padding()
        }
    }
    .somaTheme(.standard)
}
#endif
