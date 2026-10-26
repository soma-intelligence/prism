//
//  SiteNewsSourceTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Site news")
@MainActor
struct SiteNewsSourceTests {
    /// What somalabs.me serves at /news/rss.xml: a story with a cover, one
    /// without, one dated later today than `now`, and two that cannot be
    /// read. Oldest first.
    static let feed = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
      <channel>
        <title>Soma news</title>
        <link>https://www.somalabs.me/news</link>
        <description>What's new in health.</description>
        <item>
          <title>Fitbit Edge brings blood pressure trends to a $180 band</title>
          <link>https://www.somalabs.me/news/fitbit-edge-trends-not-readings</link>
          <guid isPermaLink="true">https://www.somalabs.me/news/fitbit-edge-trends-not-readings</guid>
          <description>Trends, not readings.</description>
          <pubDate>Sun, 11 Oct 2026 12:00:00 GMT</pubDate>
        </item>
        <item>
          <title>Abu Dhabi &amp; Ultrahuman build a &lt;health age&gt; model</title>
          <link>https://www.somalabs.me/news/ultrahuman-abu-dhabi-health-age</link>
          <description>A biological age, at a country's scale.</description>
          <pubDate>Mon, 12 Oct 2026 12:00:00 GMT</pubDate>
          <media:content url="https://www.somalabs.me/news/ultrahuman/cover.jpg" medium="image" />
        </item>
        <item>
          <title>Out this morning</title>
          <link>https://www.somalabs.me/news/this-morning</link>
          <description>Dated noon, read at nine.</description>
          <pubDate>Tue, 13 Oct 2026 12:00:00 GMT</pubDate>
        </item>
        <item>
          <title>No address</title>
          <link>not a url</link>
          <pubDate>Mon, 12 Oct 2026 12:00:00 GMT</pubDate>
        </item>
        <item>
          <title> </title>
          <link>https://www.somalabs.me/news/untitled</link>
          <pubDate>Mon, 12 Oct 2026 12:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """.utf8)

    static let now = Date(timeIntervalSince1970: 1_791_882_000) // 2026-10-13 09:00 UTC

    @Test("Stories decode newest first, escapes read, covers kept, unusable items dropped")
    func decodes() throws {
        let items = try SiteNewsSource.decode(Self.feed, now: Self.now)
        #expect(items.map(\.id) == ["somalabs:this-morning", "somalabs:ultrahuman-abu-dhabi-health-age",
                                    "somalabs:fitbit-edge-trends-not-readings"])
        let covered = items[1]
        #expect(covered.title == "Abu Dhabi & Ultrahuman build a <health age> model")
        #expect(covered.sourceName == "Soma")
        #expect(covered.sourceURL.absoluteString == "https://www.somalabs.me/news/ultrahuman-abu-dhabi-health-age")
        #expect(covered.summary == "A biological age, at a country's scale.")
        #expect(covered.imageURL?.absoluteString == "https://www.somalabs.me/news/ultrahuman/cover.jpg")
        #expect(covered.model == nil)
        #expect(items[2].imageURL == nil)
    }

    @Test("A story dated later than now is held at now")
    func clampsTheDay() throws {
        let items = try SiteNewsSource.decode(Self.feed, now: Self.now)
        #expect(items[0].publishedAt == Self.now)
        #expect(items[1].publishedAt < Self.now)
    }

    @Test("A page that is not a feed is malformed")
    func malformed() {
        #expect(throws: SupabaseArticleSource.Failure.malformed) {
            try SiteNewsSource.decode(Data("<html><body>Not found</body></html>".utf8), now: Self.now)
        }
    }

    @Test("The site's news and the table's merge; a source that fails keeps its own")
    func merges() async throws {
        let cache = NewsCache(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "news-cache-\(UUID().uuidString)/news_items.json"))
        defer { try? FileManager.default.removeItem(at: cache.fileURL.deletingLastPathComponent()) }

        let site = SiteNewsSource(fetch: { request in (Self.feed, ArticleFixtures.response(200, for: request)) },
                                  now: { Self.now })
        let table = SupabaseNewsSource(backend: ArticleFixtures.backend) { request in
            (NewsItemTests.rows, ArticleFixtures.response(200, for: request))
        }
        let feed = NewsFeed(sources: [site, table], cache: cache)
        #expect(feed.isWaiting)
        await feed.refresh()
        #expect(feed.phase == .read)
        #expect(!feed.isWaiting)
        #expect(feed.items.count == 5)
        #expect(feed.items.first?.id == "somalabs:this-morning")
        #expect(feed.items.map(\.publishedAt) == feed.items.map(\.publishedAt).sorted(by: >))

        // The site down, the table up: the site's stories stay.
        let siteDown = SiteNewsSource(fetch: { _ in throw URLError(.notConnectedToInternet) }, now: { Self.now })
        let next = NewsFeed(sources: [siteDown, table], cache: cache)
        await next.refresh()
        #expect(next.phase == .read)
        #expect(next.items.count == 5)
    }

    @Test("Every source down with nothing cached is a failure, and says so")
    func fails() async {
        let down = SiteNewsSource(fetch: { _ in throw URLError(.notConnectedToInternet) }, now: { Self.now })
        let feed = NewsFeed(sources: [down], cache: nil)
        await feed.refresh()
        #expect(feed.phase == .failed)
        #expect(feed.items.isEmpty)
        #expect(!feed.isWaiting)
    }

    @Test("The request reads the news feed on the canonical host")
    func request() {
        let request = SiteNewsSource().request
        #expect(request.url?.absoluteString == "https://www.somalabs.me/news/rss.xml")
        #expect(request.httpMethod == "GET")
    }
}
