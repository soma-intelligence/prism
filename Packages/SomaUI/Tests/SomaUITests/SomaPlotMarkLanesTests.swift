//
//  SomaPlotMarkLanesTests.swift
//  SomaUITests
//

import CoreGraphics
import Testing
@testable import SomaUI

/// The words over a plot: a word that would touch the one before it drops a
/// line, and a word with room stays on the first.
@Suite("Plot mark lines")
struct SomaPlotMarkLanesTests {
    private let gap: CGFloat = 4

    @Test("Words with room share the first line")
    func apart() {
        let lanes = SomaPlotMarkLanes.lanes(starts: [0, 100, 200], widths: [60, 40, 50], gap: gap)
        #expect(lanes == [0, 0, 0])
    }

    @Test("Breakfast and Lunch close together: Lunch drops a line")
    func crowded() {
        // Breakfast at 8:00 and Lunch at 12:30 on a 300 point plot.
        let lanes = SomaPlotMarkLanes.lanes(starts: [100, 156], widths: [58, 38], gap: gap)
        #expect(lanes == [0, 1])
    }

    @Test("A word goes back to the first line once it is clear")
    func reuse() {
        let lanes = SomaPlotMarkLanes.lanes(starts: [0, 30, 80], widths: [60, 40, 30], gap: gap)
        #expect(lanes == [0, 1, 0])
    }

    @Test("Lines follow reading order, whatever order the words come in")
    func unordered() {
        let lanes = SomaPlotMarkLanes.lanes(starts: [156, 100], widths: [38, 58], gap: gap)
        #expect(lanes == [1, 0])
    }

    @Test("No two words on one line ever overlap")
    func neverOverlap() {
        let starts: [CGFloat] = [0, 10, 20, 25, 90, 95, 200, 205, 210]
        let widths: [CGFloat] = [50, 45, 40, 60, 30, 70, 55, 20, 35]
        let lanes = SomaPlotMarkLanes.lanes(starts: starts, widths: widths, gap: gap)
        for a in starts.indices {
            for b in starts.indices where a < b && lanes[a] == lanes[b] {
                let first = min(a, b, by: starts), second = max(a, b, by: starts)
                #expect(starts[first] + widths[first] + gap <= starts[second])
            }
        }
    }
}

private func min(_ a: Int, _ b: Int, by starts: [CGFloat]) -> Int { starts[a] <= starts[b] ? a : b }
private func max(_ a: Int, _ b: Int, by starts: [CGFloat]) -> Int { starts[a] <= starts[b] ? b : a }
