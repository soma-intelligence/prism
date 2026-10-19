//
//  SomaMetrics+Health.swift
//  SomaUI
//

import CoreGraphics

/// The measurements of the Health style surfaces (the Vault), read off Apple
/// Health on iOS 27 and scaled to a 402 point screen.
public extension SomaMetrics {
    /// A category tile's least height.
    var healthTileHeight: CGFloat { 100 }
    /// The glyph on a category tile.
    var healthTileGlyph: CGFloat { 26 }
    /// The corner of a tile and of a summary card: rounder than a card.
    var healthCardRadius: CGFloat { 22 }
    /// The seven bars at the end of a summary card.
    var healthBarsWidth: CGFloat { 78 }
    var healthBarsHeight: CGFloat { 50 }
}
