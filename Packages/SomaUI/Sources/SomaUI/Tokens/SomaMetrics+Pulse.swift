//
//  SomaMetrics+Pulse.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the Pulse tab's Trends and Explore parts draw with.
///
/// Kept apart from ``SomaMetrics``'s stored scale on purpose: these are the
/// parts' own proportions, read from the design at one size for touch and
/// pointer alike, and computed so they add no stored field to the theme.
public extension SomaMetrics {
    // MARK: Trends

    /// The orb that leads a row of the three scores.
    var pulseRowOrbDiameter: CGFloat { 28 }
    /// The sparkline beside each of the three scores.
    var pulseSparklineWidth: CGFloat { 100 }
    var pulseSparklineHeight: CGFloat { 26 }
    /// Room at the trailing edge of a row for its value.
    var pulseRowValueWidth: CGFloat { 52 }
    /// The month's cumulative steps: the plot, its axis labels included.
    var pulseMonthPlotHeight: CGFloat { 180 }
    /// The trailing column that carries the month plot's value labels.
    var pulseAxisLabelWidth: CGFloat { 35 }
    /// The spiral of a year of nights.
    var pulseYearPlotHeight: CGFloat { 250 }
    /// The smallest and largest night on the spiral.
    var pulseNightDotRange: ClosedRange<CGFloat> { 2...5.5 }
    /// The glow round the one point a chart is about: today, last night.
    var pulseGlowDiameter: CGFloat { 30 }
    /// The active days grid: one row a weekday, one column a week.
    var pulseHeatRowPitch: CGFloat { 11 }
    var pulseHeatMaxColumnPitch: CGFloat { 11.5 }
    var pulseHeatLabelColumn: CGFloat { 26 }
    var pulseHeatMonthRow: CGFloat { 18 }

    // MARK: Explore

    /// The photograph that leads the Explore part.
    var pulseHeroPhotoHeight: CGFloat { 420 }
    var pulseHeroPhotoCornerRadius: CGFloat { cardCornerRadius }
    /// The tile a suggested read's orb sits on, and the orb inside it.
    var pulseTileSide: CGFloat { 64 }
    var pulseTileOrbDiameter: CGFloat { 48 }
    /// A card in the horizontal run of measured reads.
    var pulseShelfCardWidth: CGFloat { 240 }
    var pulseShelfPhotoHeight: CGFloat { 180 }
    /// The photograph over Soma's story.
    var pulseStoryPhotoHeight: CGFloat { 200 }
    /// The photograph at the head of a reader page.
    var pulseReaderPhotoHeight: CGFloat { 260 }
}
