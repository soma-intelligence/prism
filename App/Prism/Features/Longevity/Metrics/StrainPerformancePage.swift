//
//  StrainPerformancePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Daily strain against the target band: fourteen days of bars, thirty days
/// split into in, above and below, and how the target is set.
///
/// Strain and its target are the
/// scores `SomaScores` already works out; this page only counts the days.
struct StrainPerformancePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    private var words: MetricWords { MetricWords() }
    static let shownDays = 14

    var body: some View {
        let scores = health.scores
        let series = scores?.strainSeries ?? []
        let target = scores?.strainTarget
        let study = target.map { StrainStudy(series: series, target: $0) }
        let average = StrainStudy.average(series, days: 7)
        let lead = MetricLead.override(health.status)
        let recent = Array(series.suffix(Self.shownDays))
        let axis = words.axis(days: Self.shownDays, now: .now)

        TabPartScaffold(
            aspect: .activity,
            eyebrow: "Last \(SomaScores.seriesDays) days",
            title: lead?.title ?? headline(study: study, scores: scores),
            reason: lead?.reason ?? reason(average: average, target: target, study: study),
            stats: []
        ) {
            SomaChartCard(
                eyebrow: "Daily strain",
                value: scores?.strain.map(String.init),
                unit: "today, of 100",
                note: target.map { "Target \($0.lowerBound) to \($0.upperBound) today. The last 14 days." }
                    ?? "The last 14 days. A target shows once recovery has a week of nights."
            ) {
                MetricDailyBars(
                    values: recent.isEmpty ? Array(repeating: nil, count: Self.shownDays) : recent,
                    usual: target.map { Double($0.lowerBound)...Double($0.upperBound) },
                    aspect: .activity,
                    leadingLabel: axis.0,
                    middleLabel: axis.1,
                    trailingLabel: axis.2
                )
            }
            MetricSplitCard(
                eyebrow: "\(SomaScores.seriesDays) days against the target",
                parts: [
                    MetricSplitPart(title: "In target", value: study.map { "\($0.inside) days" }, share: study.map { $0.share($0.inside) } ?? 0, tone: .full),
                    MetricSplitPart(title: "Above", value: study.map { "\($0.above) days" }, share: study.map { $0.share($0.above) } ?? 0, tone: .danger),
                    MetricSplitPart(title: "Below", value: study.map { "\($0.below) days" }, share: study.map { $0.share($0.below) } ?? 0, tone: .faint),
                ],
                aspect: .activity,
                note: study == nil ? "Days are counted once there is a target to count them against." : nil
            )
            MetricTextCard(
                eyebrow: "How the target is set",
                lead: "The target moves with your recovery and the last weeks of load.",
                rest: scores?.recovery.map { "With recovery at \($0) today, it asks for \(target.map { "\($0.lowerBound) to \($0.upperBound)" } ?? "a band") on a training day and less on the rest." }
                    ?? "It needs a week of nights to read your recovery first."
            )
            MetricRowsCard(rows: [
                MetricRowItem("Cardio load", detail: "Seven days of effort against your band", route: .cardioLoad),
                MetricRowItem("Cardio focus", detail: "What the week trained, zone by zone", route: .cardioFocus),
            ])
        }
        .navigationTitle("Strain performance")
        .task { await health.loadScores() }
        .refreshable { await health.loadScores(force: true) }
    }

    private func headline(study: StrainStudy?, scores: SomaScores?) -> String {
        guard let scores else { return "Reading your strain." }
        guard let study, study.counted > 0 else {
            return scores.strain == nil ? "No strain recorded yet." : "Strain needs a target to read against."
        }
        return "In your target on \(study.inside) \(study.inside == 1 ? "day" : "days") of \(study.counted)."
    }

    private func reason(average: Double?, target: ClosedRange<Int>?, study: StrainStudy?) -> String {
        guard let average else {
            return "Strain is the day’s load from heart rate, 0 to 100. Workouts and a busy day both raise it."
        }
        var text = "Your 7 day average is \(words.whole(average))"
        if let target {
            let inside = Int(average.rounded()) >= target.lowerBound && Int(average.rounded()) <= target.upperBound
            text += inside ? ", inside today’s target of \(target.lowerBound) to \(target.upperBound)." : ", against today’s target of \(target.lowerBound) to \(target.upperBound)."
        } else {
            text += "."
        }
        if let study, study.counted > 0 {
            text += study.below >= study.above ? " Most misses fell short of it." : " Most misses went over it."
        }
        return text
    }
}

#Preview("Strain performance") {
    NavigationStack { StrainPerformancePage() }
        .environment(HealthDashboard())
}
