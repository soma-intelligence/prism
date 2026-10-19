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
    /// The sun's path from horizon to the top of its arc, labels apart.
    var environmentSunPathHeight: CGFloat { 74 }
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
}
