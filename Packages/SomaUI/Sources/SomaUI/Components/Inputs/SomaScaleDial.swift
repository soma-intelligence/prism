//
//  SomaScaleDial.swift
//  SomaUI
//

import SwiftUI

/// A bathroom scale's dial seen from above: an arc of ticks that turns under a
/// fixed needle. Drag sideways to turn it; the value is whatever sits under
/// the needle.
///
/// One step of the value is one tick, `scaleDragPerStep` points apart on the
/// arc, so the finger and the ticks move together.
public struct SomaScaleDial: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let majorEvery: Int
    private let label: String
    private let format: @Sendable (Double) -> String

    @Environment(\.somaTheme) private var theme
    @State private var dragStart: Double?

    /// - Parameters:
    ///   - value: the reading under the needle.
    ///   - range: how far the dial turns.
    ///   - step: one tick.
    ///   - majorEvery: ticks between two labelled ones.
    ///   - label: what VoiceOver calls it.
    ///   - format: how a labelled tick reads.
    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        majorEvery: Int = 10,
        label: String,
        format: @escaping @Sendable (Double) -> String = { "\(Int($0.rounded()))" }
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.majorEvery = max(1, majorEvery)
        self.label = label
        self.format = format
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        GeometryReader { proxy in
            let width = proxy.size.width
            let radius = width * 1.1
            let top = metrics.scaleNeedleHeight * 0.55
            let centre = CGPoint(x: width / 2, y: top + radius)
            let perStep = Double(metrics.scaleDragPerStep / radius)

            ZStack {
                Canvas { context, _ in
                    let visible = Int((Double.pi / 3) / perStep)
                    let current = (value / step).rounded()
                    for offset in -visible...visible {
                        let index = current + Double(offset)
                        let tickValue = index * step
                        guard tickValue >= range.lowerBound - step / 2, tickValue <= range.upperBound + step / 2 else { continue }
                        let angle = (tickValue - value) / step * perStep
                        let fade = max(0, 1 - abs(angle) / (Double.pi / 3))
                        let whole = Int(index.rounded())
                        let isMajor = whole % majorEvery == 0
                        let isHalf = majorEvery.isMultiple(of: 2) && whole % (majorEvery / 2) == 0
                        let length = isMajor ? metrics.scaleMajorTick : (isHalf ? metrics.scaleMinorTick * 1.5 : metrics.scaleMinorTick)
                        let outer = point(centre, radius, angle)
                        let inner = point(centre, radius - length, angle)
                        var tick = Path()
                        tick.move(to: outer)
                        tick.addLine(to: inner)
                        context.stroke(
                            tick,
                            with: .color(colors.inkPrimary.color.opacity((isMajor ? 0.9 : 0.45) * fade)),
                            lineWidth: isMajor ? 1.5 : 1
                        )
                        if isMajor {
                            let text = Text(format(tickValue))
                                .font(Self.tickRole(theme).font)
                                .tracking(Self.tickRole(theme).tracking)
                                .foregroundColor(colors.inkSecondary.color.opacity(fade))
                            context.draw(text, at: point(centre, radius - length - metrics.cardSpacing * 1.5, angle))
                        }
                    }
                    var rim = Path()
                    rim.addArc(center: centre, radius: radius, startAngle: .radians(-Double.pi / 2 - Double.pi / 3),
                               endAngle: .radians(-Double.pi / 2 + Double.pi / 3), clockwise: false)
                    context.stroke(rim, with: .color(colors.inkPrimary.color.opacity(metrics.browseSeparatorOpacity)), lineWidth: 1)
                }

                // The needle: a line from above the arc down through the
                // ticks, stopping short of the numbers, and its pin.
                let rise = metrics.scaleNeedleHeight * 0.45
                let needle = rise + metrics.scaleMajorTick
                Capsule()
                    .fill(colors.accent.color)
                    .frame(width: metrics.knobRingWidth * 1.5, height: needle)
                    .position(x: width / 2, y: top - rise + needle / 2)
                Circle()
                    .fill(colors.accent.color)
                    .frame(width: metrics.aspectDotSize * 1.6, height: metrics.aspectDotSize * 1.6)
                    .position(x: width / 2, y: top - rise)
            }
            .contentShape(.rect)
            .somaClaimsSwipe()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        value = snapped(start - Double(drag.translation.width / metrics.scaleDragPerStep) * step)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: metrics.scaleDialHeight)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(format(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = snapped(value + step)
            case .decrement: value = snapped(value - step)
            @unknown default: break
            }
        }
    }

    private func point(_ centre: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: centre.x + radius * CGFloat(sin(angle)), y: centre.y - radius * CGFloat(cos(angle)))
    }

    /// The role a label drawn into the canvas is set in: a Canvas takes a
    /// Text, so the role is applied by hand, font and tracking together.
    static func tickRole(_ theme: SomaTheme) -> SomaFontSpec { theme.typography.captionValue }

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return ((clamped / step).rounded() * step * 1000).rounded() / 1000
    }
}

#Preview("Scale dial") {
    @Previewable @State var kilograms = 68.4
    ZStack {
        SomaPreviewBackdrop()
        VStack {
            SomaReadout(String(format: "%.1f", kilograms), unit: "kg")
            SomaScaleDial(value: $kilograms, range: 20...250, step: 0.1, label: "Weight")
        }
    }
}
