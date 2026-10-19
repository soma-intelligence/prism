//
//  TrainingMenuSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Start a session: a suggestion read off today's recovery, the routines,
/// ways to start without one, and a way to log what the watch missed.
///
/// There is no live session yet, so
/// starting one says so and points at the Workout app, which records the
/// session into Health, where every page here reads it.
struct TrainingMenuSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.somaTheme) private var theme

    @State private var starting: String?
    @State private var path: [MetricRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ListScaffold(eyebrow: "Train", title: "Start a session") {
                if let suggestion {
                    SomaActionCard(
                        eyebrow: "Suggested for today",
                        title: suggestion.title,
                        detail: suggestion.detail,
                        actionTitle: "Start",
                        action: { starting = suggestion.title }
                    ) {
                        PulseMiniOrb(aspect: .activity, diameter: theme.metrics.miniOrbDiameter)
                    }
                }
                MetricRowsCard(eyebrow: "Routines", rows: TrainingRoutines.all.map { routine in
                    MetricRowItem(
                        routine.name,
                        detail: "\(routine.summary). \(routine.exerciseCount) exercises, \(routine.minutes) minutes.",
                        route: .sessionPreview(routine.id)
                    )
                })
                MetricRowsCard(eyebrow: "Start now", rows: TrainingRoutines.starts.map { start in
                    MetricRowItem(start.title, detail: start.detail, action: { starting = start.title })
                })
                MetricRowsCard(rows: [
                    MetricRowItem("Log a past session", detail: "Something the watch missed", action: { starting = "Log a past session" }),
                ])
            }
            .navigationDestination(for: MetricRoute.self) { $0.page }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await health.loadScores() }
        .sheet(item: Binding(get: { starting.map(StartingItem.init) }, set: { starting = $0?.id })) { item in
            NotWiredPage(
                eyebrow: "Train",
                title: LocalizedStringResource(stringLiteral: item.id),
                message: item.id == "Log a past session"
                    ? "Logging a session by hand isn’t connected yet. Add it in the Health app under Workouts and every page here counts it."
                    : "Live sessions aren’t in Soma yet. Start it in the Workout app on Apple Watch; when it ends it lands in Health, and Soma reads it from there."
            )
        }
    }

    /// Today's suggestion, from recovery: nothing hard on a low day.
    private var suggestion: (title: String, detail: String)? {
        guard let recovery = health.scores?.recovery else { return nil }
        let target = health.scores?.strainTarget.map { " and keeps today’s strain inside \($0.lowerBound) to \($0.upperBound)" } ?? ""
        if recovery < 40 {
            return ("A 30 minute walk", "Recovery is \(recovery), so nothing hard today. An easy walk keeps you moving\(target).")
        }
        if recovery < 70 {
            return ("Forty minutes in zone 2", "Recovery is \(recovery): a steady easy session builds the base\(target).")
        }
        return (TrainingRoutines.upperBody.name, "Recovery is \(recovery), room for a strength session\(target).")
    }
}

private struct StartingItem: Identifiable {
    let id: String
}

#Preview("Training menu") {
    TrainingMenuSheet()
        .environment(HealthDashboard())
}
