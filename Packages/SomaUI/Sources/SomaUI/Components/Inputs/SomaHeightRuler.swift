//
//  SomaHeightRuler.swift
//  SomaUI
//

import SwiftUI

/// A figure standing against a ruler. Drag up or down and the figure grows or
/// shrinks to the height under the knob.
public struct SomaHeightRuler: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let tickEvery: Double
    private let labels: [Double]
    private let label: String
    private let format: @Sendable (Double) -> String

    @Environment(\.somaTheme) private var theme
    @State private var dragStart: Double?

    /// - Parameters:
    ///   - value: centimetres.
    ///   - range: the ruler's span, foot to top.
    ///   - step: one detent of the drag.
    ///   - tickEvery: the distance between two ticks.
    ///   - labels: where the ruler is numbered.
    ///   - label: what VoiceOver calls it.
    ///   - format: how a numbered tick reads, and the value to VoiceOver.
    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...200,
        step: Double = 0.5,
        tickEvery: Double = 10,
        labels: [Double] = [50, 100, 150, 200],
        label: String,
        format: @escaping @Sendable (Double) -> String = { "\(Int($0.rounded()))" }
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.tickEvery = tickEvery
        self.labels = labels
        self.label = label
        self.format = format
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.body].identity.color

        GeometryReader { proxy in
            let size = proxy.size
            let foot = size.height - metrics.cardSpacing
            let span = foot - metrics.cardSpacing * 2
            let rulerX = size.width * 0.78
            let y = { (v: Double) -> CGFloat in foot - CGFloat((v - range.lowerBound) / (range.upperBound - range.lowerBound)) * span }
            let height = foot - y(value)
            let figureX = size.width * 0.34

            ZStack(alignment: .topLeading) {
                // The ground.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: foot))
                    path.addLine(to: CGPoint(x: size.width, y: foot))
                }
                .stroke(colors.inkPrimary.color.opacity(metrics.browseSeparatorOpacity), lineWidth: 1)

                // The ruler.
                Canvas { context, _ in
                    var tick = range.lowerBound
                    while tick <= range.upperBound + 0.001 {
                        let isLabelled = labels.contains { abs($0 - tick) < 0.001 }
                        let length = isLabelled ? metrics.rulerMajorTick : metrics.rulerTick
                        var path = Path()
                        path.move(to: CGPoint(x: rulerX - length / 2, y: y(tick)))
                        path.addLine(to: CGPoint(x: rulerX + length / 2, y: y(tick)))
                        context.stroke(path, with: .color(colors.inkSecondary.color.opacity(isLabelled ? 0.9 : 0.5)), lineWidth: 1)
                        tick += tickEvery
                    }
                    var spine = Path()
                    spine.move(to: CGPoint(x: rulerX, y: y(range.upperBound)))
                    spine.addLine(to: CGPoint(x: rulerX, y: foot))
                    context.stroke(spine, with: .color(colors.inkSecondary.color.opacity(0.5)), lineWidth: 1)
                    for mark in labels {
                        let text = Text(format(mark))
                            .font(Self.tickRole(theme).font)
                                .tracking(Self.tickRole(theme).tracking)
                            .foregroundColor(colors.inkSecondary.color)
                        context.draw(text, at: CGPoint(x: rulerX + metrics.rulerMajorTick + metrics.cardSpacing, y: y(mark)), anchor: .leading)
                    }
                }

                SomaFigure()
                    .fill(hue.opacity(0.5))
                    .frame(width: max(1, height * 0.42), height: max(1, height))
                    .position(x: figureX, y: foot - height / 2)

                Path { path in
                    path.move(to: CGPoint(x: figureX, y: y(value)))
                    path.addLine(to: CGPoint(x: rulerX, y: y(value)))
                }
                .stroke(colors.inkSecondary.color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                SomaKnob()
                    .position(x: rulerX, y: y(value))
            }
            .contentShape(.rect)
            .somaClaimsSwipe()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        let perPoint = (range.upperBound - range.lowerBound) / Double(max(span, 1))
                        value = snapped(start - Double(drag.translation.height) * perPoint)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: metrics.rulerHeight)
        .sensoryFeedback(.selection, trigger: (value / max(step, 0.001)).rounded())
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

    /// The role a label drawn into the canvas is set in: a Canvas takes a
    /// Text, so the role is applied by hand, font and tracking together.
    static func tickRole(_ theme: SomaTheme) -> SomaFontSpec { theme.typography.captionValue }

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return (clamped / step).rounded() * step
    }
}

/// A person standing, drawn in rounded blocks: head, body, arms and legs.
public struct SomaFigure: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let unit = h / 7.4
        var path = Path()
        // Head.
        path.addEllipse(in: CGRect(x: rect.midX - unit * 0.62, y: rect.minY, width: unit * 1.24, height: unit * 1.24))
        // Body.
        let torsoTop = rect.minY + unit * 1.4
        path.addRoundedRect(in: CGRect(x: rect.midX - w * 0.3, y: torsoTop, width: w * 0.6, height: unit * 2.6),
                            cornerSize: CGSize(width: unit * 0.4, height: unit * 0.4))
        // Arms.
        let armWidth = w * 0.1
        for x in [rect.minX, rect.maxX - armWidth] {
            path.addRoundedRect(in: CGRect(x: x, y: torsoTop + unit * 0.1, width: armWidth, height: unit * 2.9),
                                cornerSize: CGSize(width: armWidth / 2, height: armWidth / 2))
        }
        // Legs.
        let legTop = torsoTop + unit * 2.72
        let legWidth = w * 0.27
        for x in [rect.midX - w * 0.015 - legWidth, rect.midX + w * 0.015] {
            path.addRoundedRect(in: CGRect(x: x, y: legTop, width: legWidth, height: rect.maxY - legTop),
                                cornerSize: CGSize(width: legWidth / 2, height: legWidth / 2))
        }
        return path
    }
}

#Preview("Height ruler") {
    @Previewable @State var centimetres = 172.0
    ZStack {
        SomaPreviewBackdrop()
        VStack {
            SomaReadout(String(format: "%.1f", centimetres), unit: "cm")
            SomaHeightRuler(value: $centimetres, label: "Height")
        }
        .padding()
    }
}
