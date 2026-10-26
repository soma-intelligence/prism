//
//  ShareStudio.swift
//  Prism
//

import SwiftUI
import SomaUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pick a card, style it, hand it over as one image.
///
/// The Share studio: cards by category, a skin, a size, a
/// switch for exact numbers, then save, copy or share. Soma's cards are built
/// from today's real scores (``ShareCard/cards(from:sleepClock:)``); a score
/// the store does not hold is not offered. The image is rendered on the device
/// with `ImageRenderer` and handed to the system's own share sheet.
struct ShareStudioPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(\.displayScale) private var displayScale

    @State private var chosen: ShareCard.Kind?
    @State private var style = ShareStyle()
    @State private var isStyling = false
    @State private var copied = false

    private var cards: [ShareCard] {
        ShareCard.cards(from: health.scores, sleepClock: health.today?.sleepCard.value)
    }

    private var card: ShareCard? {
        cards.first { $0.kind == chosen } ?? cards.first
    }

    var body: some View {
        Group {
            if isStyling, let card {
                styleStep(card)
            } else {
                pickStep
            }
        }
        .task { await health.loadToday() }
    }

    // MARK: Pick

    private var pickStep: some View {
        ListScaffold(eyebrow: "Share", title: "Pick a card") {
            if cards.isEmpty {
                NoteCard(
                    title: "Nothing to share yet",
                    message: "Cards are made from today\u{2019}s scores, and Apple Health holds too little for one yet. After a few nights with your watch, they appear here."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.metrics.cardMinWidth * 0.7), spacing: theme.metrics.cardSpacing)],
                          spacing: theme.metrics.cardSpacing) {
                    ForEach(cards) { item in
                        Button { chosen = item.kind } label: {
                            ShareCardFace(card: item, style: ShareStyle())
                                .overlay(
                                    RoundedRectangle(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous)
                                        .strokeBorder(theme.colors.accent.color, lineWidth: (card?.kind == item.kind) ? 2 : 0)
                                )
                        }
                        .buttonStyle(.somaGlassPress)
                        .accessibilityAddTraits(card?.kind == item.kind ? .isSelected : [])
                    }
                }

                primaryButton("Style it") { isStyling = true }
            }
        }
    }

    // MARK: Style

    private func styleStep(_ card: ShareCard) -> some View {
        ListScaffold(eyebrow: "Share \u{00B7} \(card.kind.eyebrow)", title: "Style it") {
            SharePoster(card: card, style: style)
                .frame(maxWidth: theme.metrics.cardMinWidth * 1.1)
                .frame(maxWidth: .infinity)

            SettingsSection("Background") {
                SomaSegmentedControl(
                    segments: ShareStyle.Background.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
                    selection: $style.background
                )
            }

            SettingsSection("Size") {
                SomaSegmentedControl(
                    segments: ShareStyle.Size.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
                    selection: $style.size
                )
            }

            SettingsSection("Show") {
                SomaBrowseGroup([SettingsItem].items("numbers", "date"), hasGlyphs: false) { item in
                    if item.id == "numbers" {
                        SettingsLine("Exact numbers") { SettingsSwitch(title: "Exact numbers", isOn: $style.exactNumbers) }
                    } else {
                        SettingsLine("The date") { SettingsSwitch(title: "The date", isOn: $style.showsDate) }
                    }
                }
            }

            HStack(spacing: theme.metrics.cardSpacing) {
                Button { isStyling = false } label: {
                    actionLabel("Back", symbol: "chevron.left")
                }
                .buttonStyle(.somaGlassPress)

                Button { copy(card) } label: {
                    actionLabel(copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.somaGlassPress)

                if let image = render(card) {
                    ShareLink(
                        item: image,
                        preview: SharePreview(card.kind.eyebrow, image: image)
                    ) {
                        actionLabel("Share", symbol: "square.and.arrow.up", prominent: true)
                    }
                    .buttonStyle(.somaGlassPress)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, symbol: String, prominent: Bool = false) -> some View {
        VStack(spacing: theme.metrics.spaceXS) {
            Image(systemName: symbol)
                .font(.system(size: theme.metrics.browseGlyphSize, weight: .medium))
                .foregroundStyle(prominent ? theme.colors.onAccent.color : theme.colors.inkPrimary.color)
                .frame(width: theme.metrics.iconButtonDiameter * 1.2, height: theme.metrics.iconButtonDiameter * 1.2)
                .background(Circle().fill(prominent ? theme.colors.accent.color : theme.colors.surface.color))
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkPrimary.color)
        }
        .frame(minWidth: theme.metrics.minimumTapTarget * 1.6)
        .contentShape(.rect)
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(theme.colors.onAccent.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
                .background(Capsule().fill(theme.colors.accent.color))
                .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
    }

    // MARK: Rendering

    /// The poster as an image, at the chosen size, rendered on the device.
    private func render(_ card: ShareCard) -> Image? {
        #if canImport(UIKit)
        guard let image = renderer(card).uiImage else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = renderer(card).nsImage else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }

    private func renderer(_ card: ShareCard) -> ImageRenderer<some View> {
        let width = ShareStyle.Size.exportWidth
        let renderer = ImageRenderer(content:
            SharePoster(card: card, style: style)
                .frame(width: width, height: width / style.size.aspectRatio)
                .somaTheme(theme)
        )
        renderer.scale = max(displayScale, 3)
        return renderer
    }

    private func copy(_ card: ShareCard) {
        #if canImport(UIKit)
        #if !os(visionOS) && !os(tvOS) && !os(watchOS)
        if let image = renderer(card).uiImage { UIPasteboard.general.image = image }
        #endif
        #elseif canImport(AppKit)
        if let image = renderer(card).nsImage {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
        #endif
        copied = true
    }
}

/// The styled card at a share size: background, the card, and the signature.
struct SharePoster: View {
    let card: ShareCard
    let style: ShareStyle

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        VStack(spacing: metrics.cardSpacing) {
            if style.background == .orb {
                SomaOrb(aspect: card.kind.aspect)
                    .scaleEffect(0.5)
                    .frame(width: metrics.orbDiameter * 0.5, height: metrics.orbDiameter * 0.5)
            }
            Spacer(minLength: 0)
            ShareCardFace(card: card, style: style)
            HStack {
                SomaMark(accessibilityLabel: "Soma", role: .caption)
                Text("Soma")
                    .somaFont(theme.typography.caption)
                Spacer()
                if style.showsDate {
                    Text(Date().formatted(.dateTime.day().month(.abbreviated).year()))
                        .somaFont(theme.typography.caption)
                }
            }
            .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .padding(metrics.cardPadding)
        .aspectRatio(style.size.aspectRatio, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius * 1.5, style: .continuous)
                .fill(style.background == .clear ? Color.clear : theme.colors.canvas.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius * 1.5, style: .continuous)
                .strokeBorder(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
        )
    }
}

/// One card: what it is, the score or its direction, a line, and its month.
struct ShareCardFace: View {
    let card: ShareCard
    let style: ShareStyle

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        VStack(alignment: .leading, spacing: metrics.spaceXS) {
            Text(card.kind.eyebrow)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(colors.inkSecondary.color)
            Text(card.headline(exact: style.exactNumbers))
                .somaFont(style.exactNumbers ? theme.typography.metric : theme.typography.cardTitle)
                .foregroundStyle(colors.inkPrimary.color)
            if let detail = card.detail, style.exactNumbers {
                Text(detail)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            ShareSparkline(values: card.series, color: theme.aspects[card.kind.aspect].identity.color)
                .frame(height: metrics.chartTrackHeight * 6)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The last month of a score as one line; a day without a score breaks it.
private struct ShareSparkline: View {
    let values: [Double?]
    let color: Color

    @Environment(\.somaTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let count = max(values.count - 1, 1)
            Path { path in
                var drawing = false
                for (index, value) in values.enumerated() {
                    guard let value else { drawing = false; continue }
                    let point = CGPoint(
                        x: proxy.size.width * CGFloat(index) / CGFloat(count),
                        y: proxy.size.height * (1 - CGFloat(value) / 100)
                    )
                    if drawing { path.addLine(to: point) } else { path.move(to: point) }
                    drawing = true
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: theme.metrics.chartLineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

#Preview("Share studio") {
    GlobalSheet { ShareStudioPage() }
        .environment(HealthDashboard())
}
