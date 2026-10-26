//
//  SomaMetrics+Today.swift
//  SomaUI
//

import CoreGraphics

/// The sizes Today's body figure, reading tiles and day plan draw with.
///
/// Read from the design at one size for touch and pointer alike, and computed
/// so they add no stored field to the theme.
public extension SomaMetrics {
    /// A pin on the body figure: the outer ring's diameter.
    var bodyPinDiameter: CGFloat { 13 }
    /// The ring round a pin.
    var bodyPinRingWidth: CGFloat { 1.5 }
    /// The dot inside a pin.
    var bodyPinCoreDiameter: CGFloat { 6 }
    /// The line from a pin to its readings.
    var bodyLeaderWidth: CGFloat { 1 }
    /// The space between a leader's end and the readings it points at.
    var bodyLeaderGap: CGFloat { 6 }
    /// The widest a group of readings beside the figure grows.
    var bodyCalloutWidth: CGFloat { 140 }
    /// The space between two readings in one group.
    var bodyCalloutSpacing: CGFloat { 8 }
    /// How far the figure's grey sits from the canvas toward the secondary
    /// ink: enough to read as a shape, never as a block.
    var bodyFigureInk: CGFloat { 0.13 }
    /// The art's own swell, in its coordinates, that closes the hairline gaps
    /// the drawing leaves round every muscle.
    var bodyFigureSwell: CGFloat { 2.5 }

    /// The chart band inside a reading tile.
    var tileChartHeight: CGFloat { 44 }
    /// The space between a tile's title, value, chart and note.
    var tileSpacing: CGFloat { 6 }

    /// The day track: the bar's thickness.
    var planTrackHeight: CGFloat { 8 }
    /// The tick for a moment on the track, such as the last coffee.
    var planTickHeight: CGFloat { 16 }
    /// The line across the track at the present moment.
    var planNowHeight: CGFloat { 24 }
    /// The leading column of a plan row: its clock time.
    var planTimeWidth: CGFloat { 52 }
}
