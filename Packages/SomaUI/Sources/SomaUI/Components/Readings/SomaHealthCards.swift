//
//  SomaHealthCards.swift
//  SomaUI
//

import SwiftUI

/// One Health category as Apple Health's iOS 27 Browse draws it: a tall
/// rounded tile in the category's gradient, its glyph and its name in dark ink
/// at the leading edge.
public struct SomaCategoryTile: View {
    private let symbol: String
    private let title: LocalizedStringResource
    private let hue: SomaHealthHue

    @Environment(\.somaTheme) private var theme

    public init(symbol: String, title: LocalizedStringResource, hue: SomaHealthHue) {
        self.symbol = symbol
        self.title = title
        self.hue = hue
    }

    public var body: some View {
        let metrics = theme.metrics

        // As Apple Health's dark Browse: a plain card, the glyph in the
        // category's colour, the name in bold ink.
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Image(systemName: symbol)
                .font(.system(size: metrics.healthTileGlyph * 1.15, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [hue.start.color, hue.end.color], startPoint: .top, endPoint: .bottom))
                .frame(height: metrics.healthTileGlyph * 1.4, alignment: .leading)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(title)
                .somaFont(theme.typography.headline)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(metrics.cardPadding + 4)
        .frame(maxWidth: .infinity, minHeight: metrics.healthTileHeight, alignment: .topLeading)
        .background(theme.colors.surface.color, in: .rect(cornerRadius: metrics.healthCardRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: metrics.healthCardRadius, style: .continuous))
    }
}

/// A data type's last seven days as Apple Health's category page shows them:
/// the name in the category's hue with the date of the latest reading and a
/// chevron, the value large at the foot, and seven small bars at the trailing
/// edge, the last one in the hue.
public struct SomaHealthSummaryCard: View {
    private let symbol: String
    private let title: LocalizedStringResource
    private let hue: SomaHealthHue
    private let date: String?
    private let caption: String?
    private let value: String?
    private let unit: String?
    private let bars: [Double?]

    @Environment(\.somaTheme) private var theme

    public init(
        symbol: String,
        title: LocalizedStringResource,
        hue: SomaHealthHue,
        date: String?,
        caption: String? = nil,
        value: String?,
        unit: String?,
        bars: [Double?]
    ) {
        self.symbol = symbol
        self.title = title
        self.hue = hue
        self.date = date
        self.caption = caption
        self.value = value
        self.unit = unit
        self.bars = bars
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: metrics.cardSpacing)
                if let date {
                    Text(date)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(colors.inkSecondary.color)
                    .accessibilityHidden(true)
            }
            .somaFont(theme.typography.cardTitle)
            .fontWeight(.semibold)
            .foregroundStyle(hue.color)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let caption {
                        Text(caption)
                            .somaFont(theme.typography.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value ?? "-")
                            .somaFont(theme.typography.metric)
                            .foregroundStyle(colors.inkPrimary.color)
                        if let unit, value != nil {
                            Text(unit)
                                .somaFont(theme.typography.callout)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                    }
                }
                Spacer(minLength: metrics.cardSpacing)
                SomaWeekBars(bars, hue: hue)
                    .frame(width: metrics.healthBarsWidth, height: metrics.healthBarsHeight)
            }
            .padding(.top, metrics.cardSpacing * 2)
        }
        .padding(metrics.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface.color, in: .rect(cornerRadius: metrics.healthCardRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: metrics.healthCardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Seven small bars, the last one in the hue and the rest in quiet grey. A day
/// with nothing draws no bar.
public struct SomaWeekBars: View {
    private let values: [Double?]
    private let hue: SomaHealthHue

    @Environment(\.somaTheme) private var theme

    public init(_ values: [Double?], hue: SomaHealthHue) {
        self.values = values
        self.hue = hue
    }

    public var body: some View {
        let known = values.compactMap { $0 }
        let high = max(known.max() ?? 1, 0.0001)
        // Below the lowest bar by as much again as the bars spread, so a heart
        // rate between 60 and 70 still reads as seven different heights.
        let spread = high - (known.min() ?? 0)
        let low = max(0, (known.min() ?? 0) - max(spread, high * 0.05))
        let grey = theme.colors.inkSecondary.color.opacity(0.45)

        GeometryReader { proxy in
            let count = max(values.count, 1)
            let gap = proxy.size.width * 0.06
            let width = (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let share = value.map { CGFloat(($0 - low) / (high - low)) } ?? 0
                    RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                        .fill(index == values.count - 1 ? hue.color : grey)
                        .frame(width: width, height: value == nil ? 0 : max(proxy.size.height * share, width * 0.6))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Health cards") {
    ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(SomaHealthHue.allCases, id: \.self) { hue in
                        SomaCategoryTile(symbol: "heart.fill", title: "Heart", hue: hue)
                    }
                }
                SomaHealthSummaryCard(
                    symbol: "sun.max.fill", title: "Time In Daylight", hue: .hearing,
                    date: "Sep 26", value: "85.4", unit: "min", bars: [20, 35, 22, 80, 30, 18, 60]
                )
            }
            .padding(16)
        }
    }
}
