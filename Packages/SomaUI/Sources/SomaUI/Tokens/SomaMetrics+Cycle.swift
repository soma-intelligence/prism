//
//  SomaMetrics+Cycle.swift
//  SomaUI
//

import CoreGraphics

/// The sizes of the cycle page's month.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// A day's disc in the month: room for two digits, and seven of them
    /// across the narrowest phone card.
    var cycleDayDiameter: CGFloat { 32 }
    /// The ring of a day the next period is expected on, and of today.
    var cycleDayRing: CGFloat { 1.5 }
    /// The disc beside each word of the month's legend.
    var cycleLegendDiameter: CGFloat { 10 }
}
