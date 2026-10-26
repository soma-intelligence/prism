//
//  SomaScores+LastKnown.swift
//  Prism
//

import Foundation
import SomaWidgetKit

/// The scores the app last worked out today, drawn at launch before the
/// ninety day read has run.
///
/// The widgets already keep them: every time the app works the scores out it
/// writes them into the App Group for the Home Screen. Read back at launch,
/// they put this morning's numbers under the orb at once instead of a row of
/// placeholders, and the fresh read replaces them a moment later.
///
/// Only today's are used. A snapshot from yesterday would be yesterday's
/// scores drawn as today's, which is worse than waiting.
nonisolated extension SomaScores {
    static func lastKnown(from snapshot: SomaWidgetSnapshot?, now: Date, calendar: Calendar) -> SomaScores? {
        guard let snapshot, snapshot.hasData,
              calendar.isDate(snapshot.generatedAt, inSameDayAs: now),
              // A sleep score is only written past the seven night gate, so
              // a snapshot with one says the gate is open: the first week
              // card, which counts nights, stays as it would be after a read.
              let sleep = snapshot.sleep.value
        else { return nil }

        func padded(_ series: [Double?]) -> [Double?] {
            let tail = Array(series.suffix(seriesDays))
            return Array(repeating: nil, count: seriesDays - tail.count) + tail
        }
        func whole(_ value: Double?) -> Int? { value.map { Int($0.rounded()) } }

        return SomaScores(
            sleep: Int(sleep.rounded()),
            recovery: whole(snapshot.recovery.value),
            strain: whole(snapshot.strain.value),
            stress: whole(snapshot.stress.value),
            energy: whole(snapshot.energyNow),
            energyCurve: snapshot.energyCurve.map { EnergyPoint(date: $0.date, level: $0.level) },
            sleepDebtHours: nil,
            sleepNeedHours: 0,
            strainTarget: nil,
            recoveryTerms: [],
            recoveryMissing: [],
            sleepTrend: nil,
            recoveryTrend: nil,
            strainTrend: nil,
            stressTrend: nil,
            energyTrend: nil,
            sleepSeries: padded(snapshot.sleep.series7),
            recoverySeries: padded(snapshot.recovery.series7),
            strainSeries: padded(snapshot.strain.series7),
            stressSeries: padded(snapshot.stress.series7),
            energySeries: Array(repeating: nil, count: seriesDays),
            nightsRecorded: minimumNights
        )
    }
}

extension HealthDashboard {
    /// Draws today's last known scores until the first read lands.
    ///
    /// Called once at launch. It never replaces scores already read, and it
    /// does not count as a read: the pages still read Health as they open.
    func adoptLastKnownScores(_ snapshot: SomaWidgetSnapshot? = SnapshotStore.shared?.read(), now: Date = .now) {
        // A UI test launch reads an empty store, and every value is a dash.
        guard !UserDefaults.standard.bool(forKey: Self.emptyLaunchKey) else { return }
        guard scores == nil, let known = SomaScores.lastKnown(from: snapshot, now: now, calendar: .current) else { return }
        setLastKnownScores(known)
    }
}
