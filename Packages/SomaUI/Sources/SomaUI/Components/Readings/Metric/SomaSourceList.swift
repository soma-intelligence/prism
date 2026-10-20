//
//  SomaSourceList.swift
//  SomaUI
//

import SwiftUI

/// One app or device behind a metric's readings.
public struct SomaSource: Identifiable, Equatable, Sendable {
    public var id: String { name + "|" + (symbol ?? "") }
    public var name: String
    /// An SF Symbol for a known kind of device (a watch, a phone, a scale);
    /// nil draws the name's first letter instead.
    public var symbol: String?
    /// Its share of the readings, 0 to 1.
    public var share: Double
    /// A word on how much weight its readings bear: "Measured", "Estimated".
    public var quality: String?

    public init(name: String, symbol: String? = nil, share: Double, quality: String? = nil) {
        self.name = name
        self.symbol = symbol
        self.share = share
        self.quality = quality
    }
}

/// Where a metric's readings came from, as quiet rows on one card: a small
/// disc with the device's glyph or initial, the name with a word on its
/// quality under it, and its share of the readings as a thin bar and a
/// percentage. A footer (all the readings, say) can close the card.
///
/// The share bars grow in once when the list arrives; under Reduce Motion
/// they are simply at their length.
public struct SomaSourceList<Footer: View>: View {
    private let sources: [SomaSource]
    private let footer: Footer

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    public init(_ sources: [SomaSource], @ViewBuilder footer: () -> Footer) {
        self.sources = sources
        self.footer = footer()
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        VStack(spacing: 0) {
            ForEach(sources) { source in
                row(source)
                hairline
            }
            footer
        }
        .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        .onAppear {
            if reduceMotion { isDrawn = true } else { withAnimation(theme.motion.chartDraw) { isDrawn = true } }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
            .frame(height: 0.5)
            .padding(.leading, theme.metrics.cardPadding + theme.metrics.sourceGlyphDisc + theme.metrics.browseRowSpacing)
    }

    private func row(_ source: SomaSource) -> some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let share = min(1, max(0, source.share))
        let percent = share.formatted(.percent.precision(.fractionLength(0)))

        return HStack(spacing: metrics.browseRowSpacing) {
            ZStack {
                Circle().fill(colors.surfaceRecessed.color)
                if let symbol = source.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.sourceGlyphSize, weight: .regular))
                        .foregroundStyle(colors.inkSecondary.color)
                } else {
                    Text(source.name.prefix(1).uppercased())
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            .frame(width: metrics.sourceGlyphDisc, height: metrics.sourceGlyphDisc)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: metrics.metricFactSpacing) {
                Text(source.name)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                if let quality = source.quality {
                    Text(quality)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            Spacer(minLength: metrics.browseRowSpacing)
            Capsule()
                .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                .frame(width: metrics.sourceShareWidth, height: metrics.sourceShareHeight)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(colors.inkSecondary.color)
                        .frame(width: max(metrics.sourceShareHeight, metrics.sourceShareWidth * share), height: metrics.sourceShareHeight)
                        .scaleEffect(x: isDrawn ? 1 : 0, anchor: .leading)
                }
                .accessibilityHidden(true)
            Text(percent)
                .somaFont(theme.typography.captionValue)
                .foregroundStyle(colors.inkSecondary.color)
                .frame(minWidth: metrics.sourceShareWidth * 0.75, alignment: .trailing)
        }
        .padding(.horizontal, metrics.cardPadding)
        .padding(.vertical, metrics.browseRowVerticalPadding * 1.5)
        .frame(minHeight: metrics.browseRowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

public extension SomaSourceList where Footer == EmptyView {
    init(_ sources: [SomaSource]) {
        self.init(sources) { EmptyView() }
    }
}

#Preview("Sources") {
    SomaSourceList([
        SomaSource(name: "Apple Watch", symbol: "applewatch", share: 0.82, quality: "Measured"),
        SomaSource(name: "iPhone", symbol: "iphone", share: 0.16, quality: "Estimated"),
        SomaSource(name: "Oura", share: 0.02, quality: "Measured"),
    ])
    .padding()
}
