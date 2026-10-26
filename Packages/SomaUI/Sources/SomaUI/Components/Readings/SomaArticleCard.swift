//
//  SomaArticleCard.swift
//  SomaUI
//

import SwiftUI

/// One article in the library: its cover, then as few words as will do.
///
/// The featured style is Apple Health's story card: a large cover, a dot in
/// the topic's tone beside its name, a bold title and one line under it. The
/// tile is the same card at grid size: cover, title, reading time. The row
/// sets a small square cover beside the words, for a short list.
///
/// A card picked for the person carries a `reason`, a few words on why it is
/// there ("Because your sleep was short this week"); it takes the place of
/// the topic line, led by the tone's dot, so the card does not grow.
///
/// The card draws no button of its own; the caller wraps it in the link that
/// opens the reader. A caller that zooms the reader out of the cover passes
/// `coverID`, and marks it with `coverModifier`.
public struct SomaArticleCard<CoverStyle: ViewModifier>: View {
    public typealias Style = SomaArticleCardStyle

    private let title: String
    private let subtitle: String?
    private let topic: String
    private let caption: String
    private let reason: String?
    private let tone: SomaTrackTone
    private let mark: SomaArticleCover.Mark
    private let seed: String
    private let imageURL: URL?
    private let asset: String?
    private let style: Style
    private let coverStyle: CoverStyle

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - title: the article's title.
    ///   - subtitle: its one line, shown on the featured card only.
    ///   - topic: the topic's name, set beside the tone's dot.
    ///   - caption: the reading time, "4 min".
    ///   - reason: why this card was picked for the person, when it was.
    ///   - tone, mark, seed, imageURL, asset: what ``SomaArticleCover`` draws.
    ///   - coverStyle: applied to the cover alone, for a zoom source say.
    public init(title: String, subtitle: String? = nil, topic: String, caption: String, reason: String? = nil,
                tone: SomaTrackTone, mark: SomaArticleCover.Mark, seed: String, imageURL: URL? = nil,
                asset: String? = nil, style: Style, coverStyle: CoverStyle) {
        self.title = title
        self.subtitle = subtitle
        self.topic = topic
        self.caption = caption
        self.reason = reason
        self.tone = tone
        self.mark = mark
        self.seed = seed
        self.imageURL = imageURL
        self.asset = asset
        self.style = style
        self.coverStyle = coverStyle
    }

    public var body: some View {
        Group {
            switch style {
            case .feature: feature
            case .tile: tile
            case .row: row
            }
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func cover(_ size: SomaArticleCover.Size) -> some View {
        SomaArticleCover(tone: tone, mark: mark, seed: seed, imageURL: imageURL, asset: asset, size: size)
            .modifier(coverStyle)
    }

    private var feature: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        return VStack(alignment: .leading, spacing: metrics.articleTextSpacing) {
            cover(.feature)
                .padding(.bottom, metrics.cardSpacing - metrics.articleTextSpacing)
            if let reason {
                ReasonLine(reason: reason, tone: tone)
            } else {
                HStack(spacing: metrics.articleChipDot * 0.75) {
                    ToneDot(tone: tone)
                    Text("\(topic) · \(caption)")
                        .somaFont(type.eyebrow)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            Text(title)
                .somaFont(type.articleFeatureTitle)
                .foregroundStyle(colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tile: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        return VStack(alignment: .leading, spacing: metrics.articleTextSpacing) {
            cover(.tile)
                .padding(.bottom, metrics.cardSpacing - metrics.articleTextSpacing)
            Text(title)
                .somaFont(type.articleTileTitle)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(2, reservesSpace: true)
            Text(caption)
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var row: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        return HStack(alignment: .center, spacing: metrics.cardSpacing + metrics.articleTextSpacing) {
            cover(.row)
            VStack(alignment: .leading, spacing: metrics.articleTextSpacing) {
                if let reason {
                    ReasonLine(reason: reason, tone: tone)
                }
                Text(title)
                    .somaFont(type.articleTileTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason == nil ? "\(topic) · \(caption)" : caption)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How an article card is laid out.
public enum SomaArticleCardStyle: Sendable {
    /// A large cover, the topic or the reason, the title and one line.
    case feature
    /// A grid or shelf tile: cover, title, reading time.
    case tile
    /// A small square cover beside the words.
    case row
}

public extension SomaArticleCard where CoverStyle == EmptyModifier {
    init(title: String, subtitle: String? = nil, topic: String, caption: String, reason: String? = nil,
         tone: SomaTrackTone, mark: SomaArticleCover.Mark, seed: String, imageURL: URL? = nil,
         asset: String? = nil, style: Style) {
        self.init(title: title, subtitle: subtitle, topic: topic, caption: caption, reason: reason, tone: tone,
                  mark: mark, seed: seed, imageURL: imageURL, asset: asset, style: style, coverStyle: EmptyModifier())
    }
}

/// Why a card was picked: the tone's dot, then the reason in a small
/// secondary line.
private struct ReasonLine: View {
    let reason: String
    let tone: SomaTrackTone

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.articleChipDot * 0.75) {
            ToneDot(tone: tone)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(reason)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .lineLimit(1)
        }
    }
}

private struct ToneDot: View {
    let tone: SomaTrackTone

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: theme.metrics.articleChipDot, height: theme.metrics.articleChipDot)
    }
}

#Preview("Article cards") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            SomaArticleCard(title: "Why a steady bedtime matters", subtitle: "Regular nights, steadier days.",
                            topic: "Sleep", caption: "4 min", reason: "Because your sleep was short this week",
                            tone: .dusk, mark: .aspect(.sleep), seed: "sleep-regularity", style: .feature)
            SomaArticleCard(title: "Reading your resting heart rate", topic: "Heart", caption: "3 min",
                            reason: "Because your resting heart rate is up", tone: .rose, mark: .aspect(.heart),
                            seed: "resting-heart-rate", style: .row)
            HStack(alignment: .top, spacing: 14) {
                SomaArticleCard(title: "Reading your resting heart rate", topic: "Heart", caption: "3 min",
                                tone: .rose, mark: .aspect(.heart), seed: "resting-heart-rate", style: .tile)
                SomaArticleCard(title: "Zone 2, the easy pace that builds", topic: "Movement", caption: "4 min",
                                tone: .moss, mark: .aspect(.activity), seed: "zone-2", style: .tile)
            }
        }
        .padding()
    }
}
