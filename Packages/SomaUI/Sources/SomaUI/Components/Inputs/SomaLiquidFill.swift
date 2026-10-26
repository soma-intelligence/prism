//
//  SomaLiquidFill.swift
//  SomaUI
//

import SwiftUI

/// A whole page as the drink: liquid rises from the foot of the screen to the
/// amount poured, its surface a slow, soft swell. No glass, no outline: the
/// page is the container, and the level is the value. Drawn behind a page's
/// content; the page drives it with ``SomaLiquidPour``.
///
/// The owner found every drawn glass ugly (2026-10-24); a level that fills
/// the room reads as the drink itself.
public struct SomaLiquidFill: View {
    private let fill: Double
    private let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False once the page is covered or scrolled away: a full page of
    /// material masked by a moving wave is the most expensive frame in the
    /// app, and nobody is looking at it.
    @State private var isOnScreen = true
    private var power = SomaPowerState.shared

    /// The level on screen, which springs towards `fill`.
    @State private var shown: Double

    /// - Parameter fill: 0 to 1, the share of the page the liquid reaches.
    public init(fill: Double, aspect: SomaAspect = .mind) {
        self.fill = fill
        self.aspect = aspect
        _shown = State(initialValue: Self.clamp(fill))
    }

    private static func clamp(_ fill: Double) -> Double {
        min(max(fill.isFinite ? fill : 0, 0), 1)
    }

    public var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let dark = colorScheme == .dark
        let target = Self.clamp(fill)
        // Clear water, the way visionOS draws its glass: a frosted body that
        // lets the room through, a breath of the drink's colour, light
        // gathered under the surface and a bright edge on it. The flat
        // saturated teal it replaced read as paint (owner, 2026-10-24).
        let tint = hue.mix(with: .white, by: dark ? 0.55 : 0.7)

        // The swell holds still in Low Power Mode and off screen, the way it
        // holds still with Reduce Motion.
        SomaAnimatedLevel(level: shown) { level in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || power.isLowPower || !isOnScreen)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                GeometryReader { proxy in
                    let size = proxy.size
                    let surface = size.height * (1 - CGFloat(level))
                    ZStack {
                        // The frosted body: the system material, cut to the water.
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask {
                                Canvas { mask, maskSize in
                                    mask.fill(Self.wave(size: maskSize, surface: surface, amplitude: 5,
                                                        length: maskSize.width * 0.9, phase: -time * 0.8), with: .color(.black))
                                }
                            }
                        Canvas { canvas, size in
                            let back = Self.wave(size: size, surface: surface, amplitude: 7, length: size.width * 1.3,
                                                 phase: time * 0.55 + 1.7)
                            let front = Self.wave(size: size, surface: surface, amplitude: 5, length: size.width * 0.9,
                                                  phase: -time * 0.8)
                            // The swell behind, a whisper of tint.
                            canvas.fill(back, with: .color(tint.opacity(dark ? 0.10 : 0.16)))
                            // The water: tint thickest just under the surface, as
                            // light gathers there, thinning with depth.
                            canvas.fill(front, with: .linearGradient(
                                Gradient(stops: [.init(color: tint.opacity(dark ? 0.34 : 0.42), location: 0),
                                                 .init(color: tint.opacity(dark ? 0.16 : 0.22), location: 0.35),
                                                 .init(color: hue.opacity(dark ? 0.20 : 0.14), location: 1)]),
                                startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: 0, y: size.height)))
                            // Caustics: a few soft bands of light drifting in the
                            // body, clipped to the water.
                            var inside = canvas
                            inside.clip(to: front)
                            for band in 0..<3 {
                                let y = surface + (size.height - surface) * CGFloat(0.18 + 0.2 * Double(band))
                                var line = Path()
                                let steps = 32
                                for step in 0...steps {
                                    let x = size.width * CGFloat(step) / CGFloat(steps)
                                    let speed: Double = 0.4 + 0.1 * Double(band)
                                    let angle: Double = Double(x) / 70 + time * speed + Double(band) * 1.9
                                    let dy: CGFloat = 9 * CGFloat(sin(angle))
                                    if step == 0 { line.move(to: CGPoint(x: x, y: y + dy)) } else { line.addLine(to: CGPoint(x: x, y: y + dy)) }
                                }
                                inside.stroke(line, with: .color(.white.opacity(dark ? 0.025 : 0.06)),
                                              style: StrokeStyle(lineWidth: 26, lineCap: .round))
                            }
                            // The surface: a soft glow under it and a crisp bright
                            // edge on it, like the rim of visionOS glass.
                            let edge = Self.surfaceLine(size: size, surface: surface, amplitude: 5,
                                                        length: size.width * 0.9, phase: -time * 0.8)
                            inside.stroke(edge, with: .color(.white.opacity(dark ? 0.12 : 0.25)), lineWidth: 18)
                            canvas.stroke(edge, with: .linearGradient(
                                Gradient(colors: [.white.opacity(0.25), .white.opacity(dark ? 0.75 : 0.95), .white.opacity(0.25)]),
                                startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: size.width, y: surface)),
                                          lineWidth: 1.2)
                        }
                    }
                }
            }
        }
        // The level eases on the standard spring. It is drawn by a canvas,
        // which does not interpolate on its own, so the shown level is state
        // the spring walks towards the target; a pour that keeps moving
        // retargets the spring mid-flight instead of stepping.
        .onChange(of: target) { _, next in
            if reduceMotion { shown = next } else { withAnimation(theme.motion.standard) { shown = next } }
        }
        .somaOnScreen($isOnScreen)
        .accessibilityHidden(true)
    }

    private static func wave(size: CGSize, surface: CGFloat, amplitude: CGFloat, length: CGFloat, phase: Double) -> Path {
        var path = surfaceLine(size: size, surface: surface, amplitude: amplitude, length: length, phase: phase)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private static func surfaceLine(size: CGSize, surface: CGFloat, amplitude: CGFloat, length: CGFloat, phase: Double) -> Path {
        var path = Path()
        // A level at the very top or bottom keeps its swell inside the page.
        let calm = min(1, max(0, min(surface, size.height - surface) / 24))
        let steps = 48
        for step in 0...steps {
            let x = size.width * CGFloat(step) / CGFloat(steps)
            let y = surface + amplitude * calm * CGFloat(sin(Double(x / max(length, 1)) * 2 * .pi + phase))
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

/// Hands its content a level that SwiftUI interpolates, so a canvas that draws
/// from a number can follow a spring.
private struct SomaAnimatedLevel<Content: View>: View, Animatable {
    var level: Double
    let content: (Double) -> Content

    nonisolated var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View { content(level) }
}

public extension View {
    /// Pours with the finger: a drag anywhere on the view moves the level by
    /// the distance dragged, a light tick at each step, the way a slider on
    /// the whole page would.
    func somaLiquidPour(value: Binding<Double>, capacity: Double, step: Double, height: CGFloat) -> some View {
        modifier(SomaLiquidPour(value: value, capacity: capacity, step: step, height: height))
    }
}

struct SomaLiquidPour: ViewModifier {
    @Binding var value: Double
    let capacity: Double
    let step: Double
    let height: CGFloat

    @State private var start: Double?

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { drag in
                        let origin = start ?? value
                        if start == nil { start = value }
                        let moved = -Double(drag.translation.height / max(height, 1)) * capacity
                        let raw = min(max(origin + moved, 0), capacity)
                        let snapped = step > 0 ? (raw / step).rounded() * step : raw
                        if snapped != value { value = snapped }
                    }
                    .onEnded { _ in start = nil }
            )
            .sensoryFeedback(.selection, trigger: value)
    }
}
