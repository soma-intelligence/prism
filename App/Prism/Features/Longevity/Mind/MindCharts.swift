//
//  MindCharts.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Today's energy bank, 00 to 24, drawn from midnight to now: the line ends
/// in a ring where the day has got to, and with no bank yet the grid stands
/// empty. Under it, the stress strip: one thin mark per half hour, tall where
/// the heart was raised while still.
struct MindEnergyChart: View {
    let slots: [MindSlot]
    var curve: [MindEnergyPoint] = []

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color
        let curve = curve
        let slots = slots

        VStack(alignment: .leading, spacing: metrics.chartLabelGap) {
            SomaPlot(scale: SomaPlotScale(fixed: 0...100), height: metrics.chartCompactPlotHeight) { context, space, pen in
                let points = curve.map {
                    CGPoint(x: space.x(fraction: $0.dayFraction), y: space.y(min(100, max(0, $0.level))))
                }
                pen.line(context, points, color: hue)
                if let last = points.last { pen.ring(context, at: last, color: hue) }
            }
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: metrics.chartLabelGap) {
                VStack(alignment: .leading, spacing: metrics.chartLabelGap) {
                    Canvas { context, size in
                        let pen = SomaPen(theme)
                        let pitch = size.width / CGFloat(max(slots.count, 1))
                        for (index, slot) in slots.enumerated() {
                            let x = pitch * (CGFloat(index) + 0.5)
                            let (top, color): (CGFloat, Color) = switch slot {
                            case .raised: (0, hue)
                            case .quiet: (size.height * 0.55, hue.opacity(pen.contextOpacity))
                            case .later: (size.height * 0.8, pen.grid)
                            }
                            pen.bar(context, x: x, top: top, floor: size.height, pitch: pitch, color: color)
                        }
                    }
                    .frame(height: metrics.chartSparkHeight * 0.6)
                    .accessibilityElement()
                    .accessibilityLabel("Stress today")
                    .accessibilityValue(accessibilityValue)

                    SomaAxisLabels(["00", "06", "12", "18", "24"])
                }
                Text("Stress")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize()
            }
        }
    }

    private var accessibilityValue: Text {
        let raised = slots.filter { $0 == .raised }.count
        return raised == 0 ? Text("No stress peaks") : Text("\(raised * 30) minutes raised")
    }
}

/// Mindful minutes over the last seven days as thin bars, today in the mind
/// hue and the days before it faded, the scale on the trailing edge.
struct MindWeekBars: View {
    let bars: [MindBar]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.mind].identity.color
        let bars = bars
        let highest = bars.compactMap(\.minutes).max() ?? 0

        SomaPlot(scale: highest > 0 ? SomaPlotScale(values: [0, highest], desired: 3) : nil,
                 xLabels: bars.map(\.letter), labelsUnderBars: true, height: theme.metrics.chartCompactPlotHeight * 0.8) { context, space, pen in
            let pitch = space.pitch(bars.count)
            for (index, bar) in bars.enumerated() {
                guard let minutes = bar.minutes else { continue }
                let x = space.slot(index, of: bars.count)
                // A day with none keeps a sliver on the floor: zero, measured.
                let top = minutes > 0 ? space.y(minutes) : space.floor - 1
                pen.bar(context, x: x, top: top, floor: space.floor, pitch: pitch,
                        color: bar.isToday ? hue : hue.opacity(pen.contextOpacity))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Mindful minutes, last seven days")
        .accessibilityValue(Text(bars.map { $0.minutes.map { "\(Int($0.rounded()))" } ?? "-" }.joined(separator: ", ")))
    }
}

/// When stress peaks, weekday by two hour block: the darker the block, the
/// more minutes of heart rate raised while still it held.
struct MindHeatmapGrid: View {
    let heatmap: MindHeatmap

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color
        let highest = heatmap.highest
        let letters = Calendar.current.veryShortStandaloneWeekdaySymbols
        let cellHeight = metrics.chartBarWidth * 1.7
        let gap = metrics.chartBarCornerRadius + 1
        let labelWidth = metrics.miniOrbDiameter / 2

        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: gap) {
                    Text(letters[(row + 1) % 7])
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<MindHeatmap.columns, id: \.self) { column in
                        let share = highest > 0 ? heatmap.minutes[row][column] / highest : 0
                        RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius, style: .continuous)
                            .fill(colors.surfaceRecessed.color)
                            .overlay(
                                RoundedRectangle(cornerRadius: metrics.chartBarCornerRadius, style: .continuous)
                                    .fill(hue.opacity(share > 0 ? 0.15 + 0.85 * share : 0))
                            )
                            .frame(height: cellHeight)
                    }
                }
            }

            HStack(spacing: gap) {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(0..<MindHeatmap.columns, id: \.self) { column in
                    Text(verbatim: column.isMultiple(of: 2) ? "\(MindHeatmap.firstHour + column * MindHeatmap.blockHours)" : "")
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, gap)
        }
        .accessibilityElement()
        .accessibilityLabel("Stress by weekday and hour")
        .accessibilityValue(heatmap.isEmpty ? Text("No stress peaks yet") : Text("Darker blocks held more stress"))
    }
}

/// What came before the hard afternoons: one bar per thing, filled by the
/// share of afternoons it came before.
struct MindPrecursorBars: View {
    let precursors: [MindPrecursor]
    let total: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color

        VStack(alignment: .leading, spacing: metrics.moveRowSpacing + 4) {
            ForEach(precursors) { item in
                VStack(alignment: .leading, spacing: metrics.chartLabelGap) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                        Spacer(minLength: 8)
                        Text(total > 0 ? "\(item.count) of \(total)" : "-")
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(colors.inkPrimary.color.opacity(metrics.chartGridOpacity))
                            if total > 0, item.count > 0 {
                                Capsule()
                                    .fill(hue)
                                    .frame(width: max(proxy.size.width * CGFloat(item.count) / CGFloat(total), metrics.chartThinBarWidth * 0.75))
                            }
                        }
                    }
                    .frame(height: metrics.chartThinBarWidth * 0.75)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A reason set the way ``SomaPageHero`` sets one: the first sentence in ink,
/// the rest in grey.
struct MindReasonText: View {
    let text: String

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let parts = split
        (Text(parts.0).foregroundStyle(colors.inkPrimary.color)
            + Text(parts.1).foregroundStyle(colors.inkSecondary.color))
            .somaFont(theme.typography.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var split: (String, String) {
        guard let range = text.range(of: ". ") else { return (text, "") }
        return (String(text[..<range.upperBound]), String(text[range.upperBound...]))
    }
}

#if DEBUG
#Preview("Mind charts") {
    ScrollView {
        VStack(spacing: 16) {
            SomaCard { MindEnergyChart(slots: MindInnerSpace.preview.slots, curve: MindInnerSpace.preview.energyCurve) }
            SomaCard { MindWeekBars(bars: MindInnerSpace.preview.week) }
            SomaCard { MindHeatmapGrid(heatmap: MindInsights.preview.heatmap) }
            SomaCard { MindPrecursorBars(precursors: MindInsights.preview.precursors, total: 9) }
        }
        .padding()
    }
    .somaTheme(.standard)
}
#endif
