//
//  SomaMotion.swift
//  SomaUI
//

import SwiftUI

/// Every duration the system animates over.
///
/// Motion is a token like any other, so Reduce Motion has one place to answer
/// to and a brand can slow the whole system down in one edit.
///
/// Six curves carry nearly everything. A view reaches for one of them by what
/// the change means, never by a duration it picked itself:
///
/// - `quick`: a small thing changing state (a row ticked, a stage read off a
///   chart, a swipe springing back).
/// - `standard`: a value or a position moving (a fill rising, a card settling).
/// - `emphasized`: the one move on a screen that should be felt, with a little
///   overshoot.
/// - `press`: a control answering a finger, in and out.
/// - `fade`: opacity and nothing else, and the still counterpart Reduce Motion
///   swaps in for every curve that travels.
/// - `reveal`: a reading drawing itself once as it arrives.
///
/// Everything that moves a value is a spring, so a second change caught
/// mid-flight carries the velocity it already has instead of restarting from
/// rest. Only a pure fade is a plain ease, because opacity has no momentum to
/// keep. Loops (the breath, the orb's weather, a spin) are the one place a
/// duration runs past half a second.
public struct SomaMotion: Sendable, Equatable {
    /// A small change of state.
    public var quick: Animation
    /// A value or a position moving.
    public var standard: Animation
    /// The one move on a screen meant to be felt.
    public var emphasized: Animation
    /// A control's press, in and out.
    public var press: Animation
    /// Opacity only, and the still counterpart of every other curve.
    public var fade: Animation
    /// A reading drawing itself as it arrives.
    public var reveal: Animation
    /// Selection moving between tabs.
    public var selection: Animation
    /// Press-in and press-out on a control.
    public var pressDuration: Double
    /// Scale a control drops to while pressed.
    public var pressScale: CGFloat
    /// Opacity a control dims to while pressed. Full: a press is a scale, and a
    /// grey veil on a pressed button reads as disabled.
    public var pressOpacity: Double
    /// Opacity of something set aside rather than pressed: a move already
    /// done, a shutter that cannot fire yet.
    public var dimOpacity: Double
    /// UI feedback, 150 to 250 ms: a press released, a check, a switch.
    public var feedback: Animation
    /// Navigation, 300 to 500 ms: a row opening into its page, a sheet, a
    /// value rolling to its new figure.
    public var navigation: Animation
    /// A gesture that follows the finger and can be caught mid flight.
    public var gesture: Animation
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
    /// One part of a tab giving way to the next, from the segmented control:
    /// the new part slides in from the side of the segment chosen while the
    /// old one leaves by the other. A spring without bounce, as long as the
    /// pill's `selection`, so the page and the pill land together; a page
    /// that overshot would show a sliver of its neighbour.
    public var partSwitch: Animation
    /// The same handover under Reduce Motion: a quick cross fade in place.
    public var partFadeDuration: Double
    /// How far a part slides as it comes in, in points. Short: the page is
    /// replaced in place, not carried across the screen.
    public var partSlide: CGFloat
    /// A tab settling in after the bar selects it.
    public var tabEntrance: Animation
    /// The blur a page arrives out of, and leaves into.
    public var arrivalBlur: CGFloat
    /// The scale a page arrives from.
    public var arrivalScale: CGFloat
    /// How long a page that has just appeared holds its ambient motion (an
    /// aspect's drifting weather), in seconds, so a push or a zoom runs over
    /// a still page and every frame of it goes to the transition.
    public var settleDelay: Double

    public init(
        quick: Animation = .snappy(duration: 0.25),
        standard: Animation = .smooth(duration: 0.35),
        emphasized: Animation = .spring(duration: 0.5, bounce: 0.15),
        // Critically damped and short: a press that wobbled would read as the
        // control being loose, and one that lagged as the tap not landing.
        press: Animation = .spring(duration: 0.2, bounce: 0),
        fade: Animation = .easeOut(duration: 0.2),
        // Long enough for the eye to follow the arc round, short enough that
        // the number is never waiting on the drawing.
        reveal: Animation = .smooth(duration: 0.5),
        // Snappy rather than smooth: the bubble has to leave quickly and settle
        // once. A long soft spring reads as the indicator lagging behind the
        // tap, and the stretch never registers because nothing moves fast
        // enough to stretch.
        selection: Animation = .snappy(duration: 0.3),
        pressDuration: Double = 0.12,
        // 0.97, from the design brief: enough to feel the press, not so much
        // that the control seems to collapse under the finger.
        pressScale: CGFloat = 0.97,
        pressOpacity: Double = 1,
        dimOpacity: Double = 0.6,
        feedback: Animation = .spring(response: 0.25, dampingFraction: 0.9),
        navigation: Animation = .spring(response: 0.42, dampingFraction: 0.86),
        gesture: Animation = .interactiveSpring(response: 0.35, dampingFraction: 0.85),
        fold: Animation = .smooth(duration: 0.3, extraBounce: 0.1),
        spinDuration: Double = 16,
        breathDuration: Double = 2.6,
        orbBlendDuration: Double = 3.2,
        orbTurnDuration: Double = 600,
        partSwitch: Animation = .smooth(duration: 0.35),
        partFadeDuration: Double = 0.18,
        partSlide: CGFloat = 36,
        tabEntrance: Animation = .smooth(duration: 0.45),
        arrivalBlur: CGFloat = 8,
        arrivalScale: CGFloat = 0.985,
        // The system's push and zoom take a little under half a second.
        settleDelay: Double = 0.5
    ) {
        self.quick = quick
        self.standard = standard
        self.emphasized = emphasized
        self.press = press
        self.fade = fade
        self.reveal = reveal
        self.selection = selection
        self.pressDuration = pressDuration
        self.pressScale = pressScale
        self.pressOpacity = pressOpacity
        self.dimOpacity = dimOpacity
        self.feedback = feedback
        self.navigation = navigation
        self.gesture = gesture
        self.fold = fold
        self.spinDuration = spinDuration
        self.breathDuration = breathDuration
        self.orbBlendDuration = orbBlendDuration
        self.orbTurnDuration = orbTurnDuration
        self.partSwitch = partSwitch
        self.partFadeDuration = partFadeDuration
        self.partSlide = partSlide
        self.tabEntrance = tabEntrance
        self.arrivalBlur = arrivalBlur
        self.arrivalScale = arrivalScale
        self.settleDelay = settleDelay
    }

    public static let standard = SomaMotion()
}
