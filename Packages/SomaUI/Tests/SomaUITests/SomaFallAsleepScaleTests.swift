//
//  SomaFallAsleepScaleTests.swift
//  SomaUITests
//

import Foundation
import Testing
@testable import SomaUI

@Suite("Fall asleep scale")
struct SomaFallAsleepScaleTests {
    @Test("Fifteen minutes or less is fast, twenty five or less average, longer late")
    func bands() {
        #expect(SomaFallAsleepBand.band(minutes: 1) == .fast)
        #expect(SomaFallAsleepBand.band(minutes: 15) == .fast)
        #expect(SomaFallAsleepBand.band(minutes: 16) == .average)
        #expect(SomaFallAsleepBand.band(minutes: 25) == .average)
        #expect(SomaFallAsleepBand.band(minutes: 26) == .late)
        #expect(SomaFallAsleepBand.band(minutes: 90) == .late)
    }

    @Test("A latency reads in whole minutes, never under one")
    func minutes() {
        #expect(SomaFallAsleepBand.minutes(20) == 1)
        #expect(SomaFallAsleepBand.minutes(14.6 * 60) == 15)
        #expect(SomaFallAsleepBand.minutes(-30) == 1)
    }

    @Test("The marker is full at half an hour and never sits off the track")
    func position() {
        #expect(SomaFallAsleepBand.position(15 * 60) == 0.5)
        #expect(SomaFallAsleepBand.position(45 * 60) == 1)
        #expect(SomaFallAsleepBand.position(0) == 0.05)
    }

    @Test("The bands share the track by the minutes they cover")
    func shares() {
        let shares = SomaFallAsleepBand.shares
        #expect(shares.count == 3)
        #expect(abs(shares[0] - 0.5) < 1e-9)
        #expect(abs(shares[1] - 1.0 / 3) < 1e-9)
        #expect(abs(shares.reduce(0, +) - 1) < 1e-9)
    }
}
