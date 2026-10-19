//
//  SomaMetrics+Explainer.swift
//  SomaUI
//

import CoreGraphics

/// The sizes an explainer draws with: the sheet behind an info button, read
/// for a picture first, then a few short rows.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// The ring or donut at the head of the sheet, across.
    var explainerHeroDiameter: CGFloat { 184 }
    /// Its stroke.
    var explainerHeroStroke: CGFloat { 20 }
    /// The gap between two parts of the donut, as a fraction of the turn.
    var explainerDonutGap: Double { 0.008 }
    /// Room above the hero, under the close button.
    var explainerHeroTopPadding: CGFloat { 28 }
    /// Gap between the title block and each section under it.
    var explainerSectionSpacing: CGFloat { 22 }
    /// Gap between the title and the line under it.
    var explainerTitleSpacing: CGFloat { 8 }
    /// The tinted disc that holds a row's glyph, and the glyph in it.
    var explainerGlyphDiameter: CGFloat { 34 }
    var explainerGlyphSize: CGFloat { 15 }
    /// Opacity of that disc's tint.
    var explainerGlyphTint: Double { 0.16 }
    /// Gap between the glyph and the words of a row.
    var explainerRowGap: CGFloat { 14 }
    /// Inset of a row inside its section.
    var explainerRowPadding: CGFloat { 14 }
    /// Gap between a row's term and its line.
    var explainerLineSpacing: CGFloat { 2 }
    /// The band over a section that names it.
    var explainerSectionHeaderPadding: CGFloat { 12 }
    /// Height of a contribution bar.
    var explainerBarHeight: CGFloat { 6 }
    /// Gap between a contribution's words and its bar.
    var explainerBarGap: CGFloat { 8 }
    /// Height of the ranges strip, the gap between its bands, and its marker.
    var explainerRangeHeight: CGFloat { 10 }
    var explainerRangeGap: CGFloat { 3 }
    var explainerRangeMarker: CGFloat { 16 }
    /// Room the marker's label takes over the strip.
    var explainerRangeLabelRoom: CGFloat { 22 }
    /// Widest the sheet's column grows.
    var explainerMaxWidth: CGFloat { 560 }
    /// The sheet's size in a Mac window, where a sheet takes the size of its
    /// content unless told.
    var explainerSheetWidth: CGFloat { 480 }
    var explainerSheetHeight: CGFloat { 680 }
    /// Opacity of the aspect's wash at the top of the sheet.
    var explainerWashOpacity: Double { 0.22 }
}
