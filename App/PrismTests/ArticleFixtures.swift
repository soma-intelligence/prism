//
//  ArticleFixtures.swift
//  PrismTests
//

import Foundation
@testable import Prism

/// What PostgREST returns for `app_articles`, written out as it arrives.
enum ArticleFixtures {
    /// Three rows: a full one, a lean one keyed by a number with a
    /// whole-second date and no optional columns, and one with a topic this
    /// build does not know, which must be skipped. Oldest first, on purpose.
    static let rows = Data("""
    [
      {
        "id": 42,
        "slug": "hydration-basics",
        "title": "Water through the day",
        "subtitle": null,
        "topic": "nutrition",
        "minutes": null,
        "cover_image_url": null,
        "body": null,
        "published_at": "2026-09-01T08:00:00+00:00",
        "sources": null
      },
      {
        "id": "7d2c9a52-4f0e-4f7a-9d0c-2b8f0d0e1a11",
        "slug": "sleep-regularity",
        "title": "Why a steady bedtime matters",
        "subtitle": "Regular nights may count as much as long ones.",
        "topic": "sleep",
        "minutes": 4,
        "cover_image_url": "https://example.supabase.co/storage/v1/object/public/app-articles/sleep.jpg",
        "body": "## Heading\\n\\nA paragraph.",
        "published_at": "2026-09-30T10:15:30.123456+00:00",
        "sources": [
          {"title": "Sleep regularity", "publisher": "Sleep, 2024", "url": "https://doi.org/10.1093/sleep/zsad253"},
          {"title": "No link"}
        ]
      },
      {
        "id": "b1",
        "slug": "unknown-topic",
        "title": "From a newer build",
        "subtitle": "",
        "topic": "posture",
        "minutes": 3,
        "cover_image_url": null,
        "body": "",
        "published_at": "2026-10-01T00:00:00Z",
        "sources": []
      }
    ]
    """.utf8)

    static let backend = ArticleBackend(projectURL: URL(string: "https://example.supabase.co")!,
                                        publishableKey: "sb_publishable_fixture")

    static func response(_ status: Int, for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
}
