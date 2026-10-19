//
//  SomaMetrics+Articles.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of the article library: the featured card, the grid of
/// tiles, the topic chips and the reader page.
///
/// Computed so they add no stored field to the theme. Read at one size for
/// touch and pointer: a cover is a picture, and a picture does not shrink
/// because a cursor is more precise than a finger.
public extension SomaMetrics {
    /// The cover over the featured article, Apple Health's large illustration.
    var articleFeatureCoverHeight: CGFloat { 236 }
    /// A tile's cover in the grid.
    var articleTileCoverHeight: CGFloat { 132 }
    /// The narrowest a grid column may get before the grid drops a column.
    var articleTileMinWidth: CGFloat { 150 }
    /// A card in the sideways rail of news.
    var articleRailCardWidth: CGFloat { 236 }
    /// The cover across the top of the reader page.
    var articleReaderCoverHeight: CGFloat { 300 }
    /// The featured card and the reader cover share this radius.
    var articleCoverCornerRadius: CGFloat { 22 }
    /// A tile's cover: smaller picture, tighter corner.
    var articleTileCornerRadius: CGFloat { 16 }
    /// Between tiles, across and down.
    var articleGridSpacing: CGFloat { 14 }
    /// Between the lines of text under a cover.
    var articleTextSpacing: CGFloat { 4 }
    /// The topic glyph drawn on a generated cover.
    var articleFeatureGlyphSize: CGFloat { 64 }
    var articleTileGlyphSize: CGFloat { 34 }
    /// The coloured dot that leads a topic chip.
    var articleChipDot: CGFloat { 8 }
    /// The glyph's strength on a generated cover, and the rings' behind it.
    var articleCoverGlyphOpacity: Double { 0.92 }
    var articleCoverRingOpacity: Double { 0.16 }
    /// The extra leading of a reader paragraph, an airy body.
    var articleBodyLineSpacing: CGFloat { 6 }
    /// Between two blocks of a reader page.
    var articleBlockSpacing: CGFloat { 18 }
}
