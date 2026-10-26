//
//  RhythmEventsPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The heart notifications Apple Watch sent this year: irregular rhythm, high
/// and low heart rate, one row each by date, with what set each one off and
/// what to do about it.
struct RhythmEventsPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var readings: RhythmMobilityReadings?

    private var words: MetricWords { MetricWords() }

    var body: some View {
        let summary = (readings ?? RhythmMobilityReadings()).rhythm()
        let lead = MetricLead.override(health.status)
        let count = { (kind: RhythmEventKind) in readings == nil ? nil : "\(summary.events.filter { $0.kind == kind }.count)" }

        TabPartScaffold(
            aspect: .heart,
            eyebrow: "Last twelve months",
            title: lead?.title ?? headline(summary),
            reason: lead?.reason ?? reason(summary),
            stats: [
                SomaStat("Irregular", value: count(.irregular)),
                SomaStat("High", value: count(.high)),
                SomaStat("Low", value: count(.low)),
            ]
        ) {
            if summary.hasIrregular {
                MetricTextCard(
                    eyebrow: "Irregular rhythm",
                    lead: "Several of your readings looked like atrial fibrillation. Show these dates to your doctor.",
                    rest: "Recording an ECG on the watch when you get the next one gives them a trace to read."
                )
            }
            MetricRowsCard(
                eyebrow: "Notifications",
                rows: summary.events.isEmpty
                    ? [MetricRowItem("No notifications this year", detail: "Apple Watch sends them when rhythm or heart rate notifications are on in the Watch app.")]
                    : summary.events.map { event in
                        MetricRowItem(
                            event.kind.title,
                            detail: "\(words.day(event.date)). \(event.kind.detail)",
                            value: ScoreMath.clock(event.date),
                            id: event.id
                        )
                    }
            )
            MetricRowsCard(eyebrow: "More on your rhythm", rows: [
                MetricRowItem("ECG", detail: "Thirty seconds on the watch, a trace your doctor can read.", route: .ecg),
                MetricRowItem("AFib History", detail: summary.latestBurden.map { "Latest week \(HeartRhythmSummary.burdenText($0))" } ?? "Not switched on",
                              route: .afibBurden),
            ])
            MetricTextCard(
                eyebrow: "When to get help",
                lead: "A fast or slow heart with chest pain, fainting or breathlessness needs help now: call emergency services.",
                rest: "A notification on its own is a reason to talk to your doctor, not a diagnosis."
            )
        }
        .task { readings = await health.rhythmMobility() }
        .somaRefreshable { readings = await health.rhythmMobility() }
    }

    private func headline(_ summary: HeartRhythmSummary) -> String {
        guard readings != nil else { return "Reading your heart notifications." }
        guard let latest = summary.events.first else { return "No heart notifications this year." }
        return "\(latest.kind.title) on \(words.day(latest.date))."
    }

    private func reason(_ summary: HeartRhythmSummary) -> String {
        guard readings != nil else { return "Asking Health for the notifications your watch sent. They're read on this device only." }
        guard !summary.events.isEmpty else {
            return "These need an Apple Watch with heart notifications switched on in the Watch app."
        }
        let total = summary.events.count
        return total == 1 ? "One notification in the last twelve months." : "\(total) notifications in the last twelve months."
    }
}

#Preview("Rhythm notifications") {
    NavigationStack { RhythmEventsPage() }
        .environment(HealthDashboard())
}
