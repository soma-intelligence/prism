//
//  SomaCard.swift
//  SomaUI
//

import SwiftUI

/// The standard content container: a surface one tonal step above the canvas
/// and a single hairline.
///
/// Depth comes from the tonal step and a light from above
/// (``SomaLitSurface``). A shadow under every card read as generated, the
/// way Apple Health and the reference design never do: the card sits flat.
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
            .somaLitSurface()
    }
}
