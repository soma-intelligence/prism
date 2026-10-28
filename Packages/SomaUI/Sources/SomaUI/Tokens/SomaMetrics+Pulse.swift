//
//  SomaMetrics+Pulse.swift
//  SomaUI
//

import CoreGraphics

/// The sizes the Pulse tab's Trends and Explore parts draw with.
///
/// Kept apart from ``SomaMetrics``'s stored scale on purpose: these are the
/// parts' own proportions, read from the design at one size for touch and
/// pointer alike, and computed so they add no stored field to the theme.
public extension SomaMetrics {
    // MARK: Trends

    /// The sparkline beside each of the three scores.
    var pulseSparklineWidth: CGFloat { 100 }
    /// The smallest and largest night on the spiral.
    var pulseNightDotRange: ClosedRange<CGFloat> { 2...5.5 }
    /// The glow round the one point a chart is about: today, last night.
    var pulseGlowDiameter: CGFloat { 30 }
    /// The active days grid: one row a weekday, one column a week.
    var pulseHeatRowPitch: CGFloat { 11 }
    var pulseHeatMaxColumnPitch: CGFloat { 11.5 }
    var pulseHeatLabelColumn: CGFloat { 26 }
    var pulseHeatMonthRow: CGFloat { 18 }
}
