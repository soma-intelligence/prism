//
//  SomaMetrics+ScoreStyles.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the radial proposals for Today's three scores read
/// (``SomaScoresStyle``): bezel, arch, halo, echo, seven and zones.
///
/// Every proposal draws three dials of one diameter side by side, so the
/// sizes below are each dial's own. Computed so they add no stored field to
/// the theme, read at one size for touch and pointer alike.
public extension SomaMetrics {
    // MARK: Shared

    /// One dial, edge to edge.
    /// The space between a dial and the name under it.
    var scoreDialLabelSpacing: CGFloat { 8 }
    /// The space between a number and its trend mark.
    var scoreDialMarkSpacing: CGFloat { 3 }
    /// A track under a score, as a share of the score's hue.
    var scoreTrackOpacity: Double { 0.14 }
    /// What a past day or a quiet mark wears, as a share of the hue.
    var scoreQuietOpacity: Double { 0.4 }

    // MARK: Bezel

    /// The ticks round a bezel: one every six degrees, like a watch's
    /// minutes.
    var scoreBezelTicks: Int { 60 }
    /// One tick, from the rim inwards.
    var scoreBezelTickLength: CGFloat { 6 }
    var scoreBezelTickWidth: CGFloat { 1.3 }
    /// The tick that marks the person's usual: longer, and reaching out past
    /// the rim like a bezel's index, so it stands out of the row whether it
    /// is lit or not.
    var scoreBezelUsualLength: CGFloat { 10 }
    var scoreBezelUsualWidth: CGFloat { 2 }
    var scoreBezelUsualReach: CGFloat { 3 }
    /// An unlit tick, as a share of the hue: a touch stronger than a track,
    /// since a tick is thinner than a band.
    var scoreBezelRestOpacity: Double { 0.22 }

    // MARK: Arch

    /// The share of the circle the arch covers; the rest is the gap at the
    /// bottom, where the name sits.
    var scoreArchSpan: Double { 0.75 }
    /// The arch's band.
    var scoreArchStroke: CGFloat { 7 }
    /// Where the gradient starts, as a share of the hue, so the arch grows
    /// from a whisper into the colour.
    var scoreArchGradientFloor: Double { 0.32 }
    /// The notch for the usual, across the band.
    var scoreArchNotchLength: CGFloat { 11 }
    var scoreArchNotchWidth: CGFloat { 2 }
    /// How far the number sits above the centre, so number and name share
    /// the dial's middle.
    var scoreArchFigureLift: CGFloat { 5 }
    /// How far the name sinks below the dial's foot, so it sits in the
    /// widest part of the gap rather than between the arch's two ends.
    var scoreArchNameDrop: CGFloat { 6 }

    // MARK: Halo

    /// The halo's hairline.
    var scoreHaloStroke: CGFloat { 2.5 }
    /// How far the glow under the line spreads.
    var scoreHaloGlowBlur: CGFloat { 4 }
    /// The bright bead at the head of the line, and the light round it.
    var scoreHaloHead: CGFloat { 7 }
    var scoreHaloHeadGlow: CGFloat { 6 }
    /// How much brighter than the hue the head is, as if lit from inside.
    var scoreHaloHeadLift: Double { 0.08 }
    /// How strongly the glow under the line shows.
    var scoreHaloGlowOpacity: Double { 0.6 }
    /// The small hollow dot for the usual.
    var scoreHaloUsualDot: CGFloat { 5 }

    // MARK: Echo

    /// Today's ring.
    var scoreEchoStroke: CGFloat { 6 }
    /// The usual's ring inside it, thinner.
    var scoreEchoInnerStroke: CGFloat { 2.5 }
    /// The air between the two rings.
    var scoreEchoGap: CGFloat { 4 }

    // MARK: Seven

    /// The empty middle the number sits in, as a radius.
    var scoreSevenCore: CGFloat { 25 }
    /// The air between two days, in degrees.
    var scoreSevenGapDegrees: Double { 7 }
    /// How round a day's corners are.
    var scoreSevenCorner: CGFloat { 2.5 }
    /// The shortest a day draws, so a low day still shows.
    var scoreSevenFloor: Double { 0.08 }
    /// The line that marks the usual across the seven days.
    var scoreSevenUsualWidth: CGFloat { 1 }
    var scoreSevenUsualDash: CGFloat { 2 }
    var scoreSevenUsualOpacity: Double { 0.7 }
    /// A past day, as a share of the hue: quieter than elsewhere, since
    /// six of them sit round today's.
    var scoreSevenPastOpacity: Double { 0.3 }

    // MARK: Zones

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
}
