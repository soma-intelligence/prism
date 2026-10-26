import Foundation
import Testing
@testable import Prism

@Suite("Explore pagination")
struct ArticlePaginationTests {
    @Test("A server cap and an unreadable middle page do not hide later articles")
    func followsServerRanges() async throws {
        let source = SupabaseArticleSource(backend: ArticleFixtures.backend) { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
            let limit = Int(query.first { $0.name == "limit" }?.value ?? "2") ?? 2
            let end = min(offset + min(limit, 2), 7)
            let rows = (offset..<end).map { index in
                """
                {"id":"row-\(index)","slug":"article-\(index)","title":"Article \(index)",
                 "topic":"\((2...3).contains(index) ? "unknown" : "sleep")",
                 "published_at":"2026-09-01T00:00:00Z"}
                """
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Range": "\(offset)-\(end - 1)/7"])!
            return (Data("[\(rows.joined(separator: ","))]".utf8), response)
        }
        let articles = try await source.articles()
        #expect(Set(articles.map(\.id)) == ["row-0", "row-1", "row-4", "row-5", "row-6"])
    }

    @Test("Failure after the first page fails the whole refresh")
    func doesNotPublishPartialLibrary() async {
        let source = SupabaseArticleSource(backend: ArticleFixtures.backend) { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
            if offset > 0 { throw URLError(.notConnectedToInternet) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Range": "0-2/500"])!
            return (ArticleFixtures.rows, response)
        }
        await #expect(throws: URLError.self) { try await source.articles() }
    }
}
