//
//  SomaMetrics+Body.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the Body tab's Overview, Cardio and Strength parts draw with.
///
/// Read from the design at one size for touch and pointer alike, and computed
/// so they add no stored field to the theme.
public extension SomaMetrics {
    /// The body map's silhouette, head to feet.
    var bodyMapHeight: CGFloat { 212 }
    /// The leading column of a zone row or a region row: its name.
    var bodyRowLabelWidth: CGFloat { 124 }
    /// The trailing column of a zone row or a region row: its value.
    var bodyRowValueWidth: CGFloat { 64 }
    /// The bar in a zone row or a region row.
    var bodyRowBarHeight: CGFloat { 7 }
    /// The space between two zone rows or region rows.
    var bodyRowSpacing: CGFloat { 12 }
    /// One run's heart rate line.
    var bodyRunPlotHeight: CGFloat { 96 }
    /// Eight weeks of sessions as columns of dots.
    var bodySessionPlotHeight: CGFloat { 88 }
    /// The largest dot a session column draws.
    var bodySessionDotDiameter: CGFloat { 12 }

    /// Muscle freshness: the legend's dot and the gap between its items,
    /// the group pills (height, inset, corner, gap, and how strongly the
    /// chosen one is tinted), and how much of its tone a muscle outside the
    /// chosen group keeps as it steps back.
    var muscleLegendDot: CGFloat { 8 }
    var muscleLegendSpacing: CGFloat { 16 }
    var musclePillHeight: CGFloat { 36 }
    var musclePillPadding: CGFloat { 10 }
    var musclePillSpacing: CGFloat { 8 }
    var musclePillSelectedTint: Double { 0.16 }
    var muscleMapBackTone: Double { 0.22 }
}

/// How the muscle map sets its figure.
public extension SomaMetrics {
    /// The gap between the front and the back.
    var muscleMapFigureGap: CGFloat { 12 }
    /// The tallest the two figures stand: past it they keep their
    /// proportions and centre, so a wide card does not grow a tall figure.
    var muscleMapHeight: CGFloat { 380 }
}
