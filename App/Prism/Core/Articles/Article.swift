//
//  Article.swift
//  Prism
//

import Foundation
import SomaUI

/// One piece to read on Explore: general wellness reading, never about Soma's
/// own hardware and never a diagnosis.
struct Article: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var slug: String
    var title: String
    /// The one line under the title.
    var subtitle: String
    var topic: ArticleTopic
    /// Reading time, whole minutes.
    var minutes: Int
    var coverImageURL: URL?
    /// Markdown: `##` headings, paragraphs, `-` lists and inline emphasis.
    var body: String
    var publishedAt: Date
    var sources: [ArticleCitation]
    /// The cover photograph's credit, and for a bundled article the image in
    /// the asset catalog that stands in for `coverImageURL`.
    var photo: ArticlePhoto? = nil

    /// "4 min".
    var readingTime: String { "\(minutes) min" }

    /// Title, subtitle and body, for Explore search.
    var searchText: String { "\(title) \(subtitle) \(body)" }

    /// A case-insensitive match on the title, subtitle or body.
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return searchText.localizedStandardContains(needle)
    }
}

/// Where a claim in an article comes from.
struct ArticleCitation: Hashable, Codable, Sendable {
    var title: String
    /// The journal or the body that published it: "Sleep, 2024".
    var publisher: String?
    var url: URL?
}

/// A cover photograph: where it is, and who took it.
struct ArticlePhoto: Hashable, Codable, Sendable {
    /// The image in the app's asset catalog, for a bundled article.
    var asset: String?
    /// The photographer, as the licence asks to credit them.
    var credit: String
    /// The photo's page, "unsplash.com/photos/<id>".
    var url: URL?
    /// Where it was found: "Unsplash".
    var library: String

    /// "Photo: Name, Unsplash".
    var line: String { "Photo: \(credit), \(library)" }
}

/// What an article is about. The raw values are the strings the
/// `app_articles.topic` column holds.
enum ArticleTopic: String, CaseIterable, Codable, Sendable {
    case sleep, heart, recovery, movement, nutrition, mind, longevity

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .heart: "Heart"
        case .recovery: "Recovery"
        case .movement: "Movement"
        case .nutrition: "Nutrition"
        case .mind: "Mind"
        case .longevity: "Longevity"
        }
    }

    /// The Health hue the topic is painted in: the same colours Apple
    /// Health gives these categories, so a sleep piece reads as sleep.
    var hue: SomaHealthHue {
        switch self {
        case .sleep: .sleep
        case .heart: .heart
        case .recovery: .respiratory
        case .movement: .activity
        case .nutrition: .nutrition
        case .mind: .mind
        case .longevity: .symptoms
        }
    }

    /// The glyph on a generated cover.
    var symbol: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .heart: "heart.fill"
        case .recovery: "bolt.heart.fill"
        case .movement: "figure.run"
        case .nutrition: "leaf.fill"
        case .mind: "wind"
        case .longevity: "infinity"
        }
    }
}
