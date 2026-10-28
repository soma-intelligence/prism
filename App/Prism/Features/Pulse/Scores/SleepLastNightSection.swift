//
//  SleepLastNightSection.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The sleep period and, when it differs, the time in bed (the page's hero
/// gives the time asleep). The stages lead the page in
/// ``SleepNightHypnogram``. Labels only, the numbers and the drawing do the
/// telling.
struct SleepLastNightSection: View {
    let night: SleepNightSummary?
    var calendar: Calendar = .current

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let bed = night.map { ScoreMath.clock($0.bed, calendar: calendar) }
        let wake = night.map { ScoreMath.clock($0.wake, calendar: calendar) }

        SomaCard {
            VStack(spacing: metrics.cardPadding) {
                SomaSleepPeriodRow(bed: bed, wake: wake)
                // The hero gives the time asleep: said once on the page.
                // Time in bed shows only when it says something else, which
                // a night with no in bed record does not.
                if showsTimeInBed {
                    Rectangle()
                        .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(height: 0.5)
                    SomaSleepTotals(inBed: night?.inBed, asleep: night?.asleep, showsAsleep: false)
                }
            }
        }
    }

    /// Time in bed as it reads, set apart from the time asleep: equal to the
    /// minute, it would repeat the hero.
    private var showsTimeInBed: Bool {
        guard let inBed = night?.inBed else { return false }
        guard let asleep = night?.asleep else { return true }
        return SomaFormat.duration(inBed) != SomaFormat.duration(asleep)
    }
}

/// The night's stages in lanes, the first thing a sleep page shows (owner,
/// 2026-10-27). Time in each stage is on the lanes: one graph for the night
/// (owner, 2026-10-24).
struct SleepNightHypnogram: View {
    let night: SleepNightSummary?
    var calendar: Calendar = .current

    var body: some View {
        SomaCard {
            if let night, !night.runs.isEmpty {
                SomaHypnogram(runs: night.runs,
                              bed: night.runs.first.map { ScoreMath.clock($0.start, calendar: calendar) },
                              wake: ScoreMath.clock(night.wake, calendar: calendar))
            } else {
                ScoreEmptyPlot(message: "Stages draw here from a night your watch records.")
            }
        }
    }
}
