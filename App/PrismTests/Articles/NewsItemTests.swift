//
//  NewsItemTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("News rows")
@MainActor
struct NewsItemTests {
    /// What PostgREST returns for `news_items`: a full row, a lean one, one
    /// without a usable source address and one without a title. Oldest first.
    static let rows = Data("""
    [
      {"id": "a1", "source_name": "NIH News in Health", "source_url": "https://newsinhealth.nih.gov/2026/09/sleep",
       "title": "Sleep and the teenage brain", "summary": "First paragraph.\\n\\nSecond paragraph.",
       "topics": ["sleep", "mind"], "image_url": "https://example.org/a.jpg",
       "published_at": "2026-09-01T08:00:00+00:00", "model": "summary-model", "created_at": "2026-09-01T09:00:00+00:00"},
      {"id": 7, "source_name": "AHA News", "source_url": "https://www.heart.org/en/news/x",
       "title": "Walking after meals", "summary": null, "topics": null, "image_url": null,
       "published_at": "2026-09-30T10:15:30.5+00:00", "model": null, "created_at": "2026-09-30T10:20:00Z"},
      {"id": "bad-url", "source_name": "Somewhere", "source_url": "not a url",
       "title": "Skipped", "summary": "", "topics": [], "image_url": null,
       "published_at": "2026-09-29T00:00:00Z", "model": null, "created_at": "2026-09-29T00:00:00Z"},
      {"id": "no-title", "source_name": "Somewhere", "source_url": "https://example.org",
       "title": " ", "summary": "", "topics": [], "image_url": null,
       "published_at": "2026-09-28T00:00:00Z", "model": null, "created_at": "2026-09-28T00:00:00Z"}
    ]
    """.utf8)

    @Test("Rows decode newest first; unusable rows drop")
    func decodes() throws {
        let items = try SupabaseNewsSource.decode(Self.rows)
        #expect(items.map(\.id) == ["7", "a1"])
        let full = items[1]
        #expect(full.sourceName == "NIH News in Health")
        #expect(full.sourceURL.host() == "newsinhealth.nih.gov")
        #expect(full.topic == .sleep)
        #expect(full.imageURL != nil)
        #expect(full.model == "summary-model")
        #expect(ArticleMarkdown.blocks(full.summary) == [.paragraph("First paragraph."), .paragraph("Second paragraph.")])
        let lean = items[0]
        #expect(lean.summary.isEmpty)
        #expect(lean.topics.isEmpty)
        #expect(lean.topic == nil)
    }

    @Test("A body that is not an array is malformed")
    func malformed() {
        #expect(throws: SupabaseArticleSource.Failure.malformed) {
            try SupabaseNewsSource.decode(Data(#"{"code":"42P01"}"#.utf8))
        }
    }

    @Test("The request reads news_items newest first with the publishable key")
    func request() throws {
        let request = SupabaseNewsSource(backend: ArticleFixtures.backend).request
        let url = try #require(request.url)
        #expect(url.path() == "/rest/v1/news_items")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "order", value: "published_at.desc")))
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_fixture")
    }

    @Test("No backend, no news; a fetch fills the section and the cache")
    func feed() async throws {
        #expect(NewsFeed(source: nil, cache: nil).items.isEmpty)

        let cache = NewsCache(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "news-cache-\(UUID().uuidString)/news_items.json"))
        defer { try? FileManager.default.removeItem(at: cache.fileURL.deletingLastPathComponent()) }
        let source = SupabaseNewsSource(backend: ArticleFixtures.backend) { request in
            (Self.rows, ArticleFixtures.response(200, for: request))
        }
        let feed = NewsFeed(source: source, cache: cache)
        #expect(feed.items.isEmpty)
        await feed.refresh()
        #expect(feed.items.map(\.id) == ["7", "a1"])

        let offline = SupabaseNewsSource(backend: ArticleFixtures.backend) { _ in throw URLError(.notConnectedToInternet) }
        let next = NewsFeed(source: offline, cache: cache)
        #expect(next.items.map(\.id) == ["7", "a1"])
        await next.refresh()
        #expect(next.items.map(\.id) == ["7", "a1"])
    }
}
