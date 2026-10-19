//
//  CardioFocusPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What the last seven days of cardio trained: the split between low
/// aerobic, high aerobic and anaerobic time, then each zone with its heart
/// rates, zone 2 against its usual week.
///
/// The split is ``CardioFocus``; the zones are the ones the
/// Cardio page draws, cut from the highest heart rate your age gives.
struct CardioFocusPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var history: FitnessHistory?

    private var words: MetricWords { MetricWords() }
    static let readDays = 35

    var body: some View {
        let now = history?.now ?? .now
        let week = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        let workouts = history?.workouts ?? []
        let focus = CardioFocus(workouts: workouts, in: week)
        let hasData = focus.total > 0
        let usual = CardioFocus.usualZoneTwo(workouts, now: now)
        let ranges = FitnessZones.ranges(maxHeartRate: history?.maxHeartRate)
        let scale = max(focus.zoneMinutes.max() ?? 0, usual?.upperBound ?? 0, 1)
        let lead = MetricLead.override(health.status)

        TabPartScaffold(
            aspect: .heart,
            eyebrow: hasData ? "7 days, \(words.whole(focus.total)) minutes of cardio" : "7 days",
            title: lead?.title ?? headline(focus, hasData: hasData),
            reason: lead?.reason ?? reason(focus, usual: usual, hasData: hasData),
            stats: []
        ) {
            MetricSplitCard(
                eyebrow: "What the week trained",
                parts: CardioFocus.Band.allCases.map { band in
                    MetricSplitPart(
                        title: band.title,
                        detail: band.zones,
                        value: hasData ? "\(words.whole(focus.minutes(band))) min" : nil,
                        share: focus.minutes(band),
                        tone: band == .low ? .soft : band == .high ? .full : .danger
                    )
                },
                aspect: .heart
            )
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.bodyRowSpacing) {
                    Text("Time in zones, 7 days")
                        .somaFont(theme.typography.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    ForEach(0..<5, id: \.self) { index in
                        BodyBarRow(
                            title: "Zone \(index + 1)",
                            subtitle: ranges.map { "\($0[index].lowerBound) to \($0[index].upperBound)" },
                            fraction: hasData ? focus.zoneMinutes[index] / scale : nil,
                            value: hasData ? "\(words.whole(focus.zoneMinutes[index])) min" : nil,
                            aspect: .heart,
                            isHighlighted: index == 1,
                            usual: index == 1 ? usual.map { ($0.lowerBound / scale)...($0.upperBound / scale) } : nil
                        )
                    }
                    Text(ranges == nil ? "Zones are cut from your age. Add your date of birth in Health." : "Heart rates in bpm. The line under zone 2 is its usual week.")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            MetricTextCard(
                eyebrow: "Why most of it should stay easy",
                lead: "Easy aerobic time builds the engine every harder session runs on.",
                rest: "A good week keeps about 80% low and spends the rest high." + (hasData ? " Yours was \(focus.percent(.low))% low." : "")
            )
            if hasData, let ranges {
                SomaActionCard(
                    eyebrow: "Next",
                    title: "Forty minutes in zone 2",
                    detail: "Hold \(ranges[1].lowerBound) to \(ranges[1].upperBound) bpm; it builds the base without taking from recovery."
                ) {
                    PulseMiniOrb(aspect: .heart, diameter: theme.metrics.miniOrbDiameter)
                }
            }
            MetricRowsCard(rows: [
                MetricRowItem("Cardio load", detail: "Seven days of effort against your band", route: .cardioLoad),
                MetricRowItem("Heart rate recovery", detail: "The drop in the minute after each workout", route: .heartRateRecovery),
            ])
        }
        .navigationTitle("Cardio focus")
        .task { history = await health.fitnessHistory(days: Self.readDays) }
        .refreshable { history = await health.fitnessHistory(days: Self.readDays) }
    }

    private func headline(_ focus: CardioFocus, hasData: Bool) -> String {
        guard let history else { return "Reading your workouts." }
        guard hasData else {
            return history.maxHeartRate == nil ? "Cardio focus needs your age." : "No cardio with heart rate this week."
        }
        let low = Double(focus.percent(.low)) / 100
        if focus.minutes(.anaerobic) > 0, focus.minutes(.anaerobic) < 10, low >= 0.7 {
            return "Mostly easy, with a hard effort or two."
        }
        if low >= CardioFocus.easyShareTarget { return "Mostly easy, the way a base is built." }
        if low >= 0.5 { return "A mix of easy and hard." }
        return "Mostly hard this week."
    }

    private func reason(_ focus: CardioFocus, usual: ClosedRange<Double>?, hasData: Bool) -> String {
        guard hasData else {
            return "Every workout with heart rate splits its minutes into five zones. A week of them shows what you trained."
        }
        var text = "\(focus.percent(.low))% of your cardio sat in the low aerobic zones, \(focus.percent(.high))% high and \(focus.percent(.anaerobic))% anaerobic."
        if let usual {
            text += " Zone 2, where the base is built, ran to \(words.whole(focus.zoneMinutes[1])) minutes against a usual \(words.whole(usual.lowerBound)) to \(words.whole(usual.upperBound))."
        }
        return text
    }
}

#Preview("Cardio focus") {
    NavigationStack { CardioFocusPage() }
        .environment(HealthDashboard())
}
