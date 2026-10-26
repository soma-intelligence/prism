//
//  SomaHeightRuler.swift
//  SomaUI
//

import SwiftUI

/// A tape measure set on end, read against one fixed line.
///
/// The tape carries a fine tick every centimetre (every inch on an imperial
/// tape), a longer one halfway, and a numbered one at each `tickEvery`. Drag
/// it up or down and it follows the finger; let go mid flick and it keeps
/// turning, slowing to rest on a step, with a selection tick under the thumb
/// at every unit it passes. No figure stands beside it: the tape and the
/// number above it say everything. With Reduce Motion on, a flick lands at
/// once.
public struct SomaHeightRuler: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let tickEvery: Double
    private let labels: [Double]
    private let label: String
    private let format: @Sendable (Double) -> String

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStart: Double?
    @State private var glide: Task<Void, Never>?

    /// - Parameters:
    ///   - value: centimetres.
    ///   - range: the tape's span, foot to top.
    ///   - step: where the tape comes to rest.
    ///   - tickEvery: the distance between two numbered ticks: ten
    ///     centimetres, or half a foot.
    ///   - labels: ticks numbered on top of those, the whole feet of an
    ///     imperial tape.
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

    /// Whether the tape counts in tens, so every numbered tick reads.
    private var isMetric: Bool {
        let tens = tickEvery / 10
        return tickEvery > 0 && abs(tens - tens.rounded()) < 0.001
    }

    /// One fine tick: a centimetre in tens, an inch in half feet.
    private var minor: Double { tickEvery / (isMetric ? 10 : 6) }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        GeometryReader { proxy in
            let size = proxy.size
            // The tape sits a little left of centre, so the ticks and their
            // numbers together balance on the page.
            let tapeX = (size.width - metrics.rulerWidth) / 2 + metrics.spaceL
            let mid = size.height / 2
            let indicator = metrics.rulerMajorTick + metrics.spaceL * 2

            ZStack(alignment: .topLeading) {
                tape(height: size.height)
                    .frame(width: metrics.rulerWidth, height: size.height)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: colors.inkPrimary.color, location: 0.22),
                                .init(color: colors.inkPrimary.color, location: 0.78),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .offset(x: tapeX)

                // The line the tape is read against.
                Capsule()
                    .fill(colors.accent.color)
                    .frame(width: indicator, height: metrics.inputIndicatorWidth)
                    .position(x: tapeX - metrics.spaceL + indicator / 2, y: mid)
            }
            .contentShape(.rect)
            .somaClaimsSwipe()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        glide?.cancel()
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        value = snapped(start + Double(drag.translation.height / metrics.rulerPointsPerUnit))
                    }
                    .onEnded { drag in
                        dragStart = nil
                        let speed = Double(drag.velocity.height / metrics.rulerPointsPerUnit)
                        glide = SomaGlide.start(from: value, speed: speed, reduceMotion: reduceMotion, metrics: metrics) { value = snapped($0) }
                    }
            )
        }
        .frame(height: metrics.rulerHeight)
        .sensoryFeedback(.selection, trigger: (value / max(minor, 0.001)).rounded())
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

    /// The tape: ticks running off its left edge, numbers beside the long
    /// ones, all in one hairline.
    private func tape(height: CGFloat) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let role = Self.tickRole(theme)
        let current = value

        return Canvas { context, size in
            let mid = size.height / 2
            let reach = Double(mid / metrics.rulerPointsPerUnit) + minor
            let first = Int(((max(range.lowerBound, current - reach)) / minor).rounded(.down))
            let last = Int(((min(range.upperBound, current + reach)) / minor).rounded(.up))
            guard first <= last else { return }
            for index in first...last {
                let mark = Double(index) * minor
                guard mark >= range.lowerBound - minor / 2, mark <= range.upperBound + minor / 2 else { continue }
                let y = mid - CGFloat(mark - current) * metrics.rulerPointsPerUnit
                let isMajor = Self.lands(mark, every: tickEvery)
                let isFoot = labels.contains { abs($0 - mark) < minor / 2 }
                let isNumbered = isMetric ? isMajor : isFoot
                let isMid = !isNumbered && (isMetric ? Self.lands(mark, every: tickEvery / 2) : isMajor)
                let length = isNumbered ? metrics.rulerMajorTick : (isMid ? metrics.rulerMidTick : metrics.rulerTick)
                let ink = isNumbered ? metrics.inputTickStrong : (isMid ? metrics.inputTickMedium : metrics.inputTickFaint)
                var tick = Path()
                tick.move(to: CGPoint(x: 0, y: y))
                tick.addLine(to: CGPoint(x: length, y: y))
                context.stroke(tick, with: .color(colors.inkPrimary.color.opacity(ink)), lineWidth: metrics.inputHairline)
                if isNumbered {
                    let text = Text(format(mark))
                        .font(role.font)
                        .tracking(role.tracking)
                        .foregroundColor(colors.inkSecondary.color)
                    context.draw(text, at: CGPoint(x: metrics.rulerMajorTick + metrics.spaceM, y: y), anchor: .leading)
                }
            }
        }
    }

    /// Whether a mark falls on a multiple of a length.
    static func lands(_ mark: Double, every length: Double) -> Bool {
        guard length > 0 else { return false }
        let share = mark / length
        return abs(share - share.rounded()) < 0.001
    }

    /// The role a label drawn into the canvas is set in: a Canvas takes a
    /// Text, so the role is applied by hand, font and tracking together.
    static func tickRole(_ theme: SomaTheme) -> SomaFontSpec { theme.typography.rowValue }

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        return (clamped / step).rounded() * step
    }
}

/// A standing figure in rounded blocks. No longer drawn by the height ruler;
/// kept public for callers that still draw it.
public struct SomaFigure: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let unit = h / 7.4
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.midX - unit * 0.62, y: rect.minY, width: unit * 1.24, height: unit * 1.24))
        let torsoTop = rect.minY + unit * 1.4
        path.addRoundedRect(in: CGRect(x: rect.midX - w * 0.3, y: torsoTop, width: w * 0.6, height: unit * 2.6),
                            cornerSize: CGSize(width: unit * 0.4, height: unit * 0.4))
        let armWidth = w * 0.1
        for x in [rect.minX, rect.maxX - armWidth] {
            path.addRoundedRect(in: CGRect(x: x, y: torsoTop + unit * 0.1, width: armWidth, height: unit * 2.9),
                                cornerSize: CGSize(width: armWidth / 2, height: armWidth / 2))
        }
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
            SomaHeightRuler(value: $centimetres, range: 0...220, label: "Height")
        }
        .padding()
    }
}
