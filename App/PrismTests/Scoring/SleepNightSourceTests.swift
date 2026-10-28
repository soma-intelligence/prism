//
//  SleepNightSourceTests.swift
//  PrismTests
//
//  Who recorded the night: the source that wrote most of its sleep, read
//  from Apple Health's own names, with time in bed alone not counting.
//

import Foundation
import Testing
import HealthExportCore
import HealthScoring
@testable import Prism

@Suite("Night source")
struct SleepNightSourceTests {
    let bed = Date(timeIntervalSince1970: 1_790_033_640)
    var night: ScoringNightWindow { ScoringNightWindow(start: bed, end: bed.addingTimeInterval(8 * 3600)) }

    func sleep(_ code: Double, hours: Double, from offset: Double = 0, source: String) -> HealthReading {
        let start = bed.addingTimeInterval(offset * 3600)
        return HealthReading(metric: ScoreDetailInputs.Metric.sleep, value: code, unit: .count, start: start,
                             end: start.addingTimeInterval(hours * 3600), source: source)
    }

    @Test("The source that recorded most of the night's sleep is the night's")
    func most() {
        let readings = [
            sleep(3, hours: 5, source: "Apple Watch"),
            sleep(4, hours: 1.5, from: 5, source: "Apple Watch"),
            sleep(3, hours: 2, from: 6, source: "AutoSleep"),
        ]
        #expect(ScoreDetailInputs.dominantSource(readings, in: night) == "Apple Watch")
    }

    @Test("A phone that only noted bedtime did not record the night")
    func inBedAlone() {
        let readings = [
            sleep(0, hours: 8, source: "iPhone"),
            sleep(3, hours: 2, source: "Apple Watch"),
        ]
        #expect(ScoreDetailInputs.dominantSource(readings, in: night) == "Apple Watch")
    }

    @Test("Sleep outside the night does not count toward it, and no sleep names no source")
    func outside() {
        let earlier = sleep(3, hours: 6, from: -20, source: "Oura")
        #expect(ScoreDetailInputs.dominantSource([earlier], in: night) == nil)
        #expect(ScoreDetailInputs.dominantSource([earlier, sleep(3, hours: 1, source: "Apple Watch")], in: night) == "Apple Watch")
    }

    @Test("A tie goes to the name first in order, so the pick never flickers")
    func tie() {
        let readings = [sleep(3, hours: 2, source: "Withings"), sleep(3, hours: 2, from: 2, source: "Apple Watch")]
        #expect(ScoreDetailInputs.dominantSource(readings, in: night) == "Apple Watch")
    }

    @Test("Blood oxygen stored as a share of one reads in percent")
    func oxygenPercent() {
        let values = ScoreDetailInputs.percent([ScoringTimedValue(start: bed, end: bed, value: 0.96),
                                                ScoringTimedValue(start: bed, end: bed, value: 97)])
        #expect(abs(values[0].value - 96) < 1e-9)
        #expect(values[1].value == 97)
    }
}
