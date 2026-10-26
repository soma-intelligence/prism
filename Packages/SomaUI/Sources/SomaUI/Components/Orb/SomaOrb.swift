//
//  SomaOrb.swift
//  SomaUI
//

import SwiftUI

/// An aspect's orb: a body of the aspect's colour lit from within, with the
/// next move written on it.
///
/// The hero orb moves: the weather flows at its aspect's own speed while the
/// sphere turns slowly, and a change of aspect sends it to the new palette the
/// way the website's hero travels from organ to organ, the colours blending in
/// OKLab. With Reduce Motion on it holds still on its last frame and changes
/// palette at once. A mini orb, the one that leads a row, is always still.
public struct SomaOrb: View {
    /// How big the orb is drawn, which also decides whether it moves.
    public enum Scale: Sendable {
        /// The one orb at the head of a page. It moves, and it carries a label.
        case hero
        /// The orb that leads a row. Still, and without a label.
        case mini
    }

    private let aspect: SomaAspect
    private let label: LocalizedStringResource?
    private let scale: Scale

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Where the palette is travelling from, and since when. Nil until the
    /// first change of aspect.
    @State private var travel: SomaOrbTravel?
    /// The instant the orb first appeared: the weather's clock counts from it,
    /// so its time stays small enough for the shader's floats.
    @State private var epoch = Date()
    /// Bumped once a journey ends, so the body is read again and the timeline
    /// drops back to its slow rate.
    @State private var settledCount = 0
    /// False while the orb is off screen: on a hidden tab, under a pushed
    /// page, or scrolled out of sight.
    @State private var isOnScreen = true
    private var power = SomaPowerState.shared

    public init(aspect: SomaAspect, label: LocalizedStringResource? = nil, scale: Scale = .hero) {
        self.aspect = aspect
        self.label = label
        self.scale = scale
    }

    public var body: some View {
        Group {
            switch scale {
            case .hero:
                // Thirty frames a second for the slow weather, the display's
                // full rate while the palette travels: at thirty the blend
                // from one aspect to the next visibly stepped.
                // Only the shader is redrawn each frame. The shadow and the
                // label sit outside the timeline: rebuilt with it, the label
                // resolved its localized string thirty times a second.
                heroFrame {
                    TimelineView(.animation(minimumInterval: isTravelling ? nil : 1.0 / 30.0, paused: isPaused)) { context in
                        heroCanvas(at: context.date)
                    }
                }
                .somaOnScreen($isOnScreen)
            case .mini:
                SomaOrbCanvas(
                    frame: SomaOrbFrame(palette: palette.orb, isDark: isDark),
                    diameter: theme.metrics.miniOrbDiameter,
                    time: 0,
                    turn: 0,
                    halo: halo
                )
                .accessibilityHidden(true)
            }
        }
        .onChange(of: aspect) { old, new in
            guard scale == .hero else { return }
            if reduceMotion {
                travel = nil
                return
            }
            // Set off from wherever the orb is right now, which is part way
            // to the old aspect when a swipe interrupts a journey.
            let now = Date()
            let oldPalette = theme.aspects[old].orb
            let oldFrame = SomaOrbFrame(palette: oldPalette, isDark: isDark)
            travel = SomaOrbTravel(
                start: now,
                from: travel?.frame(at: now, target: oldFrame) ?? oldFrame,
                fromSpeed: travel?.speed(at: now, target: oldPalette.speed) ?? oldPalette.speed,
                startTime: travel?.time(at: now, targetSpeed: oldPalette.speed)
                    ?? now.timeIntervalSince(epoch) * oldPalette.speed,
                duration: theme.motion.orbBlendDuration
            )
        }
        .task(id: travel?.start) {
            guard let travel else { return }
            try? await Task.sleep(for: .seconds(travel.duration + 0.3))
            settledCount &+= 1
        }
    }

    private var palette: SomaAspectLook { theme.aspects[aspect] }

    /// True for the length of a journey between two palettes, plus a beat.
    private var isTravelling: Bool {
        _ = settledCount
        guard let travel else { return false }
        return Date().timeIntervalSince(travel.start) < travel.duration + 0.2
    }

    private var isDark: Bool { colorScheme == .dark }

    private var halo: Double {
        isDark ? theme.aspects.shading.haloDark : theme.aspects.shading.haloLight
    }

    /// Held on its last frame with Reduce Motion on, in Low Power Mode, and
    /// while the app or the orb is not on screen, where the frames would go
    /// to nobody.
    private var isPaused: Bool {
        reduceMotion || scenePhase != .active || !isOnScreen || power.isLowPower
    }

    /// The moving sphere for one instant: the only part of the hero orb the
    /// timeline redraws.
    private func heroCanvas(at date: Date) -> some View {
        let motion = theme.motion
        let target = SomaOrbFrame(palette: palette.orb, isDark: isDark)
        let frame = travel?.frame(at: date, target: target) ?? target
        let time = travel?.time(at: date, targetSpeed: palette.orb.speed)
            ?? date.timeIntervalSince(epoch) * palette.orb.speed
        let turn = 2 * Double.pi
            * date.timeIntervalSince(epoch).truncatingRemainder(dividingBy: motion.orbTurnDuration)
            / motion.orbTurnDuration

        return SomaOrbCanvas(frame: frame, diameter: theme.metrics.orbDiameter, time: time, turn: turn, halo: halo)
    }

    /// The still parts of the hero orb around its moving sphere: the contact
    /// shadow under it and the label on it.
    private func heroFrame<Sphere: View>(@ViewBuilder sphere: () -> Sphere) -> some View {
        let diameter = theme.metrics.orbDiameter
        let shading = theme.aspects.shading
        let motion = theme.motion
        let labelFont = theme.typography.orbLabel
        let onOrb = theme.colors.onOrb.color

        return ZStack {
            // No contact shadow: the orb is a body of light, not a planet
            // set down on the page.
            sphere()

            if let label {
                Text(label)
                    .somaFont(labelFont)
                    .foregroundStyle(onOrb)
                    .shadow(color: .black.opacity(shading.labelShadowOpacity), radius: 6, y: 1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: diameter * 0.8)
                    .id(label.key)
                    .transition(.opacity)
            }
        }
        .frame(width: diameter, height: diameter)
        // The word changes on the standard curve, not over half the colour's
        // blend: a 1.6 second cross fade left two words legible at once.
        .animation(reduceMotion ? nil : motion.standard, value: label?.key)
    }
}

/// The shader itself, drawn into a square larger than the sphere so the halo
/// has room, without taking that room in the layout.
struct SomaOrbCanvas: View {
    let frame: SomaOrbFrame
    let diameter: CGFloat
    let time: Double
    let turn: Double
    let halo: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let shading = theme.aspects.shading
        let side = diameter * (1 + 2 * shading.haloReach)

        Color.clear
            .frame(width: diameter, height: diameter)
            .overlay {
                Rectangle()
                    .frame(width: side, height: side)
                    .colorEffect(
                        ShaderLibrary.bundle(.module).somaOrb(
                            .float2(side, side),
                            .float(diameter / 2),
                            .float4(time, turn, 0, 0),
                            .float4(frame.proportion, frame.softness, frame.distortion, frame.swirl),
                            .float4(frame.shapeScale, frame.rotation * .pi / 180, frame.zoom, shading.detail),
                            .float4(shading.light, shading.rim, shading.depth, halo),
                            .float(shading.haloFalloff),
                            .float3(frame.stops[0].x, frame.stops[0].y, frame.stops[0].z),
                            .float3(frame.stops[1].x, frame.stops[1].y, frame.stops[1].z),
                            .float3(frame.stops[2].x, frame.stops[2].y, frame.stops[2].z),
                            .float3(frame.stops[3].x, frame.stops[3].y, frame.stops[3].z),
                            .float3(frame.accent.x, frame.accent.y, frame.accent.z)
                        )
                    )
                    .allowsHitTesting(false)
            }
    }
}

/// One palette resolved to numbers the shader reads: sRGB components and the
/// shape settings.
struct SomaOrbFrame: Equatable {
    var stops: [SIMD3<Double>]
    var accent: SIMD3<Double>
    var proportion: Double
    var softness: Double
    var distortion: Double
    var swirl: Double
    var shapeScale: Double
    var rotation: Double
    var zoom: Double

    init(palette: SomaOrbPalette, isDark: Bool) {
        stops = palette.stops.map { $0.components(isDark: isDark) }
        while stops.count < 4 { stops.append(stops.last ?? .zero) }
        accent = palette.accent.components(isDark: isDark)
        proportion = palette.proportion
        softness = palette.softness
        distortion = palette.distortion
        swirl = palette.swirl
        shapeScale = palette.shapeScale
        rotation = palette.rotation
        zoom = palette.zoom
    }

    /// The frame a share of the way to another one: colours through OKLab,
    /// where a blend between two hues stays as bright as its ends, and every
    /// setting in a straight line.
    func mixed(with other: SomaOrbFrame, by amount: Double) -> SomaOrbFrame {
        var result = self
        result.stops = zip(stops, other.stops).map { SomaOKLab.mix($0, $1, by: amount) }
        result.accent = SomaOKLab.mix(accent, other.accent, by: amount)
        func line(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        result.proportion = line(proportion, other.proportion)
        result.softness = line(softness, other.softness)
        result.distortion = line(distortion, other.distortion)
        result.swirl = line(swirl, other.swirl)
        result.shapeScale = line(shapeScale, other.shapeScale)
        result.rotation = line(rotation, other.rotation)
        result.zoom = line(zoom, other.zoom)
        return result
    }
}

/// A palette on its way from one aspect to another.
///
/// Everything is worked out from the instant it set off, so a frame is a pure
/// function of the clock: nothing accumulates between frames, and a frame
/// dropped under load costs nothing but that frame. The destination is read
/// off the theme at each frame rather than stored, so it is always the
/// aspect showing now.
struct SomaOrbTravel: Equatable {
    let start: Date
    let from: SomaOrbFrame
    let fromSpeed: Double
    /// The weather's time when it set off.
    let startTime: Double
    let duration: Double

    /// How far along it is, eased at both ends: 0 at the start, 1 once there.
    func progress(at date: Date) -> Double {
        let x = min(max(date.timeIntervalSince(start) / duration, 0), 1)
        return x * x * (3 - 2 * x)
    }

    func frame(at date: Date, target: SomaOrbFrame) -> SomaOrbFrame {
        from.mixed(with: target, by: progress(at: date))
    }

    /// The weather's speed at this instant, part way between the two aspects'.
    func speed(at date: Date, target: Double) -> Double {
        fromSpeed + (target - fromSpeed) * progress(at: date)
    }

    /// The weather's time: the integral of the speed, so it never jumps when
    /// the speed changes on the way.
    ///
    /// With the eased progress `e(x) = x²(3 − 2x)`, the integral of `e` from 0
    /// to x is `x³ − x⁴ / 2`, and past the end the speed is simply the new one.
    func time(at date: Date, targetSpeed: Double) -> Double {
        let elapsed = max(date.timeIntervalSince(start), 0)
        let x = elapsed / duration
        let eased: Double = x < 1 ? x * x * x - x * x * x * x / 2 : 0.5 + (x - 1)
        return startTime + fromSpeed * elapsed + (targetSpeed - fromSpeed) * duration * eased
    }
}

/// OKLab, Björn Ottosson's perceptual colour space, for blending two colours
/// without the grey dip a blend in sRGB takes between two hues.
enum SomaOKLab {
    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, by amount: Double) -> SIMD3<Double> {
        let la = lab(fromSRGB: a)
        let lb = lab(fromSRGB: b)
        return sRGB(fromLab: la + (lb - la) * amount)
    }

    static func lab(fromSRGB c: SIMD3<Double>) -> SIMD3<Double> {
        let r = linear(c.x), g = linear(c.y), b = linear(c.z)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    static func sRGB(fromLab c: SIMD3<Double>) -> SIMD3<Double> {
        let l = pow(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z, 3)
        let m = pow(c.x - 0.1055613458 * c.y - 0.0638541728 * c.z, 3)
        let s = pow(c.x - 0.0894841775 * c.y - 1.2914855480 * c.z, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return SIMD3(gamma(r), gamma(g), gamma(b))
    }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ v: Double) -> Double {
        let clamped = min(max(v, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}

extension SomaColorValue {
    /// The value's sRGB components in 0...1, for one appearance.
    func components(isDark: Bool) -> SIMD3<Double> {
        let rgb = isDark ? dark : light
        return SIMD3(
            Double((rgb >> 16) & 0xFF) / 255,
            Double((rgb >> 8) & 0xFF) / 255,
            Double(rgb & 0xFF) / 255
        )
    }
}

#Preview("Orb") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 40) {
            SomaOrb(aspect: .mind, label: "Slow down")
            HStack(spacing: 12) {
                ForEach(SomaAspect.allCases) { SomaOrb(aspect: $0, scale: .mini) }
            }
        }
    }
}
