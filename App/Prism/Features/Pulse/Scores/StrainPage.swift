//
//  StrainPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Strain: today's load on the gauge against the band recovery allows, the
/// day's energy, steps and stand hours, today's heart rate zones, the seven
/// day training load in its productive band, the week against your usual,
/// and the move that fits what is left.
///
/// Soma's strain runs 0 to 100 (the engine's scale), not 0 to 21.
struct StrainPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var inputs: ScoreDetailInputs?
    @State private var showsHistory = false
    @State private var showsBuilt = false

    var body: some View {
        let page = ScorePages.strain(health.scores, inputs)

        ScorePageScaffold(aspect: .activity, title: "Strain") {
            ScoreStage(aspect: .activity, lead: page.lead, series: health.scores?.strainSeries ?? [], directional: false)
            ScoreHead(page.lead)
            ScoreStats(stats: [
                SomaStat("Active kcal", value: page.activeEnergy),
                SomaStat("Steps", value: page.steps),
                SomaStat("Stand hours", value: page.standHours),
            ])
            StrainZonesCard(zones: page.zones)
            SomaChartCard(eyebrow: "Training load", value: page.load.map { ScoreMath.number($0) }, unit: "7 day load",
                          note: page.loadNote) {
                let values = page.loadSeries
                let top = max(page.loadBand?.upperBound ?? 0, values.compactMap { $0 }.max() ?? 0) * 1.15
                if values.contains(where: { $0 != nil }) {
                    ScoreDayLine(
                        points: values.enumerated().compactMap { index, value in
                            value.map { (Double(index) / Double(max(1, values.count - 1)), $0) }
                        },
                        aspect: .activity, range: 0...max(1, top), band: page.loadBand, solidUntil: 1,
                        labels: ["60 days ago", "Today"])
                } else {
                    ScoreEmptyPlot(message: "Your load draws here after a week of days.")
                }
            }
            ScoreUsualCard(title: "This week", aspect: .activity, lines: page.lines)
            ScoreLinks(links: [page.workout.map { workout in
                ScoreLink(title: workout, detail: page.workoutDetail)
            }, ScoreLink(title: "How your score is built") { showsBuilt = true }].compactMap { $0 })
            if let move = page.move {
                ScoreMoveCard(move: move, aspect: .activity)
            }
        }
        .scoreInputs([.today, .heartRecovery], into: $inputs)
        .sheet(isPresented: $showsHistory) {
            ScoreHistorySheet(kind: .strain, scores: health.scores)
        }
        .sheet(isPresented: $showsBuilt) {
            StrainBuiltSheet(page: page, target: health.scores?.strainTarget)
        }
    }
}

/// Today's minutes in each heart rate zone, zone 2 highlighted.
private struct StrainZonesCard: View {
    let zones: [ScorePages.Strain.Zone]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let longest = max(1, zones.map(\.minutes).max() ?? 1)

        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                SomaCardHeader("Heart rate zones", caption: "Today, so far")
                if zones.isEmpty {
                    Text("No zones yet")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .padding(.top, 10)
                } else {
                    ScoreRows(zones) { zone in
                        HStack(spacing: theme.metrics.moveRowGap) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Zone \(zone.id)")
                                    .somaFont(type.body)
                                    .foregroundStyle(colors.inkPrimary.color)
                                Text(zone.bpm)
                                    .somaFont(type.caption)
                                    .foregroundStyle(colors.inkSecondary.color)
                            }
                            .frame(width: theme.metrics.bodyRowLabelWidth, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity * 1.5))
                                    Capsule().fill(theme.aspects[.activity].identity.color.opacity(zone.id == 2 ? 1 : 0.6))
                                        .frame(width: proxy.size.width * zone.minutes / longest)
                                }
                            }
                            .frame(height: theme.metrics.bodyRowBarHeight)
                            Text("\(Int(zone.minutes.rounded())) min")
                                .somaFont(type.rowValue)
                                .foregroundStyle(colors.inkPrimary.color)
                                .frame(width: theme.metrics.bodyRowValueWidth, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
