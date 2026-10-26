//
//  SomaMotion+ScoreStyles.swift
//  SomaUI
//

import SwiftUI

/// How the radial proposals for Today's scores move (``SomaScoresStyle``).
///
/// Short and physical: each dial fills once on a spring, the three a beat
/// apart, then holds still. Under Reduce Motion every dial is simply drawn.
/// Computed so they add no stored field to the theme.
public extension SomaMotion {
    /// A dial filling to its score: an arc running round, ticks lighting,
    /// days growing out from the middle.
    var scoreArrival: Animation { .spring(duration: 0.9, bounce: 0.1) }
    /// The wait between one dial and the next as they fill.
    var scoreArrivalStep: Double { 0.08 }
    /// The wait between one day and the next inside the seven day dial.
    var scoreDayStep: Double { 0.035 }
    /// A dial taking a new value in place.
    var scoreChange: Animation { .spring(duration: 0.5, bounce: 0) }
}
