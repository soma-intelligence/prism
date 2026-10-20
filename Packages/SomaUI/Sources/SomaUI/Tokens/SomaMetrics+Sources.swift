//
//  SomaMetrics+Sources.swift
//  SomaUI
//

import CoreGraphics

/// The sizes of the quiet list of where a metric's readings came from.
public extension SomaMetrics {
    /// The disc that holds a source's glyph or initial.
    var sourceGlyphDisc: CGFloat { 30 }
    var sourceGlyphSize: CGFloat { 14 }
    /// The thin track a source's share is drawn on.
    var sourceShareWidth: CGFloat { 48 }
    var sourceShareHeight: CGFloat { 4 }
}
