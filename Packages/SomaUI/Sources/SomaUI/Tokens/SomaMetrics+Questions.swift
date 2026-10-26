//
//  SomaMetrics+Questions.swift
//  SomaUI
//

import SwiftUI

/// The sizes a question sheet draws with: the dots that count the questions,
/// the gap under the question, the pills and the orbs that answer it.
///
/// Computed, like the inputs' sizes, so they add no stored field to the theme.
public extension SomaMetrics {
    /// Edge of one progress dot; the current one is three dots long.
    var questionProgressDot: CGFloat { 6 }
    /// Gap between two progress dots.
    var questionProgressSpacing: CGFloat { 6 }
    /// Inset between a question sheet's edges and what it holds, the same on
    /// every platform: the pills and the orbs never run to the edge.
    var questionSheetInset: CGFloat { 24 }
    /// Gap between the question and its answer.
    var questionAnswerGap: CGFloat { 32 }
    /// Opacity of what is not chosen: a dot to come, the pill passed over.
    var questionIdleOpacity: Double { 0.3 }
    /// Opacity of the outline round the No pill.
    var questionOutlineOpacity: Double { 0.28 }
    /// Height of a yes or no pill.
    var answerPillHeight: CGFloat { 58 }
    /// Gap between two answers side by side, and between the orbs and their
    /// words.
    var answerSpacing: CGFloat { 12 }
    /// How much a chosen answer swells for its beat.
    var answerChosenScale: CGFloat { 1.04 }
    /// Diameter of a scale orb at rest, and once chosen.
    var scaleOrbIdle: CGFloat { 38 }
    var scaleOrbChosen: CGFloat { 62 }
    /// Opacity of the colour an orb at rest carries.
    var scaleOrbWash: Double { 0.32 }
    /// Diameter of the minus and plus discs of a count.
    var countButtonDiameter: CGFloat { 56 }
    /// Point size of the glyph inside those discs.
    var countGlyphSize: CGFloat { 20 }
    /// Size a question sheet asks for where a sheet has no size of its own:
    /// the Mac and the headset. About half a phone, like the medium detent.
    var questionSheetWidth: CGFloat { 440 }
    var questionSheetHeight: CGFloat { 440 }

    /// A check-in row: its glyph column, the gap between the question and an
    /// answer laid under it, and its padding top and foot.
    var questionGlyphColumn: CGFloat { 22 }
    var questionRowGap: CGFloat { 12 }
    var questionRowPadding: CGFloat { 14 }
    /// The height of the five step track a scale question answers in.
    var questionTrackHeight: CGFloat { 32 }
    /// The progress over a check-in: the height of its segments and the gap
    /// between them.
    var questionProgressHeight: CGFloat { 3 }
}

public extension SomaTypography {
    /// A question asked on its own sheet: a step over the display size, a
    /// little weight, so it holds the middle of a half height sheet.
    var question: SomaFontSpec {
        SomaFontSpec(size: display.size * 1.06, weight: .medium, tracking: display.tracking - 0.2)
    }
}

public extension SomaMotion {
    /// One question giving way to the next: a short spring with a little
    /// life in it.
    var cardAdvance: Animation { .spring(duration: 0.42, bounce: 0.16) }
    /// The same change under Reduce Motion: a crossfade, nothing travels.
    var cardAdvanceReduced: Animation { .easeInOut(duration: 0.2) }
    /// How long a chosen answer holds before the next question comes, in
    /// seconds: long enough to see the orb grow, short enough not to wait.
    var answerHold: Double { 0.34 }
}
