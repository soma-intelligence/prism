//
//  SomaTriStateControlTests.swift
//  SomaUITests
//

import Testing
@testable import SomaUI

/// The journal's answer control: the order it draws, what VoiceOver hears,
/// and how a swipe moves along it.
@Suite("Tri-state answer")
struct SomaTriStateControlTests {
    @Test("No, none, yes, from left to right")
    func order() {
        #expect(SomaTriStateControl.order == [false, nil, true])
    }

    @Test("Each answer has a spoken value, and none is not answered")
    func spoken() {
        #expect(SomaTriStateControl.spokenValue(true) == "Yes")
        #expect(SomaTriStateControl.spokenValue(false) == "No")
        #expect(SomaTriStateControl.spokenValue(nil) == "Not answered")
    }

    @Test("A step moves one segment and holds at the ends")
    func step() {
        #expect(SomaTriStateControl.step(nil, by: 1) == true)
        #expect(SomaTriStateControl.step(nil, by: -1) == false)
        #expect(SomaTriStateControl.step(false, by: 1) == nil)
        #expect(SomaTriStateControl.step(true, by: -1) == nil)
        #expect(SomaTriStateControl.step(true, by: 1) == true)
        #expect(SomaTriStateControl.step(false, by: -1) == false)
    }
}
