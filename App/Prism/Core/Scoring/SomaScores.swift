//
//  SomaScores.swift
//  Prism
//

import Foundation
import HealthScoring
import SomaUI

/// Soma's 0 to 100 scores, worked out by `HealthScoring` from what Apple
/// Health holds, with Soma's own gates on top.
///
/// The engine computes whatever the arithmetic allows. What reaches a page is
/// narrower: before seven recorded nights there is no sleep score and no
/// recovery, and before seven days of heart readings there is no stress,
/// because a personal baseline needs a week to mean anything. Seven is the
/// engine's own "reliable" tier (`HealthStats.DataGate.reliable`). Past that
/// gate, recovery still leans on the engine's confidence scaling, which pulls
/// a thin baseline's terms toward neutral until fourteen days.
///
/// Every value is optional, and nil renders as a dash.
nonisolated struct SomaScores: Equatable, Sendable {
    /// Nights, or days of heart readings, before a score is shown.
    static let minimumNights = 7
    /// Days of history each page's series covers.
    static let seriesDays = 30

    /// One moment on today's energy curve.
    struct EnergyPoint: Equatable, Sendable, Codable {
        var date: Date
        /// 0 to 100.
        var level: Double
    }

    /// One signed term of today's recovery, for the explanation.
    struct RecoveryTerm: Equatable, Sendable, Codable {
        enum Kind: String, Sendable, Codable { case hrv, rhr, sleep, rest }
        var kind: Kind
        var points: Double
        var value: Double?
        var baseline: Double?
    }

    // Today.
    var sleep: Int?
    var recovery: Int?
    /// Strain, the activity score.
    var strain: Int?
    var stress: Int?
    /// The energy bank now, 0 to 100.
    var energy: Int?
    /// Today's energy from last night's bedtime (or midnight) to now.
    var energyCurve: [EnergyPoint]
    var sleepDebtHours: Double?
    var sleepNeedHours: Double
    /// The strain band today's recovery supports.
    var strainTarget: ClosedRange<Int>?
    var recoveryTerms: [RecoveryTerm]
    /// Signals recovery had nothing for today.
    var recoveryMissing: [RecoveryTerm.Kind]

    // Direction over the last 30 days.
    var sleepTrend: SomaTrend?
    var recoveryTrend: SomaTrend?
    var strainTrend: SomaTrend?
    var stressTrend: SomaTrend?
    var energyTrend: SomaTrend?

    // The last 30 days, oldest first, ending today. Nil where there is no
    // score for the day, including the days before the gate opened.
    var sleepSeries: [Double?]
    var recoverySeries: [Double?]
    var strainSeries: [Double?]
    var stressSeries: [Double?]
    var energySeries: [Double?]

    /// Nights with sleep recorded in the window read.
    var nightsRecorded: Int

    /// What the score pages read beyond the headline numbers.
    var detail = Detail()

    /// The whole window the engine read (ninety days, oldest first, ending
    /// today), gated like the 30 day series, and last night taken apart.
    struct Detail: Equatable, Sendable, Codable {
        var sleep: [Double?] = []
        var recovery: [Double?] = []
        var strain: [Double?] = []
        var stress: [Double?] = []
        var energyMorning: [Double?] = []
        var energyEnd: [Double?] = []
        var sleepHours: [Double?] = []
        var sleepNeedHours: [Double?] = []
        var sleepDebtHours: [Double?] = []
        /// Daily training load (TRIMP).
        var trimp: [Double?] = []
        var hrvBaseline: [Double?] = []
        var restingBaseline: [Double?] = []
        var remHours: [Double?] = []
        var deepHours: [Double?] = []
        /// Bed clock hour (above 24 after midnight) and wake clock hour.
        var bedHour: [Double?] = []
        var wakeHour: [Double?] = []
        /// Last night's sleep score in its parts. Empty before the gate.
        var sleepParts: [ScoringSleepPart] = []
        var lastNightStages: [ScoringStageRun] = []
        var lastNight: ScoringNightWindow?
    }

    /// The Mind score: recovery, or 100 minus stress when recovery is missing.
    ///
    /// Recovery is the readiness Mind stands for, read off the same autonomic
    /// signals as stress plus last night's sleep. When today has no recovery
    /// yet but does have stress (a day whose own heart readings landed before
    /// any night was scored), calm is the closest honest stand-in, so stress
    /// is turned round onto the same "higher is better" scale.
    var mind: Int? {
        recovery ?? stress.map { 100 - $0 }
    }

    /// The Mind score's direction, following whichever score it came from.
    var mindTrend: SomaTrend? {
        if recovery != nil { return recoveryTrend }
        guard stress != nil else { return nil }
        switch stressTrend {
        case .up: return .down
        case .down: return .up
        case nil: return nil
        }
    }

    /// The Mind series, day by day: recovery, or 100 minus stress on a day
    /// without recovery (the same choice as ``mind``).
    var mindSeries: [Double?] {
        zip(recoverySeries, stressSeries).map { recovery, stress in
            recovery ?? stress.map { 100 - $0 }
        }
    }
}

nonisolated extension SomaScores {
    /// Scores for `inputs`.
    static func compute(_ inputs: ScoringInputs) -> SomaScores {
        make(from: SomaScoringEngine.compute(inputs))
    }

    /// Soma's gates over the engine's result.
    static func make(from result: ScoringResult) -> SomaScores {
        let enoughNights = result.nightsRecorded >= minimumNights
        let enoughHeart = max(result.variabilityDays, result.restingDays) >= minimumNights

        // A day's score in history is gated the same way as today's: only
        // once seven nights (or heart days) had been recorded by that day.
        let nightsByDay = runningCount(result.sleepHours.map { ($0 ?? 0) > 0 })
        let sleepSeries = masked(result.sleepScore, open: nightsByDay)
        let recoverySeries = masked(result.recovery, open: nightsByDay)
        // A day has a stress value exactly when it has a heart reading.
        let heartByDay = runningCount(result.stress.map { $0 != nil })
        let stressSeries = masked(result.stress, open: heartByDay)

        let recoveryTerms = result.recoveryToday?.terms.compactMap { term in
            RecoveryTerm.Kind(rawValue: term.kind.rawValue).map {
                RecoveryTerm(kind: $0, points: term.points, value: term.value, baseline: term.baseline)
            }
        } ?? []

        let curve = result.energyToday?.points.map { EnergyPoint(date: $0.date, level: $0.level) } ?? []

        return SomaScores(
            sleep: enoughNights ? result.sleepScoreToday : nil,
            recovery: enoughNights ? result.recoveryToday?.score : nil,
            strain: result.strainToday,
            stress: enoughHeart ? result.stressToday : nil,
            energy: result.energyToday.map { Int($0.current.rounded()) },
            energyCurve: curve,
            sleepDebtHours: enoughNights ? result.sleepDebtHoursToday : nil,
            sleepNeedHours: result.sleepNeedHoursToday,
            strainTarget: result.strainTargetToday,
            recoveryTerms: enoughNights ? recoveryTerms : [],
            recoveryMissing: result.recoveryToday?.missing.compactMap { RecoveryTerm.Kind(rawValue: $0.rawValue) } ?? [],
            sleepTrend: enoughNights ? trend(result.sleepTrend) : nil,
            recoveryTrend: enoughNights ? trend(result.recoveryTrend) : nil,
            strainTrend: trend(result.strainTrend),
            stressTrend: enoughHeart ? trend(result.stressTrend) : nil,
            energyTrend: trend(result.energyTrend),
            sleepSeries: tail(sleepSeries),
            recoverySeries: tail(recoverySeries),
            strainSeries: tail(result.strain),
            stressSeries: tail(stressSeries),
            energySeries: tail(result.energyEnd),
            nightsRecorded: result.nightsRecorded,
            detail: Detail(
                sleep: sleepSeries,
                recovery: recoverySeries,
                strain: result.strain,
                stress: stressSeries,
                energyMorning: result.energyMorning,
                energyEnd: result.energyEnd,
                sleepHours: result.sleepHours,
                sleepNeedHours: result.sleepNeedHours,
                sleepDebtHours: result.sleepDebtHours,
                trimp: result.trimp,
                hrvBaseline: result.hrvBaseline,
                restingBaseline: result.restingHeartRateBaseline,
                remHours: result.remHours,
                deepHours: result.deepHours,
                bedHour: result.bedHour,
                wakeHour: result.wakeHour,
                sleepParts: enoughNights ? result.sleepPartsToday : [],
                lastNightStages: result.lastNightStages,
                lastNight: result.lastNight
            )
        )
    }

    /// Rising reads as up, falling as down, flat as no mark.
    static func trend(_ trend: ScoringTrend?) -> SomaTrend? {
        switch trend {
        case .rising: .up
        case .falling: .down
        case .flat, nil: nil
        }
    }

    /// How many of the flags up to and including each day are set.
    static func runningCount(_ flags: [Bool]) -> [Int] {
        var count = 0
        return flags.map { flag in
            if flag { count += 1 }
            return count
        }
    }

    /// The series with every day before the gate opened set to nil.
    static func masked(_ series: [Double?], open counts: [Int]) -> [Double?] {
        series.indices.map { index in
            index < counts.count && counts[index] >= minimumNights ? series[index] : nil
        }
    }

    /// The last ``seriesDays`` entries, padded with nils at the front when the
    /// window was shorter.
    static func tail(_ series: [Double?]) -> [Double?] {
        let last = Array(series.suffix(seriesDays))
        return Array(repeating: nil, count: seriesDays - last.count) + last
    }
}

// Written to disk by HealthSnapshotStore so the pages draw at launch.
extension SomaScores: Codable {}
