//
//  SomaNotificationGlyph.swift
//  SomaUI
//

import SwiftUI

/// The notifications glyph of the top bar: a bell written on the aspect
/// glyphs' 24 unit grid with their round stroke, so it sits beside the six of
/// them as one more of the family rather than a symbol from elsewhere.
///
/// A round dome flaring to its foot, a short stem on the crown, a lip a little
/// wider than the foot, and the clapper as a dot beneath. When something is
/// unread, a dot in the accent sits off the bell's upper trailing shoulder,
/// and the stroke opens around it, so the two never touch.
public struct SomaNotificationGlyph: View {
    private let hasUnread: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(hasUnread: Bool) {
        self.hasUnread = hasUnread
    }

    public var body: some View {
        let metrics = theme.metrics
        let side = metrics.notificationGlyphArt
        let unit = side / metrics.aspectGlyphGrid
        let dot = SomaNotificationGlyphShape.unreadDot

        ZStack {
            SomaNotificationGlyphShape()
                .stroke(
                    theme.colors.inkPrimary.color,
                    style: StrokeStyle(lineWidth: metrics.notificationGlyphStroke * unit, lineCap: .round, lineJoin: .round)
                )
                .mask {
                    // The bell opens around the dot rather than running under it.
                    SomaNotificationKnockout(isOpen: hasUnread)
                }

            if hasUnread {
                Circle()
                    .fill(theme.colors.accent.color)
                    .frame(width: dot.radius * 2 * unit, height: dot.radius * 2 * unit)
                    .position(x: dot.centre.x * unit, y: dot.centre.y * unit)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: side, height: side)
        // Laid out in the system glyph's square, drawn a little past it.
        .frame(width: metrics.notificationGlyph, height: metrics.notificationGlyph)
        .animation(reduceMotion ? nil : theme.motion.selection, value: hasUnread)
        .accessibilityHidden(true)
    }
}

/// Everything but a disc round the unread dot, a gap wider than the dot itself.
private struct SomaNotificationKnockout: View {
    let isOpen: Bool

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 24
            let dot = SomaNotificationGlyphShape.unreadDot
            let reach = (dot.radius + SomaNotificationGlyphShape.unreadGap) * unit
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                if isOpen {
                    path.addEllipse(in: CGRect(
                        x: dot.centre.x * unit - reach,
                        y: dot.centre.y * unit - reach,
                        width: reach * 2,
                        height: reach * 2
                    ))
                }
            }
            .fill(style: FillStyle(eoFill: true))
        }
    }
}

/// The bell's outline on a 24 unit grid, fitted to the largest square the
/// rect holds.
public struct SomaNotificationGlyphShape: Shape {
    public init() {}

    /// Where the unread dot sits on the grid, and how big it is.
    public static let unreadDot = (centre: CGPoint(x: 19.2, y: 4.8), radius: 2.6)
    /// The open ring of grid between the dot and the bell's stroke.
    public static let unreadGap: CGFloat = 1.3

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let placement = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.bell.applying(placement)
    }

    /// The dome rising from a flared foot to a round crown with a short
    /// stem, the lip across its mouth, and the clapper as a dot below.
    static var bell: Path {
        var path = Path()
        // The dome, from the foot on the leading side over the crown.
        path.move(to: CGPoint(x: 4.9, y: 16.6))
        path.addCurve(to: CGPoint(x: 6.9, y: 11.4), control1: CGPoint(x: 6.2, y: 15.6), control2: CGPoint(x: 6.9, y: 13.8))
        path.addCurve(to: CGPoint(x: 12, y: 5.2), control1: CGPoint(x: 6.9, y: 7.8), control2: CGPoint(x: 9.2, y: 5.2))
        path.addCurve(to: CGPoint(x: 17.1, y: 11.4), control1: CGPoint(x: 14.8, y: 5.2), control2: CGPoint(x: 17.1, y: 7.8))
        path.addCurve(to: CGPoint(x: 19.1, y: 16.6), control1: CGPoint(x: 17.1, y: 13.8), control2: CGPoint(x: 17.8, y: 15.6))
        // The stem on the crown.
        path.move(to: CGPoint(x: 12, y: 5.2))
        path.addLine(to: CGPoint(x: 12, y: 3.6))
        // The lip, a little wider than the foot.
        path.move(to: CGPoint(x: 4.0, y: 16.6))
        path.addLine(to: CGPoint(x: 20.0, y: 16.6))
        // The clapper: a stub so short its round caps make it a dot.
        path.move(to: CGPoint(x: 11.6, y: 19.6))
        path.addLine(to: CGPoint(x: 12.4, y: 19.6))
        return path
    }
}

#Preview("Notification glyph") {
    ZStack {
        SomaPreviewBackdrop()
        HStack(spacing: 32) {
            SomaNotificationGlyph(hasUnread: false)
            SomaNotificationGlyph(hasUnread: true)
        }
    }
}
