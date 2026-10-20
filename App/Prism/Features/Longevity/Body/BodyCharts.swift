//
//  BodyCharts.swift
//  Prism
//

import SwiftUI
import SomaUI

// The plots the Body tab's three parts draw. Each is driven by its inputs and
// the theme; a plot with nothing to show still draws its frame, so the card
// keeps its shape and says what fills it.

// MARK: - Body map

/// A figure drawn from plain shapes, with five regions labelled around it,
/// each with its change or a dash.
struct BodySilhouette: View {
    /// The change per region, in the order right arm, left arm, trunk, right
    /// leg, left leg; nil for a region not measured.
    var changes: [String?] = Array(repeating: nil, count: 5)

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let fill = theme.aspects[.body].identity.color.opacity(metrics.chartContextOpacity * 0.5)
        let leader = colors.inkSecondary.color.opacity(0.6)

        GeometryReader { proxy in
            let cx = proxy.size.width / 2
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.fill(Path(ellipseIn: CGRect(x: cx - 13, y: 0, width: 26, height: 26)), with: .color(fill))
                    let parts: [(CGRect, CGFloat)] = [
                        (CGRect(x: cx - 24, y: 32, width: 48, height: 84), 12),
                        (CGRect(x: cx - 45, y: 36, width: 15, height: 76), 7),
                        (CGRect(x: cx + 30, y: 36, width: 15, height: 76), 7),
                        (CGRect(x: cx - 23, y: 122, width: 21, height: 90), 9),
                        (CGRect(x: cx + 2, y: 122, width: 21, height: 90), 9),
                    ]
                    for (rect, radius) in parts {
                        context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(fill))
                    }

                    var lines = Path()
                    lines.move(to: CGPoint(x: cx - 58, y: 74)); lines.addLine(to: CGPoint(x: cx - 49, y: 74))
                    lines.move(to: CGPoint(x: cx + 49, y: 74)); lines.addLine(to: CGPoint(x: cx + 58, y: 74))
                    lines.move(to: CGPoint(x: cx + 14, y: 40)); lines.addLine(to: CGPoint(x: cx + 20, y: 30))
                    lines.addLine(to: CGPoint(x: cx + 30, y: 30))
                    lines.move(to: CGPoint(x: cx - 37, y: 167)); lines.addLine(to: CGPoint(x: cx - 27, y: 167))
                    lines.move(to: CGPoint(x: cx + 27, y: 167)); lines.addLine(to: CGPoint(x: cx + 37, y: 167))
                    context.stroke(lines, with: .color(leader), lineWidth: 1)
                }

                label("Right arm", changes[0], trailingAt: cx - 62, y: 74)
                label("Left arm", changes[1], leadingAt: cx + 62, y: 74)
                label("Trunk", changes[2], leadingAt: cx + 34, y: 30)
                label("Right leg", changes[3], trailingAt: cx - 41, y: 167)
                label("Left leg", changes[4], leadingAt: cx + 41, y: 167)
            }
            .somaFont(type.caption)
        }
        .frame(height: metrics.bodyMapHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Body map by region"))
    }

    private func label(_ name: String, _ change: String?, trailingAt x: CGFloat, y: CGFloat) -> some View {
        Text(verbatim: "\(name) \(change ?? "-")")
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize()
            .frame(width: x, alignment: .trailing)
            .offset(y: y - 8)
    }

    private func label(_ name: String, _ change: String?, leadingAt x: CGFloat, y: CGFloat) -> some View {
        Text(verbatim: "\(name) \(change ?? "-")")
            .foregroundStyle(theme.colors.inkSecondary.color)
            .fixedSize()
            .offset(x: x, y: y - 8)
    }
}

// MARK: - Rows of bars

/// One row of a bar list: a name, a bar against the longest in the list, and
/// the value. The Cardio zones and the Strength regions both read this way.
struct BodyBarRow: View {
    let title: String
    var subtitle: String?
    /// The bar's share of the track, nil for an empty track.
    let fraction: Double?
    let value: String?
    var aspect: SomaAspect = .body
    var isHighlighted = false
    /// A span on the same scale as the bar, drawn as a line under it: the
    /// range that is usual.
    var usual: ClosedRange<Double>?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color
        let height = metrics.bodyRowBarHeight

        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                if let subtitle {
                    Text(subtitle)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: metrics.bodyRowLabelWidth, alignment: .leading)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.surfaceRecessed.color)
                    if let fraction, fraction > 0 {
                        Capsule()
                            .fill(hue.opacity(isHighlighted ? 1 : metrics.chartContextOpacity + 0.25))
                            .frame(width: max(height, width * min(fraction, 1)))
                    }
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if let usual {
                        Capsule()
                            .fill(colors.inkSecondary.color)
                            .frame(width: max(2, width * (min(usual.upperBound, 1) - usual.lowerBound)), height: 2)
                            .offset(x: width * usual.lowerBound, y: proxy.size.height / 2 + height)
                    }
                }
            }
            .frame(height: height * 3)

            Text(value ?? "-")
                .somaFont(type.rowValue)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
                .frame(width: metrics.bodyRowValueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(subtitle.map { "\(title), \($0)" } ?? title))
        .accessibilityValue(Text(value ?? "Not measured"))
    }
}

// MARK: - A line over time

/// Values in order as one line, in an aspect's hue, scaled to their own
/// span. Draws nothing below two values.
struct BodyLine: View {
    let values: [Double]
    var aspect: SomaAspect = .heart

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let width = theme.metrics.chartLineWidth
        let hairline = theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity)

        Canvas { context, size in
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height))
            base.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(base, with: .color(hairline), lineWidth: 1)

            guard values.count >= 2, let low = values.min(), let high = values.max() else { return }
            let spread = max(high - low, 1)
            let inset = width
            var line = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = inset + (size.height - 2 * inset) * (1 - CGFloat((value - low) / spread))
                if index == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(line, with: .color(hue), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Columns of dots

/// One column per week, one dot per session, the week in progress in full
/// colour and the weeks before it faded.
struct BodyDotColumns: View {
    let counts: [Int]
    var aspect: SomaAspect = .body

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[aspect].identity.color
        let hairline = theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity)

        Canvas { context, size in
            let baseline = size.height - 1 / displayScale
            var base = Path()
            base.move(to: CGPoint(x: 0, y: baseline))
            base.addLine(to: CGPoint(x: size.width, y: baseline))
            context.stroke(base, with: .color(hairline), lineWidth: 1 / displayScale)

            guard !counts.isEmpty else { return }
            let highest = max(counts.max() ?? 0, 1)
            let room = baseline - 4
            let pitch = min(metrics.bodySessionDotDiameter + 4, room / CGFloat(highest))
            let dot = max(3, pitch - 4)
            let step = size.width / CGFloat(counts.count)
            for (index, count) in counts.enumerated() where count > 0 {
                let x = step * (CGFloat(index) + 0.5)
                let shading = index == counts.count - 1 ? 1 : metrics.chartContextOpacity + 0.3
                for level in 0..<count {
                    let y = baseline - 4 - pitch * CGFloat(level) - dot / 2
                    let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(hue.opacity(shading)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Body charts") {
    SomaPageScroll {
        VStack(spacing: 24) {
            BodySilhouette()
            BodyBarRow(title: "Zone 2", subtitle: "Aerobic", fraction: 0.2, value: "38 min", aspect: .heart, isHighlighted: true, usual: 0.4...0.7)
            BodyLine(values: [120, 140, 150, 146, 152, 160, 158, 166]).frame(height: 90)
            BodyDotColumns(counts: [2, 2, 1, 2, 3, 2, 2, 2]).frame(height: 88)
        }
        .padding()
    }
}
#endif
