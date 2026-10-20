//
//  SomaMindGlyph.swift
//  SomaUI
//

import SwiftUI

/// The pages further into Mind as line glyphs drawn like the aspect glyphs
/// (``SomaAspectGlyph``): the same 24 unit grid, the same round stroke, the
/// same tinted badge, so the grid of deeper pages reads as one family with
/// the aspects rather than a row of borrowed symbols.
public struct SomaMindGlyph: View {
    /// A page further into Mind.
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        /// Heart rate variability: a beat across a line.
        case hrv
        /// The stress radar: two rings and a sweep.
        case radar
        /// The mood forecast: a sun rising over the horizon.
        case forecast
        /// The inner map: three circles that overlap.
        case innerMap
        /// The Mind score: a ring nearly closed.
        case score
        /// Insights by weekday and hour: a grid of cells.
        case insights
        /// Meetings: a page of the calendar.
        case meetings
        /// Habits: a sprout.
        case habits

        public var id: String { rawValue }
    }

    /// How the glyph is set, as for the aspect glyphs.
    public enum Style: Sendable {
        case inline
        case badge
    }

    private let kind: Kind
    private let style: Style

    @Environment(\.somaTheme) private var theme

    public init(_ kind: Kind, style: Style = .badge) {
        self.kind = kind
        self.style = style
    }

    public var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[.mind].identity.color

        Group {
            switch style {
            case .inline:
                glyph(side: metrics.aspectGlyphInline, hue: hue)
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
        return SomaMindGlyphShape(kind: kind)
            .stroke(hue, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side)
    }
}

/// The outline of one Mind glyph on the 24 unit grid, fitted to the largest
/// square the rect holds.
public struct SomaMindGlyphShape: Shape {
    public let kind: SomaMindGlyph.Kind

    public init(kind: SomaMindGlyph.Kind) {
        self.kind = kind
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let placement = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.outline(kind).applying(placement)
    }

    static func outline(_ kind: SomaMindGlyph.Kind) -> Path {
        var path = Path()
        switch kind {
        case .hrv:
            path.move(to: CGPoint(x: 3, y: 13))
            path.addLine(to: CGPoint(x: 7.2, y: 13))
            path.addLine(to: CGPoint(x: 9.2, y: 8))
            path.addLine(to: CGPoint(x: 12.2, y: 17.5))
            path.addLine(to: CGPoint(x: 14.6, y: 9.5))
            path.addLine(to: CGPoint(x: 16.4, y: 13))
            path.addLine(to: CGPoint(x: 21, y: 13))
        case .radar:
            path.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            path.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
            path.move(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 18, y: 6))
        case .forecast:
            path.move(to: CGPoint(x: 3.5, y: 17.5))
            path.addLine(to: CGPoint(x: 20.5, y: 17.5))
            path.addArc(center: CGPoint(x: 12, y: 17.5), radius: 5, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            path.move(to: CGPoint(x: 12, y: 6.5))
            path.addLine(to: CGPoint(x: 12, y: 8.5))
            path.move(to: CGPoint(x: 5.3, y: 10.8))
            path.addLine(to: CGPoint(x: 6.7, y: 12.2))
            path.move(to: CGPoint(x: 18.7, y: 10.8))
            path.addLine(to: CGPoint(x: 17.3, y: 12.2))
        case .innerMap:
            path.addEllipse(in: CGRect(x: 7.4, y: 3.6, width: 9.2, height: 9.2))
            path.addEllipse(in: CGRect(x: 3.6, y: 10.2, width: 9.2, height: 9.2))
            path.addEllipse(in: CGRect(x: 11.2, y: 10.2, width: 9.2, height: 9.2))
        case .score:
            path.addArc(center: CGPoint(x: 12, y: 12), radius: 8.2, startAngle: .degrees(-90), endAngle: .degrees(210), clockwise: false)
            path.addEllipse(in: CGRect(x: 10.6, y: 10.6, width: 2.8, height: 2.8))
        case .insights:
            for row in 0..<3 {
                for column in 0..<3 {
                    let cell = CGRect(x: 4 + Double(column) * 6, y: 4 + Double(row) * 6, width: 4, height: 4)
                    path.addRoundedRect(in: cell, cornerSize: CGSize(width: 1.2, height: 1.2))
                }
            }
        case .meetings:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 5.5, width: 17, height: 15), cornerSize: CGSize(width: 3, height: 3))
            path.move(to: CGPoint(x: 3.5, y: 10))
            path.addLine(to: CGPoint(x: 20.5, y: 10))
            path.move(to: CGPoint(x: 8, y: 3.5))
            path.addLine(to: CGPoint(x: 8, y: 7))
            path.move(to: CGPoint(x: 16, y: 3.5))
            path.addLine(to: CGPoint(x: 16, y: 7))
            path.addEllipse(in: CGRect(x: 13.4, y: 13.4, width: 3.2, height: 3.2))
        case .habits:
            path.move(to: CGPoint(x: 12, y: 20.5))
            path.addLine(to: CGPoint(x: 12, y: 10.5))
            path.move(to: CGPoint(x: 12, y: 14))
            path.addQuadCurve(to: CGPoint(x: 5, y: 9), control: CGPoint(x: 5.2, y: 14.6))
            path.addQuadCurve(to: CGPoint(x: 12, y: 14), control: CGPoint(x: 10.8, y: 8.2))
            path.move(to: CGPoint(x: 12, y: 10.5))
            path.addQuadCurve(to: CGPoint(x: 19, y: 4.5), control: CGPoint(x: 12.4, y: 4.2))
            path.addQuadCurve(to: CGPoint(x: 12, y: 10.5), control: CGPoint(x: 19.2, y: 10.4))
        }
        return path
    }
}

#Preview("Mind glyphs") {
    ZStack {
        SomaPreviewBackdrop()
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(SomaMindGlyph.Kind.allCases) { SomaMindGlyph($0) }
        }
        .padding()
    }
}
