//
//  SomaCard.swift
//  SomaUI
//

import SwiftUI

/// The standard content container: a surface one tonal step above the canvas,
/// a single hairline, and a low diffuse shadow.
///
/// Depth comes from the tonal step first: the shadow only settles the card onto
/// the ground, it never announces it.
public struct SomaCard<Content: View>: View {
    private let content: Content

    @Environment(\.somaTheme) private var theme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.metrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous)
                    .fill(theme.colors.surface.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 2, y: 2)
    }
}
