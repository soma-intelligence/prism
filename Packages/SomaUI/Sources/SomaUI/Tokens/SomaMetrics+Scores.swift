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
    var scoreGaugeWidth: CGFloat { 248 }
    /// The gauge's arc.
    var scoreGaugeStroke: CGFloat { 10 }
    /// How much larger than the display role the gauge's number reads.
    var scoreGaugeNumberScale: CGFloat { 1.65 }
    /// The knob that marks today on the arc.
    var scoreGaugeKnob: CGFloat { 12 }
    /// A plot inside a score card.
    var scorePlotHeight: CGFloat { 150 }
    /// A short plot: a sparkline row, the stress strip.
    var scoreStripHeight: CGFloat { 32 }
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
    /// The dials at the head of Today, across, range arc included.
    var scoreDialDiameter: CGFloat { 96 }
    /// The dial's track and fill: one width for both.
    var scoreDialStroke: CGFloat { 6 }
    /// The gap between the dial and the thin arc that marks its range.
    var scoreDialRangeGap: CGFloat { 4 }
    /// The range arc's width.
    var scoreDialRangeStroke: CGFloat { 2 }
    /// The numbered bullet of the page guide.
    var scoreGuideBullet: CGFloat { 28 }
}

/// Sizes other components still read, kept from the parallel design lines.
public extension SomaMetrics {
    /// The tank that holds readiness or the energy bank.
    var scoreTankWidth: CGFloat { 150 }
    var scoreTankHeight: CGFloat { 150 }
    var scoreTankCornerRadius: CGFloat { 30 }
    /// The ticks across the arc where one band of the score meets the next.
    var scoreGaugeTickLength: CGFloat { 16 }
    var scoreGaugeTickWidth: CGFloat { 1.5 }
}
