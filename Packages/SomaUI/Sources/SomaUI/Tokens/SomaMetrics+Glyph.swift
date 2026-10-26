//
//  SomaMetrics+Glyph.swift
//  SomaUI
//

import CoreGraphics

/// The sizes a glyph is set at, and the weight of its line.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// The grid every glyph is drawn on.
    var glyphGrid: CGFloat { 24 }
    /// The line, on that grid: the weight of the Pulse, Longevity and Track
    /// tab glyphs, so the two families sit side by side.
    var glyphStroke: CGFloat { 1.6 }
    /// Beside a label, at the height of its line.
    var glyphInline: CGFloat { browseGlyphSize }
    /// Leading a row of a list of readings.
    var glyphRow: CGFloat { browseGlyphSize + 2 }
    /// Over a hero value, or in a score row.
    var glyphLead: CGFloat { markSize }
    /// The dot that leads a status word under a value: a third of the glyph
    /// grid, so it matches the solid detail every glyph carries.
    var statusDotSize: CGFloat { glyphGrid / 3 }
}
