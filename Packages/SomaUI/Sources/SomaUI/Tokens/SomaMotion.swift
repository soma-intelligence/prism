//
//  SomaMotion.swift
//  SomaUI
//

import SwiftUI

/// Every duration the system animates over.
///
/// Motion is a token like any other, so Reduce Motion has one place to answer
/// to and a brand can slow the whole system down in one edit.
public struct SomaMotion: Sendable, Equatable {
    /// Selection moving between tabs.
    public var selection: Animation
    /// Press-in and press-out on a control.
    public var pressDuration: Double
    /// Scale a control drops to while pressed.
    public var pressScale: CGFloat
    /// Opacity a control dims to while pressed.
    public var pressOpacity: Double
    /// The bar folding away and coming back.
    public var fold: Animation
    /// One full turn of a slowly rotating element.
    public var spinDuration: Double
    /// One half of a breath.
    public var breathDuration: Double
    /// An orb travelling from one aspect's palette to the next, the way the
    /// website's hero travels from organ to organ.
    public var orbBlendDuration: Double
    /// One full turn of the orb. Slow enough that the turn reads as the
    /// planet moving rather than as a spinner.
    public var orbTurnDuration: Double
    /// One part of a tab giving way to the next, from the segmented control.
    public var partSwitch: Animation
    /// How far a part slides as it comes in, in points. Short: the page is
    /// replaced in place, not carried across the screen.
    public var partSlide: CGFloat
    /// A tab settling in after the bar selects it.
    public var tabEntrance: Animation
    /// The blur a page arrives out of, and leaves into.
    public var arrivalBlur: CGFloat
    /// The scale a page arrives from.
    public var arrivalScale: CGFloat
    /// The scale the orb settles to under a finger. Shallow: a sphere that
    /// size reads a few points as a press, and more as a flinch.
    public var orbPressScale: CGFloat
    /// How much the orb brightens under a finger, as if the touch lit it.
    public var orbPressBrightness: Double
    /// The orb sinking under a finger: quick and without bounce, so it
    /// answers the touch before the finger lifts.
    public var orbPress: Animation
    /// The orb rising back when the finger lifts: a touch slower, with a
    /// little bounce, so it settles rather than snaps.
    public var orbRelease: Animation

    public init(
        // Snappy rather than smooth: the bubble has to leave quickly and settle
        // once. A long soft spring reads as the indicator lagging behind the
        // tap, and the stretch never registers because nothing moves fast
        // enough to stretch.
        selection: Animation = .snappy(duration: 0.3, extraBounce: 0.12),
        pressDuration: Double = 0.12,
        pressScale: CGFloat = 0.9,
        pressOpacity: Double = 0.6,
        fold: Animation = .smooth(duration: 0.3, extraBounce: 0.1),
        spinDuration: Double = 16,
        breathDuration: Double = 2.6,
        orbBlendDuration: Double = 3.2,
        orbTurnDuration: Double = 600,
        partSwitch: Animation = .smooth(duration: 0.42),
        partSlide: CGFloat = 36,
        tabEntrance: Animation = .smooth(duration: 0.5),
        arrivalBlur: CGFloat = 8,
        arrivalScale: CGFloat = 0.985,
        orbPressScale: CGFloat = 0.965,
        orbPressBrightness: Double = 0.05,
        orbPress: Animation = .spring(duration: 0.18, bounce: 0),
        orbRelease: Animation = .spring(duration: 0.42, bounce: 0.28)
    ) {
        self.selection = selection
        self.pressDuration = pressDuration
        self.pressScale = pressScale
        self.pressOpacity = pressOpacity
        self.fold = fold
        self.spinDuration = spinDuration
        self.breathDuration = breathDuration
        self.orbBlendDuration = orbBlendDuration
        self.orbTurnDuration = orbTurnDuration
        self.partSwitch = partSwitch
        self.partSlide = partSlide
        self.tabEntrance = tabEntrance
        self.arrivalBlur = arrivalBlur
        self.arrivalScale = arrivalScale
        self.orbPressScale = orbPressScale
        self.orbPressBrightness = orbPressBrightness
        self.orbPress = orbPress
        self.orbRelease = orbRelease
    }

    public static let standard = SomaMotion()
}
