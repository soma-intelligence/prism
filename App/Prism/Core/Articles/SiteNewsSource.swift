//
//  SiteNewsSource.swift
//  Prism
//

import Foundation

/// Reads the news Soma publishes on somalabs.me, from the site's RSS feed
/// (`/news/rss.xml`): each story's title, address, one or two sentence
/// summary, day and, when the post opens with one, its cover. The text
/// itself stays on the site, and the reader opens it there.
///
/// The feed is public and needs no key, so this source works in every build,
/// with or without a Supabase backend.
nonisolated struct SiteNewsSource: NewsSource {
    typealias Fetch = SupabaseArticleSource.Fetch

    static let feedURL = URL(string: "https://www.somalabs.me/news/rss.xml")!
    /// The publication, as the card and the reader name it.
    static let sourceName = "Soma"
    /// Marks an item as the site's, so it never collides with a table row.
    static let idPrefix = "somalabs:"

    var feedURL: URL = Self.feedURL
    var fetch: Fetch = { try await URLSession.shared.data(for: $0) }
    var now: @Sendable () -> Date = { Date() }

    var request: URLRequest {
        var request = URLRequest(url: feedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/rss+xml, application/xml", forHTTPHeaderField: "Accept")
        return request
    }

    func items() async throws -> [NewsItem] {
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SupabaseArticleSource.Failure.status(http.statusCode)
        }
        return try Self.decode(data, now: now())
    }

    func owns(_ item: NewsItem) -> Bool { item.id.hasPrefix(Self.idPrefix) }

    /// Newest first. An item without a title or an http address is skipped
    /// rather than failing the section. The feed dates a story by its day,
    /// at noon UTC, so a story out this morning in California can carry a
    /// time still ahead: it is held at `now` rather than shown as to come.
    static func decode(_ data: Data, now: Date) throws -> [NewsItem] {
        let reader = FeedReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.sawChannel else { throw SupabaseArticleSource.Failure.malformed }
        return reader.items.compactMap { $0.item(now: now) }.sorted { $0.publishedAt > $1.publishedAt }
    }

    /// `Mon, 12 Oct 2026 12:00:00 GMT`, as RSS 2.0 writes a date.
    static func rfc822Date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
        }
        return nil
    }

    /// One `<item>` as the feed wrote it.
    nonisolated struct Entry {
        var title = ""
        var link = ""
        var summary = ""
        var published = ""
        var image: String?

        func item(now: Date) -> NewsItem? {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty,
                  let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme == "https" || url.scheme == "http",
                  let date = SiteNewsSource.rfc822Date(published) else { return nil }
            let slug = url.pathComponents.last ?? url.absoluteString
            return NewsItem(id: SiteNewsSource.idPrefix + slug, sourceName: SiteNewsSource.sourceName,
                            sourceURL: url, title: title,
                            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines), topics: [],
                            imageURL: image.flatMap(URL.init(string:)), publishedAt: min(date, now), model: nil)
        }
    }

    /// Collects the items of an RSS 2.0 channel. Lives for one parse.
    nonisolated private final class FeedReader: NSObject, XMLParserDelegate {
        var items: [Entry] = []
        var sawChannel = false
        private var entry: Entry?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "channel":
                sawChannel = true
            case "item":
                entry = Entry()
            case "media:content", "enclosure":
                // A cover is an image: `medium="image"` on Media RSS, an image
                // type on an enclosure.
                let isImage = attributes["medium"] == "image" || attributes["type"]?.hasPrefix("image/") == true
                if isImage, entry?.image == nil, let url = attributes["url"] { entry?.image = url }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            text += String(decoding: block, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "item":
                if let entry { items.append(entry) }
                entry = nil
            case "title": entry?.title = text
            case "link": entry?.link = text
            case "description": entry?.summary = text
            case "pubDate": entry?.published = text
            default: break
            }
            text = ""
        }
    }
}
