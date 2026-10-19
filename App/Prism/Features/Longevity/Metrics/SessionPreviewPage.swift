//
//  SessionPreviewPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A routine read before it is started: how long, how many exercises and
/// sets, each exercise with what it works, and why it fits this month.
///
/// The reason is real: it is the share of
/// the month's muscle work the routine's groups got.
struct SessionPreviewPage: View {
    let routineID: String

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var history: FitnessHistory?
    @State private var isStarting = false

    var body: some View {
        if let routine = TrainingRoutines.routine(routineID) {
            content(routine)
        } else {
            NotWiredContent(eyebrow: "Session", title: "Not found", message: "This routine is not in the catalog.")
        }
    }

    private func content(_ routine: TrainingRoutines.Routine) -> some View {
        let work = MuscleWork(workouts: history?.workouts ?? [])
        let share = routine.groups.compactMap { work.share($0) }.reduce(0, +)

        return TabPartScaffold(
            aspect: .body,
            eyebrow: routine.summary,
            title: "\(routine.name), \(routine.minutes) minutes.",
            reason: "\(routine.exerciseCount) exercises and \(routine.sets) sets. Pick loads you can finish with two reps in hand.",
            stats: [
                SomaStat("Exercises", value: "\(routine.exerciseCount)"),
                SomaStat("Sets", value: "\(routine.sets)"),
                SomaStat("Minutes", value: "\(routine.minutes)"),
            ]
        ) {
            MetricRowsCard(eyebrow: "The session", rows: routine.exercises.map { exercise in
                MetricRowItem(exercise.name, detail: exercise.prescription, value: exercise.target)
            })
            MetricTextCard(
                eyebrow: "Why this session",
                lead: work.totalPoints > 0
                    ? "\(routine.summary) got \(Int((share * 100).rounded()))% of the last 30 days of work."
                    : "A month of workouts shows which groups need this most.",
                rest: work.totalPoints > 0
                    ? "Walks and runs load the legs every day; a session like this one evens the month out."
                    : "Until then it’s a balanced place to start."
            )
            SomaActionCard(
                eyebrow: "When you’re ready",
                title: "Start it",
                detail: "Your watch counts the sets and the rest between them.",
                actionTitle: "Start",
                action: { isStarting = true }
            ) {
                PulseMiniOrb(aspect: .body, diameter: theme.metrics.miniOrbDiameter)
            }
        }
        .navigationTitle(routine.name)
        .task { history = await health.fitnessHistory(days: 30) }
        .sheet(isPresented: $isStarting) {
            NotWiredPage(
                eyebrow: LocalizedStringResource(stringLiteral: routine.name),
                title: "Start the session",
                message: "Live sessions aren’t in Soma yet. Start a strength workout in the Workout app on Apple Watch and follow this list; when it ends, Soma reads it from Health."
            )
        }
    }
}

#Preview("Session preview") {
    NavigationStack { SessionPreviewPage(routineID: "upper") }
        .environment(HealthDashboard())
}
