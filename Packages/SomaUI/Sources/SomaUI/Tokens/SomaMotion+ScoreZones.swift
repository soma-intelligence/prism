//
//  SomaMotion+ScoreZones.swift
//  SomaUI
//

import SwiftUI

/// How Today's three score dials move (``SomaScoreZones``).
///
/// Short and physical: each dial fills once on a spring, the three a beat
/// apart, then holds still. Under Reduce Motion every dial is simply drawn.
/// Computed so they add no stored field to the theme.
public extension SomaMotion {
    /// A dial filling to its score, the band running round zone by zone.
    var scoreArrival: Animation { .spring(duration: 0.9, bounce: 0.1) }
    /// The wait between one dial and the next as they fill.
    var scoreArrivalStep: Double { 0.08 }
    /// A dial taking a new value in place.
    var scoreChange: Animation { .spring(duration: 0.5, bounce: 0) }
}
