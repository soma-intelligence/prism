//
//  EnvironmentParts.swift
//  Prism
//

import SwiftUI
import SomaUI

/// One measure against its usual: the name, its usual or good range when
/// there is one, the value, and a rail with the usual band and today's dot.
/// A value worse than usual turns the value and the dot to danger.
struct EnvironmentMeasureRow: View {
    struct Rail: Equatable {
        var range: ClosedRange<Double>
        var band: ClosedRange<Double>?
        var value: Double?
    }

    let name: String
    var detail: String? = nil
    let value: String?
    var isWorse: Bool = false
    var rail: Rail?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let valueColour = isWorse ? colors.danger.color : colors.inkPrimary.color

        HStack(alignment: .top, spacing: theme.metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                if let detail {
                    Text(detail)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text(value ?? "-")
                    .somaFont(type.body)
                    .foregroundStyle(value == nil ? colors.inkSecondary.color : valueColour)
                if let rail {
                    EnvironmentRail(rail: rail, isWorse: isWorse)
                        .frame(width: theme.metrics.pulseSparklineWidth, height: theme.metrics.chartDotDiameter + 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short track over a measure's range: the usual band in a darker grey and
/// today's value as a dot.
struct EnvironmentRail: View {
    let rail: EnvironmentMeasureRow.Rail
    let isWorse: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        Canvas { context, size in
            let track = metrics.chartTrackHeight
            let midY = size.height / 2
            let span = max(rail.range.upperBound - rail.range.lowerBound, 0.0001)
            func x(_ value: Double) -> CGFloat {
                let share = (min(max(value, rail.range.lowerBound), rail.range.upperBound) - rail.range.lowerBound) / span
                return size.width * CGFloat(share)
            }
            let base = CGRect(x: 0, y: midY - track / 2, width: size.width, height: track)
            context.fill(Path(roundedRect: base, cornerRadius: track / 2), with: .color(colors.surfaceRecessed.color))
            if let band = rail.band {
                let rect = CGRect(x: x(band.lowerBound), y: midY - track / 2,
                                  width: max(x(band.upperBound) - x(band.lowerBound), track), height: track)
                context.fill(Path(roundedRect: rect, cornerRadius: track / 2),
                             with: .color(colors.inkSecondary.color.opacity(0.6)))
            }
            if let value = rail.value {
                let dot = metrics.chartDotDiameter + 1
                let centre = CGPoint(x: min(max(x(value), dot / 2), size.width - dot / 2), y: midY)
                context.fill(Path(ellipseIn: CGRect(x: centre.x - dot / 2, y: centre.y - dot / 2, width: dot, height: dot)),
                             with: .color(isWorse ? colors.danger.color : colors.inkPrimary.color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The day from midnight to midnight as a track, today's stretches outside
/// filled in, and a marker on now.
struct EnvironmentDayTrack: View {
    let spans: [ClosedRange<Double>]
    let now: Double
    /// The first and last minute outside, written under the track's ends.
    let firstLabel: String?
    let lastLabel: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let axis = theme.typography.pulseAxis

        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        let track = metrics.chartTrackHeight
                        let midY = size.height - metrics.chartDotDiameter
                        let base = CGRect(x: 0, y: midY - track / 2, width: size.width, height: track)
                        context.fill(Path(roundedRect: base, cornerRadius: track / 2), with: .color(colors.surfaceRecessed.color))
                        for span in spans {
                            let rect = CGRect(x: size.width * span.lowerBound, y: midY - track / 2,
                                              width: max(size.width * (span.upperBound - span.lowerBound), track), height: track)
                            context.fill(Path(roundedRect: rect, cornerRadius: track / 2),
                                         with: .color(colors.inkSecondary.color.opacity(0.7)))
                        }
                        let x = size.width * now
                        context.fill(Path(CGRect(x: x - 0.5, y: midY - metrics.chartDotDiameter * 1.6, width: 1,
                                                 height: metrics.chartDotDiameter * 2.2)),
                                     with: .color(colors.inkPrimary.color))
                        let dot = metrics.chartDotDiameter + 1
                        context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: midY - dot / 2, width: dot, height: dot)),
                                     with: .color(colors.inkPrimary.color))
                    }
                    Text("Now")
                        .somaFont(axis)
                        .foregroundStyle(colors.inkPrimary.color)
                        .fixedSize()
                        .position(x: min(max(width * now, 14), width - 14), y: 6)
                }
            }
            .frame(height: 34)

            HStack {
                Text(firstLabel ?? "")
                Spacer(minLength: 0)
                Text(lastLabel ?? "")
            }
            .somaFont(axis)
            .foregroundStyle(colors.inkSecondary.color)
        }
        .accessibilityHidden(true)
    }
}
