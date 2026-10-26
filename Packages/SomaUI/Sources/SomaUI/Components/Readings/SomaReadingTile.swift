//
//  SomaReadingTile.swift
//  SomaUI
//

import SwiftUI

/// One reading as a tile in Today's grid: the name and an arrow that says the
/// tile opens its page, the number large with its unit, a small chart drawn to
/// scale, and one line on what the number means for you.
///
/// Neka's metric cards without their washes: the surface stays neutral, and
/// colour arrives only through the note's dot when the reading sits outside
/// its usual range.
public struct SomaReadingTile<Chart: View>: View {
    private let title: String
    private let value: String?
    private let unit: String?
    private let note: String?
    private let tone: SomaCueTone?
    private let chart: Chart

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - value: the number as it should read, or nil for a dash.
    ///   - unit: what it counts, set small beside it.
    ///   - note: what the number means, against your usual or your need.
    ///   - tone: a dot before the note when the reading is off its usual.
    public init(
        _ title: String,
        value: String?,
        unit: String? = nil,
        note: String?,
        tone: SomaCueTone? = nil,
        @ViewBuilder chart: () -> Chart
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.note = note
        self.tone = tone
        self.chart = chart()
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.tileSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .somaFont(type.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                SomaNumber(value, type.metricCompact)
                    .foregroundStyle(colors.inkPrimary.color)
                if let unit, value != nil {
                    Text(unit)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            chart
                .frame(height: metrics.tileChartHeight)
                .padding(.vertical, metrics.tileSpacing)
                .accessibilityHidden(true)

            Group {
                if let note {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if let tone {
                            Circle()
                                .fill(tone.color(colors))
                                .frame(width: metrics.chartDotDiameter, height: metrics.chartDotDiameter)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        }
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(verbatim: " ").accessibilityHidden(true)
                }
            }
            .somaFont(type.caption)
            .foregroundStyle(colors.inkSecondary.color)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens its page."))
    }
}

/// A score from 0 to 100 on three bands, low, moderate and high, with a tick
/// at the score: where today sits, without inventing a colour for it.
public struct SomaBandGauge: View {
    private let value: Double?

    @Environment(\.somaTheme) private var theme

    /// - Parameter value: 0 to 100, or nil for an empty track.
    public init(_ value: Double?) {
        self.value = value
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let type = theme.typography
        let bands: [ClosedRange<Double>] = [0...33, 34...66, 67...100]

        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let mid = proxy.size.height / 2
                let track = metrics.chartTrackHeight
                ZStack(alignment: .topLeading) {
                    ForEach(bands, id: \.lowerBound) { band in
                        let isOn = value.map { band.contains($0.rounded()) } ?? false
                        Capsule()
                            .fill(isOn ? colors.inkPrimary.color : colors.surfaceRecessed.color)
                            .frame(width: max(0, width * (band.upperBound - band.lowerBound) / 100 - 2), height: track)
                            .offset(x: width * band.lowerBound / 100, y: mid - track / 2)
                    }
                    if let value {
                        Capsule()
                            .fill(colors.inkPrimary.color)
                            .frame(width: metrics.chartMarkerWidth, height: metrics.chartMarkerHeight)
                            .offset(x: width * min(1, max(0, value / 100)) - metrics.chartMarkerWidth / 2,
                                    y: mid - metrics.chartMarkerHeight / 2)
                    }
                }
            }
            HStack {
                Text("Low")
                Spacer()
                Text("Moderate")
                Spacer()
                Text("High")
            }
            .somaFont(type.caption)
            .foregroundStyle(colors.inkSecondary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityHidden(true)
    }
}

/// Bars for a run of days, the last one in full ink, with an optional dashed
/// line for a target such as the sleep you need. Days with nothing recorded
/// leave a gap rather than a bar of zero.
public struct SomaTargetBars: View {
    private let values: [Double?]
    private let target: Double?
    private let floor: Double?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - target: drawn as a dashed line across the bars.
    ///   - floor: the value the bars start from, so a week of seven to eight
    ///     hours does not draw as seven equal blocks. Nil starts at zero.
    public init(_ values: [Double?], target: Double? = nil, floor: Double? = nil) {
        self.values = values
        self.target = target
        self.floor = floor
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let values = values
        let target = target
        let base = floor ?? 0
        let top = max(values.compactMap { $0 }.max() ?? 0, target ?? 0) * 1.06

        Canvas { context, size in
            guard top > base, values.contains(where: { $0 != nil }) else { return }
            let pitch = size.width / CGFloat(max(values.count, 1))
            let barWidth = pitch * 0.62
            func y(_ value: Double) -> CGFloat { size.height - size.height * CGFloat((value - base) / (top - base)) }
            for (index, value) in values.enumerated() {
                guard let value, value > base else { continue }
                let isLast = index == values.count - 1
                let rect = CGRect(x: pitch * CGFloat(index) + (pitch - barWidth) / 2, y: y(value),
                                  width: barWidth, height: size.height - y(value))
                context.fill(Path(roundedRect: rect, cornerRadius: metrics.chartBarCornerRadius),
                             with: .color(isLast ? colors.inkPrimary.color : colors.inkSecondary.color.opacity(0.3)))
            }
            if let target {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(target)))
                line.addLine(to: CGPoint(x: size.width, y: y(target)))
                context.stroke(line, with: .color(colors.inkPrimary.color),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Reading tiles") {
    ZStack {
        SomaPreviewBackdrop()
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            SomaReadingTile("Sleep", value: "7 h 12", note: "28 min under your 7 h 40 need") {
                SomaTargetBars([6.7, 7.4, 6.5, 7.5, 6.9, 6.2, 7.2], target: 7.67, floor: 5)
            }
            SomaReadingTile("Recovery", value: "78", unit: "of 100", note: "HRV above usual, resting heart rate steady") {
                SomaBandGauge(78)
            }
            SomaReadingTile("Cardio fitness", value: "46.8", unit: "VO2 max", note: "Up 1.7 in 90 days", tone: .good) {
                SomaSparkline([45.1, 45.3, 45.2, 45.8, 46.0, 46.3, 46.4, 46.8], filled: true)
            }
            SomaReadingTile("Steps", value: nil, unit: "so far", note: nil) {
                SomaTargetBars([9874, 7310, 11020, nil, 8340, 9900, nil])
            }
        }
        .padding(16)
    }
}
