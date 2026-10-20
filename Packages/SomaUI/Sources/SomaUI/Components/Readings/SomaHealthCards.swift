//
//  SomaHealthCards.swift
//  SomaUI
//

import SwiftUI

/// One Health category in the Vault's grid, set in Soma's language rather
/// than Health's: the category's line glyph on a square softly tinted with
/// its aspect's hue (or a recessed square for the few that belong to no
/// aspect), the name in the ink, and a quiet line under it ("12 measures").
///
/// The glyph stays the category's own, so Heart, Vitals and Respiratory read
/// apart while sharing the heart's tone; the colour is the aspect's, never a
/// saturated gradient.
public struct SomaCategoryTile: View {
    private let symbol: String
    private let title: String
    private let caption: String?
    private let aspect: SomaAspect?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - symbol: an SF Symbol drawn as a line, not filled.
    ///   - aspect: whose tone the badge takes; nil sets it on a recessed
    ///     square in the secondary ink.
    public init(symbol: String, title: String, caption: String? = nil, aspect: SomaAspect?) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self.aspect = aspect
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = aspect.map { theme.aspects[$0].identity.color }

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Image(systemName: symbol)
                .font(.system(size: metrics.aspectBadgeGlyph * 0.82, weight: .regular))
                .foregroundStyle(hue ?? colors.inkSecondary.color)
                .frame(width: metrics.aspectBadgeSide, height: metrics.aspectBadgeSide)
                .background(
                    RoundedRectangle(cornerRadius: metrics.aspectBadgeCornerRadius, style: .continuous)
                        .fill(hue.map { $0.opacity(metrics.aspectBadgeTint) } ?? colors.surfaceRecessed.color)
                )
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: metrics.readingRowLineGap) {
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.healthTileHeight, alignment: .topLeading)
        .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Health cards") {
    ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SomaCategoryTile(symbol: "heart", title: "Heart", caption: "12 measures", aspect: .heart)
                    SomaCategoryTile(symbol: "lungs", title: "Respiratory", caption: "6 measures", aspect: .heart)
                    SomaCategoryTile(symbol: "bed.double", title: "Sleep", caption: "4 measures", aspect: .sleep)
                    SomaCategoryTile(symbol: "ear", title: "Hearing", caption: "5 measures", aspect: nil)
                }
            }
            .padding(16)
        }
    }
}
