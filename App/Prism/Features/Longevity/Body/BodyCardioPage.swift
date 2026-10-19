//
//  BodyCardioView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Cardio, pushed from the Longevity tab's Body page: VO2 max, resting heart rate and heart rate
/// recovery, then the fitness age waterfall, seven days of heart rate zones
/// and the latest run or walk.
///
/// Everything but the waterfall comes from Health. The waterfall breaks a pod
/// fitness age into what moved it, so it waits for the first visit.
struct BodyCardioPage: View {
    @Environment(HealthDashboard.self) private var health

    @State private var page = BodyCardio.make(from: BodyCardioInputs(now: .now))

    var body: some View {
        TabPartScaffold(
            aspect: .body,
            eyebrow: page.eyebrow,
            title: page.headline,
            reason: page.reason,
            stats: [
                SomaStat("VO2 max", value: page.vo2Max, trend: page.vo2Trend),
                SomaStat("Resting HR", value: page.restingHeartRate, unit: "bpm", trend: page.restingTrend),
                SomaStat("HR recovery", value: page.recovery, unit: "bpm", trend: page.recoveryTrend),
            ]
        ) {
            SomaChartCard(
                eyebrow: "Fitness age",
                value: nil,
                unit: "years in 12 weeks",
                note: "Comes from a Soma visit."
            ) {
                BodyEmptyWaterfall()
            }
            BodyZonesCard(zones: page.zones)
            BodyRunCard(run: page.run)
            MetricRowsCard(eyebrow: "More on your heart", rows: [
                MetricRowItem("Cardio load", detail: "Seven days of effort against your band", route: .cardioLoad),
                MetricRowItem("Cardio focus", detail: "What the week trained, zone by zone", route: .cardioFocus),
                MetricRowItem("Heart rate recovery", detail: "The drop in the minute after a workout", route: .heartRateRecovery),
                MetricRowItem("ECG", detail: "Your recordings from Apple Watch", route: .ecg),
            ])
            MetricRowsCard(eyebrow: "Movement", rows: [
                MetricRowItem("Steps", detail: "Today against usual, week by week", route: .steps),
                MetricRowItem("Activity summary", detail: "Thirty days of sessions by type", route: .activitySummary),
                MetricRowItem("Territory", detail: "Where your walks and runs went", route: .territory),
            ])
        }
        .navigationTitle("Cardio")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let source = await health.prepare(BodyCardioInputs.metrics) else { return }
        let inputs = await BodyCardioInputs.read(from: source, now: .now, calendar: .current)
        page = BodyCardio.make(from: inputs)
    }
}

/// Minutes in each zone over seven days of workouts, zone 2 in full colour
/// with its usual weekly span drawn under it.
private struct BodyZonesCard: View {
    let zones: BodyCardio.Zones

    @Environment(\.somaTheme) private var theme

    var body: some View {
        TileLink(value: PulseRoute.category("Heart")) {
            SomaChartCard(
                eyebrow: "Heart rate zones, 7 days",
                value: zones.zoneTwo,
                unit: "min in zone 2",
                note: zones.note
            ) {
                VStack(spacing: theme.metrics.bodyRowSpacing) {
                    ForEach(BodyMath.Zone.allCases) { zone in
                        BodyBarRow(
                            title: zone.title,
                            subtitle: zone.name,
                            fraction: zones.fraction(zone),
                            value: zones.value(zone),
                            aspect: .heart,
                            isHighlighted: zone == .two,
                            usual: zone == .two ? zones.usualFraction : nil
                        )
                    }
                }
            }
        }
    }
}

/// The latest run or walk: distance, time, pace and heart rate over it.
private struct BodyRunCard: View {
    let run: BodyCardio.Run?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        TileLink(value: PulseRoute.category("Activity")) {
            SomaChartCard(
                eyebrow: run?.title ?? "Run",
                value: run.map { $0.distance ?? $0.duration },
                unit: run.flatMap { run in run.distance.map { _ in "km in \(run.duration)" } },
                note: run?.note ?? "Your next run or walk with Apple Watch draws this."
            ) {
                if let run, run.heartRate.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Heart rate")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                        BodyLine(values: run.heartRate, aspect: .heart)
                            .frame(height: theme.metrics.bodyRunPlotHeight)
                        HStack {
                            Text(verbatim: "0:00")
                            Spacer()
                            Text(verbatim: run.duration)
                        }
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                    }
                }
            }
        }
    }
}

#Preview("Body cardio") {
    NavigationStack {
        BodyCardioPage()
    }
    .environment(HealthDashboard())
    .environment(AppRouter())
}
