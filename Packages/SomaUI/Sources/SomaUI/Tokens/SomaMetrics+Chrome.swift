//
//  SomaMetrics+Chrome.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the top bar's own pieces draw with: the notifications glyph and
/// the top edge of a page scrolling under the bar.
///
/// Computed, like the other part sizes, so they add no stored field to the
/// theme.
public extension SomaMetrics {
    /// How far below the bar the page's ground goes on fading to clear, so
    /// content slides out from under the bar rather than meeting an edge.
    var edgeFadeDepth: CGFloat { 36 }
    /// How far the page scrolls before the fade is fully drawn. At rest the
    /// page's own head (a photograph, the orb) shows under the bar untouched;
    /// the ground rises over it as the content goes up.
    var edgeFadeRamp: CGFloat { 44 }
    /// Where the fade starts to give way, as a fraction of its height from the
    /// top of the screen. Above it the ground is all but solid, under the
    /// status bar and the top of the bar's buttons.
    var edgeFadeSolidRun: Double { 0.42 }
    /// The ground's strength at the very top. A hair under solid, so a bright
    /// card passing under the clock still reads as being under it.
    var edgeFadeTopOpacity: Double { 0.97 }

    /// The notifications glyph in the top bar: the square it takes in the
    /// bar (the system glyph's, so its glass disc matches the account's), the
    /// square the bell is drawn on, a little larger and spilling past it
    /// because a bell fills less of its square than a filled figure does, and
    /// its stroke on the 24 unit grid, a touch heavier than the aspect glyphs'
    /// so the line holds its own next to that figure.
    var notificationGlyph: CGFloat { 24 }
    var notificationGlyphArt: CGFloat { 26 }
    var notificationGlyphStroke: CGFloat { 1.75 }
}
