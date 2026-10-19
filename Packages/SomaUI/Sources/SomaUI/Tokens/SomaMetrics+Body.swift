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
    /// The fitness age plot and the fitness age waterfall.
    var bodyPlotHeight: CGFloat { 150 }
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
    /// The thumbnail that leads an action card on the Body tab.
    var bodyActionThumbnail: CGFloat { 44 }
}
