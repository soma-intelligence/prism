//
//  SomaScaleDial.swift
//  SomaUI
//

import SwiftUI

/// A precision scale's dial seen from above: an arc of hair ticks that turns
/// under one fixed line. Drag sideways to turn it, or flick it and it keeps
/// turning, slowing to rest on a step; the value is whatever sits under the
/// line, with a selection tick at every step it passes.
///
/// One step of the value is one tick, `scaleDragPerStep` points apart on the
/// arc, so the finger and the ticks move together. With Reduce Motion on, a
/// flick lands at once.
public struct SomaScaleDial: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let majorEvery: Int
    private let label: String
    private let format: @Sendable (Double) -> String

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStart: Double?
    @State private var glide: Task<Void, Never>?

    /// - Parameters:
    ///   - value: the reading under the line.
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
        let role = Self.tickRole(theme)

        GeometryReader { proxy in
            let width = proxy.size.width
            let radius = width * 1.1
            let top = metrics.scaleNeedleHeight * 0.55
            let centre = CGPoint(x: width / 2, y: top + radius)
            let perStep = Double(metrics.scaleDragPerStep / radius)
            let window = Double.pi / 3.2

            ZStack {
                Canvas { context, _ in
                    let visible = Int(window / perStep)
                    let current = (value / step).rounded()
                    for offset in -visible...visible {
                        let index = current + Double(offset)
                        let tickValue = index * step
                        guard tickValue >= range.lowerBound - step / 2, tickValue <= range.upperBound + step / 2 else { continue }
                        let angle = (tickValue - value) / step * perStep
                        // The arc turns away at its ends: ticks fade out as
                        // they leave the reading, never cut off.
                        let fade = pow(max(0, 1 - abs(angle) / window), 1.4)
                        let whole = Int(index.rounded())
                        let isMajor = whole % majorEvery == 0
                        let isHalf = majorEvery.isMultiple(of: 2) && whole % (majorEvery / 2) == 0
                        let length = isMajor ? metrics.scaleMajorTick : (isHalf ? (metrics.scaleMajorTick + metrics.scaleMinorTick) / 2 : metrics.scaleMinorTick)
                        let ink = isMajor ? metrics.inputTickStrong : (isHalf ? metrics.inputTickMedium : metrics.inputTickFaint)
                        var tick = Path()
                        tick.move(to: point(centre, radius, angle))
                        tick.addLine(to: point(centre, radius - length, angle))
                        context.stroke(tick, with: .color(colors.inkPrimary.color.opacity(ink * fade)), lineWidth: metrics.inputHairline)
                        if isMajor {
                            let text = Text(format(tickValue))
                                .font(role.font)
                                .tracking(role.tracking)
                                .foregroundColor(colors.inkSecondary.color.opacity(fade))
                            context.draw(text, at: point(centre, radius - metrics.scaleMajorTick - metrics.spaceL, angle))
                        }
                    }
                }

                // The fixed line: from just above the arc down through the
                // longest ticks, in the accent, with nothing on its head.
                let rise = metrics.spaceS
                let needle = rise + metrics.scaleMajorTick + metrics.spaceXS
                Capsule()
                    .fill(colors.accent.color)
                    .frame(width: metrics.inputIndicatorWidth, height: needle)
                    .position(x: width / 2, y: top - rise + needle / 2)
            }
            .contentShape(.rect)
            .somaClaimsSwipe()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        glide?.cancel()
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        value = snapped(start - Double(drag.translation.width / metrics.scaleDragPerStep) * step)
                    }
                    .onEnded { drag in
                        dragStart = nil
                        let speed = -Double(drag.velocity.width / metrics.scaleDragPerStep) * step
                        glide = SomaGlide.start(from: value, speed: speed, reduceMotion: reduceMotion, metrics: metrics) { value = snapped($0) }
                    }
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

/// The coast after a flick, shared by the tape and the scale: the value runs
/// on at the speed the finger left it and slows to rest, frame by frame, so
/// every step it passes is a real change of value with its own tick.
@MainActor
enum SomaGlide {
    /// Starts a coast and hands back its task, to cancel when a finger lands
    /// again. Under Reduce Motion, or for a slow release, nothing moves.
    ///
    /// - Parameters:
    ///   - from: where the value is when the finger lifts.
    ///   - speed: units a second at that moment.
    ///   - set: called with each frame's value, which the caller snaps.
    static func start(
        from: Double,
        speed: Double,
        reduceMotion: Bool,
        metrics: SomaMetrics,
        set: @escaping @MainActor (Double) -> Void
    ) -> Task<Void, Never>? {
        guard !reduceMotion, speed.isFinite, abs(speed) > 0.5 else { return nil }
        let duration = metrics.inputGlideDuration
        // An exponential coast, all but settled by the end of `duration`;
        // `inputGlideReach` scales how far a flick of a given speed carries.
        let constant = duration / 4
        let travel = speed * duration * metrics.inputGlideReach / 3
        return Task { @MainActor in
            let clock = ContinuousClock()
            let began = clock.now
            while !Task.isCancelled {
                let elapsed = began.duration(to: clock.now)
                let t = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let share = 1 - exp(-t / constant)
                set(from + travel * share)
                if t >= duration { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
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
