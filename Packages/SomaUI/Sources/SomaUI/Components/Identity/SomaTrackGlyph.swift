//
//  SomaTrackGlyph.swift
//  SomaUI
//

import SwiftUI

/// What a person logs by hand, as line glyphs drawn like the aspect glyphs
/// (``SomaAspectGlyph``): the same 24 unit grid, the same round stroke, the
/// same softly tinted badge. The quick add tiles, the Journal's questions, its
/// automatic rows and the rituals' steps all draw from this one set, so Track
/// reads as one family with the rest of the app.
public struct SomaTrackGlyph: View {
    /// One thing logged.
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case drink, coffee, meal, lateMeal, fast, mood, weight, height
        case breathe, sauna, cold, evening, wake, supplement, scan, bloodTest
        case alcohol, training, screens, meditation, travel, nap, tag
        case sleep, steps, daylight, exercise, hrv
        case stretch, read, journal, walk, cloud
        case more, less

        public var id: String { rawValue }
    }

    /// How the glyph is set.
    public enum Style: Sendable {
        /// Bare, in its tone, at the inline size.
        case inline
        /// Bare and small: the ends of a scale.
        case caption
        /// On a softly tinted square, at the row size: the head of a row.
        case row
        /// On a softly tinted square, at the tile size: a quick add tile.
        case badge
    }

    private let kind: Kind
    private let tone: SomaTrackTone?
    private let style: Style

    @Environment(\.somaTheme) private var theme

    /// - Parameter tone: the glyph's colour. Nil draws it in the primary
    ///   ink on a recessed square, for a control rather than a thing logged.
    public init(_ kind: Kind, tone: SomaTrackTone?, style: Style = .inline) {
        self.kind = kind
        self.tone = tone
        self.style = style
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let ink = tone?.color ?? colors.inkPrimary.color

        Group {
            switch style {
            case .inline:
                glyph(side: metrics.aspectGlyphInline, ink: ink)
            case .caption:
                glyph(side: metrics.aspectGlyphCaption, ink: ink)
            case .row:
                badge(side: metrics.trackRowBadge, glyph: metrics.trackRowBadgeGlyph,
                      radius: metrics.trackRowBadgeCornerRadius, ink: ink)
            case .badge:
                badge(side: metrics.aspectBadgeSide, glyph: metrics.aspectBadgeGlyph,
                      radius: metrics.aspectBadgeCornerRadius, ink: ink)
            }
        }
        .accessibilityHidden(true)
    }

    private func badge(side: CGFloat, glyph: CGFloat, radius: CGFloat, ink: Color) -> some View {
        let metrics = theme.metrics
        return self.glyph(side: glyph, ink: ink)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tone.map { $0.color.opacity(metrics.trackBadgeTint) } ?? theme.colors.surfaceRecessed.color)
            )
    }

    private func glyph(side: CGFloat, ink: Color) -> some View {
        let metrics = theme.metrics
        let stroke = side * metrics.aspectGlyphStroke / metrics.aspectGlyphGrid
        return SomaTrackGlyphShape(kind: kind)
            .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side)
    }
}

/// The outline of one Track glyph on the 24 unit grid, fitted to the largest
/// square the rect holds.
public struct SomaTrackGlyphShape: Shape {
    public let kind: SomaTrackGlyph.Kind

    public init(kind: SomaTrackGlyph.Kind) {
        self.kind = kind
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let placement = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.outline(kind).applying(placement)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func outline(_ kind: SomaTrackGlyph.Kind) -> Path {
        var p = Path()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        func line(_ points: (Double, Double)...) {
            guard let first = points.first else { return }
            p.move(to: pt(first.0, first.1))
            for point in points.dropFirst() { p.addLine(to: pt(point.0, point.1)) }
        }
        func circle(_ x: Double, _ y: Double, _ r: Double) {
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        func steam(_ x: Double, from top: Double, to bottom: Double) {
            let mid = (top + bottom) / 2
            p.move(to: pt(x, bottom))
            p.addQuadCurve(to: pt(x, mid), control: pt(x - 1.4, (bottom + mid) / 2))
            p.addQuadCurve(to: pt(x, top), control: pt(x + 1.4, (mid + top) / 2))
        }

        switch kind {
        case .drink:
            // A tumbler, the water line a third down.
            line((5.5, 4), (18.5, 4), (17, 20), (7, 20))
            p.closeSubpath()
            line((6.4, 10), (17.6, 10))

        case .coffee:
            // A cup with its handle, steam rising.
            p.move(to: pt(4.5, 10))
            p.addLine(to: pt(16.5, 10))
            p.addLine(to: pt(16.5, 14.5))
            p.addCurve(to: pt(10.5, 19.5), control1: pt(16.5, 17.5), control2: pt(14, 19.5))
            p.addCurve(to: pt(4.5, 14.5), control1: pt(7, 19.5), control2: pt(4.5, 17.5))
            p.closeSubpath()
            p.move(to: pt(16.5, 11.5))
            p.addCurve(to: pt(16.5, 16), control1: pt(20.6, 11.5), control2: pt(20.6, 16))
            steam(8.5, from: 3.5, to: 7.5)
            steam(12.5, from: 3.5, to: 7.5)

        case .meal:
            // A bowl, steam over it.
            line((3, 11.5), (21, 11.5))
            p.move(to: pt(4, 11.5))
            p.addCurve(to: pt(12, 19.5), control1: pt(4, 16.5), control2: pt(7.5, 19.5))
            p.addCurve(to: pt(20, 11.5), control1: pt(16.5, 19.5), control2: pt(20, 16.5))
            steam(9.5, from: 3.5, to: 8.5)
            steam(14.5, from: 3.5, to: 8.5)

        case .lateMeal:
            // A fork and a knife.
            line((5, 3.5), (5, 8))
            line((8, 3.5), (8, 8))
            p.move(to: pt(5, 8))
            p.addQuadCurve(to: pt(8, 8), control: pt(6.5, 11.5))
            line((6.5, 10.2), (6.5, 20.5))
            line((11, 3.5), (11, 8))
            p.move(to: pt(17, 20.5))
            p.addLine(to: pt(17, 3.5))
            p.addCurve(to: pt(17, 13.5), control1: pt(20.8, 5.5), control2: pt(20.8, 11.5))

        case .fast:
            // A stopwatch: its dial, a hand, the crown.
            circle(12, 13.5, 7.5)
            line((12, 13.5), (12, 9.5))
            line((12, 13.5), (14.8, 15.2))
            line((10, 3.5), (14, 3.5))
            line((12, 3.5), (12, 6))

        case .mood:
            // A face, smiling a little.
            circle(12, 12, 8.5)
            circle(9.2, 10, 0.4)
            circle(14.8, 10, 0.4)
            p.move(to: pt(8.6, 14.2))
            p.addQuadCurve(to: pt(15.4, 14.2), control: pt(12, 17.4))

        case .weight:
            // A bathroom scale with its dial.
            p.addRoundedRect(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17), cornerSize: CGSize(width: 4.5, height: 4.5))
            p.move(to: pt(8.2, 9.8))
            p.addQuadCurve(to: pt(15.8, 9.8), control: pt(12, 5.6))
            line((12, 10.5), (13.6, 8.1))

        case .height:
            // A ruler standing up, its marks.
            p.addRoundedRect(in: CGRect(x: 8, y: 3, width: 8, height: 18), cornerSize: CGSize(width: 1.6, height: 1.6))
            line((8, 7), (11, 7))
            line((8, 10.5), (10, 10.5))
            line((8, 14), (11, 14))
            line((8, 17.5), (10, 17.5))

        case .breathe:
            // Three strokes of wind, two curling.
            p.move(to: pt(3, 9))
            p.addLine(to: pt(15, 9))
            p.addCurve(to: pt(15.5, 4), control1: pt(18.6, 9), control2: pt(18.6, 4))
            p.move(to: pt(3, 13))
            p.addLine(to: pt(19, 13))
            p.move(to: pt(3, 17))
            p.addLine(to: pt(12.5, 17))
            p.addCurve(to: pt(13, 21.2), control1: pt(15.6, 17), control2: pt(15.6, 21.2))

        case .sauna:
            // Heat rising off a bench.
            line((3.5, 20), (20.5, 20))
            for x in [7.0, 12, 17] {
                p.move(to: pt(x, 16.5))
                p.addCurve(to: pt(x, 10.5), control1: pt(x - 2.2, 14.5), control2: pt(x + 2.2, 12.5))
                p.addCurve(to: pt(x, 4.5), control1: pt(x - 2.2, 8.5), control2: pt(x + 2.2, 6.5))
            }

        case .cold:
            // A snowflake: three strokes through its centre, a chevron at each end.
            for angle in stride(from: 0.0, to: 180, by: 60) {
                let a = angle * .pi / 180
                let dx = cos(a) * 8.5, dy = sin(a) * 8.5
                line((12 - dx, 12 - dy), (12 + dx, 12 + dy))
                for end in [1.0, -1.0] {
                    // A V on the stroke, opening outward.
                    let out = a + (end > 0 ? 0 : .pi)
                    let vertex = pt(12 + cos(out) * 5.2, 12 + sin(out) * 5.2)
                    for turn in [0.8, -0.8] {
                        p.move(to: vertex)
                        p.addLine(to: pt(vertex.x + cos(out + turn) * 2.8, vertex.y + sin(out + turn) * 2.8))
                    }
                }
            }

        case .evening:
            // The crescent, a small star beside it.
            p.addPath(SomaAspectGlyphShape.crescent.applying(
                CGAffineTransform(translationX: 0.6, y: 2.4).scaledBy(x: 0.86, y: 0.86)))
            circle(18.6, 5.2, 0.9)

        case .wake:
            // The sun clearing the horizon.
            p.addPath(SomaMindGlyphShape.outline(.forecast))

        case .supplement:
            // A capsule on the slant, its seam across.
            let capsule = Path(roundedRect: CGRect(x: 8.3, y: 3, width: 7.4, height: 18), cornerRadius: 3.7)
            let turn = CGAffineTransform(translationX: 12, y: 12).rotated(by: .pi / 4).translatedBy(x: -12, y: -12)
            p.addPath(capsule.applying(turn))
            var seam = Path()
            seam.move(to: pt(8.3, 12))
            seam.addLine(to: pt(15.7, 12))
            p.addPath(seam.applying(turn))

        case .scan:
            // A viewfinder's corners round a face's oval.
            line((3.5, 8), (3.5, 3.5), (8, 3.5))
            line((16, 3.5), (20.5, 3.5), (20.5, 8))
            line((20.5, 16), (20.5, 20.5), (16, 20.5))
            line((8, 20.5), (3.5, 20.5), (3.5, 16))
            p.addEllipse(in: CGRect(x: 8.5, y: 7.5, width: 7, height: 9))

        case .bloodTest:
            // A drop, a highlight inside it.
            p.move(to: pt(12, 3.5))
            p.addCurve(to: pt(18, 14.5), control1: pt(14, 7), control2: pt(18, 10.5))
            p.addCurve(to: pt(12, 20.5), control1: pt(18, 17.8), control2: pt(15.3, 20.5))
            p.addCurve(to: pt(6, 14.5), control1: pt(8.7, 20.5), control2: pt(6, 17.8))
            p.addCurve(to: pt(12, 3.5), control1: pt(6, 10.5), control2: pt(10, 7))
            p.move(to: pt(9.2, 14.8))
            p.addQuadCurve(to: pt(11.5, 17.6), control: pt(9.4, 17.2))

        case .alcohol:
            // A wine glass, the wine in it.
            p.move(to: pt(7, 3.5))
            p.addLine(to: pt(17, 3.5))
            p.addCurve(to: pt(12, 13), control1: pt(17.6, 9), control2: pt(15.5, 13))
            p.addCurve(to: pt(7, 3.5), control1: pt(8.5, 13), control2: pt(6.4, 9))
            line((7.4, 7.5), (16.6, 7.5))
            line((12, 13), (12, 20))
            line((8.5, 20), (15.5, 20))

        case .training:
            // A kettlebell.
            circle(12, 14.5, 6)
            p.move(to: pt(8.4, 9.8))
            p.addCurve(to: pt(15.6, 9.8), control1: pt(6.6, 2.8), control2: pt(17.4, 2.8))

        case .screens:
            // A phone.
            p.addRoundedRect(in: CGRect(x: 7, y: 3, width: 10, height: 18), cornerSize: CGSize(width: 2.6, height: 2.6))
            line((10.5, 17.6), (13.5, 17.6))

        case .meditation:
            // The lotus Mind wears.
            p.addPath(SomaAspectGlyphShape.lotus)

        case .travel:
            // A suitcase.
            p.addRoundedRect(in: CGRect(x: 3.5, y: 8, width: 17, height: 12), cornerSize: CGSize(width: 2.6, height: 2.6))
            line((9, 8), (9, 5.2), (15, 5.2), (15, 8))
            line((7.5, 8), (7.5, 20))
            line((16.5, 8), (16.5, 20))

        case .nap:
            // Two letters z, the second smaller and higher.
            line((4, 10), (11.5, 10), (4, 19), (11.5, 19))
            line((14, 4.5), (19.5, 4.5), (14, 10.5), (19.5, 10.5))

        case .tag:
            // A tag with its hole.
            line((4, 4), (11.5, 4), (20, 12.5), (12.5, 20), (4, 11.5))
            p.closeSubpath()
            circle(8.3, 8.3, 1.4)

        case .sleep:
            p.addPath(SomaAspectGlyphShape.crescent)

        case .steps, .walk:
            p.addPath(SomaAspectGlyphShape.route)

        case .daylight:
            // A sun and its eight rays.
            circle(12, 12, 4)
            for index in 0..<8 {
                let a = Double(index) * .pi / 4
                line((12 + cos(a) * 6.6, 12 + sin(a) * 6.6), (12 + cos(a) * 8.9, 12 + sin(a) * 8.9))
            }

        case .exercise:
            // A ring nearly closed, the way a day's minutes fill it, an arrow
            // at its start.
            let ring = (0...40).map { step -> CGPoint in
                let angle = (-90 + 300 * Double(step) / 40) * .pi / 180
                return pt(12 + cos(angle) * 8, 12.5 + sin(angle) * 8)
            }
            p.addLines(ring)
            line((10.2, 2.4), (12.4, 4.5), (10.2, 6.6))

        case .hrv:
            p.addPath(SomaMindGlyphShape.outline(.hrv))

        case .stretch:
            p.addPath(SomaAspectGlyphShape.figure)

        case .read:
            // An open book.
            line((12, 6.5), (3.5, 4.5), (3.5, 18), (12, 20), (20.5, 18), (20.5, 4.5), (12, 6.5))
            line((12, 6.5), (12, 20))

        case .journal:
            // A pencil on the slant.
            line((4.5, 19.5), (5.6, 14.6), (15.8, 4.4), (19.6, 8.2), (9.4, 18.4))
            p.closeSubpath()
            line((13.8, 6.4), (17.6, 10.2))

        case .cloud:
            // A cloud, rain under it.
            p.move(to: pt(7, 15))
            p.addCurve(to: pt(7.4, 8.2), control1: pt(3, 15), control2: pt(3.4, 8.6))
            p.addCurve(to: pt(16.4, 7.4), control1: pt(8.6, 3.6), control2: pt(14.8, 3.6))
            p.addCurve(to: pt(17, 15), control1: pt(21, 7.4), control2: pt(21, 15))
            p.closeSubpath()
            line((9, 18), (8.2, 20.4))
            line((13, 18), (12.2, 20.4))

        case .more:
            circle(6, 12, 0.6)
            circle(12, 12, 0.6)
            circle(18, 12, 0.6)

        case .less:
            line((6, 15), (12, 9), (18, 15))
        }
        return p
    }
}

#Preview("Track glyphs") {
    ZStack {
        SomaPreviewBackdrop()
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
            ForEach(Array(SomaTrackGlyph.Kind.allCases.enumerated()), id: \.element) { index, kind in
                SomaTrackGlyph(kind, tone: SomaTrackTone.allCases[index % SomaTrackTone.allCases.count], style: .badge)
            }
        }
        .padding()
    }
}
