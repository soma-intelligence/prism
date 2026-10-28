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
    var hypnogramTallLaneHeight: CGFloat { 52 }
    /// The corner of a stage block.
    var hypnogramBlockRadius: CGFloat { 4 }
    /// The thin line joining one stage block to the next.
    var hypnogramConnectorWidth: CGFloat { 1 }
    /// The night chart, measured off the earlier app's (owner, 2026-10-24): a block's
    /// share of its lane, its corner, the narrowest a block is drawn so a
    /// minute awake still shows, and the ring round it and how far into
    /// black its shade goes, and the gap between two blocks in a row, where
    /// the link between them stands. A link is one rim wide.
    var hypnogramNightBlockShare: CGFloat { 0.7 }
    var hypnogramNightBlockRadius: CGFloat { 7 }
    var hypnogramNightMinBlockWidth: CGFloat { 8 }
    var hypnogramRimWidth: CGFloat { 3 }
    var hypnogramRimShade: Double { 0.55 }
    var hypnogramNightBlockGap: CGFloat { 4 }
    /// The line joining two stages, standing in the gap between them.
    var hypnogramLinkWidth: CGFloat { 2 }
    /// The room for the lane names, left of the axis, and the gap between
    /// the axis and the first block.
    var hypnogramLaneLabelWidth: CGFloat { 52 }
    var hypnogramPlotInset: CGFloat { 6 }

    /// The glyph at the head of the period row, and of each grade cell.
    var sleepGlyphSize: CGFloat { 15 }
    /// A grade's progress bar: its length, and its height.
    var sleepGradeBarWidth: CGFloat { 88 }
    var sleepGradeBarHeight: CGFloat { 4 }
    /// The vertical room round a grade cell.
    var sleepGradeCellPadding: CGFloat { spaceM }

    /// The share ring in a stage tile, and its stroke.
    var sleepStageRingDiameter: CGFloat { 46 }
    var sleepStageRingStroke: CGFloat { 5 }
    /// The track under that ring, against the ink.
    var sleepStageRingTrackOpacity: Double { 0.12 }
}
