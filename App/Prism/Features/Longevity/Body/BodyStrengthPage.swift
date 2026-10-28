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
                SomaStat("Lean mass", value: page.leanMass, unit: "kg", trend: page.leanTrend, better: .higher),
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
                SomaObjectIcon(aspect: .body, size: .row)
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
        .somaRefreshable { await load() }
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
        if page.weeks.reduce(0, +) == 0 {
            // No session in eight weeks: one line on what fills the chart,
            // rather than 300 points of empty columns.
            BodyWaitingCard(title: "Strength sessions, 8 weeks", line: page.sessionsNote)
        } else {
            chart
        }
    }

    private var chart: some View {
        let type = theme.typography
        let colors = theme.colors

        return SomaChartCard(
            eyebrow: "Strength sessions, 8 weeks",
            value: page.sessionsPerWeek,
            unit: "a week on average",
            note: page.sessionsNote
        ) {
            VStack(spacing: theme.metrics.spaceS) {
                BodyDotColumns(counts: page.weeks)
                    .frame(height: theme.metrics.bodySessionPlotHeight)
                HStack {
                    if let first = page.firstWeek {
                        Text(first, format: .dateTime.month(.abbreviated).day())
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
