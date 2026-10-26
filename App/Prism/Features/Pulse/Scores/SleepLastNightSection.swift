//
//  SleepLastNightSection.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Last night as the reference design lays it out, for the Home sheet: the sleep period and
/// its two totals, the stages in lanes, and a tile per stage. Labels only,
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
                    Rectangle()
                        .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(height: 0.5)
                    SomaSleepTotals(inBed: night?.inBed, asleep: night?.asleep)
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
}
