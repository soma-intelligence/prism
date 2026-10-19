//
//  HeartRateRecoveryPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Heart rate recovery: the drop in the minute after the latest workout,
/// thirty days of drops against their usual range, the recent workouts with
/// theirs, and why it matters.
///
/// The drop is Apple Watch's own one minute recovery sample. The bands and the
/// trend are ``HeartRateRecovery``.
struct HeartRateRecoveryPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var history: FitnessHistory?

    private var words: MetricWords { MetricWords() }
    static let shownDays = 30
    static let readDays = 90

    var body: some View {
        let now = history?.now ?? .now
        let all = (history?.recovery ?? []).sorted { $0.start < $1.start }
        let recent = all.filter { $0.start >= now.addingTimeInterval(-Double(Self.shownDays) * 86_400) }
        let latest = all.last
        let usual = EnvironmentReport.usual(recent.map(\.value), roundedTo: 1)
        let slope = HeartRateRecovery.monthlySlope(all)
        let workouts = (history?.workouts ?? []).reversed().compactMap { workout in
            HeartRateRecovery.reading(after: workout, in: all).map { (workout, $0) }
        }
        let lead = MetricLead.override(health.status)

        TabPartScaffold(
            aspect: .heart,
            eyebrow: eyebrow(latest: latest, workouts: workouts),
            title: lead?.title ?? headline(latest),
            reason: lead?.reason ?? reason(latest: latest, usual: usual, slope: slope, first: all.first),
            stats: []
        ) {
            SomaChartCard(
                eyebrow: "Heart rate recovery",
                value: latest.map { words.whole($0.value) },
                unit: "bpm in a minute",
                note: "\(Self.shownDays) days, after each workout." + (usual.map { " Usually \(words.whole($0.lowerBound)) to \(words.whole($0.upperBound))." } ?? "")
            ) {
                MetricBandChart(
                    values: recent.map(\.value),
                    lower: usual.map { band in recent.map { _ in band.lowerBound } },
                    upper: usual.map { band in recent.map { _ in band.upperBound } },
                    aspect: .heart,
                    axis: [recent.first.map { words.short($0.start) }, recent.last.map { words.short($0.start) }].compactMap { $0 }
                )
            }
            MetricRowsCard(eyebrow: "Recent workouts", rows: workouts.isEmpty
                ? [MetricRowItem("No recovery readings yet", detail: "Apple Watch writes one after most workouts, when you stay still for a minute at the end.")]
                : workouts.prefix(4).map { workout, reading in
                    MetricRowItem(
                        workout.title(words: words),
                        detail: words.day(workout.start),
                        value: "\(words.whole(reading.value)) bpm",
                        id: "\(workout.start)"
                    )
                })
            MetricTextCard(
                eyebrow: "Why it matters",
                lead: "The faster your heart slows after effort, the sooner your nervous system takes the brake back.",
                rest: "A drop of 12 beats or less in a minute is worth a doctor’s look."
                    + (recent.map(\.value).min().map { " Yours has not fallen below \(words.whole($0)) this month." } ?? "")
            )
            SomaActionCard(
                eyebrow: "Next workout",
                title: "Stand still for a minute at the end",
                detail: "Stop, stay still and keep the watch on: that minute gives a clean recovery reading."
            ) {
                PulseMiniOrb(aspect: .heart, diameter: theme.metrics.miniOrbDiameter)
            }
        }
        .navigationTitle("Heart rate recovery")
        .task { history = await health.fitnessHistory(days: Self.readDays) }
        .refreshable { history = await health.fitnessHistory(days: Self.readDays) }
    }

    private func eyebrow(latest: HealthReading?, workouts: [(FitnessWorkout, HealthReading)]) -> String {
        guard let latest else { return "Heart rate recovery" }
        if let match = workouts.first(where: { $0.1 == latest }) {
            return "After the \(match.0.name.lowercased()), \(words.relativeDay(match.0.start, now: .now))"
        }
        return words.day(latest.start)
    }

    private func headline(_ latest: HealthReading?) -> String {
        guard history != nil else { return "Reading your recovery." }
        guard let latest else { return "No recovery reading yet." }
        return "\(words.whole(latest.value)) bpm in the first minute."
    }

    private func reason(latest: HealthReading?, usual: ClosedRange<Double>?, slope: Double?, first: HealthReading?) -> String {
        guard let latest else {
            return "Apple Watch measures how far your heart falls in the minute after a workout. The next one fills this."
        }
        var text = "Your heart dropped \(words.whole(latest.value)) beats in the minute after you stopped"
        if let usual {
            let inside = latest.value >= usual.lowerBound && latest.value <= usual.upperBound
            text += inside ? ", inside your usual \(words.whole(usual.lowerBound)) to \(words.whole(usual.upperBound))." : ", against a usual \(words.whole(usual.lowerBound)) to \(words.whole(usual.upperBound))."
        } else {
            text += "."
        }
        text += " That reads as \(HeartRateRecovery.band(latest.value).title.lowercased())."
        if let slope, abs(slope) >= HeartRateRecovery.meaningfulMonthlySlope {
            text += slope > 0 ? " It has been rising: a fitter heart settles faster." : " It has been easing down over the last months."
        }
        return text
    }
}

#Preview("Heart rate recovery") {
    NavigationStack { HeartRateRecoveryPage() }
        .environment(HealthDashboard())
}
