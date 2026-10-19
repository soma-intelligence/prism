//
//  ArticleSources.swift
//  Prism
//

import Foundation

/// Anything Explore can read its articles from.
protocol ArticleSource: Sendable {
    /// Every published article, newest first.
    func articles() async throws -> [Article]
}

// MARK: - Where the backend is

/// The company's Supabase project, as far as Explore needs it: the project
/// address and the publishable (anon) key. Both are public by design: row
/// level security decides what the key can read, and `app_articles` lets it
/// read published rows only.
///
/// Nothing is written in source. The values come from the app's Info.plist
/// (`SomaSupabaseURL`, `SomaSupabasePublishableKey`, set through build
/// settings or an xcconfig the repository does not track), or for a
/// development run from the scheme's environment (`SOMA_SUPABASE_URL`,
/// `SOMA_SUPABASE_PUBLISHABLE_KEY`). Absent either, there is no backend and
/// Explore reads the bundled library.
struct ArticleBackend: Equatable, Sendable {
    var projectURL: URL
    var publishableKey: String

    static let infoURLKey = "SomaSupabaseURL"
    static let infoKeyKey = "SomaSupabasePublishableKey"
    static let environmentURLKey = "SOMA_SUPABASE_URL"
    static let environmentKeyKey = "SOMA_SUPABASE_PUBLISHABLE_KEY"

    /// The backend this build is configured for, if any.
    static var configured: ArticleBackend? {
        resolve(info: Bundle.main.infoDictionary ?? [:], environment: ProcessInfo.processInfo.environment)
    }

    /// Info.plist first, then the environment. A value still holding an
    /// unexpanded build setting (`$(SOMA_SUPABASE_URL)`) counts as absent,
    /// and so does an address that is not https.
    static func resolve(info: [String: Any], environment: [String: String]) -> ArticleBackend? {
        func clean(_ value: Any?) -> String? {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, !text.contains("$(") else { return nil }
            return text
        }
        guard let address = clean(info[infoURLKey]) ?? clean(environment[environmentURLKey]),
              let key = clean(info[infoKeyKey]) ?? clean(environment[environmentKeyKey]),
              let url = URL(string: address), url.scheme == "https", url.host() != nil
        else { return nil }
        return ArticleBackend(projectURL: url, publishableKey: key)
    }
}

// MARK: - Supabase

/// Reads `public.app_articles` over Supabase's REST endpoint (PostgREST),
/// with the publishable key. The app does not link WellnessKit's
/// `SyncSupabase`, and a single GET does not need it.
struct SupabaseArticleSource: ArticleSource {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    enum Failure: Error, Equatable {
        case status(Int)
        case malformed
    }

    static let table = "app_articles"
    static let columns = "id,slug,title,subtitle,topic,minutes,cover_image_url,cover_credit,cover_credit_url,body,published_at,sources"

    var backend: ArticleBackend
    var fetch: Fetch

    init(backend: ArticleBackend, fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.backend = backend
        self.fetch = fetch
    }

    /// One page of published rows. PostgREST caps a response; Explore walks
    /// `offset` until `Content-Range` says the table is done.
    static let pageSize = 200

    func request(offset: Int, limit: Int = pageSize) -> URLRequest {
        var components = URLComponents(url: backend.projectURL.appending(path: "rest/v1/\(Self.table)"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: Self.columns),
            URLQueryItem(name: "published", value: "eq.true"),
            URLQueryItem(name: "order", value: "published_at.desc"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        var request = URLRequest(url: components?.url ?? backend.projectURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(backend.publishableKey, forHTTPHeaderField: "apikey")
        // A legacy anon key is a JWT and goes in Authorization too; a new
        // `sb_publishable_` key is not a JWT and is refused there.
        if backend.publishableKey.hasPrefix("eyJ") {
            request.setValue("Bearer \(backend.publishableKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Prefer exact counts so a short last page still reports the total.
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        return request
    }

    /// The first page, kept so existing tests that inspect the request still
    /// compile while pagination lands.
    var request: URLRequest { request(offset: 0) }

    func articles() async throws -> [Article] {
        var collected: [Article] = []
        var offset = 0
        while true {
            let (data, response) = try await fetch(request(offset: offset))
            let http = response as? HTTPURLResponse
            if let http, !(200..<300).contains(http.statusCode) {
                throw Failure.status(http.statusCode)
            }
            let page = try Self.decode(data)
            collected.append(contentsOf: page)
            let range = http.flatMap(Self.contentRange(from:))
            let next = range?.nextOffset ?? offset + max(page.count, 1)
            if let range, next >= range.total { break }
            if range == nil && page.count < Self.pageSize { break }
            if next <= offset { break }
            offset = next
            if offset > 10_000 { break }
        }
        return collected.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// `Content-Range: 0-199/1000` as PostgREST sends it when Prefer asks
    /// for an exact count. The next offset is one past the last index the
    /// server included, even when this build skipped every row on the page.
    static func contentRange(from response: HTTPURLResponse) -> (nextOffset: Int, total: Int)? {
        guard let header = response.value(forHTTPHeaderField: "Content-Range") else { return nil }
        // "2-3/7" or "*/0".
        let parts = header.split(separator: "/")
        guard parts.count == 2, parts[1] != "*", let total = Int(parts[1]) else { return nil }
        let span = parts[0].split(separator: "-")
        let next: Int
        if span.count == 2, let end = Int(span[1]) {
            next = end + 1
        } else {
            next = total
        }
        return (next, total)
    }

    /// The rows PostgREST returns, newest first. A row this build cannot read
    /// (a topic it does not know, a missing title) is skipped rather than
    /// failing the whole library.
    static func decode(_ data: Data) throws -> [Article] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = postgresDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "date \(text)"))
            }
            return date
        }
        guard let rows = try? decoder.decode([Lenient<Row>].self, from: data) else { throw Failure.malformed }
        return rows.compactMap(\.value).compactMap(\.article).sorted { $0.publishedAt > $1.publishedAt }
    }

    /// `timestamptz` as PostgREST writes it: ISO 8601, with or without
    /// fractional seconds, with a `+00:00` offset or a `Z`.
    static func postgresDate(_ text: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let whole = Date.ISO8601FormatStyle()
        return (try? fractional.parse(text)) ?? (try? whole.parse(text))
    }

    struct Row: Decodable {
        var id: FlexibleID
        var slug: String
        var title: String
        var subtitle: String?
        var topic: String
        var minutes: Int?
        var coverImageUrl: String?
        var coverCredit: String?
        var coverCreditUrl: String?
        var body: String?
        var publishedAt: Date
        var sources: [Citation]?

        struct Citation: Decodable {
            var title: String
            var publisher: String?
            var url: String?
        }

        /// The cover's credit, when the row names a photographer.
        var photo: ArticlePhoto? {
            guard let credit = coverCredit?.trimmingCharacters(in: .whitespaces), !credit.isEmpty else { return nil }
            let url = coverCreditUrl.flatMap(URL.init(string:))
            let library = url?.host()?.contains("unsplash.com") == true ? "Unsplash" : (url?.host() ?? "")
            return ArticlePhoto(asset: nil, credit: credit, url: url, library: library.isEmpty ? "Photo library" : library)
        }

        var article: Article? {
            guard let topic = ArticleTopic(rawValue: topic.lowercased()),
                  !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Article(
                id: id.text, slug: slug, title: title, subtitle: subtitle ?? "", topic: topic,
                minutes: max(1, minutes ?? 1),
                coverImageURL: coverImageUrl.flatMap(URL.init(string:)),
                body: body ?? "", publishedAt: publishedAt,
                sources: (sources ?? []).map {
                    ArticleCitation(title: $0.title, publisher: $0.publisher, url: $0.url.flatMap(URL.init(string:)))
                },
                photo: photo)
        }
    }

    /// A uuid or a bigint key: the table uses a uuid, and a row keyed by a
    /// number still reads.
    struct FlexibleID: Decodable {
        var text: String
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self.text = text
            } else {
                self.text = String(try container.decode(Int64.self))
            }
        }
    }

    /// One element of an array that decodes to nil instead of throwing.
    struct Lenient<Value: Decodable>: Decodable {
        var value: Value?
        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}

// MARK: - Bundled

/// The library that ships in the app: what Explore shows with no backend,
/// and before the first fetch ever lands.
struct BundledArticleSource: ArticleSource {
    func articles() async throws -> [Article] { BundledArticles.all }
}

// MARK: - Cache

/// The last library the backend returned, on disk, so Explore opens at once
/// and offline.
struct ArticleCache: Sendable {
    var fileURL: URL

    /// `Caches/Articles/app_articles.json`. The system may purge Caches; the
    /// bundled library covers that.
    static var standard: ArticleCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ArticleCache(fileURL: caches.appending(path: "Articles/app_articles.json"))
    }

    private struct Envelope: Codable {
        var version: Int
        var savedAt: Date
        var articles: [Article]
    }

    static let version = 1

    func load() -> [Article]? {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? Self.coder.decoder.decode(Envelope.self, from: data),
              envelope.version == Self.version, !envelope.articles.isEmpty else { return nil }
        return envelope.articles
    }

    func save(_ articles: [Article], now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.coder.encoder.encode(Envelope(version: Self.version, savedAt: now, articles: articles))
        try data.write(to: fileURL, options: .atomic)
    }

    private static var coder: (encoder: JSONEncoder, decoder: JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }
}

// MARK: - Choosing

enum ArticleSources {
    /// The remote source when this build has a backend, the bundled library
    /// otherwise.
    static func preferred(backend: ArticleBackend?, fetch: SupabaseArticleSource.Fetch? = nil) -> any ArticleSource {
        guard let backend else { return BundledArticleSource() }
        if let fetch { return SupabaseArticleSource(backend: backend, fetch: fetch) }
        return SupabaseArticleSource(backend: backend)
    }
}

/// What Explore shows, and where it came from.
@MainActor
@Observable
final class ArticleLibrary {
    enum Origin: Equatable, Sendable {
        case bundled
        case cache
        case remote
    }

    private(set) var articles: [Article]
    private(set) var origin: Origin

    private let source: any ArticleSource
    private let cache: ArticleCache?

    /// Opens on the cache when there is one, the bundled library otherwise,
    /// so the first frame always has something to show.
    init(source: any ArticleSource, cache: ArticleCache?) {
        self.source = source
        self.cache = cache
        if source is BundledArticleSource {
            articles = BundledArticles.all
            origin = .bundled
        } else if let cached = cache?.load() {
            articles = cached
            origin = .cache
        } else {
            articles = BundledArticles.all
            origin = .bundled
        }
    }

    /// The app's one library.
    static let shared = live()

    /// The library this build should run with.
    static func live() -> ArticleLibrary {
        ArticleLibrary(source: ArticleSources.preferred(backend: .configured), cache: .standard)
    }

    /// Asks the source again. A failure or an empty answer keeps what is
    /// showing: an empty table is not a reason to blank the page.
    func refresh() async {
        guard !(source is BundledArticleSource) else { return }
        guard let fresh = try? await source.articles(), !fresh.isEmpty else { return }
        articles = fresh
        origin = .remote
        try? cache?.save(fresh)
    }
}
