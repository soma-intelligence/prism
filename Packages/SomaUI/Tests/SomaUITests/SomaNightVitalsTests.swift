//
//  SomaNightVitalsTests.swift
//  SomaUITests
//

import Foundation
import Testing
@testable import SomaUI

@Suite("Night vitals")
struct SomaNightVitalsTests {
    private let bed = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func readings(_ values: [Double], every minutes: Double = 30) -> [SomaNightReading] {
        values.enumerated().map { SomaNightReading(start: bed.addingTimeInterval(Double($0) * minutes * 60), value: $1) }
    }

    @Test("A vital with fewer than two readings has no summary, so its card says what fills it")
    func tooFew() {
        #expect(SomaNightVitalSummary.make(.oxygen, readings: []) == nil)
        #expect(SomaNightVitalSummary.make(.oxygen, readings: readings([97])) == nil)
    }

    @Test("Heart reads its plain average, lowest and highest")
    func heart() throws {
        let summary = try #require(SomaNightVitalSummary.make(.heart, readings: readings([50, 54, 58])))
        #expect(summary.average == 54)
        #expect(summary.lowest == 50)
        #expect(summary.highest == 58)
        #expect(summary.secondsAboveQuiet == nil)
    }

    @Test("Noise averages as sound energy, so a loud half hour lifts it above the plain mean")
    func noiseEnergy() throws {
        let summary = try #require(SomaNightVitalSummary.make(.noise, readings: readings([30, 30, 30, 60])))
        #expect(summary.average > 37.5)
        #expect(abs(summary.average - 54.0) < 0.1)
    }

    @Test("Time above the quiet line counts each spot reading up to the next, half an hour at most")
    func secondsAbove() {
        let spots = readings([35, 45, 50, 38], every: 20) + [SomaNightReading(start: bed.addingTimeInterval(4 * 3600), value: 55)]
        // 45 and 50 count twenty minutes each; the last loud reading has no
        // next one to run to, so it counts nothing.
        #expect(SomaNightVitalSummary.secondsAbove(40, readings: spots) == 40 * 60)
        let spans = [SomaNightReading(start: bed, end: bed.addingTimeInterval(600), value: 44)]
        #expect(SomaNightVitalSummary.secondsAbove(40, readings: spans) == 600)
    }

    @Test("The line breaks across a stretch with no readings")
    func breaks() {
        let night = DateInterval(start: bed, duration: 8 * 3600)
        let gapped = readings([50, 51]) + [SomaNightReading(start: bed.addingTimeInterval(5 * 3600), value: 52)]
        let points = SomaNightVitals.fractions(gapped, in: night)
        #expect(points.count == 4)
        #expect(points[2] == nil)
        #expect(points.last??.x == 5.0 / 8)
    }

    @Test("Oxygen's scale stops at a hundred percent")
    func oxygenCeiling() throws {
        let scale = try #require(SomaNightVitals.scale(.oxygen, readings: readings([96, 99.5, 100]), average: 98.5))
        #expect(scale.domain.upperBound == 100)
        #expect(scale.ticks.allSatisfy { $0 <= 100 })
        #expect(scale.domain.lowerBound <= 96)
    }
}
