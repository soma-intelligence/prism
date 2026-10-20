//
//  PulseExploreView.swift
//  Prism
//

import SwiftUI
import SomaUI
import Synchronization

/// The Pulse tab's Explore part: a library of short, general wellness
/// reads, in the spirit of Apple Health's story cards, ordered for the
/// person reading it.
///
/// "For you" leads: a few pieces, each with the reason it is there ("Because
/// your sleep was short this week"), chosen by ``ExploreRanking`` from what
/// is already on this device: readings that moved against the person's usual,
/// the pages they open most, the pieces they read and save. Then what they
/// saved, then a shelf a topic, the topics they lean toward first. A topic
/// chip or a search turns the page into one ranked grid. Nothing about the
/// person leaves the device to do this.
///
/// Every piece opens a reader that zooms out of its cover. The library comes
/// from the company's Supabase project when this build has one, from the
/// copy cached on disk while that loads, and from the bundled set otherwise;
/// see `ArticleLibrary`.
struct PulseExploreView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HealthDashboard.self) private var health
    @State private var topic: ArticleTopic?
    @State private var query = ""
    @State private var plan = ExplorePlan.empty
    /// Whether the cards have arrived; once a launch, see ``ExploreArrival``.
    @State private var arrived = ExploreArrival.played
    /// Keeps the page still while a reader covers it; see ``ExplorePlanHold``.
    @State private var hold = ExplorePlanHold()

    /// One library for the app's life, so a tab switch does not read the
    /// cache again or lose a refresh.
    private let library: ArticleLibrary
    private let news: NewsFeed
    private let interest: ExploreInterest

    /// False only for a still render; see `ExploreScroll`.
    var scrolls = true

    init(library: ArticleLibrary = .shared, news: NewsFeed = .shared, interest: ExploreInterest = .shared,
         scrolls: Bool = true) {
        self.library = library
        self.news = news
        self.interest = interest
        self.scrolls = scrolls
    }

    var body: some View {
        let metrics = theme.metrics

        ExploreScroll(scrolls: scrolls) {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                ExploreTopicChips(selection: $topic, topics: topics)
                    .somaCardArrival(index: 0, isShown: arrived)

                if isBrowsing {
                    browse
                } else {
                    filtered
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
        .navigationDestination(for: ExploreOpen.self) { open in
            ArticleReader(article: open.article)
                .zoomDestination(open.id)
        }
        .navigationDestination(for: NewsItem.self) { item in
            NewsReader(item: item)
                .zoomDestination(item.id)
        }
        .refreshable { await refresh() }
        .task { await load() }
        .onChange(of: interest.log) { requestReplan() }
        .onChange(of: "\(library.origin) \(library.articles.count)") { requestReplan() }
        .onDisappear { hold.cover() }
        .onAppear { showAgain() }
        .searchableForExplore(text: $query)
    }

    private var isBrowsing: Bool {
        topic == nil && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Browsing

    @ViewBuilder
    private var browse: some View {
        let metrics = theme.metrics

        if !plan.forYou.isEmpty {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                SomaShelfHeader("For you")
                    .somaCardArrival(index: 1, isShown: arrived)
                ForEach(Array(plan.forYou.enumerated()), id: \.element.id) { index, pick in
                    ExploreArticleLink(article: pick.article, place: "for-you", reason: pick.reason,
                                       style: index == 0 ? .feature : .row)
                        .padding(.bottom, index == 0 ? metrics.cardSpacing : 0)
                        .somaCardArrival(index: index + 2, isShown: arrived)
                        .somaScrollEdge()
                }
            }
        }

        let latest = news.items
        if !latest.isEmpty {
            ExploreNewsRail(items: latest)
        }

        if !plan.saved.isEmpty {
            ExploreShelfView(title: "Saved", place: "saved", articles: plan.saved, seeAll: nil)
        }

        ForEach(Array(plan.shelves.enumerated()), id: \.element.id) { index, shelf in
            ExploreShelfView(title: shelf.topic.title, place: "shelf", articles: shelf.articles) {
                topic = shelf.topic
            }
            .somaCardArrival(index: plan.forYou.count + 2 + index, isShown: arrived)
        }
    }

    // MARK: A topic or a search

    @ViewBuilder
    private var filtered: some View {
        let metrics = theme.metrics
        let shown = plan.ranked.filter { article in
            (topic == nil || article.topic == topic) && article.matches(query)
        }

        if shown.isEmpty {
            Text(query.isEmpty
                 ? "Nothing in \(topic?.title ?? "this topic") yet."
                 : "Nothing matches \"\(query)\".")
                .somaFont(theme.typography.callout)
                .foregroundStyle(theme.colors.inkSecondary.color)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.articleTileMinWidth),
                                         spacing: metrics.articleGridSpacing, alignment: .top)],
                      alignment: .leading, spacing: metrics.articleGridSpacing * 2) {
                ForEach(shown) { article in
                    ExploreArticleLink(article: article, place: "grid", style: .tile)
                        .somaScrollEdge()
                }
            }
        }
    }

    /// The topics the library holds, in the enum's order: a chip that filters
    /// to nothing is not offered.
    private var topics: [ArticleTopic] {
        let present = Set(library.articles.map(\.topic))
        return ArticleTopic.allCases.filter(present.contains)
    }

    // MARK: Reading

    private func load() async {
        requestReplan()
        let reading = Task { await readReadings(force: false) }
        if !arrived {
            // The first time, wait a moment for the readings, so the cards
            // arrive as the person's picks rather than the starters swapped
            // for them a beat later. A slow read does not hold the page:
            // the cards come at whichever is first, the readings or the
            // patience, and readings that land later replan quietly.
            if !ExploreReadings.isFresh {
                await ExploreArrival.wait(for: reading, atMost: ExploreArrival.patience)
            }
            arrived = true
            ExploreArrival.played = true
        }
        await reading.value
        await refreshSources()
    }

    private func refresh() async {
        await readReadings(force: true)
        await refreshSources()
    }

    private func refreshSources() async {
        async let articles: Void = library.refresh()
        async let latest: Void = news.refresh()
        _ = await (articles, latest)
    }

    /// The readings that moved, read from Health on this device, kept for a
    /// few minutes so a part switch does not read them again.
    private func readReadings(force: Bool) async {
        if !force, ExploreReadings.isFresh { return }
        await health.loadScores(requestAccess: false)
        guard let read = await PulseInsights.read(health: health, now: .now, calendar: .current) else { return }
        ExploreReadings.store(Dictionary(read.items.map { ($0.metric, $0.insight) }, uniquingKeysWith: { first, _ in first }))
        requestReplan()
    }

    /// Replans now, unless a reader covers the page or a zoom back is still
    /// landing: then once the page is settled again.
    private func requestReplan() {
        if hold.allowsReplan() { replan() }
    }

    /// The page shows again, after a reader or a part switch: anything held
    /// while it was covered is replanned once the zoom back has landed on the
    /// card it came from, the cards gliding to their new places.
    private func showAgain() {
        guard hold.uncover() else { return }
        let settle = theme.motion.zoomBackSettle
        let reorder = reduceMotion ? nil : theme.motion.pageReorder
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(settle))
            guard hold.release() else { return }
            withAnimation(reorder) { replan() }
        }
    }

    private func replan() {
        let now = Date.now
        let signals = ExploreSignals.make(readings: ExploreReadings.latest, log: interest.log, now: now)
        let next = ExploreRanking.plan(articles: library.articles, signals: signals, log: interest.log, now: now)
        if next != plan { plan = next }
    }
}

/// Whether Explore's cards have arrived once since launch: they fade up the
/// first time the page shows, and are simply there after that, so going
/// back and forth between Today and Explore never replays it.
@MainActor
enum ExploreArrival {
    static var played = false
    /// The longest the first arrival waits for the readings.
    static let patience = Duration.milliseconds(800)

    /// Returns when `task` ends or `patience` runs out, whichever is first.
    /// The task itself runs on: only the wait is cut short.
    nonisolated static func wait(for task: Task<Void, Never>, atMost patience: Duration) async {
        let gate = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.set(continuation)
            let timer = Task {
                try? await Task.sleep(for: patience)
                gate.resume()
            }
            Task {
                await task.value
                timer.cancel()
                gate.resume()
            }
        }
    }

    /// A continuation resumed once, by whichever caller comes first.
    private final class ResumeOnce: Sendable {
        private let continuation = Mutex<CheckedContinuation<Void, Never>?>(nil)

        func set(_ next: CheckedContinuation<Void, Never>) {
            continuation.withLock { $0 = next }
        }

        func resume() {
            continuation.withLock { stored in
                stored?.resume()
                stored = nil
            }
        }
    }
}

/// Holds Explore's page still while something covers it.
///
/// Opening a piece notes the read, and a read piece leaves "For you": were
/// the page replanned under the reader, the zoom back would have no card to
/// land on. So a replan asked for while the page is covered, or while a zoom
/// back is still landing, waits, and runs once the page has settled.
struct ExplorePlanHold: Equatable {
    private(set) var isCovered = false
    /// The page has shown again and a zoom back may still be landing.
    private(set) var isSettling = false
    /// A replan was asked for and held.
    private(set) var isStale = false

    /// Whether to replan now. If not, the replan is held for later.
    mutating func allowsReplan() -> Bool {
        guard isCovered || isSettling else { return true }
        isStale = true
        return false
    }

    /// Something covers the page: a reader, another part.
    mutating func cover() {
        isCovered = true
    }

    /// The page shows again. True when it was covered, so the caller waits
    /// for the zoom back to land and then calls ``release()``; false on the
    /// first show, which nothing held.
    mutating func uncover() -> Bool {
        guard isCovered else { return false }
        isCovered = false
        isSettling = true
        return true
    }

    /// The zoom back has landed. True when a replan was held and should run
    /// now. A page covered again meanwhile keeps holding.
    mutating func release() -> Bool {
        guard !isCovered else { return false }
        isSettling = false
        defer { isStale = false }
        return isStale
    }
}

/// The last read of the readings Explore orders itself by, for the life of
/// the app.
@MainActor
enum ExploreReadings {
    private(set) static var latest: [InsightMetric: Insight] = [:]
    private static var readAt: Date?
    /// How long a read stands.
    static let lifetime: TimeInterval = 10 * 60

    static var isFresh: Bool {
        guard let readAt else { return false }
        return Date.now.timeIntervalSince(readAt) < lifetime
    }

    static func store(_ readings: [InsightMetric: Insight]) {
        latest = readings
        readAt = .now
    }
}

/// An article opened from one place on the page. The same piece can show in
/// "For you" and on a shelf; each place is its own zoom source.
struct ExploreOpen: Hashable {
    var article: Article
    var place: String
    var id: String { "\(place)/\(article.id)" }
}

/// One article as a link to its reader, zooming out of its cover.
struct ExploreArticleLink: View {
    let article: Article
    let place: String
    var reason: String?
    let style: SomaArticleCardStyle

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let open = ExploreOpen(article: article, place: place)
        NavigationLink(value: open) {
            SomaArticleCard(title: article.title, subtitle: article.subtitle, topic: article.topic.title,
                            caption: article.readingTime, reason: reason, tone: article.topic.tone,
                            mark: article.topic.mark, seed: article.slug, imageURL: article.coverImageURL,
                            asset: article.photo?.asset, style: style,
                            coverStyle: ExploreZoomCover(id: open.id, cornerRadius: cornerRadius))
        }
        .buttonStyle(TilePressStyle())
    }

    private var cornerRadius: CGFloat {
        let metrics = theme.metrics
        switch style {
        case .feature: return metrics.articleCoverCornerRadius
        case .tile: return metrics.articleTileCornerRadius
        case .row: return metrics.articleRowCornerRadius
        }
    }
}

/// Marks a card's cover as where its reader zooms out of.
private struct ExploreZoomCover: ViewModifier {
    let id: String
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.zoomSource(id, cornerRadius: cornerRadius)
    }
}

/// A named row of tiles that scrolls sideways, with a way to see the whole
/// topic.
private struct ExploreShelfView: View {
    let title: String
    let place: String
    let articles: [Article]
    let seeAll: (() -> Void)?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.articleTextSpacing) {
            SomaShelfHeader(title, action: seeAll == nil ? nil : "See all", perform: seeAll)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: metrics.articleGridSpacing) {
                    ForEach(articles) { article in
                        ExploreArticleLink(article: article, place: "\(place)-\(title)", style: .tile)
                            .frame(width: metrics.articleShelfCardWidth)
                            .somaScrollEdge(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
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
                SomaTopicChip("All", tone: nil, isOn: selection == nil) { selection = nil }
                ForEach(topics, id: \.self) { topic in
                    SomaTopicChip(topic.title, tone: topic.tone, isOn: selection == topic) {
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
        PulseExploreView(library: ArticleLibrary(source: BundledArticleSource(), cache: nil),
                         interest: ExploreInterest(defaults: nil))
    }
    .environment(HealthDashboard())
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
