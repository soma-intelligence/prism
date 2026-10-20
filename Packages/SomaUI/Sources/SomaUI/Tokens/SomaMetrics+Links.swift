//
//  SomaMetrics+Links.swift
//  SomaUI
//

import CoreGraphics

/// The proportions of a cause and effect card: the two averages set on one
/// track under the headline, their dots and the labels under them.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// The track the two averages sit on, and the segment that joins them.
    var linkTrackHeight: CGFloat { 4 }
    /// The usual side's dot and the side the card is about.
    var linkDotSmall: CGFloat { 10 }
    var linkDotLarge: CGFloat { 14 }
    /// How strongly the segment between the two shows.
    var linkSpanOpacity: Double { 0.35 }
    /// The row the track and its dots take, labels left out.
    var linkTrackRow: CGFloat { 18 }
    /// Gap between the headline, the line under it and the track.
    var linkCardSpacing: CGFloat { 8 }
}
