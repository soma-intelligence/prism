//
//  WidgetSnapshotBuilder.swift
//  Prism
//
//  Turns what the app already holds (Soma's scores, the latest vitals, today's
//  Track log) into the one snapshot the widgets draw.
//

import Foundation
import HealthScoring
import SomaWidgetKit

nonisolated enum WidgetSnapshotBuilder {
    /// Everything the snapshot is made from, gathered on the main actor and
    /// handed over as plain values.
    struct Inputs: Sendable {
        var scores: SomaScores?
        /// Latest resting heart rate, bpm.
        var restingHR: Double?
        /// Latest heart rate variability (SDNN), ms.
        var hrv: Double?
        /// Today's active energy, kcal.
        var activeKcal: Double?
        /// Today's resting energy, kcal.
        var basalKcal: Double?
        var tally: SomaWidgetSnapshot.Tally
        /// Today's meals, kcal; nil when no meal was logged.
        var eatenKcal: Double?
    }

    /// Days in a widget's trace.
    static let traceDays = 7

    static func build(_ inputs: Inputs, now: Date) -> SomaWidgetSnapshot {
        let scores = inputs.scores
        let detail = scores?.detail

        func score(_ value: Int?, _ series: [Double?]?) -> SomaWidgetSnapshot.Score {
            SomaWidgetSnapshot.Score(value: value.map(Double.init), series7: trace(series ?? []))
        }

        let sleepHoursSeries = detail?.sleepHours ?? []
        let stages = (detail?.lastNightStages ?? []).compactMap { run in
            Stage.Kind(rawValue: run.stage).map { Stage(kind: $0, start: run.start, end: run.end) }
        }
        let band = detail?.lastNight.flatMap { night in
            night.start <= night.end ? night.start...night.end : nil
        }

        let burned: Double? = inputs.activeKcal.map { active in active + (inputs.basalKcal ?? 0) }

        var snapshot = SomaWidgetSnapshot(
            generatedAt: now,
            sleep: score(scores?.sleep, scores?.sleepSeries),
            recovery: score(scores?.recovery, scores?.recoverySeries),
            strain: score(scores?.strain, scores?.strainSeries),
            stress: score(scores?.stress, scores?.stressSeries),
            energyNow: scores?.energy.map(Double.init),
            energyCurve: (scores?.energyCurve ?? []).map {
                SomaWidgetSnapshot.EnergyPoint(date: $0.date, level: $0.level)
            },
            sleepBand: band,
            // Baselines, smoothed: Soma keeps no raw daily resting heart rate
            // or variability series.
            restingHR: .init(value: inputs.restingHR, series7: trace(detail?.restingBaseline ?? [])),
            hrv: .init(value: inputs.hrv, series7: trace(detail?.hrvBaseline ?? [])),
            sleepHours: .init(value: sleepHoursSeries.last ?? nil, series7: trace(sleepHoursSeries)),
            hypnogram: stages.isEmpty ? nil : stages,
            burnedKcal: burned,
            eatenKcal: inputs.eatenKcal,
            tally: inputs.tally
        )
        snapshot.hasData = hasData(snapshot)
        return snapshot
    }

    /// Whether the snapshot holds any Health value to draw.
    static func hasData(_ snapshot: SomaWidgetSnapshot) -> Bool {
        [
            snapshot.sleep.value, snapshot.recovery.value, snapshot.strain.value, snapshot.stress.value,
            snapshot.energyNow, snapshot.restingHR.value, snapshot.hrv.value, snapshot.sleepHours.value,
        ].contains { $0 != nil }
    }

    /// The last week of a daily series, oldest first.
    static func trace(_ series: [Double?]) -> [Double?] {
        Array(series.suffix(traceDays))
    }
}
