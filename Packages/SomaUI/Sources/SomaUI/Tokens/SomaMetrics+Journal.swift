//
//  SomaMetrics+Journal.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of a journal: the quick add tiles, the habit rows with
/// their glyphs and trailing marks, the progress ring and the feeling
/// scale.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// A quick add tile: its height, its corners, and its glyph.
    var journalTileHeight: CGFloat { 74 }
    var journalTileCornerRadius: CGFloat { cardCornerRadius }
    var journalTileGlyph: CGFloat { 22 }
    /// Gap between a tile's glyph and its label, and between tiles.
    var journalTileLabelSpacing: CGFloat { spaceS }
    var journalTileSpacing: CGFloat { cardSpacing }
    /// A habit row's height: a little taller than a browse row, so the disc
    /// breathes.
    var journalRowMinHeight: CGFloat { 54 }
    /// The trailing mark: a circle a thumb can find.
    var journalMarkDiameter: CGFloat { 28 }
    var journalMarkLine: CGFloat { 2 }
    var journalMarkGlyph: CGFloat { 13 }
    /// The header's progress ring.
    var journalRingDiameter: CGFloat { 46 }
    var journalRingLine: CGFloat { 5 }
    /// A feeling stop: its height, and how far a chosen one grows.
    var journalFeelStopHeight: CGFloat { 30 }
    var journalFeelStopSpacing: CGFloat { 6 }
    /// The ring of a habit that is off.
    var journalMarkIdleOpacity: Double { 0.45 }
    /// The answer control on a habit card: one segment of the three, the
    /// inset between the track and the raised pill, and the glyph inside.
    /// A segment is a thumb wide (44 points) because the three sit abreast
    /// with no gap: the reach below adds height, never width. The Journal's
    /// ``SomaAnswerSwitch`` reads the same width and idle ink.
    var journalChoiceWidth: CGFloat { 44 }
    var journalChoiceHeight: CGFloat { 26 }
    var journalChoiceInset: CGFloat { 2.5 }
    var journalChoiceGlyph: CGFloat { 12 }
    /// How far a segment's touch area reaches past its drawing, up and down:
    /// the card is taller than the control, so a thumb landing just above a
    /// glyph still answers.
    var journalChoiceReach: CGFloat { 8 }
    /// The glyph of a segment that is not chosen: faint beside the chosen
    /// one, still legible on the dark ground.
    var journalChoiceIdleOpacity: Double { 0.7 }
    /// The raised pill on the dark ground, as a wash of ink over the track.
    var journalChoiceLiftOpacity: Double { 0.13 }
    /// A "No": the alert colour, held low. A real answer that does not shout.
    var journalChoiceNoOpacity: Double { 0.75 }
    /// The habit cards: each its own card, a short gap between them.
    var journalCardSpacing: CGFloat { 8 }
    var journalCardCornerRadius: CGFloat { cardCornerRadius }
    /// The gap between a section's small heading and its first card.
    var journalSectionHeadingSpacing: CGFloat { 8 }
}
