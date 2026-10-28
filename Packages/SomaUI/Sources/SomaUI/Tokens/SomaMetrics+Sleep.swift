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

    /// The full bleed night, read off the earlier app's sleep sheet (owner,
    /// 2026-10-27): no card, no lane names, four lanes with a block in the
    /// middle of each at a little over half its height, cornered and ringed
    /// in a shade of its colour, a minute awake still a pill, and a hairline
    /// on the seam between two stages. Under the plot, the room the night's
    /// ground takes to fade into the page.
    var hypnogramBleedLaneHeight: CGFloat { 58 }
    var hypnogramBleedBlockShare: CGFloat { 0.62 }
    var hypnogramBleedBlockRadius: CGFloat { 6 }
    var hypnogramBleedMinBlockWidth: CGFloat { 2.5 }
    var hypnogramBleedRimWidth: CGFloat { 4 }
    var hypnogramBleedThreadWidth: CGFloat { 1.5 }
    var hypnogramBleedFoot: CGFloat { 48 }
    /// How far a stage's colour sinks into the page for its rim, and for the
    /// thread that joins it to the next stage.
    var hypnogramBleedRimShade: Double { 0.58 }
    var hypnogramBleedThreadShade: Double { 0.42 }
    /// While a finger reads the night, how far the blocks it is not on fade.
    var hypnogramBleedDimmed: Double { 0.45 }
    /// The finger's cursor, and the reading floating over the plot.
    var hypnogramBleedCursorWidth: CGFloat { 1.5 }
    /// The cursor's strength at its ends and in its middle, so it fades out
    /// both ways and reads as a cursor rather than a hard rule.
    var hypnogramBleedCursorEnds: Double { 0.05 }
    var hypnogramBleedCursorPeak: Double { 0.6 }
    /// How strong the night's sky already is halfway down the plot, before
    /// it reaches its full colour at the deep lane.
    var hypnogramBleedSkyRise: Double { 0.55 }
    var hypnogramBleedReadingWidth: CGFloat { 104 }
    var hypnogramBleedReadingDot: CGFloat { 6 }

    /// The head under the full bleed night, set as the earlier app set its
    /// hero: a moon in a disc beside the title and the night's span, the
    /// score's ring on the trailing edge, and the two totals under them.
    var sleepHeadlineDisc: CGFloat { 38 }
    var sleepHeadlineDiscGlyph: CGFloat { 18 }
    var sleepHeadlineDiscFill: Double { 0.12 }
    var sleepHeadlineDiscRim: Double { 0.2 }
    var sleepHeadlineDiscRimWidth: CGFloat { 1 }
    var sleepHeadlineDial: CGFloat { 78 }
    var sleepHeadlineSpacing: CGFloat { 16 }

    /// The stage breakdown: the stacked bar's height, its corner and the gap
    /// between two stages, the dot leading a row, and the pill a share sits in.
    var sleepStageBarHeight: CGFloat { 18 }
    var sleepStageBarRadius: CGFloat { 6 }
    var sleepStageBarGap: CGFloat { 3 }
    var sleepStageDot: CGFloat { 10 }
    var sleepStageShareWidth: CGFloat { 56 }
    var sleepStageShareHeight: CGFloat { 24 }

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

    /// The time to fall asleep: the scale's track, the band the night fell
    /// in set in the sleep colour this strong, and the marker on the track
    /// with the ring that lifts it off it.
    var fallAsleepTrackHeight: CGFloat { 6 }
    var fallAsleepBandOpacity: Double { 0.45 }
    var fallAsleepMarker: CGFloat { 16 }
    var fallAsleepMarkerRing: CGFloat { 3 }

    /// The sleep debt plot's legend: the stroke standing for the debt line.
    var sleepDebtLegendLine: CGFloat { 12 }

    /// The moon on the morning's rating card.
    var sleepFeltMoon: CGFloat { 40 }
}
