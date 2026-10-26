//
//  SomaMetrics+Onboarding.swift
//  SomaUI
//

import SwiftUI

/// The places and sizes of the first run's one orb, and its progress bar.
///
/// The orb is one view carried through every screen, so where it sits is a
/// scale of the hero diameter and a few anchors rather than a frame per page.
/// Computed, so they add no stored field to the theme.
public extension SomaMetrics {
    /// Height of the top row: the back chevron and the progress bar.
    var onboardingTopBarHeight: CGFloat { iconButtonDiameter + 8 }
    /// Height of one segment of the progress bar.
    var onboardingProgressHeight: CGFloat { 3 }
    /// Gap between two segments of the progress bar.
    var onboardingProgressSpacing: CGFloat { 4 }
    /// Widest the progress bar draws, so it stays a slim mark on a Mac.
    var onboardingProgressMaxWidth: CGFloat { 220 }
    /// The orb on the first screen, as a share of the hero diameter.
    var onboardingOrbWelcomeScale: CGFloat { 1 }
    /// Where the welcome orb's centre sits, as a share of the screen height.
    var onboardingOrbWelcomeHeight: CGFloat { 0.33 }
    /// The orb once a screen has questions under it.
    var onboardingOrbQuestionScale: CGFloat { 0.4 }
    /// The orb while a screen holds fields: smaller, set at the leading edge.
    var onboardingOrbFieldScale: CGFloat { 0.28 }
    /// The orb parked in the corner, beside the progress bar.
    var onboardingOrbCornerScale: CGFloat { 0.17 }
    /// Gap between the orb and the title under it.
    var onboardingOrbGap: CGFloat { spaceL }
    /// Gap between a screen's title and its content.
    var onboardingTitleGap: CGFloat { 20 }
}
