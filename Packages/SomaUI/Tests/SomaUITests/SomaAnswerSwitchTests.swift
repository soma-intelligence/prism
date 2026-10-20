//
//  SomaAnswerSwitchTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

/// The journal's three state switch (not done, no entry, done): how
/// VoiceOver steps through it, what it says, where its knob rests, and what
/// a tap on a slot leaves.
@Suite("Answer switch")
struct SomaAnswerSwitchTests {
    @Test("VoiceOver steps from not done, through none, to done")
    func order() {
        #expect(SomaAnswerSwitch.order == [false, nil, true])
    }

    @Test("Each answer has a spoken value, and none is not answered")
    func spoken() {
        #expect(SomaAnswerSwitch.spokenValue(true) == "Done")
        #expect(SomaAnswerSwitch.spokenValue(false) == "Not done")
        #expect(SomaAnswerSwitch.spokenValue(nil) == "Not answered")
    }

    @Test("A step moves one answer and holds at the ends")
    func step() {
        #expect(SomaAnswerSwitch.step(nil, by: 1) == true)
        #expect(SomaAnswerSwitch.step(nil, by: -1) == false)
        #expect(SomaAnswerSwitch.step(false, by: 1) == nil)
        #expect(SomaAnswerSwitch.step(true, by: -1) == nil)
        #expect(SomaAnswerSwitch.step(true, by: 1) == true)
        #expect(SomaAnswerSwitch.step(false, by: -1) == false)
    }

    @Test("A tap chooses its cell, and a second tap on it clears the answer")
    func tapping() {
        #expect(SomaAnswerSwitch.tapping(true, on: nil) == true)
        #expect(SomaAnswerSwitch.tapping(false, on: nil) == false)
        #expect(SomaAnswerSwitch.tapping(true, on: false) == true)
        #expect(SomaAnswerSwitch.tapping(false, on: true) == false)
        #expect(SomaAnswerSwitch.tapping(true, on: true) == nil)
        #expect(SomaAnswerSwitch.tapping(false, on: false) == nil)
    }

    @Test("The dash in the middle always clears the answer")
    func dash() {
        #expect(SomaAnswerSwitch.tapping(nil, on: true) == nil)
        #expect(SomaAnswerSwitch.tapping(nil, on: false) == nil)
        #expect(SomaAnswerSwitch.tapping(nil, on: nil) == nil)
    }

    @Test("The knob rests on the cross, the dash in the middle, or the check")
    func slots() {
        #expect(SomaAnswerSwitch.slot(false) == 0)
        #expect(SomaAnswerSwitch.slot(nil) == 1)
        #expect(SomaAnswerSwitch.slot(true) == 2)
    }

    @Test("The dash is one level line in the grid's middle")
    func dashMark() {
        let bounds = SomaAnswerMarkShape(answer: nil).path(in: CGRect(x: 0, y: 0, width: 24, height: 24)).boundingRect
        #expect(bounds.height == 0)
        #expect(abs(bounds.midX - 12) < 0.001 && abs(bounds.midY - 12) < 0.001)
    }
}

/// The Track glyphs: every kind draws inside its grid, and the tones stay
/// muted.
@Suite("Track glyphs and tones")
struct SomaTrackGlyphTests {
    @Test("Every glyph draws something inside the 24 unit grid")
    func outlines() {
        for kind in SomaTrackGlyph.Kind.allCases {
            let bounds = SomaTrackGlyphShape.outline(kind).boundingRect
            #expect(!bounds.isEmpty, "\(kind) draws nothing")
            #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 24 && bounds.maxY <= 24, "\(kind) leaves the grid: \(bounds)")
        }
    }

    @Test("Glyphs fit the largest square the rect holds")
    func fitting() {
        let path = SomaTrackGlyphShape(kind: .drink).path(in: CGRect(x: 0, y: 0, width: 48, height: 24))
        #expect(path.boundingRect.minX >= 12 && path.boundingRect.maxX <= 36)
    }

    @Test("Every tone is muted: no channel far from the others, in either appearance")
    func muted() {
        func saturation(_ rgb: UInt32) -> Double {
            let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
            let high = max(r, g, b), low = min(r, g, b)
            return high == 0 ? 0 : (high - low) / high
        }
        for tone in SomaTrackTone.allCases {
            #expect(saturation(tone.value.light) < 0.65, "\(tone) light is too bright")
            #expect(saturation(tone.value.dark) < 0.5, "\(tone) dark is too bright")
        }
    }
}
