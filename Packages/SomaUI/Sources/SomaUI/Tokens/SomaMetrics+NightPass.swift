//
//  SomaMetrics+NightPass.swift
//  SomaUI
//

import CoreGraphics

/// The sizes of the night pass, read from Flighty's flight card: two times
/// at the ends, a thin track between them, and the object riding the track.
///
/// Computed so they add no stored field to the theme.
public extension SomaMetrics {
    /// The track's height: a little thicker than a chart track, so the
    /// filled span reads at arm's length.
    var nightPassTrackHeight: CGFloat { chartTrackHeight * 1.5 }
    /// The room between the times and the track, and between the track and
    /// the totals under it.
    var nightPassSpacing: CGFloat { cardHeaderSpacing * 3 }
    /// The dot where sleep began.
    var nightPassEndDot: CGFloat { chartTrackHeight * 2 }
    /// The empty track, as a share of the primary ink.
    var nightPassTrackOpacity: Double { 0.1 }
    /// The midnight and usual marks across the track.
    var nightPassTickWidth: CGFloat { 2 }
}
