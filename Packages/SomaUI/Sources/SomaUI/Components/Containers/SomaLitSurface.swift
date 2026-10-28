//
//  SomaLitSurface.swift
//  SomaUI
//

import SwiftUI

/// A card's ground: the flat surface and a single rim, in both appearances.
///
/// It was lit from above in dark (owner, 2026-10-25): a gradient fill a breath
/// lighter at the top and a rim fading down the sides. The design pass of
/// 2026-10-27 took the gradients out (flat, one stroke, no gloss), so dark
/// cards keep a slightly brighter rim than light ones, at `surfaceRimOpacity`,
/// and nothing else. The name stays so call sites stay put.
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? metrics.cardCornerRadius, style: .continuous)
        let rim = colorScheme == .dark ? metrics.surfaceRimOpacity : metrics.hairlineOpacity

        content
            .background(shape.fill(theme.colors.surface.color))
            .overlay(
                shape.strokeBorder(theme.colors.inkPrimary.color.opacity(rim), lineWidth: metrics.surfaceRimWidth)
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
    /// The rim's opacity on a dark card, against the ink: a touch above the
    /// hairline, so a card holds its edge on the dark page.
    var surfaceRimOpacity: Double { 0.12 }
    /// The rim's width.
    var surfaceRimWidth: CGFloat { 0.75 }
}
