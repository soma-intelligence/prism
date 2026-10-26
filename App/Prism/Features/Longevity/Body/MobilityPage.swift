//
//  MobilityPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Walking steadiness and falls: Apple's steadiness band (OK, low, very
/// low) over a year, its notifications, the falls the watch detected, the
/// two gait readings behind steadiness, and balance work from CDC STEADI.
///
/// Steadiness comes from iPhone carried on walks, falls from Apple Watch, so
/// the page fills in part for a person with only one of the two. A recent
/// fall puts the help line first, before any number.
struct MobilityPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var readings: RhythmMobilityReadings?

    private var words: MetricWords { MetricWords() }

    var body: some View {
        let summary = (readings ?? RhythmMobilityReadings()).mobility()
        let lead = MetricLead.override(health.status)
        let history = summary.history.map { $0.value * 100 }

        TabPartScaffold(
            aspect: .activity,
            eyebrow: summary.history.last.map { "Walking steadiness, \(words.day($0.start))" } ?? "Mobility",
            title: lead?.title ?? headline(summary),
            reason: lead?.reason ?? reason(summary),
            stats: [
                SomaStat("Steadiness", value: summary.steadiness.map(percent)),
                SomaStat("Falls, 12 months", value: readings == nil ? nil : "\(summary.fallsLast12Months)"),
                SomaStat("Double support", value: summary.doubleSupport.map(percent)),
            ]
        ) {
            if let help = summary.helpLine {
                MetricTextCard(eyebrow: "After a fall", lead: help)
            }
            SomaChartCard(
                eyebrow: "Walking steadiness",
                value: summary.steadiness.map { words.whole($0 * 100) },
                unit: summary.steadiness == nil ? nil : "% \(summary.level.title)",
                note: summary.history.isEmpty
                    ? "Carry your iPhone in a pocket on walks. After a week or two, Health works out a steadiness score."
                    : "Twelve months. The band is Apple's OK range, 40 % and up; under 20 % reads very low."
            ) {
                MetricBandChart(
                    values: history,
                    lower: history.isEmpty ? nil : history.map { _ in SteadinessLevel.okFloor * 100 },
                    upper: history.isEmpty ? nil : history.map { _ in 100 },
                    aspect: .activity,
                    axis: [summary.history.first.map { words.short($0.start) }, summary.history.last.map { words.short($0.start) }].compactMap { $0 }
                )
            }
            if !summary.events.isEmpty {
                MetricRowsCard(eyebrow: "Steadiness notifications", rows: summary.events.map { event in
                    MetricRowItem(event.kind.title, detail: words.day(event.date), value: ScoreMath.clock(event.date),
                                  id: "\(event.date.timeIntervalSince1970)")
                })
            }
            MetricRowsCard(
                eyebrow: "Falls",
                rows: summary.falls.isEmpty
                    ? [MetricRowItem("No falls in the last twelve months",
                                     detail: "Apple Watch counts a hard fall when fall detection is on in the Watch app.",
                                     value: readings == nil ? nil : "0")]
                    : summary.falls.map { fall in
                        MetricRowItem(Int(fall.value.rounded()) > 1 ? "\(Int(fall.value.rounded())) falls" : "Fall",
                                      detail: words.day(fall.start), value: ScoreMath.clock(fall.start),
                                      id: "\(fall.start.timeIntervalSince1970)")
                    }
            )
            MetricRowsCard(
                eyebrow: "How you walk",
                rows: [
                    // Apple, "Measuring Walking Quality Through iPhone Mobility
                    // Metrics" (2021): double support usually runs 20 to 40 %
                    // of a step, and asymmetry is best near zero.
                    MetricRowItem("Double support", detail: "Time with both feet on the ground. Usually 20 to 40 % of a step.",
                                  value: summary.doubleSupport.map(percent)),
                    MetricRowItem("Walking asymmetry", detail: "How much one step differs from the other. Lower is steadier.",
                                  value: summary.asymmetry.map(percent)),
                ],
                footnote: "The latest walk of the last 90 days, measured by iPhone."
            )
            // CDC STEADI (Stopping Elderly Accidents, Deaths and Injuries,
            // 2023): strength and balance work most days lowers the chance
            // of a fall; chair rises and a tandem stand are its home moves.
            MetricRowsCard(
                eyebrow: "Balance work",
                rows: [
                    MetricRowItem("Chair rise", detail: "Stand up from a chair and sit back down without your hands, 10 times.", value: "Daily"),
                    MetricRowItem("Tandem stand", detail: "One foot right in front of the other, beside a counter, for 30 seconds each side.", value: "Daily"),
                    MetricRowItem("Heel raises", detail: "Up on your toes and slowly down, holding the counter, 10 times.", value: "Daily"),
                ],
                footnote: "From CDC STEADI. Tai chi twice a week works too. Ask your doctor first if you have fallen or feel unsteady."
            )
        }
        .task { readings = await health.rhythmMobility() }
        .somaRefreshable { readings = await health.rhythmMobility() }
    }

    private func percent(_ fraction: Double) -> String {
        "\(words.whole(fraction * 100))%"
    }

    private func headline(_ summary: MobilitySummary) -> String {
        guard readings != nil else { return "Reading your steadiness." }
        switch summary.level {
        case .ok: return "Walking steadiness is OK."
        case .low: return "Walking steadiness is low."
        case .veryLow: return "Walking steadiness is very low."
        case .unknown:
            switch summary.fallsLast12Months {
            case 0: return "No steadiness score yet."
            case 1: return "One fall this year."
            default: return "\(summary.fallsLast12Months) falls this year."
            }
        }
    }

    private func reason(_ summary: MobilitySummary) -> String {
        guard readings != nil else { return "Asking Health for your steadiness and falls. They're read on this device only." }
        switch summary.level {
        case .ok:
            return "Your walking looks steady: a low chance of a fall in the next twelve months."
        case .low:
            return "A higher chance of a fall in the next twelve months. Balance work most days can bring it back up."
        case .veryLow:
            return "A much higher chance of a fall in the next twelve months. Talk to your doctor, and start the balance work below."
        case .unknown:
            return "Walking steadiness needs an iPhone carried on walks; falls need an Apple Watch with fall detection on."
        }
    }
}

#Preview("Mobility") {
    NavigationStack { MobilityPage() }
        .environment(HealthDashboard())
}
