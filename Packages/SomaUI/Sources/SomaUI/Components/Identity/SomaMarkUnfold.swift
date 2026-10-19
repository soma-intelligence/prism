//
//  SomaMarkUnfold.swift
//  SomaUI
//

import SwiftUI

/// The mark growing out of its dot, holding, and folding back into it: the
/// website's Unfold loop (`soma-unfold` in the brand motion exports), frame for
/// frame.
///
/// Every cycle starts and ends on the dot alone, so the loop has no seam, and a
/// launch screen that shows only the dot hands over to it without a jump.
/// While the arms move they are drawn fused, a blur under an alpha threshold
/// (the website's `feGaussianBlur` and `feColorMatrix`), so the cuts between
/// them never show; once they settle, the crisp mark fades in over them.
///
/// Sized by its frame, like `SomaMark`'s outline: the mark fills the largest
/// square the frame holds, in the primary ink. With Reduce Motion on it is the
/// still mark.
public struct SomaMarkUnfold: View {
    /// How long the animation runs.
    public enum Mode: Sendable {
        /// Grows, holds, folds back into the dot and starts again. For a wait.
        case loop
        /// Grows once and stays as the mark. For an entrance, such as the
        /// first screen after launch.
        case once
    }

    private let accessibilityLabel: LocalizedStringResource
    private let mode: Mode

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var settled = false

    public init(accessibilityLabel: LocalizedStringResource, mode: Mode = .loop) {
        self.accessibilityLabel = accessibilityLabel
        self.mode = mode
    }

    public var body: some View {
        let ink = theme.colors.inkPrimary.color

        Group {
            if reduceMotion || settled {
                SomaMarkShape().fill(ink, style: FillStyle(eoFill: true))
            } else {
                TimelineView(.animation) { context in
                    SomaMarkUnfoldFrame(time: context.date.timeIntervalSince(start), ink: ink)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isImage)
        .onAppear { start = .now }
        .task(id: mode) {
            guard mode == .once else { return }
            try? await Task.sleep(for: .seconds(SomaMarkUnfoldChoreography.entrance))
            settled = true
        }
    }
}

/// One frame of the unfold, drawn for a moment of the cycle.
///
/// A pure function of the time, so previews and tests can stop the animation
/// anywhere.
struct SomaMarkUnfoldFrame: View {
    /// Seconds since the cycle began. Anything past one period wraps around.
    let time: Double
    let ink: Color

    var body: some View {
        Canvas { context, size in
            typealias C = SomaMarkUnfoldChoreography
            let side = min(size.width, size.height)
            let unit = side / SomaMarkShape.box
            let place = CGAffineTransform(
                translationX: (size.width - side) / 2,
                y: (size.height - side) / 2
            )
            .scaledBy(x: unit, y: unit)

            let phase = C.phase(time)

            // The arms, fused while they travel.
            let fused = C.fusedOpacity(phase)
            if fused > 0 {
                context.drawLayer { faded in
                    faded.opacity = fused
                    faded.drawLayer { goo in
                        goo.addFilter(.alphaThreshold(min: C.threshold, color: ink))
                        goo.addFilter(.blur(radius: C.fuseRadius * unit))
                        goo.drawLayer { arms in
                            for arm in SomaMarkUnfoldChoreography.Arm.allCases {
                                var piece = arms
                                piece.transform = C.transform(for: arm, at: time).concatenating(place)
                                piece.clip(to: arm.wedge)
                                // Any opaque fill: the threshold repaints it in ink.
                                piece.fill(C.ring, with: .color(.black))
                            }
                        }
                    }
                }
            }

            // The crisp mark, over the arms once they settle.
            let crisp = C.crispOpacity(phase)
            if crisp > 0 {
                var sharp = context
                sharp.opacity = crisp
                sharp.fill(C.ring.applying(place), with: .color(ink))
            }

            // The dot, which never moves: everything grows out of it and back into it.
            let dot = CGAffineTransform(translationX: -C.dotCentre.x, y: -C.dotCentre.y)
                .concatenating(CGAffineTransform(scaleX: C.dotScale(phase), y: C.dotScale(phase)))
                .concatenating(CGAffineTransform(translationX: C.dotCentre.x, y: C.dotCentre.y))
            context.fill(C.dot.applying(dot.concatenating(place)), with: .color(ink))
        }
    }
}

/// The unfold's keyframes, kept beside the drawing the way the mark keeps its
/// trace: they are the mark's own motion, the same numbers the website's CSS
/// runs, so the two surfaces move alike and a change is one edit on each side.
///
/// Fractions are of one period, and match the CSS keyframe percentages.
enum SomaMarkUnfoldChoreography {
    /// One full cycle, dot to mark to dot, in seconds.
    static let period: Double = 4.4
    /// Where the `once` mode stops: halfway, in the middle of the hold.
    static let entrance: Double = period * 0.5

    static let openStart = 0.06
    static let openEnd = 0.42
    static let foldStart = 0.70
    static let foldEnd = 0.92

    /// How small the arms shrink when folded: hidden under the dot.
    static let foldedScale: Double = 0.06
    /// The quarter turn they open with, and the next quarter they fold with.
    static let turn: Double = 90
    /// How far each arm starts toward the centre, in mark units.
    static let reach: CGFloat = 18
    /// The fusing blur, in mark units, and the alpha the edge is cut at.
    static let fuseRadius: CGFloat = 2.2
    static let threshold: Double = 0.475
    /// The dot's centre in the trace, which the dot swells around.
    static let dotCentre = CGPoint(x: 49.8, y: 49.85)

    /// The arms leave clockwise, a few frames apart.
    enum Arm: CaseIterable {
        case north, east, south, west

        var delay: Double {
            switch self {
            case .north: 0
            case .east: 0.03
            case .south: 0.06
            case .west: 0.09
            }
        }

        /// The direction the arm starts from, toward the centre.
        var inward: CGVector {
            switch self {
            case .north: CGVector(dx: 0, dy: SomaMarkUnfoldChoreography.reach)
            case .east: CGVector(dx: -SomaMarkUnfoldChoreography.reach, dy: 0)
            case .south: CGVector(dx: 0, dy: -SomaMarkUnfoldChoreography.reach)
            case .west: CGVector(dx: SomaMarkUnfoldChoreography.reach, dy: 0)
            }
        }

        /// The quarter of the mark this arm owns: a triangle from the centre
        /// out past one side, cut along the diagonals, overlapping its
        /// neighbours by a hair so no seam shows at rest.
        var wedge: Path {
            let o: CGFloat = 0.4
            let points: [CGPoint] = switch self {
            case .north: [CGPoint(x: -10 - o, y: -10), CGPoint(x: 110 + o, y: -10), CGPoint(x: 50, y: 50 + o)]
            case .east: [CGPoint(x: 110, y: -10 - o), CGPoint(x: 110, y: 110 + o), CGPoint(x: 50 - o, y: 50)]
            case .south: [CGPoint(x: 110 + o, y: 110), CGPoint(x: -10 - o, y: 110), CGPoint(x: 50, y: 50 - o)]
            case .west: [CGPoint(x: -10, y: 110 + o), CGPoint(x: -10, y: -10 - o), CGPoint(x: 50 + o, y: 50)]
            }
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            return path
        }
    }

    /// The trace split in two: the arms, and the dot.
    static let ring: Path = SomaMarkShape.path(from: pieces.ring) ?? Path()
    static let dot: Path = SomaMarkShape.path(from: pieces.dot) ?? Path()

    private static var pieces: (ring: String, dot: String) {
        let parts = SomaMarkShape.trace.split(separator: "Z", omittingEmptySubsequences: true)
        return (String(parts[0]) + "Z", String(parts[1]) + "Z")
    }

    /// Where in the cycle a moment falls, from 0 up to 1.
    static func phase(_ time: Double) -> Double {
        let wrapped = time.truncatingRemainder(dividingBy: period)
        return (wrapped < 0 ? wrapped + period : wrapped) / period
    }

    /// How open the arms are (0 folded, 1 home) and how far they have turned,
    /// in degrees.
    static func pose(_ phase: Double) -> (open: Double, degrees: Double) {
        switch phase {
        case ..<openStart:
            return (0, -turn)
        case ..<openEnd:
            let p = spring((phase - openStart) / (openEnd - openStart))
            return (p, -turn + turn * p)
        case ..<foldStart:
            return (1, 0)
        case ..<foldEnd:
            let q = foldCurve.value(at: (phase - foldStart) / (foldEnd - foldStart))
            return (1 - q, turn * q)
        default:
            return (0, turn)
        }
    }

    /// Where one arm sits at a moment, in mark units.
    static func transform(for arm: Arm, at time: Double) -> CGAffineTransform {
        let pose = pose(phase(time - arm.delay))
        let scale = foldedScale + (1 - foldedScale) * pose.open
        let away = 1 - pose.open
        return CGAffineTransform(translationX: arm.inward.dx * away, y: arm.inward.dy * away)
            .concatenating(CGAffineTransform(translationX: -50, y: -50))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: pose.degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: 50, y: 50))
    }

    /// The fused arms show while they move and hand over to the crisp mark
    /// around the hold: the crisp mark comes in first, then the fused one
    /// leaves, so the ink never dips.
    static func fusedOpacity(_ phase: Double) -> Double {
        switch phase {
        case ..<0.41: 1
        case ..<0.46: 1 - cssEase.value(at: (phase - 0.41) / 0.05)
        case ..<0.62: 0
        case ..<0.66: cssEase.value(at: (phase - 0.62) / 0.04)
        default: 1
        }
    }

    static func crispOpacity(_ phase: Double) -> Double {
        switch phase {
        case ..<0.36: 0
        case ..<0.41: cssEase.value(at: (phase - 0.36) / 0.05)
        case ..<0.66: 1
        case ..<0.70: 1 - cssEase.value(at: (phase - 0.66) / 0.04)
        default: 0
        }
    }

    /// The dot swells a little as it swallows the folding arms.
    static func dotScale(_ phase: Double) -> CGFloat {
        switch phase {
        case ..<0.86: 1
        case ..<0.93: 1 + 0.25 * swell.value(at: (phase - 0.86) / 0.07)
        default: 1.25 - 0.25 * swell.value(at: (phase - 0.93) / 0.07)
        }
    }

    /// A soft spring, damping 0.78 and 9 radians a second over the opening,
    /// which overshoots by about 2 percent. The website samples the same curve
    /// into a CSS `linear()` easing.
    static func spring(_ x: Double) -> Double {
        let zeta = 0.78
        let omega = 9.0
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * x) * (cos(damped * x) + zeta * omega / damped * sin(damped * x))
    }

    static let foldCurve = SomaCubicCurve(0.65, 0, 0.35, 1)
    static let swell = SomaCubicCurve(0.45, 0, 0.55, 1)
    /// CSS `ease`, which the website's opacity keyframes run on.
    static let cssEase = SomaCubicCurve(0.25, 0.1, 0.25, 1)
}

/// A CSS `cubic-bezier()` easing, solved for a progress value.
struct SomaCubicCurve: Sendable {
    private let x1: Double, y1: Double, x2: Double, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    func value(at x: Double) -> Double {
        let x = min(max(x, 0), 1)
        // Newton's method on the curve's x, falling back to bisection.
        var t = x
        for _ in 0..<8 {
            let error = Self.bezier(t, x1, x2) - x
            let slope = Self.slope(t, x1, x2)
            if abs(error) < 1e-6 { return Self.bezier(t, y1, y2) }
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0
        var high = 1.0
        t = x
        for _ in 0..<30 {
            let guess = Self.bezier(t, x1, x2)
            if abs(guess - x) < 1e-6 { break }
            if guess < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return Self.bezier(t, y1, y2)
    }

    private static func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private static func slope(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}

#Preview("Unfold") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaMarkUnfold(accessibilityLabel: "Soma")
                .frame(width: 120, height: 120)
            SomaMarkUnfold(accessibilityLabel: "Soma", mode: .once)
                .frame(width: 56, height: 56)
        }
    }
}

#Preview("Unfold, frame by frame") {
    ZStack {
        SomaPreviewBackdrop()
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(64)), count: 4), spacing: 12) {
            ForEach(0..<12, id: \.self) { step in
                SomaMarkUnfoldFrame(time: Double(step) * 0.4, ink: .primary)
                    .frame(width: 64, height: 64)
            }
        }
    }
}
