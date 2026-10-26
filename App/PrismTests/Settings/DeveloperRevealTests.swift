//
//  DeveloperRevealTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Developer reveal")
@MainActor
struct DeveloperRevealTests {

    /// A clock the test moves by hand, so a two second window can be crossed
    /// without a test that takes two seconds.
    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    private func make(threshold: Int = 7, window: TimeInterval = 2) -> (DeveloperReveal, Clock) {
        let clock = Clock()
        let reveal = DeveloperReveal(threshold: threshold, window: window, now: { clock.now })
        reveal.hide()
        return (reveal, clock)
    }

    @Test("Nothing is revealed before the first tap")
    func startsHidden() {
        let (reveal, _) = make()
        #expect(reveal.isRevealed == false)
        #expect(reveal.tapsRemaining == 7)
    }

    @Test("Six taps are not enough")
    func sixTapsDoNothing() {
        let (reveal, _) = make()
        for _ in 0..<6 { reveal.tap() }
        #expect(reveal.isRevealed == false)
        #expect(reveal.tapsRemaining == 1)
    }

    @Test("The seventh tap reveals")
    func seventhTapReveals() {
        let (reveal, _) = make()
        for _ in 0..<7 { reveal.tap() }
        #expect(reveal.isRevealed == true)
        #expect(reveal.tapsRemaining == 0)
    }

    @Test("A pause longer than the window starts the count again")
    func pauseResetsTheCount() {
        let (reveal, clock) = make()
        for _ in 0..<6 { reveal.tap() }
        clock.advance(2.1)
        reveal.tap()

        #expect(reveal.isRevealed == false)
        #expect(reveal.tapsRemaining == 6)
    }

    @Test("A pause inside the window does not")
    func pauseInsideTheWindowKeepsCounting() {
        let (reveal, clock) = make()
        for _ in 0..<6 {
            reveal.tap()
            clock.advance(1.9)
        }
        reveal.tap()

        #expect(reveal.isRevealed == true)
    }

    @Test("Hiding puts it back, and the count starts over")
    func hidingIsReversible() {
        let (reveal, _) = make()
        for _ in 0..<7 { reveal.tap() }
        #expect(reveal.isRevealed == true)

        reveal.hide()

        #expect(reveal.isRevealed == false)
        #expect(reveal.tapsRemaining == 7)
    }

    @Test("Tapping on while already revealed changes nothing")
    func tappingWhileRevealedIsInert() {
        let (reveal, _) = make()
        for _ in 0..<7 { reveal.tap() }
        for _ in 0..<7 { reveal.tap() }
        #expect(reveal.isRevealed == true)
    }
}
