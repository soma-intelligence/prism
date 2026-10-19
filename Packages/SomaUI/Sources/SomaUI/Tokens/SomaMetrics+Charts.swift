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
    /// Room kept round the plot so a dot on the edge is never clipped.
    var chartPlotInset: CGFloat { 6 }
    /// Gap between the plot and its labels.
    var chartLabelGap: CGFloat { 6 }

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
