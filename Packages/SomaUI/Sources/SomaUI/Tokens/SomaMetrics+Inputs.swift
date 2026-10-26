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
    var knobDiameter: CGFloat { 18 }
    var knobRingWidth: CGFloat { 2 }

    /// The one stroke every input draws its ticks, rims and walls with.
    var inputHairline: CGFloat { 1 }
    /// How much ink a fine tick, a medium tick and a numbered tick carry.
    var inputTickFaint: Double { 0.22 }
    var inputTickMedium: Double { 0.4 }
    var inputTickStrong: Double { 0.75 }
    /// The fixed line a tape or a scale is read against.
    var inputIndicatorWidth: CGFloat { 2 }
    /// How long a flick keeps a tape or a scale turning, in seconds, and how
    /// far its predicted travel carries.
    var inputGlideDuration: Double { 0.9 }
    var inputGlideReach: Double { 0.6 }

    /// The big glass on the water sheet, and the small ones under it.
    var vesselHeight: CGFloat { 250 }
    var vesselWidth: CGFloat { 170 }
    var vesselGlyphHeight: CGFloat { 36 }
    var vesselStroke: CGFloat { 1 }
    /// The glass: how far the rim's ellipse opens, the thickness of its foot
    /// and its walls, as shares of its width and height.
    var vesselRimDepth: CGFloat { 0.075 }
    var vesselFootDepth: CGFloat { 0.06 }
    var vesselWallDepth: CGFloat { 0.035 }
    /// The ink the glass itself carries: its body, its walls, its foot.
    var vesselBodyOpacity: Double { 0.025 }
    var vesselWallOpacity: Double { 0.26 }
    var vesselFootOpacity: Double { 0.05 }
    /// The water: its colour near the surface and at depth, and how high the
    /// surface swells and how slowly it moves.
    var vesselWaterTop: Double { 0.32 }
    var vesselWaterDeep: Double { 0.62 }
    var vesselRipple: CGFloat { 1.1 }
    var vesselRipplePeriod: Double { 3.4 }

    /// The scale on the weight sheet: the arc's height and the needle.
    var scaleDialHeight: CGFloat { 170 }
    var scaleNeedleHeight: CGFloat { 52 }
    var scaleMajorTick: CGFloat { 26 }
    var scaleMinorTick: CGFloat { 11 }
    /// Points of drag for one step of the scale.
    var scaleDragPerStep: CGFloat { 6 }

    /// The tape on the height sheet.
    var rulerHeight: CGFloat { 430 }
    var rulerTick: CGFloat { 12 }
    var rulerMajorTick: CGFloat { 34 }
    /// The tape: points per centimetre, and the medium tick between two
    /// numbered ones.
    var rulerPointsPerUnit: CGFloat { 9 }
    var rulerMidTick: CGFloat { 20 }
    var rulerWidth: CGFloat { 110 }

    /// The 24 hour clock and the value dials.
    var clockDiameter: CGFloat { 270 }
    var clockTrackWidth: CGFloat { 6 }
    var clockBandWidth: CGFloat { 2 }
    var dialDiameter: CGFloat { 230 }
    var dialTrackWidth: CGFloat { 6 }
    /// The bezel's fine tick and its long one, outside a dial or a clock.
    var bezelTick: CGFloat { 5 }
    var bezelMajorTick: CGFloat { 10 }
    /// The gap between a track and its bezel.
    var bezelGap: CGFloat { 8 }
    /// The gap between two segments of a segmented ring, in degrees.
    var dialSegmentGap: Double { 4 }
    /// The sweep of a gauge dial, in degrees.
    var dialGaugeSweep: Double { 270 }

    /// The moon a rating fills, and the row of small ones.
    var moonDiameter: CGFloat { 180 }
    var moonRowDiameter: CGFloat { 22 }
    /// How soft the line between day and night is, as a share of the moon.
    var moonTerminatorSoftness: CGFloat { 0.02 }
    /// How much of its light the night side keeps: earthshine.
    var moonEarthshine: Double { 0.16 }

    /// The square the mood orb lives in on the mood sheet. The orb grows to
    /// fill it as the feeling turns pleasant and settles smaller below.
    var moodOrbDiameter: CGFloat { 210 }
    /// The share of that square the orb fills at the two ends of the scale,
    /// and before anything is chosen.
    var moodOrbSmallest: CGFloat { 0.74 }
    var moodOrbUnset: CGFloat { 0.82 }
    /// How much of its colour the mood orb lays over its stone ground.
    var moodOrbStrength: Double { 0.68 }

    /// The macronutrient ring on the food sheet.
    var macroRingDiameter: CGFloat { 190 }
    var macroRingWidth: CGFloat { 8 }
    var macroLabelReach: CGFloat { 30 }

    /// The valence track's height, its stop dots, and the thumb a finger
    /// drags along it, with the dot of the feeling's colour at its centre.
    var valenceTrackHeight: CGFloat { 4 }
    var valenceStopDiameter: CGFloat { 4 }
    var valenceThumbDiameter: CGFloat { 28 }
    var valenceThumbDotDiameter: CGFloat { 8 }
    /// How much of its colour the track keeps: the scale reads calm.
    var valenceTrackOpacity: Double { 0.7 }
    /// How far the track sits dimmed before a feeling is chosen.
    var valenceUnsetOpacity: Double { 0.4 }

    /// A chosen chip's wash and rim in the feeling's colour.
    var chipTintOpacity: Double { 0.24 }
    var chipTintRimOpacity: Double { 0.7 }

    /// A mood face in the row of five: its side, how much heavier its line
    /// is than a glyph's, the soft fill when chosen, how far the chosen one
    /// rises and the others step back, and the gap to its word.
    var moodFaceSide: CGFloat { 40 }
    var moodFaceStrokeScale: CGFloat { 1.1 }
    var moodFaceFill: Double { 0.18 }
    var moodFaceChosenScale: CGFloat { 1.08 }
    var moodFaceQuietOpacity: Double { 0.55 }
    var moodFaceLabelGap: CGFloat { 6 }

    /// The mood log sheet: the chosen face drawn large at its head, the gap
    /// between a prompt and its chips, and the inset of the note field.
    var moodLogFaceSide: CGFloat { moodFaceSide * 2.2 }
    var moodLogPromptSpacing: CGFloat { cardHeaderSpacing * 2 }
    var noteFieldHorizontalInset: CGFloat { cardPadding - 2 }
    var noteFieldVerticalInset: CGFloat { cardPadding - 4 }
}
