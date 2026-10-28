//
//  CardioLoadPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Seven day cardio load against the productive band on the metric stage,
/// thirty days by status,
/// and the explainer that says how the band is drawn.
///
/// The model is ``TrainingLoad``: Edwards' TRIMP per day from
/// the heart rate zones of each workout, a 7 day and a 42 day weighted mean,
/// and a band from 0.8 to 1.5 times the longer one.
struct CardioLoadPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var history: FitnessHistory?
    @State private var isExplaining = false

    private var words: MetricWords { MetricWords() }
    /// Days read: the chronic window and the six weeks the chart shows.
    static let readDays = 90
    static let chartDays = 42
    static let statusDays = 30

    var body: some View {
        let model = history.flatMap { history in
            TrainingLoad.model(
                daily: TrainingLoad.dailyTrimp(history.workouts, days: Self.readDays, now: history.now, calendar: .current),
                shown: Self.chartDays
            )
        }
        let lead = MetricLead.override(health.status)

        TabPartScaffold(
            aspect: .heart,
            eyebrow: "7 day load, today",
            title: lead?.title ?? headline(model),
            reason: lead?.reason ?? reason(model),
            stats: []
        ) {
            AspectStage(
                aspect: .heart,
                lead: SomaMetricLead(
                    caption: "7 day load, today",
                    value: model.map { words.whole($0.today) },
                    unit: nil,
                    meaning: model?.todayStatus.title ?? "Workouts with heart rate draw this",
                    detail: model.map { "Band \(words.whole($0.todayBand.lowerBound)) to \(words.whole($0.todayBand.upperBound))" },
                    tone: model.map { $0.todayBand.contains($0.today) ? .good : .watch } ?? .neutral
                ),
                values: (model?.acute ?? []).map { Optional($0) },
                scale: nil,
                higherIsBetter: nil,
                style: .line,
                format: { MetricWords().whole($0) },
                bands: model.map { model in
                    zip(model.bandLower, model.bandUpper).map { low, high in Optional(min(low, high)...max(low, high)) }
                }
            )
            statusCard(model)
            MetricRowsCard(rows: [
                MetricRowItem("How cardio load works", action: { isExplaining = true }),
                MetricRowItem("Cardio focus", detail: "What the week trained, zone by zone", route: .cardioFocus),
            ])
            if let model {
                SomaActionCard(eyebrow: "This week", title: advice(model).title, detail: advice(model).detail) {
                    PulseMiniOrb(aspect: .heart, diameter: theme.metrics.miniOrbDiameter)
                }
            }
        }
        .navigationTitle("Cardio load")
        .task { await load() }
        .somaRefreshable { await load() }
        .sheet(isPresented: $isExplaining) {
            CardioLoadExplainer(model: model)
        }
    }

    private func statusCard(_ model: TrainingLoad.Model?) -> some View {
        let recent = model.map { Array($0.statuses.suffix(Self.statusDays)) } ?? []
        let counts = Dictionary(grouping: recent, by: { $0 }).mapValues(\.count)
        let total = max(1, recent.count)
        return SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
                Text("\(Self.statusDays) days by status")
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                MetricDayStrip(tones: recent.isEmpty ? Array(repeating: .empty, count: Self.statusDays) : recent.map(Self.tone))
                VStack(spacing: theme.metrics.bodyRowSpacing) {
                    ForEach(TrainingLoad.Status.counted) { status in
                        let days = counts[status]
                        HStack(spacing: theme.metrics.metricColumnSpacing) {
                            Circle()
                                .fill(Self.tone(status).color(theme, aspect: .heart))
                                .frame(width: theme.metrics.identityDotDiameter, height: theme.metrics.identityDotDiameter)
                            Text(status.title)
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            SomaNumber(model == nil ? nil : "\(days ?? 0) days", theme.typography.rowValue)
                                .foregroundStyle(theme.colors.inkPrimary.color)
                            SomaNumber(model == nil ? nil : "\(Int((Double(days ?? 0) / Double(total) * 100).rounded()))%", theme.typography.rowValue)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                                .frame(width: theme.metrics.metricColumnWidth * 0.7, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    static func tone(_ status: TrainingLoad.Status) -> MetricTone {
        switch status {
        case .productive: .full
        case .tooMuch: .danger
        case .maintaining: .soft
        case .detraining: .faint
        case .calibrating: .empty
        }
    }

    private func headline(_ model: TrainingLoad.Model?) -> String {
        guard let history else { return "Reading your workouts." }
        guard let model else {
            return history.maxHeartRate == nil ? "Cardio load needs your age." : "No cardio load yet."
        }
        switch model.todayStatus {
        case .productive: return "\(words.whole(model.today)), inside your productive band."
        case .tooMuch: return "\(words.whole(model.today)), above what your body is used to."
        case .maintaining: return "\(words.whole(model.today)), holding your fitness."
        case .detraining: return "\(words.whole(model.today)), under your usual load."
        case .calibrating: return "Still learning your usual load."
        }
    }

    private func reason(_ model: TrainingLoad.Model?) -> String {
        guard let history else { return "Asking Health for three months of workouts and their heart rate." }
        guard let model else {
            return history.maxHeartRate == nil
                ? "Zones are cut from your age. Add your date of birth in Health, and every workout with heart rate adds to the load."
                : "Every workout with heart rate adds to the load. Six weeks of them draw the band."
        }
        guard model.todayStatus != .calibrating else {
            return "The band comes from your last six weeks. A few more sessions with heart rate and it settles."
        }
        var text = "Your short term load sits against \(words.whole(model.todayBand.lowerBound)) to \(words.whole(model.todayBand.upperBound)), the range your last six weeks can absorb."
        if let spike = model.longestSpike, spike.count >= 2 {
            let today = Calendar.current.startOfDay(for: history.now)
            let offset = model.statuses.count - 1
            if let from = Calendar.current.date(byAdding: .day, value: spike.lowerBound - offset, to: today),
               let to = Calendar.current.date(byAdding: .day, value: spike.upperBound - offset, to: today) {
                text += " It ran too high from \(words.short(from)) to \(words.short(to))."
            }
        }
        return text
    }

    private func advice(_ model: TrainingLoad.Model) -> (title: String, detail: String) {
        switch model.todayStatus {
        case .tooMuch:
            return ("Ease back into the band", "A few easy days in zone 1 and 2 let the load settle before the next hard one.")
        case .detraining:
            return ("Add a session", "Forty minutes in zone 2 lifts the load back toward the band without a spike.")
        case .maintaining:
            return ("Hold, or build a little", "One longer zone 2 session this week moves the load into the productive band.")
        case .productive, .calibrating:
            return ("Hold the band", "Keep the week’s sessions as they are. The band widens as steady training adds up.")
        }
    }

    private func load() async {
        history = await health.fitnessHistory(days: Self.readDays)
    }
}

/// How cardio load works, on the explainer: this week against the last six
/// as a ring, three rows on how it is counted, and the four statuses as
/// bands on the same ratio, cut where ``TrainingLoad/status(acute:chronic:)``
/// cuts them.
struct CardioLoadExplainer: View {
    let model: TrainingLoad.Model?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.somaTheme) private var theme

    private var words: MetricWords { MetricWords() }

    /// This week's load over the six week usual it is held against.
    private var ratio: Double? {
        guard let model, model.todayStatus != .calibrating else { return nil }
        let chronic = model.todayBand.lowerBound / TrainingLoad.bandLow
        return chronic > 0 ? model.today / chronic : nil
    }

    var body: some View {
        let ratio = ratio

        SomaExplainer(title: "Cardio load", summary: "Your last 7 days of effort against the 42 before.",
                      aspect: .heart, onClose: { dismiss() }) {
            SomaExplainerRing(fraction: (ratio ?? 0) / 2, value: ratio.map { "\(ScoreMath.number($0, decimals: 1))×" },
                              caption: model?.todayStatus.title ?? "Calibrating", aspect: .heart)
        } content: {
            SomaExplainerSection("How it’s counted") {
                SomaExplainerRow(symbol: "heart.fill", hue: .heart, term: "Each session",
                                 line: "Minutes in each heart rate zone, weighted 1 to 5.")
                SomaExplainerRow(symbol: "calendar", hue: .activity, term: "This week",
                                 line: "Recent days count most.", trailing: model.map { words.whole($0.today) })
                SomaExplainerRow(symbol: "arrow.left.and.right", hue: .mind, term: "Your band",
                                 line: "From your last 42 days, so it moves with you.",
                                 trailing: model.map { "\(words.whole($0.todayBand.lowerBound)) to \(words.whole($0.todayBand.upperBound))" })
            }
            SomaExplainerRanges("Ranges", bands: [
                SomaExplainerBand("Detraining", 0...0.8, tone: .poor, detail: "under 0.8×"),
                SomaExplainerBand("Maintaining", 0.8...1.0, tone: .fair, detail: "0.8 to 1×"),
                SomaExplainerBand("Productive", 1.0...1.5, tone: .good, detail: "1 to 1.5×"),
                SomaExplainerBand("Too much", 1.5...2.0, tone: .poor, detail: "over 1.5×"),
            ], aspect: .heart, marker: ratio.map { min(2, $0) }, markerLabel: ratio.map { "This week, \(ScoreMath.number($0, decimals: 1))×" })
            SomaExplainerSection(nil) {
                Button {
                    if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=Banister+training+impulse+fitness+fatigue") { openURL(url) }
                } label: {
                    SomaExplainerRow(symbol: "book.closed.fill", hue: .other, term: "Read the source",
                                     line: "Banister’s model of training impulse")
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("Cardio load") {
    NavigationStack { CardioLoadPage() }
        .environment(HealthDashboard())
}
