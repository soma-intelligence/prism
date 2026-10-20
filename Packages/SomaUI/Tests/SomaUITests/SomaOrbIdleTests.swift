//
//  SomaOrbIdleTests.swift
//  SomaUITests
//

import Testing
import SwiftUI
@testable import SomaUI

@Suite("Orb idle motion")
struct SomaOrbIdleTests {
    private let motion = SomaMotion.standard

    @Test("The breath stays within one full breath in and out")
    func breathIsBounded() {
        for step in 0..<2_000 {
            let value = SomaOrbIdle.breath(at: Double(step) * 0.05, period: motion.orbBreathPeriod)
            #expect(value >= -1 && value <= 1)
        }
    }

    @Test("Frame to frame at 120 Hz the breath moves by a hair: no jitter, no jump")
    func breathIsSmooth() {
        let frame = 1.0 / 120
        var previous = SomaOrbIdle.breath(at: 0, period: motion.orbBreathPeriod)
        for step in 1..<3_000 {
            let value = SomaOrbIdle.breath(at: Double(step) * frame, period: motion.orbBreathPeriod)
            #expect(abs(value - previous) < 0.01)
            previous = value
        }
    }

    @Test("The orb grows and shrinks by little more than a percent")
    func scaleIsShallow() {
        for step in 0..<400 {
            let scale = SomaOrbIdle.scale(at: Double(step) * 0.1, period: motion.orbBreathPeriod, depth: motion.orbBreathDepth)
            #expect(abs(scale - 1) <= motion.orbBreathDepth + 1e-9)
        }
        #expect(motion.orbBreathDepth < 0.02)
    }

    @Test("Slow and calm: a breath of several seconds, the weather slowed, the fine swirl smoothed")
    func calmSettings() {
        #expect(motion.orbBreathPeriod >= 6 && motion.orbBreathPeriod <= 12)
        #expect(motion.orbFlowRate > 0 && motion.orbFlowRate <= 0.5)
        #expect(motion.orbCalm > 0 && motion.orbCalm <= 1)
        #expect(SomaOrbIdle.breath(at: 3, period: 0) == 0)
    }
}
