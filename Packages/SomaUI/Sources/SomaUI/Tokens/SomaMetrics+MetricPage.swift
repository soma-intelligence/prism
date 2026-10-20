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

    /// The ring beside a score page's number, and its stroke: Today's score
    /// rings grown, with the same weight of line.
    var scoreHeroDial: CGFloat { 104 }
    var scoreHeroStroke: CGFloat { 7 }
    /// The ring's faint track, and the person's usual laid over it.
    var scoreHeroTrackOpacity: Double { 0.13 }
    var scoreHeroUsualOpacity: Double { 0.32 }
    /// The room above a score page's head, under the bar.
    var scoreHeroTopPadding: CGFloat { 8 }

    /// A reading's row: the gap between its name and when it was read, the
    /// week's small line, and the column its value sits in.
    var readingRowLineGap: CGFloat { 2 }
    var readingRowSparkWidth: CGFloat { 56 }
    var readingRowSparkHeight: CGFloat { 22 }
    var readingRowValueWidth: CGFloat { 52 }

    /// The plot of a fortnight of sleep windows, labels left out.
    var sleepWindowsHeight: CGFloat { 150 }

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
    /// How strongly the person's usual band shows behind the data: the
    /// chart's hue softened most of the way to the secondary ink, so it reads
    /// as a calm ground of the same family rather than a grey slab.
    var metricChartBandOpacity: Double { 0.13 }
    /// How far the band's hue is softened toward the secondary ink.
    var metricChartBandMix: Double { 0.55 }
    /// The band's two edges, drawn as hairlines in the same tint.
    var metricChartBandEdgeOpacity: Double { 0.32 }
    /// How strongly the fill under a line shows at the line; it fades to
    /// nothing at the foot.
    var metricChartFillOpacity: Double { 0.16 }
    /// A bar or a dot that is context rather than the latest or the one
    /// being read.
    var metricChartContextOpacity: Double { 0.55 }
    /// How far a context bar's hue is softened toward the secondary ink.
    var metricChartContextMix: Double { 0.45 }
    /// Points a line is resampled to, so two spans of different lengths
    /// can morph into each other.
    var metricChartSamples: Int { 96 }
    /// How far an axis label's centre keeps from the plot's sides.
    var metricChartLabelInset: CGFloat { 20 }
    /// How far a finger travels sideways before the chart takes the drag.
    var metricChartScrubReach: CGFloat { 6 }

    /// The plot of a metric's stage, the chart that carries the page: taller
    /// than a card's chart and the page's full width.
    var metricStageHeight: CGFloat { 248 }
    /// The gap between the stage's head, its chart and the line under it.
    var metricStageSpacing: CGFloat { 18 }
    /// The halo around the dot that marks the latest or the picked reading,
    /// as a multiple of the dot.
    var metricChartHaloScale: CGFloat { 2.6 }
    var metricChartHaloOpacity: Double { 0.22 }
    /// The average line's dash and its strength.
    var metricChartAverageDash: [CGFloat] { [2, 4] }
    var metricChartAverageOpacity: Double { 0.45 }
    /// The small swatch that leads each key above the plot.
    var metricChartKeySwatch: CGFloat { 14 }
    /// How far the highest and lowest labels sit off their mark.
    var metricChartExtremeGap: CGFloat { 6 }

    /// A fact's column inside the strip.
    var metricFactSpacing: CGFloat { 2 }
}
