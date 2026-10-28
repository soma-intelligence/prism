//
//  SomaMetrics+Aspects.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the six aspect glyphs and the tiles that carry them draw with.
///
/// Computed, like the other part sizes, so they add no stored field to the
/// theme.
public extension SomaMetrics {
    /// The square every aspect glyph is drawn on, in grid units: the paths are
    /// written on this grid and scaled to the frame.
    var aspectGlyphGrid: CGFloat { 24 }
    /// The stroke on that grid, the same for all six so they read as a set.
    var aspectGlyphStroke: CGFloat { 1.6 }
    /// A glyph set inline: beside a move, at the head of a card.
    var aspectGlyphInline: CGFloat { 20 }
    /// A glyph beside an eyebrow.
    var aspectGlyphCaption: CGFloat { 15 }
    /// The tinted square a glyph sits on in a tile or a list row, and the
    /// glyph inside it.
    var aspectBadgeSide: CGFloat { 36 }
    var aspectBadgeGlyph: CGFloat { 22 }
    var aspectBadgeCornerRadius: CGFloat { 10 }
    /// How strongly the badge is tinted with the aspect's hue.
    var aspectBadgeTint: Double { 0.14 }

    /// A tile in the grid of aspects: its height and the gap between tiles.
    var aspectTileHeight: CGFloat { 96 }
    var aspectTileSpacing: CGFloat { 10 }

    /// A quiet pill under a section: its height and its inset.
    var quietPillHeight: CGFloat { 40 }
    var quietPillPadding: CGFloat { 16 }
}

/// The aspect backdrop's photograph and colour field: how much of the page's
/// ground veils the photograph from the bar down, how strong and how soft
/// the colour field is, and where its fade passes the middle.
public extension SomaMetrics {
    /// The ground over the photograph at its top, a third of the way down
    /// and two thirds of the way down; it is whole at the foot.
    var backdropVeilOpacities: (top: Double, third: Double, lower: Double) { (0.08, 0.5, 0.82) }
}
