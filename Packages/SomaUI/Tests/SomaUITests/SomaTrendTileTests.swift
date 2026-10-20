//
//  SomaTrendTileTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Trend tile")
struct SomaTrendTileTests {
    @Test("The band's edges are named in the value's own precision")
    func bandLabels() {
        #expect(SomaTrendTileChart.format(4.84, like: "5.1") == (4.8).formatted(.number.precision(.fractionLength(1))))
        #expect(SomaTrendTileChart.format(36.512, like: "36.58") == (36.51).formatted(.number.precision(.fractionLength(2))))
        #expect(SomaTrendTileChart.format(62.4, like: "66") == "62")
        // A grouping comma is not a decimal point.
        #expect(SomaTrendTileChart.format(7_168.2, like: "2,913") == (7_168.0).formatted(.number.precision(.fractionLength(0))))
        #expect(SomaTrendTileChart.format(0.4, like: nil) == "0")
    }

    @Test("A sparkline's band is read in shares of the chart, high over low")
    func bandShares() {
        let shape = SomaSparkShape.make([5.0, 5.1, 4.9, 5.2], band: 4.8...5.3, samples: 48)
        #expect(shape.hasBand)
        #expect(shape.bandHigh > shape.bandLow)
        #expect((0...1).contains(shape.bandLow) && (0...1).contains(shape.bandHigh))
    }
}
