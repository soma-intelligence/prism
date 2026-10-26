//
//  SomaScoreStylesTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Score styles")
struct SomaScoreStylesTests {
    @Test("Every style is chosen by its launch name")
    func names() {
        #expect(SomaScoresStyle.allCases.map(\.rawValue) == ["rings", "bezel", "arch", "halo", "echo", "seven", "zones"])
        #expect(SomaScoresStyle(rawValue: "halo") == .halo)
        #expect(SomaScoresStyle(rawValue: "orbit") == nil)
        #expect(SomaScoresStyle(rawValue: "unknown") == nil)
    }

    @Test("Shares stay between 0 and 1, and a missing score has none")
    func shares() {
        #expect(SomaRingScore(aspect: .sleep, value: 140, usual: -5).fraction == 1)
        #expect(SomaRingScore(aspect: .sleep, value: 140, usual: -5).usualFraction == 0)
        #expect(SomaRingScore(aspect: .sleep, value: nil).fraction == nil)
        #expect(SomaRingScore(aspect: .sleep, value: 87).figure == "87")
        #expect(SomaRingScore(aspect: .sleep, value: nil).figure == nil)
    }

    @Test("The week is seven days, padded at the front, today last")
    func week() {
        #expect(SomaRingScore(aspect: .mind, value: 25, week: [40, 25]).lastSeven == [nil, nil, nil, nil, nil, 40, 25])
        #expect(SomaRingScore(aspect: .mind, value: 1, week: Array(1...9)).lastSeven == Array(3...9))
        #expect(SomaRingScore(aspect: .mind, value: nil).lastSeven == Array(repeating: nil, count: 7))
    }

    @Test("A bezel lights one tick per sixtieth, none for nothing, all for a full score")
    func bezelTicks() {
        func lit(_ share: Double) -> Int {
            ticks(SomaTicks(count: 60, length: 7, upTo: share).path(in: CGRect(x: 0, y: 0, width: 92, height: 92)))
        }
        #expect(lit(0) == 0)
        #expect(lit(0.01) == 1)
        #expect(lit(0.94) == 56)
        #expect(lit(1) == 60)
    }

    @Test("Zones fill one after the next and leave their gaps empty")
    func zones() {
        func zones(_ share: Double) -> Int {
            ticks(SomaZoneBand(gap: 0.02, upTo: share).path(in: CGRect(x: 0, y: 0, width: 92, height: 92)))
        }
        #expect(zones(0) == 0)
        #expect(zones(0.2) == 1)
        // Inside the gap after the first zone: the second has not begun.
        #expect(zones(1.0 / 3 + 0.005) == 1)
        #expect(zones(0.5) == 2)
        #expect(zones(1) == 3)
    }

    @Test("A day that has not grown draws no petal")
    func petals() {
        let rect = CGRect(x: 0, y: 0, width: 92, height: 92)
        #expect(SomaPetal(centre: 0, width: 1.0 / 7, reach: 0, metrics: .standard).path(in: rect).isEmpty)
        #expect(!SomaPetal(centre: 0, width: 1.0 / 7, reach: 0.1, metrics: .standard).path(in: rect).isEmpty)
        #expect(!SomaPetal(centre: 0, width: 1.0 / 7, reach: 1, metrics: .standard).path(in: rect).isEmpty)
    }

    /// The number of separate strokes in a path: one per move.
    private func ticks(_ path: Path) -> Int {
        var moves = 0
        path.forEach { element in
            if case .move = element { moves += 1 }
        }
        return moves
    }
}
