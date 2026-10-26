//
//  SomaLitSurface.swift
//  SomaUI
//

import SwiftUI

/// A card's ground lit from above (owner, 2026-10-25):
/// light falls from above, so the top of the card sits a breath lighter than
/// its foot and its top edge catches a thin rim that fades down the sides.
/// No shadow and no glow: the card still sits flat on the page.
///
/// In light mode the light is already there, so the card keeps its flat white
/// and the single hairline.
public struct SomaLitSurface: ViewModifier {
    private let cornerRadius: CGFloat?

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameter cornerRadius: the card's radius; the theme's card radius
    ///   when nil.
    public init(cornerRadius: CGFloat? = nil) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let metrics = theme.metrics
        let surface = theme.colors.surface.color
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? metrics.cardCornerRadius, style: .continuous)
        let dark = colorScheme == .dark

        content
            .background(
                shape.fill(dark
                    ? AnyShapeStyle(LinearGradient(
                        colors: [surface.mix(with: .white, by: metrics.surfaceLightLift), surface],
                        startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(surface))
            )
            .overlay(
                shape.strokeBorder(
                    dark
                        ? AnyShapeStyle(LinearGradient(
                            stops: [.init(color: .white.opacity(metrics.surfaceRimOpacity), location: 0),
                                    .init(color: .white.opacity(metrics.hairlineOpacity), location: 0.45)],
                            startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity)),
                    lineWidth: metrics.surfaceRimWidth
                )
            )
    }
}

public extension View {
    /// The card ground with a light from above. See ``SomaLitSurface``.
    func somaLitSurface(cornerRadius: CGFloat? = nil) -> some View {
        modifier(SomaLitSurface(cornerRadius: cornerRadius))
    }
}

public extension SomaMetrics {
    /// How much white the top of a dark card takes.
    var surfaceLightLift: Double { 0.045 }
    /// The rim's opacity at the card's top edge.
    var surfaceRimOpacity: Double { 0.16 }
    /// The rim's width.
    var surfaceRimWidth: CGFloat { 0.75 }
}
