//
//  SomaScorePagePartsTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Score page parts")
struct SomaScorePagePartsTests {
    // MARK: The ring

    @Test("A score fills its share of the ring, held in 0 to 1; nothing is an empty ring")
    func dialShare() {
        #expect(SomaScoreDialMath.share(0.25) == 0.25)
        #expect(SomaScoreDialMath.share(1.4) == 1)
        #expect(SomaScoreDialMath.share(-0.2) == 0)
        #expect(SomaScoreDialMath.share(nil) == 0)
        #expect(SomaScoreDialMath.share(.nan) == 0)
        let band = SomaScoreDialMath.clamp(0.5...0.5)
        #expect(band.upperBound > band.lowerBound)
    }

    @Test("A reading's usual takes the middle of the marker ring, with room either side")
    func markerPlaces() {
        let placed = SomaScoreHero.markerShares(66, usual: 56...58)
        let usual = try! #require(placed.usual)
        #expect(usual.lowerBound > 0.3 && usual.upperBound < 0.7)
        #expect((placed.value ?? 0) > usual.upperBound)
        let inside = SomaScoreHero.markerShares(57, usual: 56...58)
        #expect(usual.contains(inside.value ?? -1))
        #expect(SomaScoreHero.markerShares(60, usual: nil).value == nil)
        #expect(SomaScoreHero.markerShares(200, usual: 56...58).value == 1)
    }

    @Test("The top of the ring is twelve o'clock, a quarter turn is three")
    func dialPoints() {
        let size = CGSize(width: 100, height: 100)
        let top = SomaScoreDialMath.point(share: 0, in: size, inset: 0)
        #expect(abs(top.x - 50) < 0.001 && abs(top.y) < 0.001)
        let right = SomaScoreDialMath.point(share: 0.25, in: size, inset: 0)
        #expect(abs(right.x - 100) < 0.001 && abs(right.y - 50) < 0.001)
    }

    // MARK: Sleep windows

    @Test("Bedtimes and wake times read as one run past noon, evening at the top")
    func windowScale() {
        #expect(SomaSleepWindowScale.pastNoon(22) == 10)
        #expect(SomaSleepWindowScale.pastNoon(2) == 14)
        #expect(SomaSleepWindowScale.pastNoon(-1.5) == 10.5)
        let nights = [
            SomaSleepWindow(id: 0, bed: 22.5, wake: 6.5),
            SomaSleepWindow(id: 1, bed: 23.0, wake: 7.0),
            SomaSleepWindow(id: 2, bed: 0.5, wake: 8.0),
            SomaSleepWindow(id: 3, bed: nil, wake: nil),
        ]
        let scale = SomaSleepWindowScale(nights)
        #expect(scale.y(clock: 22.5) < scale.y(clock: 0.5))
        #expect(scale.y(clock: 0.5) < scale.y(clock: 8))
        #expect(scale.y(clock: 21) >= 0 && scale.y(clock: 9) <= 1)
        #expect(scale.usual?.bed == 11)
        #expect(SomaSleepWindowScale.clock(10) == "22:00")
        #expect(SomaSleepWindowScale([SomaSleepWindow(id: 0, bed: 23, wake: 7)]).usual == nil)
    }

    // MARK: Trends pair

    @Test("A link's two sides share one scale; the averages sit where the means do")
    func linkPair() {
        let layout = SomaLinkPairLayout(high: [60, 62, 64], low: [50, 52, 54])
        let low = try! #require(layout.lowMean)
        let high = try! #require(layout.highMean)
        #expect(high > low)
        #expect(layout.lowDays.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(layout.highDays.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(abs(layout.middle - (low + high) / 2) < 1e-9)
        #expect(layout.lowAverage == 52 && layout.highAverage == 62)
        #expect(SomaLinkPairLayout(high: [], low: [1]).highMean == nil)
    }

    @Test("Days keep their place in a lane: the nudge is fixed and stays inside it")
    func linkJitter() {
        for index in 0..<200 {
            let nudge = SomaLinkPairLayout.jitter(index)
            #expect(nudge >= -1 && nudge <= 1)
            #expect(nudge == SomaLinkPairLayout.jitter(index))
        }
        #expect(SomaLinkPairLayout.number(56.4) == "56")
        #expect(SomaLinkPairLayout.number(3.14) == "3.1")
        #expect(SomaLinkPairLayout.number(nil) == "-")
    }
}
