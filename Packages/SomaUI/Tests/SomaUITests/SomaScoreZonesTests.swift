//
//  SomaScoreZonesTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Score zones")
struct SomaScoreZonesTests {
    @Test("Shares stay between 0 and 1, and a missing score has none")
    func shares() {
        #expect(SomaRingScore(aspect: .sleep, value: 140, usual: -5).fraction == 1)
        #expect(SomaRingScore(aspect: .sleep, value: 140, usual: -5).usualFraction == 0)
        #expect(SomaRingScore(aspect: .sleep, value: nil).fraction == nil)
        #expect(SomaRingScore(aspect: .sleep, value: 87).figure == "87")
        #expect(SomaRingScore(aspect: .sleep, value: nil).figure == nil)
    }

    @Test("A range reads as shares of the turn, clamped to the dial")
    func rangeShares() {
        #expect(SomaRingScore(aspect: .sleep, value: 80, range: 70...85).rangeShares == 0.7...0.85)
        #expect(SomaRingScore(aspect: .activity, value: 80, range: -10...130).rangeShares == 0...1)
        #expect(SomaRingScore(aspect: .mind, value: 80, range: 120...140).rangeShares == 1...1)
        #expect(SomaRingScore(aspect: .mind, value: 80).rangeShares == nil)
    }

    @Test("On a dark ground every zone stays deeper than on a light one, and still steps up")
    func darkDepth() {
        let metrics = SomaMetrics.standard
        let light = metrics.scoreZonesDepth
        let dark = metrics.scoreZonesDepthDark
        #expect(dark.count == 3)
        #expect(zip(dark, light).allSatisfy { $0 >= $1 })
        #expect(dark == dark.sorted())
        #expect(metrics.scoreTrackOpacityDark > metrics.scoreTrackOpacity)
    }

    @Test("Zones fill one after the next and leave their gaps empty")
    func zones() {
        func zones(_ share: Double) -> Int {
            strokes(SomaZoneBand(gap: 0.02, upTo: share).path(in: CGRect(x: 0, y: 0, width: 92, height: 92)))
        }
        #expect(zones(0) == 0)
        #expect(zones(0.2) == 1)
        // Inside the gap after the first zone: the second has not begun.
        #expect(zones(1.0 / 3 + 0.005) == 1)
        #expect(zones(0.5) == 2)
        #expect(zones(1) == 3)
    }

    @Test("A range arc is one stroke, and a range with no width draws nothing")
    func rangeArc() {
        let rect = CGRect(x: 0, y: 0, width: 96, height: 96)
        #expect(strokes(SomaRangeArc(from: 0.4, to: 0.65).path(in: rect)) == 1)
        #expect(SomaRangeArc(from: 0.5, to: 0.5).path(in: rect).isEmpty)
    }

    @Test("A range arc starts at twelve o'clock and runs clockwise")
    func rangeArcClock() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        // A quarter of the range from zero: twelve o'clock round to three.
        let bounds = SomaRangeArc(from: 0, to: 0.25).path(in: rect).boundingRect
        #expect(abs(bounds.minX - 50) < 0.5)
        #expect(abs(bounds.maxX - 100) < 0.5)
        #expect(abs(bounds.minY - 0) < 0.5)
        #expect(abs(bounds.maxY - 50) < 0.5)
    }

    /// The number of separate strokes in a path: one per move.
    private func strokes(_ path: Path) -> Int {
        var moves = 0
        path.forEach { element in
            if case .move = element { moves += 1 }
        }
        return moves
    }
}
