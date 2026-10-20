//
//  BodyStrengthView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Strength, pushed from the Longevity tab's Body page: lean mass and
/// sessions a week, then eight weeks of strength sessions and the next
/// session, all from Health.
struct BodyStrengthPage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var page = BodyStrength.make(from: BodyStrengthInputs(now: .now))
    @State private var isPlanning = false

    var body: some View {
        TabPartScaffold(
            aspect: .body,
            eyebrow: page.eyebrow,
            title: page.headline,
            reason: page.reason,
            stats: [
                SomaStat("Lean mass", value: page.leanMass, unit: "kg", trend: page.leanTrend),
                SomaStat("Sessions", value: page.sessionsPerWeek, unit: "a week"),
            ]
        ) {
            BodySessionsCard(page: page)
            SomaActionCard(
                eyebrow: "Next session",
                title: "Nothing planned",
                detail: "Plan a strength session and it shows here.",
                actionTitle: "Plan it",
                action: { isPlanning = true }
            ) {
                SomaOrb(aspect: .body, scale: .mini)
            }
            MetricRowsCard(eyebrow: "Training", rows: [
                MetricRowItem("Muscle work", detail: "Which groups the month loaded", route: .muscleWork),
                MetricRowItem("Strain performance", detail: "Daily strain against your target", route: .strainPerformance),
            ] + TrainingRoutines.all.map { routine in
                MetricRowItem(routine.name, detail: "\(routine.exerciseCount) exercises, \(routine.minutes) minutes", route: .sessionPreview(routine.id))
            })
        }
        .navigationTitle("Strength")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $isPlanning) {
            TrainingMenuSheet()
        }
    }

    private func load() async {
        guard let source = await health.prepare(BodyStrengthInputs.metrics) else { return }
        let inputs = await BodyStrengthInputs.read(from: source, now: .now, calendar: .current)
        page = BodyStrength.make(from: inputs)
    }
}

/// Strength sessions per week for eight weeks, one dot each.
private struct BodySessionsCard: View {
    let page: BodyStrength

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        SomaChartCard(
            eyebrow: "Strength sessions, 8 weeks",
            value: page.sessionsPerWeek,
            unit: "a week on average",
            note: page.sessionsNote
        ) {
            VStack(spacing: 6) {
                BodyDotColumns(counts: page.weeks.isEmpty ? Array(repeating: 0, count: BodyMath.trendWeeks) : page.weeks)
                    .frame(height: theme.metrics.bodySessionPlotHeight)
                HStack {
                    if let first = page.firstWeek {
                        Text(first, format: .dateTime.month(.abbreviated).day())
                    } else {
                        Text(verbatim: "-")
                    }
                    Spacer()
                    Text("This week")
                }
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
            }
        }
    }
}

#Preview("Body strength") {
    NavigationStack {
        BodyStrengthPage()
    }
    .environment(HealthDashboard())
    .environment(AppRouter())
}
