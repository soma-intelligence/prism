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

    /// The calm tone the topic is painted in: the muted family Track and
    /// Today use, so the library reads as part of the same app rather than
    /// as a wall of Health's saturated category colours.
    var tone: SomaTrackTone {
        switch self {
        case .sleep: .dusk
        case .heart: .rose
        case .recovery: .tide
        case .movement: .moss
        case .nutrition: .sand
        case .mind: .sage
        case .longevity: .clay
        }
    }

    /// The line glyph on a generated cover, from the aspect and Track
    /// families so a sleep piece wears the same crescent as Today's sleep.
    var mark: SomaArticleCover.Mark {
        switch self {
        case .sleep: .aspect(.sleep)
        case .heart: .aspect(.heart)
        case .recovery: .track(.hrv)
        case .movement: .aspect(.activity)
        case .nutrition: .aspect(.gut)
        case .mind: .aspect(.mind)
        case .longevity: .aspect(.body)
        }
    }

    /// The topic as a person's own: "your sleep", for a reason line.
    var yours: String {
        switch self {
        case .sleep: "your sleep"
        case .heart: "your heart"
        case .recovery: "your recovery"
        case .movement: "your activity"
        case .nutrition: "what you eat"
        case .mind: "your mind"
        case .longevity: "your body"
        }
    }

    /// The topic an aspect of the person reads under.
    init(aspect: SomaAspect) {
        switch aspect {
        case .sleep: self = .sleep
        case .mind: self = .mind
        case .heart: self = .heart
        case .activity: self = .movement
        case .gut: self = .nutrition
        case .body: self = .longevity
        }
    }
}
