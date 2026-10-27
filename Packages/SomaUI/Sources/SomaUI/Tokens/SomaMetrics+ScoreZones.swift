//
//  SomaMetrics+ScoreZones.swift
//  SomaUI
//

import CoreGraphics

/// The sizes Today's three score dials read (``SomaScoreZones``).
///
/// Each dial is ``SomaMetrics/scoreDialDiameter`` across, range arc
/// included; the sizes below are each dial's own. Computed so they add no
/// stored field to the theme, read at one size for touch and pointer alike.
public extension SomaMetrics {
    /// The space between a dial and the name under it.
    var scoreDialLabelSpacing: CGFloat { 8 }
    /// The space between a number and its trend mark.
    var scoreDialMarkSpacing: CGFloat { 3 }
    /// A track under a score, as a share of the score's hue.
    var scoreTrackOpacity: Double { 0.14 }

    /// The band the three zones share.
    var scoreZonesStroke: CGFloat { 7 }
    /// The air between two zones, in degrees.
    var scoreZonesGapDegrees: Double { 6 }
    /// How deep each zone's fill is, low to high, as a share of the hue.
    var scoreZonesDepth: [Double] { [0.5, 0.75, 1] }
    /// The bead riding at the score, and the canvas ring that cuts it out of
    /// the band.
    var scoreZonesBead: CGFloat { 13 }
    var scoreZonesBeadRim: CGFloat { 3 }
    /// The short tick across the band for the usual.
    var scoreZonesUsualLength: CGFloat { 11 }
    var scoreZonesUsualWidth: CGFloat { 2 }
    /// The air between the bead's edge and the range arc outside the band,
    /// so the bead never touches the arc as it rides under it.
    var scoreZonesRangeClearance: CGFloat { 1.5 }
}
