//
//  SomaEnergyGaugeTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Energy gauge")
struct SomaEnergyGaugeTests {
    @Test("The day's hours: a rise is charge, a fall is drain, hours after now are still to come")
    func slotsReadTheDay() {
        let points: [SomaEnergyTimeline.Point] = [
            .init(x: 0.05, level: 20), .init(x: 0.30, level: 60), .init(x: 0.55, level: 40),
        ]
        let slots = SomaEnergyTimeline.slots(points, now: 0.6, count: 4)
        #expect(slots.map(\.level) == [20, 60, 40, nil])
        #expect(slots.map(\.isRising) == [false, true, false, false])
        #expect(slots.map(\.isToCome) == [false, false, false, true])
    }

    @Test("An hour with no reading between two that have one carries the earlier level")
    func gapsCarry() {
        let points: [SomaEnergyTimeline.Point] = [.init(x: 0.1, level: 30), .init(x: 0.9, level: 50)]
        let slots = SomaEnergyTimeline.slots(points, now: nil, count: 4)
        #expect(slots.map(\.level) == [30, 30, 30, 50])
    }

    @Test("No readings, no bars: a missing day is never drawn as an empty bank")
    func emptyDay() {
        #expect(SomaEnergyTimeline.slots([], now: 0.5, count: 3).allSatisfy { $0.level == nil })
    }

    @Test("The level reads as one of three calm tones, never a blend")
    func tones() {
        #expect(SomaEnergyRamp.tone(at: 0.1) == SomaEnergyRamp.tone(at: 0.3))
        #expect(SomaEnergyRamp.tone(at: 0.5) != SomaEnergyRamp.tone(at: 0.3))
        #expect(SomaEnergyRamp.tone(at: 0.9) == SomaEnergyRamp.charge)
    }

    @Test("The charge fills from the foot, and an empty bank draws nothing")
    func chargeShape() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 100)
        #expect(SomaChargeShape(level: 0, tilt: 0, slosh: 0.1).path(in: rect).isEmpty)
        let half = SomaChargeShape(level: 0.5, tilt: 0, slosh: 0.1).path(in: rect).boundingRect
        #expect(abs(half.minY - 50) < 0.5 && abs(half.maxY - 100) < 0.5)
    }
}
