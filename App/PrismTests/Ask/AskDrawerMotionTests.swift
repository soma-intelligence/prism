//
//  AskDrawerMotionTests.swift
//  PrismTests
//

import CoreGraphics
import Testing
@testable import Prism

/// The history drawer follows the finger and lands where the release sends it.
@Suite("Ask drawer motion")
struct AskDrawerMotionTests {
    let width: CGFloat = 338
    let flick: CGFloat = 420

    @Test("Between shut and open the drawer follows the finger one to one")
    func followsTheFinger() {
        #expect(AskDrawerMotion.offset(-120, width: width) == -120)
        #expect(AskDrawerMotion.offset(0, width: width) == 0)
    }

    @Test("Pushed past shut the drawer stays shut")
    func holdsAtShut() {
        #expect(AskDrawerMotion.offset(-500, width: width) == -width)
    }

    @Test("Pulled past open the drawer gives a little and no more")
    func dampsPastOpen() {
        let small = AskDrawerMotion.offset(20, width: width)
        let large = AskDrawerMotion.offset(400, width: width)
        #expect(small > 0 && small < 20)
        #expect(large > small && large < width * 0.2)
    }

    @Test("A quick flick shut closes the drawer however short it was")
    func flickCloses() {
        #expect(!AskDrawerMotion.landsOpen(offset: -10, velocity: -600, width: width, flick: flick))
    }

    @Test("A flick back open keeps it open even past half way")
    func flickBackKeepsOpen() {
        #expect(AskDrawerMotion.landsOpen(offset: -250, velocity: 600, width: width, flick: flick))
    }

    @Test("A slow release decides by where the drawer would come to rest")
    func slowReleaseProjects() {
        #expect(AskDrawerMotion.landsOpen(offset: -100, velocity: 0, width: width, flick: flick))
        #expect(!AskDrawerMotion.landsOpen(offset: -200, velocity: 0, width: width, flick: flick))
        // Slower than a flick, but carried past half way by its momentum.
        #expect(!AskDrawerMotion.landsOpen(offset: -100, velocity: -300, width: width, flick: flick))
    }

    @Test("The spring starts at the finger's speed, counted in journeys a second")
    func springVelocity() {
        // 169 points to go at 338 points a second: half the journey a second.
        #expect(AskDrawerMotion.springVelocity(-338, from: -169, to: -338) == 2)
        #expect(AskDrawerMotion.springVelocity(500, from: 0, to: 0) == 0)
    }
}
