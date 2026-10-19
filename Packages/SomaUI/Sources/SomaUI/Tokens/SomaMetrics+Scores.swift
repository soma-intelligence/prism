//
//  SomaMetrics+Scores.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the score pages (recovery, strain, stress, sleep, energy, the
/// peak window and weather) draw with.
///
/// Read from the design at one size for touch and pointer alike, and computed
/// so they add no stored field to the theme.
public extension SomaMetrics {
    /// The gauge at the head of a score page, across.
    var scoreGaugeWidth: CGFloat { 300 }
    /// The gauge's arc.
    var scoreGaugeStroke: CGFloat { 30 }
    /// How much larger than the display role the gauge's number reads.
    var scoreGaugeNumberScale: CGFloat { 1.9 }
    /// The knob that marks today on the arc.
    var scoreGaugeKnob: CGFloat { 18 }
    /// A plot inside a score card.
    var scorePlotHeight: CGFloat { 150 }
    /// A short plot: a sparkline row, the stress strip.
    var scoreStripHeight: CGFloat { 32 }
    /// The tank that holds readiness or the energy bank.
    var scoreTankWidth: CGFloat { 150 }
    var scoreTankHeight: CGFloat { 150 }
    var scoreTankCornerRadius: CGFloat { 30 }
    /// The track a value sits on against its usual band.
    var scoreTrackWidth: CGFloat { 100 }
    var scoreTrackHeight: CGFloat { 4 }
    /// The dot on that track.
    var scoreTrackDot: CGFloat { 10 }
    /// A row of a card that lists lines.
    var scoreRowSpacing: CGFloat { 12 }
    /// The trailing column of the trend table.
    var scoreTableColumn: CGFloat { 90 }
    /// The ring of the peak window's day.
    var scoreRingDiameter: CGFloat { 200 }
    var scoreRingStroke: CGFloat { 16 }
    /// The numbered bullet of the page guide.
    var scoreGuideBullet: CGFloat { 28 }
}
