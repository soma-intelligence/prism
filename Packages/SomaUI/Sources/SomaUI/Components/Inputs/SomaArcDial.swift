//
//  SomaArcDial.swift
//  SomaUI
//

import SwiftUI

/// A value set by turning a dial: minutes in a cold plunge, grams in a scoop.
///
/// Both styles draw one thin continuous track, filled in the aspect's hue,
/// inside a bezel of fine ticks the way a watch's is cut. The ring style is a
/// full circle with a longer tick at each segment, for a count of something.
/// The gauge style is three quarters of a circle with numbered ticks, for an
/// amount. No glow and no cut segments: those read as generated (owner,
/// 2026-10-24). Drag the knob, or anywhere on the dial, round to the value.
public struct SomaArcDial<Center: View>: View {
    public enum Style: Sendable {
        /// A full ring in this many segments.
        case ring(segments: Int)
        /// A three quarter gauge, ticked every `tick` and numbered every
        /// `label`.
        case gauge(tick: Double, label: Double)
    }

    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let style: Style
    private let aspect: SomaAspect
    private let label: String
    private let center: Center

    @Environment(\.somaTheme) private var theme

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        style: Style,
        aspect: SomaAspect = .mind,
        label: String,
        @ViewBuilder center: () -> Center
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.style = style
        self.aspect = aspect
        self.label = label
        self.center = center()
    }

    private var sweep: Double {
        switch style {
        case .ring: 360
        case .gauge: theme.metrics.dialGaugeSweep
        }
    }

    /// Degrees clockwise from twelve where the dial starts.
    private var origin: Double { -sweep / 2 == -180 ? 0 : -sweep / 2 }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (value - range.lowerBound) / span : 0
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color

        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side / 2 - metrics.bezelGap - metrics.bezelMajorTick - metrics.spaceXL * 1.4
            let track = metrics.dialTrackWidth

            ZStack {
                let bezel = radius + track / 2 + metrics.bezelGap
                let tickInk = colors.inkPrimary.color

                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .rotation(.degrees(origin - 90))
                    .stroke(tickInk.opacity(metrics.hairlineOpacity), style: StrokeStyle(lineWidth: track, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(middle)
                if fraction > 0 {
                    arc(middle, radius, origin, origin + sweep * fraction)
                        .stroke(hue, style: StrokeStyle(lineWidth: track, lineCap: .round))
                }

                switch style {
                case .ring(let segments):
                    let count = max(1, segments)
                    let fine = count * max(1, 60 / count)
                    Canvas { context, _ in
                        for index in 0..<fine {
                            let degrees = Double(index) * 360 / Double(fine)
                            let isMajor = index % max(1, fine / count) == 0
                            var path = Path()
                            path.move(to: point(middle, bezel, degrees))
                            path.addLine(to: point(middle, bezel + (isMajor ? metrics.bezelMajorTick : metrics.bezelTick), degrees))
                            context.stroke(path, with: .color(tickInk.opacity(isMajor ? metrics.inputTickMedium : metrics.inputTickFaint)),
                                           lineWidth: metrics.inputHairline)
                        }
                    }
                case .gauge(let tick, let labelEvery):
                    let role = Self.tickRole(theme)
                    Canvas { context, _ in
                        guard tick > 0 else { return }
                        // A fine tick between every two numbered ones as well.
                        let fine = tick / 2
                        var mark = range.lowerBound
                        while mark <= range.upperBound + fine / 1000 {
                            let degrees = angle(of: mark)
                            let isTick = abs((mark / tick).rounded() * tick - mark) < fine / 1000
                            let isLabelled = isTick && labelEvery > 0 && abs((mark / labelEvery).rounded() * labelEvery - mark) < tick / 1000
                            let length = isLabelled ? metrics.bezelMajorTick : (isTick ? metrics.bezelTick : metrics.bezelTick * 0.6)
                            let ink = isLabelled ? metrics.inputTickStrong : (isTick ? metrics.inputTickMedium : metrics.inputTickFaint)
                            var path = Path()
                            path.move(to: point(middle, bezel, degrees))
                            path.addLine(to: point(middle, bezel + length, degrees))
                            context.stroke(path, with: .color(tickInk.opacity(ink)), lineWidth: metrics.inputHairline)
                            if isLabelled {
                                let text = Text(Self.number(mark))
                                    .font(role.font)
                                    .tracking(role.tracking)
                                    .foregroundColor(colors.inkSecondary.color)
                                context.draw(text, at: point(middle, bezel + metrics.bezelMajorTick + metrics.spaceL, degrees))
                            }
                            mark += fine
                        }
                    }
                }

                SomaKnob()
                    .position(point(middle, radius, angle(of: value)))

                center.position(middle)
            }
            .contentShape(.rect)
            .somaClaimsSwipe()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in set(from: drag.location, around: middle) }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: metrics.dialDiameter + metrics.cardSpacing * 5)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(Self.number(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = snapped(value + step)
            case .decrement: value = snapped(value - step)
            @unknown default: break
            }
        }
    }

    /// The angle, clockwise from twelve, a value sits at.
    private func angle(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        let share = span > 0 ? (value - range.lowerBound) / span : 0
        return origin + sweep * min(max(share, 0), 1)
    }

    private func set(from location: CGPoint, around middle: CGPoint) {
        var degrees = atan2(Double(location.x - middle.x), Double(middle.y - location.y)) * 180 / .pi
        degrees -= origin
        while degrees < 0 { degrees += 360 }
        while degrees >= 360 { degrees -= 360 }
        var share = degrees / sweep
        if share > 1 {
            // Past the end of a gauge: stick to whichever end is nearer.
            share = degrees - sweep < (360 - degrees) ? 1 : 0
        }
        // A full ring does not jump from its top straight to the other end.
        if sweep == 360, abs(share - fraction) > 0.5 { return }
        value = snapped(range.lowerBound + share * (range.upperBound - range.lowerBound))
    }

    /// The role a label drawn into the canvas is set in: a Canvas takes a
    /// Text, so the role is applied by hand, font and tracking together.
    static func tickRole(_ theme: SomaTheme) -> SomaFontSpec { theme.typography.captionValue }

    private func snapped(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return step > 0 ? (clamped / step).rounded() * step : clamped
    }

    private func point(_ middle: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: middle.x + radius * CGFloat(sin(radians)), y: middle.y - radius * CGFloat(cos(radians)))
    }

    private func arc(_ middle: CGPoint, _ radius: CGFloat, _ from: Double, _ to: Double) -> Path {
        Path { path in
            let steps = max(2, Int(abs(to - from) / 3))
            for index in 0...steps {
                let p = point(middle, radius, from + (to - from) * Double(index) / Double(steps))
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }

    public static func number(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

#Preview("Arc dial") {
    @Previewable @State var minutes = 3.0
    @Previewable @State var grams = 10.0
    ZStack {
        SomaPreviewBackdrop()
        VStack {
            SomaArcDial(value: $minutes, range: 0...10, step: 0.5, style: .ring(segments: 10), label: "Minutes") {
                SomaReadout(SomaArcDial<EmptyView>.number(minutes), unit: "min")
            }
            SomaArcDial(value: $grams, range: 0...20, step: 0.5, style: .gauge(tick: 1, label: 5), label: "Grams") {
                SomaReadout(SomaArcDial<EmptyView>.number(grams), unit: "g")
            }
        }
    }
}
