//
//  SomaMetricStageTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Metric stage")
struct SomaMetricStageTests {
    private let lead = SomaMetricLead(caption: "Today", value: "66", unit: "bpm",
                                      meaning: "Above your usual", detail: "Up 3", tone: .watch)

    @Test("With no finger on the chart the head says the lead")
    func leadWhenNothingIsPicked() {
        #expect(SomaMetricStage<Int>.shown(lead, picked: nil) == lead)
    }

    @Test("A picked slot takes the head: its day, its value, what it means; the unit stays and the detail goes")
    func pickedSlotTakesTheHead() {
        let slot = SomaChartBucket(id: 3, value: 58, band: 56...60, readout: "Fri, Oct 9", valueText: "58",
                                   note: "Within your usual", tone: .good)
        let shown = SomaMetricStage<Int>.shown(lead, picked: slot)
        #expect(shown.caption == "Fri, Oct 9")
        #expect(shown.value == "58")
        #expect(shown.unit == "bpm")
        #expect(shown.meaning == "Within your usual")
        #expect(shown.detail == nil)
        #expect(shown.tone == .good)
    }

    @Test("A score's ring fills to the value out of its top, with the usual on the same scale")
    func fillRing() {
        let dial = SomaStageDial(aspect: .sleep, scale: .fill(top: 100), value: 87, usual: 80...90)
        let ring = dial.ring(for: 50)
        #expect(ring.dial == .fill(0.5))
        #expect(ring.usual == 0.8...0.9)
    }

    @Test("A reading's ring marks where it sits against the usual, as the score head does")
    func markerRing() {
        let dial = SomaStageDial(aspect: .heart, scale: .marker, value: 66, usual: 56...58)
        let ring = dial.ring(for: 66)
        let expected = SomaScoreHero.markerShares(66, usual: 56...58)
        #expect(ring.dial == .marker(expected.value))
        #expect(ring.usual == expected.usual)
    }
}
