//
//  DeveloperReveal.swift
//  Prism
//

import Foundation
import Observation

/// Seven taps on the version number, and the Developer section appears.
///
/// A type rather than three `@State` properties in the footer, because the rule
/// has a shape: a count, a window the count lives inside, and a flag that
/// outlives the app. All three are wrong in ways nobody notices until they are
/// standing somewhere with a strap on, unable to open the section.
///
/// It works in a Release build on purpose. CoreBluetooth does not exist in the
/// Simulator, so anything behind this door can only be tried on a device, and a
/// device build is often a Release one. A `#if DEBUG` gate would put the tools
/// exactly where they cannot be used.
@Observable
@MainActor
final class DeveloperReveal {
    /// How many taps it takes.
    private let threshold: Int
    /// How long a tap waits for the next one before the count starts over.
    private let window: TimeInterval
    /// Injected so a test can cross a two second window without taking two
    /// seconds, and so the rule is provable rather than tried by hand.
    private let now: () -> Date

    private var count = 0
    private var lastTap: Date?

    /// Survives the app. `UserDefaults` directly rather than `@AppStorage`,
    /// because that property wrapper belongs to a view and this is not one.
    private let defaultsKey = "dev.revealed"

    private(set) var isRevealed: Bool

    init(
        threshold: Int = 7,
        window: TimeInterval = 2,
        now: @escaping () -> Date = Date.init
    ) {
        self.threshold = threshold
        self.window = window
        self.now = now
        self.isRevealed = UserDefaults.standard.bool(forKey: "dev.revealed")
    }

    /// How many more taps are needed. Zero once revealed.
    var tapsRemaining: Int {
        isRevealed ? 0 : threshold - count
    }

    /// One tap on the version number.
    func tap() {
        guard !isRevealed else { return }

        let instant = now()
        if let lastTap, instant.timeIntervalSince(lastTap) > window {
            count = 0
        }
        lastTap = instant
        count += 1

        if count >= threshold {
            isRevealed = true
            count = 0
            lastTap = nil
            UserDefaults.standard.set(true, forKey: defaultsKey)
        }
    }

    /// Puts the section away again.
    ///
    /// Without this the flag is one way and the only route back is deleting the
    /// app, which is a poor answer for something a person turned on by accident.
    func hide() {
        isRevealed = false
        count = 0
        lastTap = nil
        UserDefaults.standard.set(false, forKey: defaultsKey)
    }
}
