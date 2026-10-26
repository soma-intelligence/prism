//
//  SleepNightSummaryTests.swift
//  PrismTests
//
//  Last night's section: the period, the two totals, the seconds in each
//  stage and the grades are read straight off the runs and the score's parts,
//  and nothing missing turns into a zero.
//

import Foundation
import Testing
import SomaUI
import HealthScoring
@testable import Prism

@Suite("Last night summary")
struct SleepNightSummaryTests {
    let start = Date(timeIntervalSince1970: 1_790_033_640)

    /// Stretches in minutes, laid end to end from `start`.
    func runs(_ stretches: [(SomaSleepStage, Double)], from origin: Date? = nil) -> [SomaStageRun] {
        var at = origin ?? start
        return stretches.map { stage, minutes in
            defer { at = at.addingTimeInterval(minutes * 60) }
            return SomaStageRun(stage: stage, start: at, end: at.addingTimeInterval(minutes * 60))
        }
    }

    @Test("Totals, stage seconds and shares come from the runs")
    func totals() throws {
        let night = try #require(SleepNightSummary.make(
            runs: runs([(.awake, 10), (.core, 120), (.deep, 60), (.rem, 90), (.awake, 5), (.core, 60)]),
            inBedStart: nil, parts: []))
        #expect(night.bed == start)
        #expect(night.wake == start.addingTimeInterval(345 * 60))
        #expect(night.inBed == 345 * 60)
        #expect(night.asleep == 330 * 60)
        let seconds: [TimeInterval?] = SomaSleepStage.allCases.map { night.stages[$0] }
        let expected: [TimeInterval?] = [900, 5_400, 10_800, 3_600]
        #expect(seconds == expected)
        let deep = try #require(night.share(of: .deep))
        #expect(abs(deep - 60.0 / 345) < 1e-9)
    }

    @Test("A recorded bedtime opens the period, unless it belongs to another night")
    func bedtime() throws {
        let stretches: [(SomaSleepStage, Double)] = [(.core, 60), (.deep, 30)]
        let early = start.addingTimeInterval(-20 * 60)
        let withBed = try #require(SleepNightSummary.make(runs: runs(stretches), inBedStart: early, parts: []))
        #expect(withBed.bed == early)
        #expect(withBed.inBed == 110 * 60)
        #expect(withBed.asleep == 90 * 60)

        let stale = start.addingTimeInterval(-5 * 3600)
        let withStale = try #require(SleepNightSummary.make(runs: runs(stretches), inBedStart: stale, parts: []))
        #expect(withStale.bed == start)

        let late = start.addingTimeInterval(10 * 60)
        let withLate = try #require(SleepNightSummary.make(runs: runs(stretches), inBedStart: late, parts: []))
        #expect(withLate.bed == start)
    }

    @Test("A staged night counts a stage it never reached as zero; an unstaged one leaves it out")
    func missingStages() throws {
        let staged = try #require(SleepNightSummary.make(runs: runs([(.core, 60), (.deep, 30)]), inBedStart: nil, parts: []))
        #expect(staged.stages[.awake] == 0)
        #expect(staged.stages[.rem] == 0)

        let plain = try #require(SleepNightSummary.make(runs: runs([(.core, 400)]), inBedStart: nil, parts: []))
        #expect(plain.stages[.awake] == nil)
        #expect(plain.stages[.deep] == nil)
        #expect(plain.share(of: .deep) == nil)
    }

    @Test("Runs out of order are sorted, and an empty or zero length night is nil")
    func ordering() throws {
        let night = try #require(SleepNightSummary.make(
            runs: runs([(.core, 30), (.rem, 20)]).reversed(), inBedStart: nil, parts: []))
        #expect(night.runs.map(\.stage) == [.core, .rem])
        #expect(SleepNightSummary.make(runs: [], inBedStart: nil, parts: []) == nil)
        #expect(SleepNightSummary.make(runs: [SomaStageRun(stage: .core, start: start, end: start)],
                                       inBedStart: nil, parts: []) == nil)
    }

    @Test("The scoring engine's stage names map onto the four lanes")
    func scoringNames() throws {
        let scoring = [
            ScoringStageRun(stage: "awake", start: start, end: start + 600),
            ScoringStageRun(stage: "core", start: start + 600, end: start + 3_600),
            ScoringStageRun(stage: "deep", start: start + 3_600, end: start + 5_400),
            ScoringStageRun(stage: "rem", start: start + 5_400, end: start + 7_200),
            ScoringStageRun(stage: "unknown", start: start + 7_200, end: start + 7_800),
        ]
        let night = try #require(SleepNightSummary.make(scoring: scoring, inBedStart: nil, parts: []))
        #expect(night.runs.map(\.stage) == [.awake, .core, .deep, .rem])
        #expect(night.wake == start + 7_200)
    }

    @Test("Credit grades at 85, 70 and 45 percent")
    func gradeBands() {
        #expect(SleepNightSummary.grade(1) == .excellent)
        #expect(SleepNightSummary.grade(0.85) == .excellent)
        #expect(SleepNightSummary.grade(0.84) == .good)
        #expect(SleepNightSummary.grade(0.7) == .good)
        #expect(SleepNightSummary.grade(0.69) == .fair)
        #expect(SleepNightSummary.grade(0.45) == .fair)
        #expect(SleepNightSummary.grade(0.44) == .poor)
        #expect(SleepNightSummary.grade(0) == .poor)
    }

    @Test("Six grades in the grid's order, a part not scored left without one")
    func grades() {
        let grades = SleepNightSummary.grades(credits: [.duration: 0.9, .dip: 0.2, .rem: 0.75, .deep: 0.5, .efficiency: 1])
        #expect(grades.map(\.factor) == [.timeAsleep, .heartRateDip, .rem, .deep, .efficiency, .continuity])
        #expect(grades.map(\.grade) == [.excellent, .poor, .good, .fair, .excellent, nil])
        #expect(grades[0].progress == 0.9)
        #expect(grades[5].progress == nil)
        #expect(SleepNightSummary.grades([]).allSatisfy { $0.grade == nil && $0.progress == nil })
    }

    @Test("The scored parts of a real month grade every part they hold")
    @MainActor
    func realParts() {
        let scores = SomaScores.compute(SomaScoresTests().inputs(nights: 30))
        let parts = scores.detail.sleepParts
        let grades = SleepNightSummary.grades(parts)
        #expect(grades.compactMap(\.grade).count == parts.count)
        for part in parts {
            let grade = grades.first { $0.factor == SleepNightSummary.factor(part.kind) }
            #expect(grade?.progress == part.credit)
        }
    }
}
