//
//  SomaMacroRing.swift
//  SomaUI
//

import SwiftUI

/// One part of a ``SomaMacroRing``.
public struct SomaMacroPart: Identifiable, Sendable {
    public var id: String { title }
    public var title: String
    public var detail: String
    /// The part's energy, which sets its share of the ring.
    public var weight: Double

    public init(title: String, detail: String, weight: Double) {
        self.title = title
        self.detail = detail
        self.weight = weight
    }
}

/// A meal as a ring in proportion: each part's arc is its share of the
/// energy, and its name and grams sit just outside it.
public struct SomaMacroRing<Center: View>: View {
    private let parts: [SomaMacroPart]
    private let aspect: SomaAspect
    private let center: Center

    @Environment(\.somaTheme) private var theme

    public init(parts: [SomaMacroPart], aspect: SomaAspect = .gut, @ViewBuilder center: () -> Center) {
        self.parts = parts
        self.aspect = aspect
        self.center = center()
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color
        let total = parts.reduce(0) { $0 + max(0, $1.weight) }
        let gap = metrics.dialSegmentGap

        GeometryReader { proxy in
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = metrics.macroRingDiameter / 2
            let spans = Self.spans(parts.map { max(0, $0.weight) }, total: total)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [hue.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: radius))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(middle)

                if total <= 0 {
                    Circle()
                        .stroke(colors.surface.color, lineWidth: metrics.macroRingWidth)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(middle)
                } else {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        let span = spans[index]
                        if span.to - span.from > gap {
                            arc(middle, radius, span.from + gap / 2, span.to - gap / 2)
                                .stroke(hue.opacity(1 - 0.22 * Double(index)), style: StrokeStyle(lineWidth: metrics.macroRingWidth))
                        }
                        VStack(spacing: metrics.scoreLabelSpacing) {
                            Text(part.title)
                                .somaFont(theme.typography.callout)
                                .foregroundStyle(colors.inkPrimary.color)
                            Text(part.detail)
                                .somaFont(theme.typography.captionValue)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        .fixedSize()
                        .position(point(middle, radius + metrics.macroRingWidth + metrics.macroLabelReach, (span.from + span.to) / 2))
                    }
                }

                center.position(middle)
            }
        }
        .frame(height: metrics.macroRingDiameter + (metrics.macroRingWidth + metrics.macroLabelReach) * 2 + metrics.cardSpacing * 2)
        .accessibilityElement(children: .combine)
    }

    /// Where each part starts and ends, in degrees clockwise from twelve.
    static func spans(_ weights: [Double], total: Double) -> [(from: Double, to: Double)] {
        var start = 0.0
        return weights.map { weight in
            let degrees = total > 0 ? weight / total * 360 : 0
            defer { start += degrees }
            return (start, start + degrees)
        }
    }

    private func point(_ middle: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: middle.x + radius * CGFloat(sin(radians)), y: middle.y - radius * CGFloat(cos(radians)))
    }

    private func arc(_ middle: CGPoint, _ radius: CGFloat, _ from: Double, _ to: Double) -> Path {
        Path { path in
            let steps = max(2, Int((to - from) / 3))
            for index in 0...steps {
                let p = point(middle, radius, from + (to - from) * Double(index) / Double(steps))
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }
}

#Preview("Macro ring") {
    ZStack {
        SomaPreviewBackdrop()
        SomaMacroRing(parts: [
            .init(title: "Protein", detail: "38 g", weight: 152),
            .init(title: "Carbs", detail: "62 g", weight: 248),
            .init(title: "Fat", detail: "22 g", weight: 198),
        ]) {
            SomaReadout("598", caption: "kcal")
        }
    }
}
