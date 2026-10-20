//
//  SomaMetrics+MetricPage.swift
//  SomaUI
//

import CoreGraphics

/// The sizes a metric's page draws with: its hero, its chart and the strip of
/// facts under it.
///
/// Computed, like the other page sizes, so they add no stored field to the
/// theme.
public extension SomaMetrics {
    /// The gap between the hero's caption, its number and its meaning.
    var metricHeroSpacing: CGFloat { 4 }
    /// The dot that leads the meaning line, in its tone.
    var metricMeaningDot: CGFloat { 7 }

    /// The plot of a metric's chart, its axis labels left out.
    var metricChartHeight: CGFloat { 210 }
    /// The trailing column that holds the band's two labels.
    var metricChartGutter: CGFloat { 44 }
    /// The widest a bar grows when a span holds few of them.
    var metricChartBarMaxWidth: CGFloat { 18 }
    /// A bar's share of its slot; the rest is the gap.
    var metricChartBarShare: CGFloat { 0.58 }
    /// The thinnest a bar gets when a span holds many.
    var metricChartBarMinWidth: CGFloat { 2 }
    /// The line's stroke, and the dot that ends it.
    var metricChartLine: CGFloat { 2.25 }
    var metricChartEndDot: CGFloat { 9 }
    /// A reading on a sparse chart.
    var metricChartPoint: CGFloat { 7 }
    /// How strongly the person's usual band shows behind the data: a quiet
    /// ground in the ink, so the values keep the only colour.
    var metricChartBandOpacity: Double { 0.06 }
    /// How strongly the fill under a line shows at the line; it fades to
    /// nothing at the foot.
    var metricChartFillOpacity: Double { 0.16 }
    /// A bar or a dot that is context rather than the latest or the one
    /// being read.
    var metricChartContextOpacity: Double { 0.65 }
    /// How far a context bar's hue is softened toward the secondary ink.
    var metricChartContextMix: Double { 0.45 }
    /// Points a line is resampled to, so two spans of different lengths
    /// can morph into each other.
    var metricChartSamples: Int { 96 }
    /// How far an axis label's centre keeps from the plot's sides.
    var metricChartLabelInset: CGFloat { 20 }
    /// How far a finger travels sideways before the chart takes the drag.
    var metricChartScrubReach: CGFloat { 6 }

    /// A fact's column inside the strip.
    var metricFactSpacing: CGFloat { 2 }
}
