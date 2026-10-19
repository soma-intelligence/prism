//
//  SomaMetrics+Links.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of a cause and effect card: the paired strip beside the
/// effect, its dots and its mean marks.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// The strip's width beside the effect, and its height for two rows.
    var linkStripWidth: CGFloat { 132 }
    var linkStripHeight: CGFloat { 30 }
    /// One day's dot on the strip.
    var linkStripDot: CGFloat { 5 }
    /// A day's dot against its row's mean mark, which is drawn solid.
    var linkStripDotOpacity: Double { 0.42 }
    /// The mean mark's width.
    var linkStripMeanWidth: CGFloat { 2.5 }
    /// Gap between the title, the effect and the caption.
    var linkCardSpacing: CGFloat { 8 }
}
