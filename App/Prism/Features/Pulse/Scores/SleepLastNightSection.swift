//
//  SleepLastNightSection.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Last night as the reference design lays it out: the sleep period and,
/// when it differs, the time in bed (the page's hero gives the time asleep), the stages in lanes, and a tile per stage. Labels only,
/// the numbers and the drawing do the telling.
struct SleepLastNightSection: View {
    let night: SleepNightSummary?
    var calendar: Calendar = .current

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let bed = night.map { ScoreMath.clock($0.bed, calendar: calendar) }
        let wake = night.map { ScoreMath.clock($0.wake, calendar: calendar) }

        VStack(spacing: metrics.cardSpacing) {
            SomaCard {
                VStack(spacing: metrics.cardPadding) {
                    SomaSleepPeriodRow(bed: bed, wake: wake)
                    // The hero above gives the time asleep: said once on the
                    // page. Time in bed shows only when it says something
                    // else, which a night with no in bed record does not.
                    if showsTimeInBed {
                        Rectangle()
                            .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                            .frame(height: 0.5)
                        SomaSleepTotals(inBed: night?.inBed, asleep: night?.asleep, showsAsleep: false)
                    }
                }
            }

            SomaCard {
                if let night, !night.runs.isEmpty {
                    SomaHypnogram(runs: night.runs,
                                  bed: night.runs.first.map { ScoreMath.clock($0.start, calendar: calendar) },
                                  wake: wake)
                } else {
                    ScoreEmptyPlot(message: "Stages draw here from a night your watch records.")
                }
            }
            // Time in each stage is on the chart's lanes now: one graph for
            // the night (owner, 2026-10-24).
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
