//
//  SomaMotion+Onboarding.swift
//  SomaUI
//

import SwiftUI

/// The timings of the first run, which tells one continuous story: a single
/// orb and a single ground carried from screen to screen, with the words of
/// each screen arriving over them.
///
/// Computed, like the other feature timings, so they add no stored field to
/// the theme.
public extension SomaMotion {
    /// One screen of the first run giving way to the next: the orb gliding to
    /// its new place, the bar filling, the button changing its words. Short
    /// and interruptible, so a fast tap never waits on the last move.
    var onboardingStep: Animation { .smooth(duration: 0.4) }
    /// The same change with Reduce Motion on: a cross fade, nothing travels.
    var onboardingStepStill: Animation { fade }
    /// One line of a screen arriving: a fade and a rise of a few points.
    var onboardingArrival: Animation { .smooth(duration: 0.34) }
    /// The pause before the first line of a screen arrives, so the words
    /// follow the orb rather than race it.
    var onboardingArrivalLead: Double { 0.06 }
    /// The pause between one line and the next.
    var onboardingArrivalStagger: Double { 0.045 }
    /// How far a line rises as it arrives, in points.
    var onboardingArrivalRise: CGFloat { 6 }
    /// A screen's words leaving: quicker than they came.
    var onboardingDeparture: Animation { .easeOut(duration: 0.14) }
}
