//
//  SomaMetrics+Sleep.swift
//  SomaUI
//

import CoreGraphics

/// The sizes of last night's section:
/// the period row, the two totals, the grade grid, the hypnogram and the
/// stage tiles.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// A lane of the full width hypnogram, where it is the card's subject.
    var hypnogramTallLaneHeight: CGFloat { 40 }
    /// The corner of a stage block.
    var hypnogramBlockRadius: CGFloat { 4 }
    /// The thin line joining one stage block to the next.
    var hypnogramConnectorWidth: CGFloat { 1 }
    /// The glyph in the moon and sun chips under the hypnogram.
    var hypnogramEndGlyph: CGFloat { 10 }
    /// The chips' inner padding, across and down.
    var hypnogramEndPadding: CGFloat { 6 }

    /// The glyph at the head of the period row, and of each grade cell.
    var sleepGlyphSize: CGFloat { 15 }
    /// A grade's progress bar: its length, and its height.
    var sleepGradeBarWidth: CGFloat { 88 }
    var sleepGradeBarHeight: CGFloat { 4 }
    /// The vertical room round a grade cell.
    var sleepGradeCellPadding: CGFloat { 14 }

    /// The share ring in a stage tile, and its stroke.
    var sleepStageRingDiameter: CGFloat { 46 }
    var sleepStageRingStroke: CGFloat { 5 }
    /// The track under that ring, against the ink.
    var sleepStageRingTrackOpacity: Double { 0.12 }
}
