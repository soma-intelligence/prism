//
//  SleepNightLatencyTests.swift
//  PrismTests
//
//  The time it took to fall asleep: from bed, recorded or opened by awake
//  stretches, to the first stretch asleep, and nothing when the night says
//  nothing about bed.
//

import Foundation
import Testing
import SomaUI
@testable import Prism

@Suite("Time to fall asleep")
struct SleepNightLatencyTests {
    let start = Date(timeIntervalSince1970: 1_790_033_640)

    func runs(_ stretches: [(SomaSleepStage, Double)]) -> [SomaStageRun] {
        var at = start
        return stretches.map { stage, minutes in
            defer { at = at.addingTimeInterval(minutes * 60) }
            return SomaStageRun(stage: stage, start: at, end: at.addingTimeInterval(minutes * 60))
        }
    }

    @Test("A recorded bedtime before the first stage is the time it took")
    func recordedBed() throws {
        let night = try #require(SleepNightSummary.make(runs: runs([(.core, 60), (.deep, 30)]),
                                                        inBedStart: start.addingTimeInterval(-12 * 60), parts: []))
        #expect(abs((night.latency ?? 0) - 12 * 60) < 0.001)
    }

    @Test("Awake stretches at the start count from the first of them")
    func awakeFirst() throws {
        let night = try #require(SleepNightSummary.make(runs: runs([(.awake, 8), (.awake, 4), (.core, 60)]),
                                                        inBedStart: nil, parts: []))
        #expect(abs((night.latency ?? 0) - 12 * 60) < 0.001)
    }

    @Test("A night that begins asleep with no bedtime measured nothing")
    func noBed() throws {
        let night = try #require(SleepNightSummary.make(runs: runs([(.core, 60), (.awake, 5), (.rem, 30)]),
                                                        inBedStart: nil, parts: []))
        #expect(night.latency == nil)
    }

    @Test("A night with no sleep in it has no time to fall asleep")
    func noSleep() {
        #expect(SleepNightSummary.latency(runs: runs([(.awake, 30)]), bed: start, bedRecorded: true) == nil)
    }

    @Test("A bedtime that belongs to another night is not this night's latency")
    func farBed() throws {
        let night = try #require(SleepNightSummary.make(runs: runs([(.core, 60)]),
                                                        inBedStart: start.addingTimeInterval(-5 * 3600), parts: []))
        #expect(night.latency == nil)
    }
}
