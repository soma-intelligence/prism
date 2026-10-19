//
//  ArticleSourceTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Article rows")
@MainActor
struct ArticleRowDecodingTests {
    @Test("Rows decode newest first, lean rows fill in, unknown topics drop")
    func decodesRows() throws {
        let articles = try SupabaseArticleSource.decode(ArticleFixtures.rows)
        #expect(articles.map(\.slug) == ["sleep-regularity", "hydration-basics"])

        let full = articles[0]
        #expect(full.id == "7d2c9a52-4f0e-4f7a-9d0c-2b8f0d0e1a11")
        #expect(full.topic == .sleep)
        #expect(full.minutes == 4)
        #expect(full.coverImageURL?.host() == "example.supabase.co")
        #expect(full.sources.count == 2)
        #expect(full.sources[0].url?.absoluteString == "https://doi.org/10.1093/sleep/zsad253")
        #expect(full.sources[1].url == nil)
        #expect(ArticleMarkdown.blocks(full.body) == [.heading("Heading"), .paragraph("A paragraph.")])

        let lean = articles[1]
        #expect(lean.id == "42")
        #expect(lean.subtitle.isEmpty)
        #expect(lean.minutes == 1)
        #expect(lean.body.isEmpty)
        #expect(lean.sources.isEmpty)
    }

    @Test("Fractional and whole second timestamps both parse")
    func parsesDates() {
        #expect(SupabaseArticleSource.postgresDate("2026-09-30T10:15:30.123456+00:00") != nil)
        #expect(SupabaseArticleSource.postgresDate("2026-09-30T10:15:30Z") != nil)
        #expect(SupabaseArticleSource.postgresDate("yesterday") == nil)
    }

    @Test("A body that is not an array is malformed")
    func rejectsNonArray() {
        #expect(throws: SupabaseArticleSource.Failure.malformed) {
            try SupabaseArticleSource.decode(Data(#"{"message":"relation does not exist"}"#.utf8))
        }
    }

    @Test("The request reads published rows with the publishable key")
    func buildsRequest() throws {
        let request = SupabaseArticleSource(backend: ArticleFixtures.backend).request
        let url = try #require(request.url)
        #expect(url.path() == "/rest/v1/app_articles")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "published", value: "eq.true")))
        #expect(query.contains(URLQueryItem(name: "order", value: "published_at.desc")))
        #expect(query.contains(URLQueryItem(name: "limit", value: "200")))
        #expect(query.contains(URLQueryItem(name: "offset", value: "0")))
        #expect(request.value(forHTTPHeaderField: "Prefer") == "count=exact")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_fixture")
        // A publishable key is not a JWT and stays out of Authorization.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let legacy = ArticleBackend(projectURL: ArticleFixtures.backend.projectURL, publishableKey: "eyJhbGciOi.fixture")
        #expect(SupabaseArticleSource(backend: legacy).request.value(forHTTPHeaderField: "Authorization") == "Bearer eyJhbGciOi.fixture")
    }

    @Test("A refused request throws its status")
    func surfacesStatus() async {
        let source = SupabaseArticleSource(backend: ArticleFixtures.backend) { request in
            (Data("[]".utf8), ArticleFixtures.response(401, for: request))
        }
        await #expect(throws: SupabaseArticleSource.Failure.status(401)) {
            try await source.articles()
        }
    }
}

@Suite("Article cache")
@MainActor
struct ArticleCacheTests {
    private func scratch() -> ArticleCache {
        ArticleCache(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "article-cache-\(UUID().uuidString)/app_articles.json"))
    }

    @Test("What is saved comes back the same")
    func roundTrip() throws {
        let cache = scratch()
        defer { try? FileManager.default.removeItem(at: cache.fileURL.deletingLastPathComponent()) }
        #expect(cache.load() == nil)

        let articles = try SupabaseArticleSource.decode(ArticleFixtures.rows)
        try cache.save(articles)
        let loaded = try #require(cache.load())
        #expect(loaded.map(\.id) == articles.map(\.id))
        #expect(loaded[0].sources == articles[0].sources)
        #expect(loaded[0].coverImageURL == articles[0].coverImageURL)
        // ISO 8601 on disk keeps whole seconds.
        #expect(abs(loaded[0].publishedAt.timeIntervalSince(articles[0].publishedAt)) < 1)
    }

    @Test("A damaged or empty file reads as no cache")
    func damagedFile() throws {
        let cache = scratch()
        defer { try? FileManager.default.removeItem(at: cache.fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: cache.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.fileURL)
        #expect(cache.load() == nil)
        try cache.save([])
        #expect(cache.load() == nil)
    }
}

@Suite("Article source selection")
@MainActor
struct ArticleSourceSelectionTests {
    @Test("Info.plist wins, the environment fills in, placeholders and http do not count")
    func resolvesBackend() {
        let info: [String: Any] = [ArticleBackend.infoURLKey: "https://abc.supabase.co", ArticleBackend.infoKeyKey: "sb_publishable_a"]
        #expect(ArticleBackend.resolve(info: info, environment: [:])?.projectURL.host() == "abc.supabase.co")

        let environment = [ArticleBackend.environmentURLKey: "https://env.supabase.co", ArticleBackend.environmentKeyKey: "sb_publishable_b"]
        #expect(ArticleBackend.resolve(info: [:], environment: environment)?.publishableKey == "sb_publishable_b")

        let placeholder: [String: Any] = [ArticleBackend.infoURLKey: "$(SOMA_SUPABASE_URL)", ArticleBackend.infoKeyKey: "$(SOMA_SUPABASE_PUBLISHABLE_KEY)"]
        #expect(ArticleBackend.resolve(info: placeholder, environment: [:]) == nil)

        let plain: [String: Any] = [ArticleBackend.infoURLKey: "http://abc.supabase.co", ArticleBackend.infoKeyKey: "k"]
        #expect(ArticleBackend.resolve(info: plain, environment: [:]) == nil)
        #expect(ArticleBackend.resolve(info: [ArticleBackend.infoURLKey: "https://abc.supabase.co"], environment: [:]) == nil)
    }

    @Test("Remote when configured, bundled otherwise")
    func picksSource() {
        #expect(ArticleSources.preferred(backend: nil) is BundledArticleSource)
        #expect(ArticleSources.preferred(backend: ArticleFixtures.backend) is SupabaseArticleSource)
    }

    @Test("The library opens on the cache, then takes the remote answer and caches it")
    func libraryFlow() async throws {
        let cache = ArticleCache(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "article-library-\(UUID().uuidString)/app_articles.json"))
        defer { try? FileManager.default.removeItem(at: cache.fileURL.deletingLastPathComponent()) }

        let remote = SupabaseArticleSource(backend: ArticleFixtures.backend) { request in
            (ArticleFixtures.rows, ArticleFixtures.response(200, for: request))
        }
        let first = ArticleLibrary(source: remote, cache: cache)
        #expect(first.origin == .bundled)
        #expect(first.articles == BundledArticles.all)
        await first.refresh()
        #expect(first.origin == .remote)
        #expect(first.articles.map(\.slug) == ["sleep-regularity", "hydration-basics"])

        // Offline on the next launch: the cache opens the page.
        let offline = SupabaseArticleSource(backend: ArticleFixtures.backend) { _ in throw URLError(.notConnectedToInternet) }
        let second = ArticleLibrary(source: offline, cache: cache)
        #expect(second.origin == .cache)
        await second.refresh()
        #expect(second.origin == .cache)
        #expect(second.articles.map(\.slug) == ["sleep-regularity", "hydration-basics"])
    }

    @Test("An empty table keeps what is showing")
    func emptyRemote() async {
        let empty = SupabaseArticleSource(backend: ArticleFixtures.backend) { request in
            (Data("[]".utf8), ArticleFixtures.response(200, for: request))
        }
        let library = ArticleLibrary(source: empty, cache: nil)
        await library.refresh()
        #expect(library.origin == .bundled)
        #expect(!library.articles.isEmpty)
    }
}

@Suite("Bundled articles")
@MainActor
struct BundledArticleTests {
    @Test("The twelve written for the app each carry an Unsplash cover and credit")
    func covers() {
        let written = BundledArticles.all.filter { $0.id.hasPrefix("bundled-") }
        #expect(written.count == 12)
        for article in written {
            #expect(article.photo?.asset == "Articles/\(article.slug)", "\(article.slug) has no cover")
            #expect(article.photo?.url?.host() == "unsplash.com", "\(article.slug)")
            #expect(article.photo?.line.hasPrefix("Photo: ") == true)
        }
    }

    @Test("Every piece is complete, cited, unique, and never about the pod")
    func library() {
        let all = BundledArticles.all
        #expect(all.count >= 1000)
        #expect(Set(all.map(\.slug)).count == all.count)
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(Set(all.map(\.topic)) == Set(ArticleTopic.allCases))
        for topic in ArticleTopic.allCases {
            #expect(all.filter { $0.topic == topic }.count >= 100, "\(topic.rawValue) is thin")
        }
        for article in all {
            #expect(!article.sources.isEmpty, "\(article.slug) has no sources")
            // A citation whose address is gone keeps its title and no link.
            #expect(article.sources.allSatisfy { $0.url == nil || $0.url?.scheme == "https" }, "\(article.slug)")
            #expect(article.sources.contains { $0.url != nil }, "\(article.slug) has no linked source")
            #expect(article.sources.allSatisfy { $0.url?.host()?.contains("pagefreezer") != true }, "\(article.slug)")
            #expect(!ArticleMarkdown.blocks(article.body).isEmpty)
            // An NIH piece ships no picture: Explore paints its generated cover.
            // Only the twelve written for the app carry a photo, and its credit.
            if article.id.hasPrefix("bundled-") {
                #expect(article.photo?.asset != nil, "\(article.slug) has no cover")
                #expect(article.photo != nil, "\(article.slug) has no photo credit")
            } else {
                #expect(article.coverImageURL == nil, "\(article.slug)")
                #expect(article.photo == nil, "\(article.slug)")
                #expect(!article.body.contains("reviewed by NIH scientists"), "\(article.slug)")
            }
            let text = "\(article.title) \(article.subtitle) \(article.body)".lowercased()
            for word in ["pod", "soma", "axon", "diagnos", "cure", "treatment"] {
                #expect(!text.contains(word), "\(article.slug) mentions \(word)")
            }
        }
    }

    @Test("Markdown blocks: headings, paragraphs, lists and quotes")
    func markdown() {
        let body = """
        Intro line one
        and line two.

        ## Section
        - first
        * second
        > A quote
        Closing.
        """
        #expect(ArticleMarkdown.blocks(body) == [
            .paragraph("Intro line one and line two."),
            .heading("Section"),
            .bullets(["first", "second"]),
            .quote("A quote"),
            .paragraph("Closing."),
        ])
        #expect(String(ArticleMarkdown.inline("**bold** and *soft*").characters) == "bold and soft")
    }

    @Test("Search matches title, subtitle or body, and ignores blank queries")
    func search() {
        let article = BundledArticles.sleepRegularity
        #expect(article.matches(""))
        #expect(article.matches("  "))
        #expect(article.matches("bedtime"))
        #expect(article.matches("REGULAR"))
        #expect(!article.matches("xylitol"))
    }
}
