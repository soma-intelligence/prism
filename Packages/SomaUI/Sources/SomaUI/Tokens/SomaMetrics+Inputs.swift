//
//  SomaMetrics+Inputs.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the visual inputs draw with: the glass, the scale, the ruler,
/// the clock, the dials, the moons and the valence track.
///
/// Read from the design at one size for touch and pointer alike, and computed
/// so they add no stored field to the theme.
public extension SomaMetrics {
    /// The one number an input screen is about, and the unit beside it.
    var readoutSize: CGFloat { 64 }
    var readoutUnitSize: CGFloat { 24 }
    /// The space between a readout's number and its unit.
    var readoutUnitGap: CGFloat { 4 }

    /// The knob a finger drags.
    var knobDiameter: CGFloat { 22 }
    var knobRingWidth: CGFloat { 2 }

    /// The big glass on the water sheet, and the small ones under it.
    var vesselHeight: CGFloat { 250 }
    var vesselWidth: CGFloat { 170 }
    var vesselGlyphHeight: CGFloat { 36 }
    var vesselStroke: CGFloat { 2 }

    /// The scale on the weight sheet: the arc's height and the needle.
    var scaleDialHeight: CGFloat { 170 }
    var scaleNeedleHeight: CGFloat { 52 }
    var scaleMajorTick: CGFloat { 22 }
    var scaleMinorTick: CGFloat { 10 }
    /// Points of drag for one step of the scale.
    var scaleDragPerStep: CGFloat { 6 }

    /// The figure and the ruler on the height sheet.
    var rulerHeight: CGFloat { 430 }
    var rulerTick: CGFloat { 10 }
    var rulerMajorTick: CGFloat { 16 }

    /// The 24 hour clock and the value dials.
    var clockDiameter: CGFloat { 270 }
    var clockTrackWidth: CGFloat { 14 }
    var clockBandWidth: CGFloat { 3 }
    var dialDiameter: CGFloat { 230 }
    var dialTrackWidth: CGFloat { 12 }
    /// The gap between two segments of a segmented ring, in degrees.
    var dialSegmentGap: Double { 4 }
    /// The sweep of a gauge dial, in degrees.
    var dialGaugeSweep: Double { 270 }

    /// The moon a rating fills, and the row of small ones.
    var moonDiameter: CGFloat { 180 }
    var moonRowDiameter: CGFloat { 22 }

    /// The square the mood orb lives in on the mood sheet. The orb grows to
    /// fill it as the feeling turns pleasant and settles smaller below.
    var moodOrbDiameter: CGFloat { 210 }
    /// The share of that square the orb fills at the two ends of the scale,
    /// and before anything is chosen.
    var moodOrbSmallest: CGFloat { 0.74 }
    var moodOrbUnset: CGFloat { 0.82 }

    /// The macronutrient ring on the food sheet.
    var macroRingDiameter: CGFloat { 190 }
    var macroRingWidth: CGFloat { 18 }
    var macroLabelReach: CGFloat { 30 }

    /// The valence track's height, its stop dots, and the thumb a finger
    /// drags along it, with the dot of the feeling's colour at its centre.
    var valenceTrackHeight: CGFloat { 12 }
    var valenceStopDiameter: CGFloat { 4 }
    var valenceThumbDiameter: CGFloat { 32 }
    var valenceThumbDotDiameter: CGFloat { 14 }
    /// How far the track sits dimmed before a feeling is chosen.
    var valenceUnsetOpacity: Double { 0.4 }

    /// A chosen chip's wash and rim in the feeling's colour.
    var chipTintOpacity: Double { 0.24 }
    var chipTintRimOpacity: Double { 0.7 }
}
