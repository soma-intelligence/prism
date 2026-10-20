//
//  SomaAspectGlyph.swift
//  SomaUI
//

import SwiftUI

/// The six aspects as one set of line glyphs: a crescent for sleep, a lotus
/// for mind, a heart, a route between two points for activity, a leaf for gut
/// and a standing figure for body.
///
/// All six are written on the same 24 unit grid with the same round stroke,
/// so side by side they read as a family rather than six symbols borrowed from
/// six places. Drawn from paths, like ``SomaMark``, so they take the theme's
/// hue and stay sharp on every platform the package builds for.
public struct SomaAspectGlyph: View {
    /// How the glyph is set.
    public enum Style: Sendable {
        /// Bare, in the aspect's hue: beside a move, at the head of a card.
        case inline
        /// Bare and smaller, beside an eyebrow.
        case caption
        /// On a softly tinted square: a tile, a list row.
        case badge
    }

    private let aspect: SomaAspect
    private let style: Style

    @Environment(\.somaTheme) private var theme

    public init(_ aspect: SomaAspect, style: Style = .inline) {
        self.aspect = aspect
        self.style = style
    }

    public var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[aspect].identity.color

        Group {
            switch style {
            case .inline:
                glyph(side: metrics.aspectGlyphInline, hue: hue)
            case .caption:
                glyph(side: metrics.aspectGlyphCaption, hue: hue)
            case .badge:
                glyph(side: metrics.aspectBadgeGlyph, hue: hue)
                    .frame(width: metrics.aspectBadgeSide, height: metrics.aspectBadgeSide)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.aspectBadgeCornerRadius, style: .continuous)
                            .fill(hue.opacity(metrics.aspectBadgeTint))
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func glyph(side: CGFloat, hue: Color) -> some View {
        let metrics = theme.metrics
        let stroke = side * metrics.aspectGlyphStroke / metrics.aspectGlyphGrid
        return SomaAspectGlyphShape(aspect: aspect)
            .stroke(hue, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side)
    }
}

/// The outline of one aspect's glyph, written on a 24 unit grid and fitted to
/// the largest square the rect holds.
public struct SomaAspectGlyphShape: Shape {
    public let aspect: SomaAspect

    public init(aspect: SomaAspect) {
        self.aspect = aspect
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let placement = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.outline(aspect).applying(placement)
    }

    static func outline(_ aspect: SomaAspect) -> Path {
        switch aspect {
        case .sleep: crescent
        case .mind: lotus
        case .heart: heart
        case .activity: route
        case .gut: leaf
        case .body: figure
        }
    }

    // MARK: The six outlines

    /// A crescent: the arc of one circle closed by the arc of a second that
    /// bites into it from the upper right.
    static var crescent: Path {
        let outer = (centre: CGPoint(x: 11.5, y: 12.5), radius: 8.0)
        let bite = (centre: CGPoint(x: 16.2, y: 8.4), radius: 6.6)
        guard let (a, b) = intersections(outer.centre, outer.radius, bite.centre, bite.radius) else {
            return Path(ellipseIn: CGRect(x: 3.5, y: 4.5, width: 16, height: 16))
        }
        var path = Path()
        // The lit edge: round the outer circle the long way, away from the bite.
        let lit = arc(outer.centre, outer.radius, from: a, to: b) { point in
            hypot(point.x - bite.centre.x, point.y - bite.centre.y) > bite.radius
        }
        // The shadow edge: back along the bite, inside the outer circle.
        let shadow = arc(bite.centre, bite.radius, from: b, to: a) { point in
            hypot(point.x - outer.centre.x, point.y - outer.centre.y) < outer.radius
        }
        path.addLines(lit + shadow.dropFirst())
        path.closeSubpath()
        return path
    }

    /// A lotus: a tall centre petal and two that open to the sides.
    static var lotus: Path {
        var path = Path()
        let base = CGPoint(x: 12, y: 19)
        path.move(to: base)
        path.addQuadCurve(to: CGPoint(x: 12, y: 5.5), control: CGPoint(x: 6.8, y: 11.5))
        path.addQuadCurve(to: base, control: CGPoint(x: 17.2, y: 11.5))
        path.move(to: base)
        path.addQuadCurve(to: CGPoint(x: 3.5, y: 10.5), control: CGPoint(x: 3.6, y: 18.6))
        path.addQuadCurve(to: CGPoint(x: 8.6, y: 13.6), control: CGPoint(x: 6.6, y: 10.6))
        path.move(to: base)
        path.addQuadCurve(to: CGPoint(x: 20.5, y: 10.5), control: CGPoint(x: 20.4, y: 18.6))
        path.addQuadCurve(to: CGPoint(x: 15.4, y: 13.6), control: CGPoint(x: 17.4, y: 10.6))
        return path
    }

    /// A heart, its lobes round and its point soft.
    static var heart: Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 19.6))
        path.addCurve(to: CGPoint(x: 3.4, y: 9.6), control1: CGPoint(x: 7.2, y: 16.4), control2: CGPoint(x: 3.4, y: 13.4))
        path.addCurve(to: CGPoint(x: 12, y: 7.4), control1: CGPoint(x: 3.4, y: 4.8), control2: CGPoint(x: 9.4, y: 3.8))
        path.addCurve(to: CGPoint(x: 20.6, y: 9.6), control1: CGPoint(x: 14.6, y: 3.8), control2: CGPoint(x: 20.6, y: 4.8))
        path.addCurve(to: CGPoint(x: 12, y: 19.6), control1: CGPoint(x: 20.6, y: 13.4), control2: CGPoint(x: 16.8, y: 16.4))
        path.closeSubpath()
        return path
    }

    /// A route: a start, a winding way, an arrival.
    static var route: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 3.2, y: 16.2, width: 4.6, height: 4.6))
        path.addEllipse(in: CGRect(x: 16.2, y: 3.2, width: 4.6, height: 4.6))
        path.move(to: CGPoint(x: 7.6, y: 17.2))
        path.addCurve(to: CGPoint(x: 16.4, y: 6.8), control1: CGPoint(x: 17.5, y: 15.5), control2: CGPoint(x: 6.5, y: 8.5))
        return path
    }

    /// A leaf on a short stem, its midrib drawn.
    static var leaf: Path {
        var path = Path()
        let stem = CGPoint(x: 6, y: 18)
        path.move(to: stem)
        path.addQuadCurve(to: CGPoint(x: 19.5, y: 4.5), control: CGPoint(x: 4.6, y: 5.2))
        path.addQuadCurve(to: stem, control: CGPoint(x: 18.8, y: 19.4))
        path.move(to: CGPoint(x: 3.8, y: 20.2))
        path.addLine(to: stem)
        path.addLine(to: CGPoint(x: 13.4, y: 10.6))
        return path
    }

    /// A figure standing at ease: head, arms falling from the shoulders,
    /// legs apart.
    static var figure: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 9.7, y: 2.8, width: 4.6, height: 4.6))
        path.move(to: CGPoint(x: 6.2, y: 15))
        path.addQuadCurve(to: CGPoint(x: 12, y: 9.9), control: CGPoint(x: 7.4, y: 10))
        path.addQuadCurve(to: CGPoint(x: 17.8, y: 15), control: CGPoint(x: 16.6, y: 10))
        path.move(to: CGPoint(x: 12, y: 9.9))
        path.addLine(to: CGPoint(x: 12, y: 15.2))
        path.move(to: CGPoint(x: 8.8, y: 21))
        path.addLine(to: CGPoint(x: 12, y: 15.2))
        path.addLine(to: CGPoint(x: 15.2, y: 21))
        return path
    }

    // MARK: Geometry

    /// Where two circles cross, or nil when they do not.
    static func intersections(_ c0: CGPoint, _ r0: Double, _ c1: CGPoint, _ r1: Double) -> (CGPoint, CGPoint)? {
        let dx = c1.x - c0.x, dy = c1.y - c0.y
        let d = hypot(dx, dy)
        guard d > 0, d < r0 + r1, d > abs(r0 - r1) else { return nil }
        let along = (r0 * r0 - r1 * r1 + d * d) / (2 * d)
        let across = sqrt(max(0, r0 * r0 - along * along))
        let mid = CGPoint(x: c0.x + along * dx / d, y: c0.y + along * dy / d)
        return (CGPoint(x: mid.x + across * dy / d, y: mid.y - across * dx / d),
                CGPoint(x: mid.x - across * dy / d, y: mid.y + across * dx / d))
    }

    /// The points of the arc from `start` to `end` round `centre`, taking the
    /// way round whose middle passes `keep`.
    static func arc(_ centre: CGPoint, _ radius: Double, from start: CGPoint, to end: CGPoint,
                    keep: (CGPoint) -> Bool) -> [CGPoint] {
        let a0 = atan2(start.y - centre.y, start.x - centre.x)
        var a1 = atan2(end.y - centre.y, end.x - centre.x)
        while a1 <= a0 { a1 += 2 * .pi }
        func point(_ angle: Double) -> CGPoint {
            CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }
        // Counter to the clock from a0 up to a1, or the other way round.
        let forward = keep(point((a0 + a1) / 2))
        let sweep = forward ? a1 - a0 : -(2 * .pi - (a1 - a0))
        let steps = 48
        return (0...steps).map { point(a0 + sweep * Double($0) / Double(steps)) }
    }
}

#Preview("Aspect glyphs") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                ForEach(SomaAspect.allCases) { SomaAspectGlyph($0) }
            }
            HStack(spacing: 12) {
                ForEach(SomaAspect.allCases) { SomaAspectGlyph($0, style: .badge) }
            }
        }
        .padding()
    }
}
