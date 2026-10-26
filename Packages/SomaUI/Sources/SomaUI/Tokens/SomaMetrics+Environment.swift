//
//  SomaMetrics+Environment.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the Environment lens draws its gauges with: the daylight arc,
/// the sun's path, the scale bars and the thermometer pill.
///
/// One size for touch and pointer alike, computed so they add no stored
/// field to the theme.
public extension SomaMetrics {
    /// The daylight gauge, edge to edge.
    var environmentGaugeDiameter: CGFloat { 128 }
    /// The daylight gauge's stroke.
    var environmentGaugeStroke: CGFloat { 13 }
    /// The sun's day: the curve's height, where the horizon sits on it (as
    /// a share from the top), the gap between its lines, the band its times
    /// sit in and how far they keep from the sides, the dots on the horizon
    /// at sunrise and sunset, and the fill under the arc.
    var sunPathHeight: CGFloat { 96 }
    var sunPathHorizon: CGFloat { 0.68 }
    var sunPathSpacing: CGFloat { 8 }
    var sunPathLabelHeight: CGFloat { 16 }
    var sunPathLabelInset: CGFloat { 22 }
    var sunPathTick: CGFloat { 5 }
    var sunPathFillOpacity: Double { 0.28 }
    /// The sun on its path.
    var environmentSunDiameter: CGFloat { 14 }
    /// A scale bar's track.
    var environmentScaleHeight: CGFloat { 8 }
    /// The marker riding a scale bar.
    var environmentMarkerDiameter: CGFloat { 16 }
    /// The tick that stands for a limit on a level bar.
    var environmentLimitTickHeight: CGFloat { 16 }
    /// The disc that leads the weather pill.
    var environmentPillDisc: CGFloat { 36 }
    /// The weather pill and the thermometer pill, top to bottom.
    var environmentPillHeight: CGFloat { 56 }
    /// The still maps of where you are and where you slept.
    var environmentMapHeight: CGFloat { 132 }
    /// A sleep place's pin, and last night's, which stands out.
    var environmentPinDiameter: CGFloat { 26 }
    var environmentPinLastDiameter: CGFloat { 34 }
    /// The halo round where you are.
    var environmentHaloDiameter: CGFloat { 44 }
    /// The dot that leads a sleep place's row.
    var environmentLegendDot: CGFloat { 12 }
    /// How much ground the map of where you are spans, in metres.
    var environmentMapSpan: Double { 9000 }
    /// The span the map shows round the device's own position: close enough
    /// to read the street you are on.
    var environmentMapExactSpan: Double { 900 }
    /// The sleep places heat map: how tall the tile is, the least ground it
    /// frames (metres across), and each warm spot's glow: its reach in
    /// metres, how many rings build it and how dense each ring is.
    var heatMapHeight: CGFloat { 228 }
    var heatMapMinimumSpan: Double { 640 }
    var heatSpotRadius: Double { 80 }
    var heatSpotLayers: Int { 14 }
    var heatLayerOpacity: Double { 0.06 }

    /// How far the chips over a map (the Sleep places name, its status)
    /// sit in from the tile's corners.
    var mapChipInset: CGFloat { 10 }
}

/// Sizes other components still read, kept from the parallel design lines.
public extension SomaMetrics {
    /// The sun's path from horizon to the top of its arc, labels apart.
    var environmentSunPathHeight: CGFloat { 74 }
}
