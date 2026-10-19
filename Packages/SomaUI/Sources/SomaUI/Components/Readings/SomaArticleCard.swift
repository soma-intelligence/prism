//
//  SomaArticleCard.swift
//  SomaUI
//

import SwiftUI

/// One article in the library: its cover, then as few words as will do.
///
/// The featured style is Apple Health's story card: a large cover, a dot in
/// the topic's hue beside its name, a bold title and one line under it. The
/// tile is the same card at grid size: cover, title, reading time.
/// The card draws no button of its own; the caller wraps it in the link that
/// opens the reader.
public struct SomaArticleCard: View {
    public enum Style: Sendable {
        case feature
        case tile
    }

    private let title: String
    private let subtitle: String?
    private let topic: String
    private let caption: String
    private let hue: SomaHealthHue
    private let symbol: String
    private let seed: String
    private let imageURL: URL?
    private let asset: String?
    private let style: Style

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - title: the article's title.
    ///   - subtitle: its one line, shown on the featured card only.
    ///   - topic: the topic's name, set beside the hue's dot.
    ///   - caption: the reading time, "4 min".
    ///   - hue, symbol, seed, imageURL, asset: what ``SomaArticleCover`` draws.
    public init(title: String, subtitle: String? = nil, topic: String, caption: String,
                hue: SomaHealthHue, symbol: String, seed: String, imageURL: URL? = nil, asset: String? = nil,
                style: Style) {
        self.title = title
        self.subtitle = subtitle
        self.topic = topic
        self.caption = caption
        self.hue = hue
        self.symbol = symbol
        self.seed = seed
        self.imageURL = imageURL
        self.asset = asset
        self.style = style
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.articleTextSpacing) {
            SomaArticleCover(hue: hue, symbol: symbol, seed: seed, imageURL: imageURL, asset: asset,
                             size: style == .feature ? .feature : .tile)
                .padding(.bottom, metrics.cardSpacing - metrics.articleTextSpacing)

            switch style {
            case .feature:
                HStack(spacing: metrics.articleChipDot * 0.75) {
                    Circle()
                        .fill(hue.color)
                        .frame(width: metrics.articleChipDot, height: metrics.articleChipDot)
                    Text("\(topic) · \(caption)")
                        .somaFont(type.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Text(title)
                    .somaFont(type.articleFeatureTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
            case .tile:
                Text(title)
                    .somaFont(type.articleTileTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(2, reservesSpace: true)
                Text(caption)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Article cards") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            SomaArticleCard(title: "Why a steady bedtime matters", subtitle: "Regular nights, steadier days.",
                            topic: "Sleep", caption: "4 min", hue: .sleep, symbol: "moon.stars.fill",
                            seed: "sleep-regularity", style: .feature)
            HStack(alignment: .top, spacing: 14) {
                SomaArticleCard(title: "Reading your resting heart rate", topic: "Heart", caption: "3 min",
                                hue: .heart, symbol: "heart.fill", seed: "resting-heart-rate", style: .tile)
                SomaArticleCard(title: "Zone 2, the easy pace that builds", topic: "Movement", caption: "4 min",
                                hue: .activity, symbol: "figure.run", seed: "zone-2", style: .tile)
            }
        }
        .padding()
    }
}
