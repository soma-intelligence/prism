//
//  SomaMetrics+Links.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of a cause and effect card: the two sides as a pair of
/// columns under the headline, their averages and the labels under them.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// The bar an average sits on, and twice the line that joins the two.
    var linkTrackHeight: CGFloat { 4 }
    /// How strongly the line between the two averages shows.
    var linkSpanOpacity: Double { 0.35 }
    /// Gap between the headline, the line under it and the track.
    var linkCardSpacing: CGFloat { 8 }
    /// The pair of columns, before and after: its height with the room
    /// over the plot for the averages' numbers, each column's width (and its
    /// average's bar), and a day's faint dot.
    var linkPairHeight: CGFloat { 120 }
    var linkPairLabelRoom: CGFloat { 26 }
    var linkPairLaneWidth: CGFloat { 44 }
    var linkPairDayDot: CGFloat { 5 }
    var linkPairDayOpacity: Double { 0.28 }
}

/// Sizes other components still read, kept from the parallel design lines.
public extension SomaMetrics {
    /// The strip's width beside the effect, and its height for two rows.
    var linkStripWidth: CGFloat { 132 }
    var linkStripHeight: CGFloat { 30 }
    /// One day's dot on the strip.
    var linkStripDot: CGFloat { 5 }
    /// A day's dot against its row's mean mark, which is drawn solid.
    var linkStripDotOpacity: Double { 0.42 }
    /// The mean mark's width.
    var linkStripMeanWidth: CGFloat { 2.5 }
}
