//
//  SomaMotion+Parts.swift
//  SomaUI
//

import SwiftUI

/// How a tab's parts hand over after a swipe: the spring the strip is let go
/// into.
///
/// Computed so they add no stored field to the theme.
public extension SomaMotion {
    /// The spring a swipe lets the strip go into: as long as `partSwitch`
    /// and the pill's `selection`, without bounce, starting at the finger's
    /// speed.
    func partSettle(velocity: Double) -> Animation {
        .interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: velocity)
    }

}

/// How far a swipe has to go to change part.
public extension SomaMetrics {
    /// The share of the width a drag has to pass to land on the next part.
    var partSwipeReach: CGFloat { 0.32 }
    /// The speed, in points a second, of a flick that changes part however
    /// short it was.
    var partSwipeFlick: CGFloat { 420 }
}
