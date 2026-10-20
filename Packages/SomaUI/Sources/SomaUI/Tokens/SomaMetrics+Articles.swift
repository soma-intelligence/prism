//
//  SomaMetrics+Articles.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of the article library: the featured card, the grid of
/// tiles, the rows and shelves, the topic chips and the reader page.
///
/// Computed so they add no stored field to the theme. Read at one size for
/// touch and pointer: a cover is a picture, and a picture does not shrink
/// because a cursor is more precise than a finger.
public extension SomaMetrics {
    /// The cover over the featured article, Apple Health's large illustration.
    var articleFeatureCoverHeight: CGFloat { 236 }
    /// A tile's cover in the grid and on a shelf.
    var articleTileCoverHeight: CGFloat { 132 }
    /// The square cover at the head of a row.
    var articleRowCoverSide: CGFloat { 76 }
    /// The narrowest a grid column may get before the grid drops a column.
    var articleTileMinWidth: CGFloat { 150 }
    /// A card in the sideways rail of news.
    var articleRailCardWidth: CGFloat { 236 }
    /// A tile on a topic shelf: two and a bit show on a phone, so the shelf
    /// says it scrolls.
    var articleShelfCardWidth: CGFloat { 164 }
    /// The cover across the top of the reader page.
    var articleReaderCoverHeight: CGFloat { 300 }
    /// The featured card and the reader cover share this radius.
    var articleCoverCornerRadius: CGFloat { 22 }
    /// A tile's cover: smaller picture, tighter corner.
    var articleTileCornerRadius: CGFloat { 16 }
    /// A row's square cover.
    var articleRowCornerRadius: CGFloat { 14 }
    /// Between tiles, across and down.
    var articleGridSpacing: CGFloat { 14 }
    /// Between the lines of text under a cover.
    var articleTextSpacing: CGFloat { 4 }
    /// The coloured dot that leads a topic chip and a reason.
    var articleChipDot: CGFloat { 8 }
    /// The extra leading of a reader paragraph, an airy body.
    var articleBodyLineSpacing: CGFloat { 6 }
    /// Between two blocks of a reader page.
    var articleBlockSpacing: CGFloat { 18 }

    // MARK: The generated cover

    /// The line glyph at the heart of a generated cover, by cover size.
    var articleCoverGlyphFeature: CGFloat { 34 }
    var articleCoverGlyphTile: CGFloat { 24 }
    var articleCoverGlyphRow: CGFloat { 20 }
    /// The quiet disc the glyph sits on, as a multiple of the glyph.
    var articleCoverMedallion: CGFloat { 2.1 }
    /// How much of the card's surface that disc keeps, light and dark.
    var articleCoverMedallionLight: Double { 0.72 }
    var articleCoverMedallionDark: Double { 0.55 }
    /// How much of the topic's tone washes the cover, top and bottom of its
    /// gradient, on a light page and on a dark one. Low: a cover is a calm
    /// tint of the card, not a poster.
    var articleCoverWashLight: (top: Double, bottom: Double) { (0.15, 0.30) }
    var articleCoverWashDark: (top: Double, bottom: Double) { (0.18, 0.31) }
    /// The second tone that drifts in from one corner, for variety.
    var articleCoverDrift: Double { 0.16 }
    /// The rings: a hairline in the tone.
    var articleCoverRingOpacity: Double { 0.34 }
    var articleCoverRingWidth: CGFloat { 1 }
    /// A filled disc (a sun on the horizon, a body in orbit).
    var articleCoverDiscOpacity: Double { 0.22 }
}
