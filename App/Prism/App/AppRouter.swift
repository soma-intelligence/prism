//
//  AppRouter.swift
//  Prism
//

import Foundation
import Observation
import SwiftUI

/// Which tab the shell is showing.
///
/// It exists because a surface presented over the tabs sometimes needs to send
/// a person to one of them. The settings sheet's data row is the first: it does
/// not draw a second health browser, it opens the one the Longevity tab already
/// has, and two screens answering the same question is what that avoids.
///
/// The tab keys are strings because that is what `Tab(value:)` already takes in
/// ``ContentView``. An enum would be tidier and would mean touching the shell
/// for no gain today.
@Observable
@MainActor
final class AppRouter {
    /// Changing tab sends every other tab back to its first part.
    ///
    /// Pulse opens on Today, Longevity on Body, Track on Journal. A tab is a
    /// promise of one place, and landing on whichever part was left showing
    /// last time made a person look for where they were.
    var selection: String {
        didSet {
            guard selection != oldValue else { return }
            if selection != "pulse" { pulseSection = .today }
            if selection != "longevity" { longevitySection = .body }
            if selection != "track" { trackSection = .journal }
        }
    }

    /// Which part the Pulse tab shows. Held here so a tab switch can reset it.
    var pulseSection: PulseSection = .today

    /// What is pushed on the Pulse stack. The score rings and the orb push
    /// onto it rather than through a destination of their own, so a page
    /// they open can push the next one on top (a Stress row on the Mind
    /// page) instead of under itself.
    var pulsePath = NavigationPath()

    /// Which part the Track tab shows. Held here so a tab switch can reset it.
    var trackSection: TrackSection = .journal

    /// Which lens the Longevity tab reads through, and what is pushed on its
    /// stack.
    ///
    /// Held here rather than by the page for the same reason as `selection`:
    /// the browser the settings row opens is pushed from the Body lens, and a
    /// row that promised every reading and landed on the last page opened
    /// would be lying.
    var longevitySection: LongevitySection = .body

    /// A `NavigationPath` rather than `[LongevityRoute]`: the lenses also push
    /// the journey's routes (Mind, Lab, Metric and the rest), and a typed path
    /// silently drops a value of any other type.
    var longevityPath = NavigationPath()

    init(selection: String = "pulse") {
        self.selection = selection
#if DEBUG
        // `-app.tab longevity` opens a tab directly, for screenshots.
        if let tab = UserDefaults.standard.string(forKey: "app.tab") {
            self.selection = tab
        }
#endif
    }
}
