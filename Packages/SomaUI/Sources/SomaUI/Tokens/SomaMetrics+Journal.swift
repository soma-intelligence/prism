//
//  SomaMetrics+Journal.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of a journal: the quick add tiles, the habit rows with
/// their glyph discs and trailing marks, the progress ring and the feeling
/// scale.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// A quick add tile: its height, its corners, and its glyph.
    var journalTileHeight: CGFloat { 74 }
    var journalTileCornerRadius: CGFloat { 18 }
    var journalTileGlyph: CGFloat { 22 }
    /// The hue's wash behind a tile, and the rim around it.
    var journalTileWashOpacity: Double { 0.2 }
    var journalTileRimOpacity: Double { 0.35 }
    /// Gap between a tile's disc and its label, and between tiles.
    var journalTileLabelSpacing: CGFloat { 7 }
    var journalTileSpacing: CGFloat { 10 }
    /// A habit row's glyph disc, and the glyph inside it.
    var journalRowDisc: CGFloat { 28 }
    var journalRowGlyph: CGFloat { 14 }
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
    /// A tinted disc's fill under its glyph.
    var journalDiscOpacity: Double { 0.18 }
    /// A feeling stop: its height, and how far a chosen one grows.
    var journalFeelStopHeight: CGFloat { 30 }
    var journalFeelStopSpacing: CGFloat { 6 }
    /// The opacity of the stops on either side of the chosen one.
    var journalFeelIdleOpacity: Double { 0.32 }
    /// The opacity of every stop while none is chosen.
    var journalFeelRestOpacity: Double { 0.55 }
    /// The ring of a habit that is off.
    var journalMarkIdleOpacity: Double { 0.45 }
    /// The answer control on a habit card: one segment of the three, the
    /// inset between the track and the raised pill, and the glyph inside.
    var journalChoiceWidth: CGFloat { 34 }
    var journalChoiceHeight: CGFloat { 26 }
    var journalChoiceInset: CGFloat { 2.5 }
    var journalChoiceGlyph: CGFloat { 12 }
    /// How far a segment's touch area reaches past its drawing, up and down:
    /// the card is taller than the control, so a thumb landing just above a
    /// glyph still answers.
    var journalChoiceReach: CGFloat { 8 }
    /// The glyph of a segment that is not chosen.
    var journalChoiceIdleOpacity: Double { 0.5 }
    /// The raised pill on the dark ground, as a wash of ink over the track.
    var journalChoiceLiftOpacity: Double { 0.13 }
    /// The shadow under the raised pill on the light ground.
    var journalChoiceShadowOpacity: Double { 0.12 }
    var journalChoiceShadowRadius: CGFloat { 1.5 }
    /// A "No": the alert colour, held low. A real answer that does not shout.
    var journalChoiceNoOpacity: Double { 0.75 }
    /// The habit cards: each its own card, a short gap between them.
    var journalCardSpacing: CGFloat { 8 }
    var journalCardCornerRadius: CGFloat { 14 }
    /// The gap between a section's small heading and its first card.
    var journalSectionHeadingSpacing: CGFloat { 8 }
}
