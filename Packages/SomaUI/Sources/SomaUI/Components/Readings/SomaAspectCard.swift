//
//  SomaAspectCard.swift
//  SomaUI
//

import SwiftUI

/// One card per aspect: its identity dot and name, the value that sums it up,
/// one line saying what the value means, and a small chart at the end.
public struct SomaAspectCard<Chart: View>: View {
    private let aspect: SomaAspect
    private let value: String?
    private let unit: String?
    private let summary: String?
    private let chart: Chart

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - value: the number as it should read, or nil for a dash.
    ///   - unit: what it counts, set small beside it.
    ///   - summary: what the value means, in one sentence.
    ///   - chart: the small chart at the trailing edge.
    public init(
        aspect: SomaAspect,
        value: String?,
        unit: String?,
        summary: String?,
        @ViewBuilder chart: () -> Chart
    ) {
        self.aspect = aspect
        self.value = value
        self.unit = unit
        self.summary = summary
        self.chart = chart()
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color

        SomaCard {
            HStack(alignment: .center, spacing: metrics.cardSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: metrics.identityDotSpacing) {
                        Circle()
                            .fill(hue)
                            .frame(width: metrics.identityDotDiameter, height: metrics.identityDotDiameter)
                        Text(aspect.title)
                            .somaFont(type.eyebrow)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.inkSecondary.color)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(value ?? "-")
                            .somaFont(type.metricCompact)
                            .foregroundStyle(colors.inkPrimary.color)
                        if let unit {
                            Text(unit)
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                    }
                    .lineLimit(1)

                    if let summary {
                        Text(summary)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                chart
                    .frame(width: metrics.aspectChartWidth, height: metrics.aspectChartHeight)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A run of nights as thin bars, the last one full and the others faded:
/// last night against the week before it.
///
/// A night with no value leaves a gap on the baseline rather than a bar of
/// nothing.
public struct SomaNightBars: View {
    private let aspect: SomaAspect
    private let values: [Double?]

    @Environment(\.somaTheme) private var theme

    public init(aspect: SomaAspect, values: [Double?]) {
        self.aspect = aspect
        self.values = values
    }

    public var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let pen = SomaPen(theme)
        let values = values
        let highest = values.compactMap { $0 }.max() ?? 0

        Canvas { context, size in
            let floor = size.height - 0.5
            pen.gridline(context, y: floor, to: size.width)
            guard highest > 0 else { return }
            let pitch = size.width / CGFloat(max(values.count, 1))
            for (index, value) in values.enumerated() {
                guard let value, value > 0 else { continue }
                let top = floor - (floor - pen.ring / 2) * CGFloat(value / highest)
                let isLast = index == values.count - 1
                pen.bar(context, x: pitch * (CGFloat(index) + 0.5), top: top, floor: floor, pitch: pitch,
                        color: hue.opacity(isLast ? 1 : pen.contextOpacity))
            }
        }
    }
}

/// A line of daily values over the band that is usual for them, with a ring
/// on the last value: where today sits against the normal range.
public struct SomaBandLine: View {
    private let aspect: SomaAspect
    private let values: [Double?]
    private let band: ClosedRange<Double>?

    @Environment(\.somaTheme) private var theme

    public init(aspect: SomaAspect, values: [Double?], band: ClosedRange<Double>?) {
        self.aspect = aspect
        self.values = values
        self.band = band
    }

    public var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let pen = SomaPen(theme)
        let inset = theme.metrics.chartRingDiameter / 2 + 1
        let values = values
        let band = band

        Canvas { context, size in
            let known = values.compactMap { $0 }
            guard let first = known.min(), let top = known.max() else { return }
            let low = min(first, band?.lowerBound ?? first)
            let high = max(top, band?.upperBound ?? top)
            let spread = max(high - low, 1)
            let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * CGFloat((value - low) / spread) }

            if let band {
                pen.band(context, top: y(band.upperBound), bottom: y(band.lowerBound),
                         in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            // A missing day breaks the line instead of bridging it.
            let points: [CGPoint?] = values.enumerated().map { index, value in
                value.map {
                    CGPoint(x: values.count < 2 ? plot.midX : plot.minX + plot.width * CGFloat(index) / CGFloat(values.count - 1),
                            y: y($0))
                }
            }
            pen.line(context, points, color: hue)
            if let last = points.compactMap({ $0 }).last {
                pen.ring(context, at: last, color: hue)
            }
        }
    }
}

/// A value on a track between two ends: an estimate with the span it may be
/// off by, and a reference tick to read it against, such as your age under a
/// fitness age.
public struct SomaRangeTrack: View {
    private let aspect: SomaAspect
    private let range: ClosedRange<Double>
    private let estimate: Double?
    private let spread: Double?
    private let reference: Double?
    private let estimateLabel: String?
    private let referenceLabel: String?

    @Environment(\.somaTheme) private var theme

    public init(
        aspect: SomaAspect,
        range: ClosedRange<Double>,
        estimate: Double?,
        spread: Double? = nil,
        reference: Double? = nil,
        estimateLabel: String? = nil,
        referenceLabel: String? = nil
    ) {
        self.aspect = aspect
        self.range = range
        self.estimate = estimate
        self.spread = spread
        self.reference = reference
        self.estimateLabel = estimateLabel
        self.referenceLabel = referenceLabel
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let midY = geometry.size.height / 2
            let hue = theme.aspects[aspect].identity.color
            let track = theme.metrics.chartTrackHeight

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(theme.colors.surfaceRecessed.color)
                    .frame(width: width, height: track)
                    .offset(y: midY - track / 2)

                if let estimate, let spread {
                    let from = position(estimate - spread, in: width)
                    let to = position(estimate + spread, in: width)
                    Capsule()
                        .fill(hue.opacity(theme.metrics.chartSpreadOpacity))
                        .frame(width: max(to - from, track), height: track)
                        .offset(x: from, y: midY - track / 2)
                }

                if let reference {
                    let x = position(reference, in: width)
                    Rectangle()
                        .fill(theme.colors.inkSecondary.color)
                        .frame(width: theme.metrics.chartMarkerWidth, height: theme.metrics.chartMarkerHeight)
                        .offset(x: x - theme.metrics.chartMarkerWidth / 2, y: midY - theme.metrics.chartMarkerHeight / 2)
                    if let referenceLabel {
                        label(referenceLabel, colour: theme.colors.inkSecondary.color)
                            .position(x: x, y: midY + theme.metrics.chartMarkerHeight / 2 + 7)
                    }
                }

                if let estimate {
                    let x = position(estimate, in: width)
                    let dot = theme.metrics.chartEstimateDiameter
                    Circle()
                        .fill(hue)
                        .frame(width: dot, height: dot)
                        .background(Circle().fill(theme.colors.surface.color).padding(-2))
                        .offset(x: x - dot / 2, y: midY - dot / 2)
                    if let estimateLabel {
                        label(estimateLabel, colour: theme.colors.inkPrimary.color)
                            .position(x: x, y: midY - theme.metrics.chartMarkerHeight / 2 - 7)
                    }
                }
            }
        }
    }

    private func position(_ value: Double, in width: CGFloat) -> CGFloat {
        let share = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
            / max(range.upperBound - range.lowerBound, 1)
        return width * CGFloat(share)
    }

    private func label(_ text: String, colour: Color) -> some View {
        Text(text)
            .somaFont(theme.typography.captionValue)
            .foregroundStyle(colour)
            .fixedSize()
    }
}

#Preview("Aspect cards") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 12) {
            SomaAspectCard(aspect: .sleep, value: "7:12", unit: "asleep",
                           summary: "Your longest night this week, 68 min deep.") {
                SomaNightBars(aspect: .sleep, values: [6.7, 6.9, 5.8, 7.4, 5.8, 7.7, 7.2])
            }
            SomaAspectCard(aspect: .heart, value: "54", unit: "bpm resting",
                           summary: "4 below your usual, lowest at 03:40.") {
                SomaBandLine(aspect: .heart, values: [58, 57, nil, 59, 56, 57, 55, 54], band: 55...60)
            }
            SomaAspectCard(aspect: .body, value: nil, unit: "fitness age",
                           summary: "No fitness age yet. It comes from a Soma visit. You are 46.") {
                SomaRangeTrack(aspect: .body, range: 20...80, estimate: nil, reference: 46, referenceLabel: "46")
            }
        }
        .padding()
    }
}
