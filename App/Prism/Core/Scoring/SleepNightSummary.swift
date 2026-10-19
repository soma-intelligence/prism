//
//  SleepNightSummary.swift
//  Prism
//

import Foundation
import SomaUI
import HealthScoring

/// Last night as its section reads it: when it started and ended, time in bed
/// and asleep, the seconds in each stage, and each part of the sleep score as
/// a grade.
///
/// Pure arithmetic on the stage runs the scoring engine or the Health store
/// already returned, so the Sleep page and the Home sheet print the same
/// night the same way.
struct SleepNightSummary: Equatable, Sendable {
    /// Into bed, or the first stage when bed was not recorded.
    var bed: Date
    /// The end of the last stage.
    var wake: Date
    /// Seconds from bed to wake.
    var inBed: TimeInterval
    /// Seconds in every stage but awake.
    var asleep: TimeInterval
    /// Seconds in each stage. A staged night holds all four, a stage it never
    /// reached at zero; a night recorded without stages holds what it has.
    var stages: [SomaSleepStage: TimeInterval]
    /// The runs, in order, for the hypnogram.
    var runs: [SomaStageRun]
    /// The six parts of the score, a part not scored without a grade.
    var grades: [SomaSleepFactorGrade]

    /// How far before the first stage a recorded bedtime still counts as this
    /// night's: past that it belongs to an earlier one.
    static let bedReach: TimeInterval = 3 * 3600

    /// The night, or nil when there are no runs to read.
    static func make(runs: [SomaStageRun], inBedStart: Date?, parts: [ScoringSleepPart]) -> SleepNightSummary? {
        let runs = runs.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard let first = runs.first?.start, let wake = runs.map(\.end).max() else { return nil }

        var bed = first
        if let inBedStart, inBedStart < first, first.timeIntervalSince(inBedStart) <= bedReach {
            bed = inBedStart
        }

        var stages: [SomaSleepStage: TimeInterval] = [:]
        for run in runs {
            stages[run.stage, default: 0] += run.end.timeIntervalSince(run.start)
        }
        if stages[.rem] != nil || stages[.deep] != nil {
            for stage in SomaSleepStage.allCases where stages[stage] == nil { stages[stage] = 0 }
        }
        let asleep = stages.filter { $0.key != .awake }.values.reduce(0, +)

        return SleepNightSummary(bed: bed, wake: wake, inBed: wake.timeIntervalSince(bed), asleep: asleep,
                                 stages: stages, runs: runs, grades: grades(parts))
    }

    /// From the scoring engine's runs, named the way it names stages.
    static func make(scoring runs: [ScoringStageRun], inBedStart: Date?, parts: [ScoringSleepPart]) -> SleepNightSummary? {
        make(runs: runs.compactMap { run in
            SomaSleepStage(name: run.stage).map { SomaStageRun(stage: $0, start: run.start, end: run.end) }
        }, inBedStart: inBedStart, parts: parts)
    }

    /// From the Home sheet's read of the Health store, bed as it recorded it.
    static func make(home night: HomeNightStages, parts: [ScoringSleepPart]) -> SleepNightSummary? {
        make(runs: night.segments.map { segment in
            let stage: SomaSleepStage = switch segment.stage {
            case .awake: .awake
            case .rem: .rem
            case .core, .asleep: .core
            case .deep: .deep
            }
            return SomaStageRun(stage: stage, start: segment.start, end: segment.end)
        }, inBedStart: night.night.bedtime, parts: parts)
    }

    /// The share of the night a stage took, 0 to 1.
    func share(of stage: SomaSleepStage) -> Double? {
        let total = stages.values.reduce(0, +)
        guard total > 0, let seconds = stages[stage] else { return nil }
        return seconds / total
    }

    // MARK: Grades

    /// Each part of the score in the grid's order, its credit as the bar and
    /// its grade from that credit.
    static func grades(_ parts: [ScoringSleepPart]) -> [SomaSleepFactorGrade] {
        grades(credits: Dictionary(parts.map { ($0.kind, $0.credit) }, uniquingKeysWith: { first, _ in first }))
    }

    /// The same from each part's credit, 0 to 1.
    static func grades(credits byKind: [ScoringSleepPart.Kind: Double]) -> [SomaSleepFactorGrade] {
        let credits = Dictionary(byKind.map { (factor($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        return SomaSleepFactor.allCases.map { factor in
            let credit = credits[factor]
            return SomaSleepFactorGrade(factor: factor, grade: credit.map(grade), progress: credit)
        }
    }

    /// Credit to a word: 85 percent and up is excellent, 70 good, 45 fair.
    static func grade(_ credit: Double) -> SomaSleepGrade {
        switch credit {
        case 0.85...: .excellent
        case 0.7..<0.85: .good
        case 0.45..<0.7: .fair
        default: .poor
        }
    }

    static func factor(_ kind: ScoringSleepPart.Kind) -> SomaSleepFactor {
        switch kind {
        case .duration: .timeAsleep
        case .dip: .heartRateDip
        case .rem: .rem
        case .deep: .deep
        case .efficiency: .efficiency
        case .continuity: .continuity
        }
    }
}
