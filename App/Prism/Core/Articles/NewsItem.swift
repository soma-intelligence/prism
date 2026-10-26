//
//  NewsItem.swift
//  Prism
//

import Foundation

/// One item of health and wellness news: a short summary of a piece published
/// elsewhere, with the way back to it. Read from the news Soma publishes on
/// somalabs.me (`SiteNewsSource`) and from `public.news_items`.
struct NewsItem: Identifiable, Hashable, Codable, Sendable {
    var id: String
    /// The publication: "NIH News in Health".
    var sourceName: String
    /// The original piece.
    var sourceURL: URL
    var title: String
    var summary: String
    /// Topic names as the table holds them; the ones this build knows map
    /// to an `ArticleTopic`.
    var topics: [String]
    var imageURL: URL?
    var publishedAt: Date
    /// The model that wrote the summary, when one did.
    var model: String?

    /// The first topic this build knows, for the cover's hue.
    var topic: ArticleTopic? {
        topics.lazy.compactMap { ArticleTopic(rawValue: $0.lowercased()) }.first
    }

    /// "3 hr. ago", "yesterday".
    var age: String {
        publishedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

/// Anything the news can be read from.
protocol NewsSource: Sendable {
    /// Every item, newest first.
    func items() async throws -> [NewsItem]
    /// Whether an item already showing came from here: when this source
    /// fails, those items stay rather than vanishing with the request.
    func owns(_ item: NewsItem) -> Bool
}

/// Reads `public.news_items` over Supabase's REST endpoint with the same
/// project and publishable key as the articles.
struct SupabaseNewsSource: NewsSource {
    typealias Fetch = SupabaseArticleSource.Fetch

    static let table = "news_items"
    static let columns = "id,source_name,source_url,title,summary,topics,image_url,published_at,model"
    static let limit = 40

    var backend: ArticleBackend
    var fetch: Fetch

    init(backend: ArticleBackend, fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.backend = backend
        self.fetch = fetch
    }

    var request: URLRequest {
        var components = URLComponents(url: backend.projectURL.appending(path: "rest/v1/\(Self.table)"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: Self.columns),
            URLQueryItem(name: "order", value: "published_at.desc"),
            URLQueryItem(name: "limit", value: String(Self.limit)),
        ]
        var request = URLRequest(url: components?.url ?? backend.projectURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(backend.publishableKey, forHTTPHeaderField: "apikey")
        if backend.publishableKey.hasPrefix("eyJ") {
            request.setValue("Bearer \(backend.publishableKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func items() async throws -> [NewsItem] {
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SupabaseArticleSource.Failure.status(http.statusCode)
        }
        return try Self.decode(data)
    }

    func owns(_ item: NewsItem) -> Bool { !item.id.hasPrefix(SiteNewsSource.idPrefix) }

    /// Newest first. A row without a title, a readable source address or a
    /// date is skipped rather than failing the section.
    static func decode(_ data: Data) throws -> [NewsItem] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = SupabaseArticleSource.postgresDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "date \(text)"))
            }
            return date
        }
        guard let rows = try? decoder.decode([SupabaseArticleSource.Lenient<Row>].self, from: data) else {
            throw SupabaseArticleSource.Failure.malformed
        }
        return rows.compactMap(\.value).compactMap(\.item).sorted { $0.publishedAt > $1.publishedAt }
    }

    struct Row: Decodable {
        var id: SupabaseArticleSource.FlexibleID
        var sourceName: String
        var sourceUrl: String
        var title: String
        var summary: String?
        var topics: [String]?
        var imageUrl: String?
        var publishedAt: Date
        var model: String?

        var item: NewsItem? {
            guard let url = URL(string: sourceUrl), url.scheme == "https" || url.scheme == "http",
                  !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return NewsItem(id: id.text, sourceName: sourceName, sourceURL: url, title: title,
                            summary: summary ?? "", topics: topics ?? [],
                            imageURL: imageUrl.flatMap(URL.init(string:)), publishedAt: publishedAt, model: model)
        }
    }
}

/// The last news the backend returned, on disk.
struct NewsCache: Sendable {
    var fileURL: URL

    static var standard: NewsCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return NewsCache(fileURL: caches.appending(path: "Articles/news_items.json"))
    }

    private struct Envelope: Codable {
        var version: Int
        var savedAt: Date
        var items: [NewsItem]
    }

    static let version = 1

    func load() -> [NewsItem]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.version == Self.version, !envelope.items.isEmpty else { return nil }
        return envelope.items
    }

    func save(_ items: [NewsItem], now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Envelope(version: Self.version, savedAt: now, items: items)).write(to: fileURL, options: .atomic)
    }
}

/// The news Explore shows: the site's and the table's, merged newest first.
/// There is no bundled news: with no source, or nothing fetched and nothing
/// cached, the section says so or hides.
@MainActor
@Observable
final class NewsFeed {
    /// Where the latest read stands.
    enum Phase: Equatable, Sendable {
        /// Not asked yet.
        case idle
        /// A read is out.
        case reading
        /// At least one source answered.
        case read
        /// Every source failed.
        case failed
    }

    private(set) var items: [NewsItem]
    private(set) var phase: Phase = .idle

    private let sources: [any NewsSource]
    private let cache: NewsCache?

    init(sources: [any NewsSource], cache: NewsCache?) {
        self.sources = sources
        self.cache = cache
        items = sources.isEmpty ? [] : (cache?.load() ?? [])
    }

    convenience init(source: SupabaseNewsSource?, cache: NewsCache?) {
        self.init(sources: source.map { [$0] } ?? [], cache: cache)
    }

    /// The site's news always, the table's when this build has a backend.
    static let shared = NewsFeed(
        sources: [SiteNewsSource()] + (ArticleBackend.configured.map { [SupabaseNewsSource(backend: $0)] } ?? []),
        cache: .standard)

    /// True while nothing shows and the first answer is still on its way:
    /// the section holds its place rather than appearing late.
    var isWaiting: Bool {
        !sources.isEmpty && items.isEmpty && (phase == .idle || phase == .reading)
    }

    /// Asks every source at once. A source that fails keeps what it had
    /// showing; one that answers replaces its own items, an empty answer
    /// included, since old news is not worth keeping once the source is clear.
    func refresh() async {
        guard !sources.isEmpty else { return }
        phase = .reading
        let sources = sources
        let answers = await withTaskGroup(of: (Int, [NewsItem]?).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { (index, try? await source.items()) }
            }
            var collected = [[NewsItem]?](repeating: nil, count: sources.count)
            for await (index, items) in group { collected[index] = items }
            return collected
        }
        guard answers.contains(where: { $0 != nil }) else {
            phase = .failed
            return
        }
        var seen = Set<String>()
        let merged = zip(sources, answers)
            .flatMap { source, answer in answer ?? items.filter { source.owns($0) } }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.publishedAt > $1.publishedAt }
        items = merged
        phase = .read
        try? cache?.save(merged)
    }
}
