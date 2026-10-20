//
//  ExploreNews.swift
//  Prism
//

import SwiftUI
import WebKit
import SomaUI

/// "Latest": the newest health news as a grid of cards, each a picture, the
/// publication and how long ago, and the title: the first few, the rest in
/// place behind "Show all". Hidden when there is no news: the section has no
/// bundled fallback.
struct ExploreNewsRail: View {
    let items: [NewsItem]

    @Environment(\.somaTheme) private var theme
    @State private var isOpen = false

    var body: some View {
        let metrics = theme.metrics
        let shown = isOpen ? items : Array(items.prefix(ExploreGrid.firstShown))
        let opens = items.count > ExploreGrid.firstShown

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            SomaShelfHeader(String(localized: "Latest"),
                            action: opens ? (isOpen ? String(localized: "Show fewer") : String(localized: "Show all")) : nil,
                            perform: opens ? { isOpen.toggle() } : nil)

            LazyVGrid(columns: ExploreGrid.columns(metrics), alignment: .leading, spacing: metrics.articleGridSpacing) {
                ForEach(shown) { item in
                    NavigationLink(value: item) {
                        SomaArticleCard(title: item.title, topic: item.topic?.title ?? item.sourceName,
                                        caption: "\(item.sourceName) · \(item.age)",
                                        tone: item.topic?.tone ?? .stone, mark: .track(.read),
                                        seed: item.id, imageURL: item.imageURL, style: .tile)
                            .zoomSource(item.id)
                            .somaScrollEdge()
                    }
                    .buttonStyle(TilePressStyle())
                }
            }
        }
    }
}

/// One news item opened: its picture, the publication, the title and the
/// summary, then the way to the original.
struct NewsReader: View {
    let item: NewsItem
    /// False only for a still render; see `ExploreScroll`.
    var scrolls = true

    @Environment(\.somaTheme) private var theme
    @State private var reading: NewsLink?

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        ExploreScroll(scrolls: scrolls) {
            VStack(alignment: .leading, spacing: metrics.articleTextSpacing * 2) {
                SomaArticleCover(tone: item.topic?.tone ?? .stone, mark: .track(.read), seed: item.id,
                                 imageURL: item.imageURL, size: .reader)
                    .padding(.bottom, metrics.leadSpacing)

                Text("\(item.sourceName) · \(item.age)")
                    .somaFont(type.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.inkSecondary.color)
                Text(item.title)
                    .somaFont(type.articleReaderTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: metrics.articleBlockSpacing) {
                    ForEach(Array(ArticleMarkdown.blocks(item.summary).enumerated()), id: \.offset) { _, block in
                        if case .paragraph(let text) = block {
                            Text(ArticleMarkdown.inline(text))
                                .somaFont(type.body)
                                .lineSpacing(metrics.articleBodyLineSpacing)
                                .foregroundStyle(colors.inkSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, metrics.leadSpacing)

                SomaActionButton("Read at \(item.sourceName)") { reading = NewsLink(url: item.sourceURL) }
                    .padding(.top, metrics.leadSpacing)

                Text(item.model == nil
                     ? "A short summary of the original. General wellness information, not medical advice."
                     : "Summarised automatically from the original. General wellness information, not medical advice.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, metrics.cardSpacing)
            }
            .padding(.top, metrics.cardSpacing)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding * 2)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(colors.canvas.color.ignoresSafeArea())
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(item: $reading) { link in
            NewsWebSheet(title: item.sourceName, url: link.url)
        }
    }
}

/// The original being read, as a sheet's item.
private struct NewsLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The original piece, drawn inside the app with a way out.
private struct NewsWebSheet: View {
    let title: String
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open in browser", systemImage: "safari") { openURL(url) }
                    }
                }
        }
    }
}
