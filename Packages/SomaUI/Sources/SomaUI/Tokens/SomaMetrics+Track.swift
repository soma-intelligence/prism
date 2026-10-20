//
//  SomaMetrics+Track.swift
//  SomaUI
//

import CoreGraphics

/// The sizes Track's glyphs, answer switch and rituals draw with.
///
/// Computed, like the other part sizes, so they add no stored field to the
/// theme.
public extension SomaMetrics {
    /// The tinted square at the head of a row, and the glyph inside it.
    var trackRowBadge: CGFloat { 32 }
    var trackRowBadgeGlyph: CGFloat { 19 }
    var trackRowBadgeCornerRadius: CGFloat { 9 }
    /// How strongly a badge is tinted with its tone.
    var trackBadgeTint: Double { 0.15 }

    /// The answer switch: one of its two cells, the inset between the track
    /// and a chosen cell, the corners of each, and the glyph inside.
    var trackAnswerCellWidth: CGFloat { 40 }
    var trackAnswerCellHeight: CGFloat { 30 }
    var trackAnswerInset: CGFloat { 3 }
    var trackAnswerCornerRadius: CGFloat { 10 }
    var trackAnswerGlyph: CGFloat { 12 }
    var trackAnswerGlyphStroke: CGFloat { 2 }
    /// How far a cell's touch area reaches past its drawing, up and down.
    var trackAnswerReach: CGFloat { 8 }
    /// The glyph of a cell that is not chosen.
    var trackAnswerIdleOpacity: Double { 0.42 }
    /// A chosen "No": the ink at this strength, so a no reads as an answer
    /// without the weight of a yes.
    var trackAnswerNoOpacity: Double { 0.16 }

    /// A ritual's step: the box it is ticked in, and the row's height.
    var ritualCheckSide: CGFloat { 26 }
    var ritualCheckCornerRadius: CGFloat { 8 }
    var ritualStepMinHeight: CGFloat { 52 }
    /// The days of the consistency strip: one cell's height, its corners and
    /// the gap between cells.
    var ritualDayHeight: CGFloat { 22 }
    var ritualDayCornerRadius: CGFloat { 5 }
    var ritualDaySpacing: CGFloat { 4 }
    /// A day not kept at all, as a wash of the ink.
    var ritualDayIdleOpacity: Double { 0.08 }
}
