//
//  MindInsightsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Mind · Insights, last sixty days: when stress peaks, what comes before a
/// hard afternoon, and the way into what habits do to recovery and sleep.
///
/// The arithmetic is the Mind lens's own (`MindInsights`, `MindHeatmap`),
/// over heart rate raised while still, read one day at a time.
struct MindInsightsPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var inputs: MindInputs?
    @State private var stress: [MindStressDay]?

    var body: some View {
        let calendar = Calendar.current
        let insights = MindInsights.make(from: inputs ?? MindInputs(now: Date()), stress: stress ?? [], journal: MindJournal(journal), calendar: calendar)

        MindPage(
            navigationTitle: "Insights",
            stats: [
                SomaStat("Hard days", value: insights.hardDays.map { "\($0)" }),
                SomaStat("Short nights", value: insights.shortNights.map { "\($0)" }),
                SomaStat("Calm days", value: insights.calmDays.map { "\($0)" }),
            ]
        ) {
            SomaChartCard(
                eyebrow: "When stress peaks",
                value: insights.peakDays,
                unit: insights.peakPart,
                note: insights.heatmap.isEmpty
                    ? "No stress peaks to place yet. Darker blocks will mean more heart rate raised while you were still."
                    : "Darker is more stress, read from heart rate raised while you were still."
            ) {
                MindHeatmapGrid(heatmap: insights.heatmap)
            }

            if insights.hardAfternoons > 0 {
                SomaCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SomaCardHeader("What comes before", caption: "\(insights.hardAfternoons) hard afternoons")
                        MindPrecursorBars(precursors: insights.precursors, total: insights.hardAfternoons)
                    }
                }
            }

            MindEyebrow(text: "What your days do")
            HStack(spacing: 12) {
                ForEach(MindHabitLens.allCases, id: \.self) { lens in
                    TileLink(value: MindRoute.habits(lens)) {
                        MindTile(title: lens.title)
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let read = await MindLoad.inputs(health)
        inputs = read
        stress = await MindLoad.stress(health, inputs: read)
    }
}

/// A small tile that leads to a page: a title, a line under it, a chevron.
struct MindTile: View {
    let title: String
    var detail: String? = nil

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .somaFont(theme.typography.cardTitle)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .accessibilityHidden(true)
                }
                if let detail {
                    Text(detail)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
