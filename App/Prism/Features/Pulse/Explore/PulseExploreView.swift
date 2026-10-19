//
//  PulseExploreView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The Pulse tab's Explore part: a library of short, general wellness
/// reads, in the spirit of Apple Health's story cards.
///
/// The newest piece leads in a large card, the topics follow as coloured
/// chips, and the rest sit in a grid of covers with a title and a reading
/// time. Every piece opens a reader pushed on the Pulse stack. The library
/// comes from the company's Supabase project when this build has one, from
/// the copy cached on disk while that loads, and from the bundled set
/// otherwise; see `ArticleLibrary`.
struct PulseExploreView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topic: ArticleTopic?
    @State private var query = ""

    /// One library for the app's life, so a tab switch does not read the
    /// cache again or lose a refresh.
    private let library: ArticleLibrary
    private let news: NewsFeed

    /// False only for a still render; see `ExploreScroll`.
    var scrolls = true

    init(library: ArticleLibrary = .shared, news: NewsFeed = .shared, scrolls: Bool = true) {
        self.library = library
        self.news = news
        self.scrolls = scrolls
    }

    var body: some View {
        let metrics = theme.metrics
        let shown = library.articles.filter { article in
            (topic == nil || article.topic == topic) && article.matches(query)
        }

        ExploreScroll(scrolls: scrolls) {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                if let featured = shown.first {
                    ArticleLink(article: featured, style: .feature)
                }

                let latest = news.items.filter { topic == nil || $0.topic == topic }
                if !latest.isEmpty {
                    ExploreNewsRail(items: latest)
                }

                ExploreTopicChips(selection: $topic, topics: topics)

                if shown.count > 1 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.articleTileMinWidth),
                                                 spacing: metrics.articleGridSpacing, alignment: .top)],
                              alignment: .leading, spacing: metrics.articleGridSpacing * 2) {
                        ForEach(shown.dropFirst()) { article in
                            ArticleLink(article: article, style: .tile)
                        }
                    }
                } else if shown.isEmpty {
                    Text(query.isEmpty
                         ? "Nothing in \(topic?.title ?? "this topic") yet."
                         : "Nothing matches \"\(query)\".")
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            .padding(.top, metrics.cardSpacing)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: theme.motion.pressDuration * 2), value: topic)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .navigationDestination(for: Article.self) { article in
            ArticleReader(article: article)
                .zoomDestination(article.id)
        }
        .navigationDestination(for: NewsItem.self) { item in
            NewsReader(item: item)
                .zoomDestination(item.id)
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .searchableForExplore(text: $query)
    }

    private func refresh() async {
        async let articles: Void = library.refresh()
        async let latest: Void = news.refresh()
        _ = await (articles, latest)
    }

    /// The topics the library holds, in the enum's order: a chip that filters
    /// to nothing is not offered.
    private var topics: [ArticleTopic] {
        let present = Set(library.articles.map(\.topic))
        return ArticleTopic.allCases.filter(present.contains)
    }
}

/// One article as a link to its reader.
private struct ArticleLink: View {
    let article: Article
    let style: SomaArticleCard.Style

    var body: some View {
        NavigationLink(value: article) {
            SomaArticleCard(title: article.title, subtitle: article.subtitle, topic: article.topic.title,
                            caption: article.readingTime, hue: article.topic.hue, symbol: article.topic.symbol,
                            seed: article.slug, imageURL: article.coverImageURL, asset: article.photo?.asset,
                            style: style)
                .zoomSource(article.id)
        }
        .buttonStyle(TilePressStyle())
    }
}

/// "All" and one chip a topic, in a row that scrolls sideways.
private struct ExploreTopicChips: View {
    @Binding var selection: ArticleTopic?
    let topics: [ArticleTopic]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: theme.metrics.articleChipDot) {
                SomaTopicChip("All", hue: nil, isOn: selection == nil) { selection = nil }
                ForEach(topics, id: \.self) { topic in
                    SomaTopicChip(topic.title, hue: topic.hue, isOn: selection == topic) {
                        selection = selection == topic ? nil : topic
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

private extension View {
    /// The search field, pinned open: a library of a thousand pieces is
    /// not browsable by chips alone.
    func searchableForExplore(text: Binding<String>) -> some View {
#if os(macOS)
        searchable(text: text, prompt: "Search")
#else
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
#endif
    }
}

#Preview("Explore") {
    NavigationStack {
        PulseExploreView(library: ArticleLibrary(source: BundledArticleSource(), cache: nil))
    }
}

/// A page's vertical scroll. A still render (ImageRenderer, used for review
/// shots) draws nothing inside a ScrollView, so those pass `scrolls: false`
/// and get the same column laid out flat.
struct ExploreScroll<Content: View>: View {
    let scrolls: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if scrolls {
            ScrollView { content }
        } else {
            content.frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
