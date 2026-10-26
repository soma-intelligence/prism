//
//  SomaSwitchTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

/// The on and off switch: where its knob rests, and that its on knob reads
/// apart from the track in both appearances (the system switch in the accent
/// drew white on white in dark).
@Suite("Switch")
struct SomaSwitchTests {
    @Test("Off rests on the cross, on on the check")
    func slots() {
        #expect(SomaSwitch.slot(false) == 0)
        #expect(SomaSwitch.slot(true) == 1)
    }

    @Test("The on knob, the accent, differs from the track and from its mark in both appearances")
    func contrast() {
        let colors = SomaTheme.standard.colors
        #expect(colors.accent.light != colors.surfaceRecessed.light)
        #expect(colors.accent.dark != colors.surfaceRecessed.dark)
        #expect(colors.accent.light != colors.onAccent.light)
        #expect(colors.accent.dark != colors.onAccent.dark)
    }

    @Test("The cross and check toggle style is reachable as .somaCrossCheck")
    func style() {
        let style: SomaSwitchToggleStyle = .somaCrossCheck
        _ = style
    }
}
