//
//  SomaMetrics+Charts.swift
//  SomaUI
//

import CoreGraphics

/// The proportions every chart in the app shares: a hairline grid, few ticks, thin bars, hollow dots, one plot height.
///
/// Computed so they add no stored field to the theme, and one size for touch
/// and pointer alike: a chart is read, not tapped.
public extension SomaMetrics {
    /// The grid's hairlines, against the ink.
    var chartGridOpacity: Double { 0.15 }
    /// The normal range behind a line, in the status green.
    var chartBandOpacity: Double { 0.16 }
    /// The top of the soft fill under a sparkline; it fades to nothing.
    var chartFillOpacity: Double { 0.26 }
    /// A bar that is context rather than the one the chart is about.
    var chartContextBarOpacity: Double { 0.45 }

    /// A chart on a detail page or in a full width card.
    var chartPlotHeight: CGFloat { 150 }
    /// A chart that shares its card with a headline and a legend.
    var chartCompactPlotHeight: CGFloat { 110 }
    /// A sparkline in a trend row or tile.
    var chartSparkHeight: CGFloat { 36 }
    /// A trend row's height: title, status and a cue line, held even when
    /// the row has no cue.
    var trendRowMinHeight: CGFloat { 92 }
    /// A trend tile's height: title, value, status and its chart, so tiles
    /// side by side share one top edge and one chart baseline.
    var trendTileMinHeight: CGFloat { 164 }
    /// The chart at a trend tile's foot.
    var trendTileChartHeight: CGFloat { 44 }
    /// How many points an eased sparkline keeps: a month of days averaged
    /// down to about one point every day and a half.
    var sparkEasedPoints: Int { 20 }
    /// The faint halo round the last value of an eased sparkline.
    var chartHaloOpacity: Double { 0.22 }
    /// The gap between the day bars of a trend tile.
    var sparkBarGap: CGFloat { 2 }
    /// Room kept round the plot so a dot on the edge is never clipped.
    var chartPlotInset: CGFloat { 6 }
    /// Gap between the plot and its labels.
    var chartLabelGap: CGFloat { spaceXS }

    /// The stroke of a chart's line.
    var chartStroke: CGFloat { 1.75 }
    /// A hollow dot on each value of a short series.
    var chartPointDiameter: CGFloat { 6 }
    /// The ring that ends a line: the latest value.
    var chartRingDiameter: CGFloat { 10 }
    /// A thin bar, and the radius of its ends.
    var chartThinBarWidth: CGFloat { 6 }
    var chartThinBarRadius: CGFloat { 1.5 }

    /// One lane of a hypnogram, and the share of it a stage block fills.
    var hypnogramLaneHeight: CGFloat { 26 }
    var hypnogramBlockShare: CGFloat { 0.62 }
}

/// The trend tile, set like a metric page's head: the gap between its name
/// line and its value, the chart beside the value, and the band's edges
/// named on the chart's trailing side (the gap to them, their column, and
/// the least room two labels need before they part).
public extension SomaMetrics {
    var trendTileSpacing: CGFloat { 8 }
    var trendTileLabelGap: CGFloat { 6 }
    var trendTileLabelWidth: CGFloat { 34 }
    var trendTileLabelLine: CGFloat { 16 }

    /// The line that closes a night on a day's chart, in the sleep hue.
    var chartNightEdgeOpacity: Double { 0.5 }
}

/// Sizes other components still read, kept from the parallel design lines.
public extension SomaMetrics {
    /// A sparkline's stroke, the dot that ends it on the latest value, the
    /// points its curve is drawn through, and how far its line is softened
    /// toward the secondary ink (the dot keeps the full hue).
    var sparkLine: CGFloat { 1.75 }
    var sparkEndDot: CGFloat { 7 }
    var sparkSamples: Int { 48 }
    var sparkLineMix: Double { 0.3 }
}
