//
//  ActivitySummaryPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Thirty days of sessions: time by type, today's Move ring and the most
/// recent sessions.
///
/// Sessions are the workouts in
/// Health, from the watch or any app that writes them; the Move goal is the
/// one set on the Activity rings.
struct ActivitySummaryPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var history: FitnessHistory?
    @State private var moveToday: Double?
    @State private var moveGoal: Double?
    @State private var isLogging = false

    private let reader = FitnessHealthKit()
    private var words: MetricWords { MetricWords() }
    static let days = 30

    var body: some View {
        let workouts = history?.workouts ?? []
        let byType = Dictionary(grouping: workouts, by: \.activity)
            .map { (activity: $0.key, sessions: $0.value.count, seconds: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.seconds > $1.seconds }
        let total = byType.reduce(0) { $0 + $1.seconds }
        let longest = byType.first?.seconds ?? 0
        let lead = MetricLead.override(health.status)

        TabPartScaffold(
            aspect: .activity,
            eyebrow: "Last \(Self.days) days",
            title: lead?.title ?? headline(byType: byType, total: total),
            reason: lead?.reason ?? reason(workouts: workouts, byType: byType, total: total),
            stats: []
        ) {
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.bodyRowSpacing) {
                    Text("Time by type")
                        .somaFont(theme.typography.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    if byType.isEmpty {
                        BodyBarRow(title: "No sessions yet", fraction: nil, value: nil, aspect: .activity)
                    }
                    ForEach(byType.prefix(6), id: \.activity) { item in
                        BodyBarRow(
                            title: FitnessActivities.name(item.activity),
                            subtitle: "×\(item.sessions)",
                            fraction: longest > 0 ? item.seconds / longest : nil,
                            value: SoundExposure.duration(item.seconds),
                            aspect: .activity,
                            isHighlighted: item.activity == byType.first?.activity
                        )
                    }
                }
            }
            SomaChartCard(
                eyebrow: "Move, today",
                value: moveToday.map(words.whole),
                unit: moveGoal.map { "of \(words.whole($0)) kcal" } ?? "kcal",
                note: moveNote
            ) {
                MetricRing(fraction: moveGoal.flatMap { goal in moveToday.map { $0 / goal } }, aspect: .activity)
            }
            MetricRowsCard(eyebrow: "Recent sessions", rows: workouts.isEmpty
                ? [MetricRowItem("No sessions in 30 days", detail: "A workout with Apple Watch, or any app that writes one to Health, lands here.")]
                : workouts.suffix(5).reversed().map { workout in
                    MetricRowItem(
                        workout.title(words: words),
                        detail: "\(words.relativeDay(workout.start, now: .now)), \(words.time(workout.start))",
                        value: workout.length,
                        id: "\(workout.start)"
                    )
                })
            MetricRowsCard(rows: [
                MetricRowItem("Cardio load", detail: "Seven days of effort against your band", route: .cardioLoad),
                MetricRowItem("Muscle work", detail: "Which groups the month loaded", route: .muscleWork),
            ])
            SomaActionCard(
                eyebrow: "Something missing?",
                title: "Log a past session",
                detail: "A swim or a class the watch didn’t see still counts toward the month.",
                actionTitle: "Log it",
                action: { isLogging = true }
            ) {
                PulseMiniOrb(aspect: .activity, diameter: theme.metrics.miniOrbDiameter)
            }
        }
        .navigationTitle("Activity summary")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $isLogging) {
            NotWiredPage(
                eyebrow: "Something missing?",
                title: "Log a past session",
                message: "Logging a session by hand isn’t connected yet. Until it is, add it in the Health app under Workouts and it shows here."
            )
        }
    }

    private var moveNote: String {
        guard let moveToday else { return "Active energy from your watch fills the ring." }
        guard let moveGoal else { return "Set a Move goal in the Fitness app and the ring shows how far along you are." }
        return "\(Int((moveToday / moveGoal * 100).rounded()))% of today’s goal."
    }

    private func headline(byType: [(activity: Int, sessions: Int, seconds: Double)], total: Double) -> String {
        guard let top = byType.first, total > 0 else {
            return history == nil ? "Reading your sessions." : "No sessions in the last \(Self.days) days."
        }
        let hours = Int((total / 3600).rounded())
        let share = top.seconds / total
        let lead = hours >= 1 ? "\(hours) \(hours == 1 ? "hour" : "hours") on the move" : "\(Int((total / 60).rounded())) minutes on the move"
        return share >= 0.5 ? "\(lead), most of it \(FitnessActivities.name(top.activity).lowercased())." : "\(lead)."
    }

    private func reason(workouts: [FitnessWorkout], byType: [(activity: Int, sessions: Int, seconds: Double)], total: Double) -> String {
        guard let first = workouts.first, let top = byType.first, total > 0 else {
            return "Workouts from Apple Watch, or any app that writes them to Health, add up here by type."
        }
        let share = Int((top.seconds / total * 100).rounded())
        return "\(workouts.count) \(workouts.count == 1 ? "session" : "sessions") since \(words.short(first.start)), and \(FitnessActivities.name(top.activity).lowercased()) took \(share)% of the time."
    }

    private func load() async {
        let now = Date()
        history = await health.fitnessHistory(days: Self.days, now: now)
        if let source = await health.prepare([FitnessHistory.Metric.activeEnergy]),
           let metric = HealthMetricCatalog.metric(for: FitnessHistory.Metric.activeEnergy) {
            moveToday = (try? await source.total(metric, from: Calendar.current.startOfDay(for: now), to: now))?.value
        }
        moveGoal = await reader.moveGoal(now: now, calendar: .current)
    }
}

#Preview("Activity summary") {
    NavigationStack { ActivitySummaryPage() }
        .environment(HealthDashboard())
}
