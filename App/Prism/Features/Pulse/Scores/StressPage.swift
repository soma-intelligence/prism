//
//  StressPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore
import HealthScoring

/// Stress: the gauge against your usual, the day's highest, lowest and
/// average, today on lanes with its peaks, the time spent in each band since
/// waking, what the score leans on, and a breathing session to bring it down.
struct StressPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var inputs: ScoreDetailInputs?
    @State private var reader: ScoreReader?
    @State private var showsHistory = false
    @State private var breathes = false

    var body: some View {
        let page = ScorePages.stress(health.scores, inputs)
        let now = inputs?.now ?? Date()
        let calendar = Calendar.current

        ScorePageScaffold(aspect: .mind, title: "Stress") {
            ScoreStage(aspect: .mind, lead: page.lead, series: health.scores?.stressSeries ?? [], higherIsBetter: false)
            ScoreHead(page.lead)
            ScoreStats(stats: [
                SomaStat("Highest", value: page.highest),
                SomaStat("Lowest", value: page.lowest),
                SomaStat("Average", value: page.average),
            ])
            SomaChartCard(eyebrow: "Today", value: page.line.isEmpty ? nil : "\(page.peaks.count)",
                          unit: page.peaks.count == 1 ? "stress peak" : "stress peaks", note: page.peaksNote) {
                ScoreDayLanes(
                    sleep: (inputs?.recordedNights ?? []).filter { $0.end > calendar.startOfDay(for: now) },
                    moves: (inputs?.workouts ?? []).filter { calendar.isDate($0.start, inSameDayAs: now) }
                        .map { ScoringNightWindow(start: $0.start, end: $0.end) },
                    peaks: page.peaks, now: now, aspect: .mind)
            }
            StressBandsCard(minutes: page.bandMinutes, wake: page.wakeTime)
            ScoreUsualCard(title: "What stress leans on", aspect: .mind, lines: page.lines)
            ScoreLinks(links: [
                ScoreLink(title: "Reading your stress score", detail: "4 min") { reader = .stressArticle },
                ScoreLink(title: "How stress is measured") { reader = .stressMeasured },
            ])
            ScoreMoveCard(
                move: ScorePages.Move(eyebrow: "Now", title: "Four minutes of slow breathing",
                                      detail: "Slow breathing lifts HRV within minutes.", remindAt: nil),
                aspect: .mind, actionTitle: "Start", action: { breathes = true })
        }
        .scoreInputs([.heart, .today, .nights], into: $inputs)
        .sheet(item: $reader) { $0.sheet(stress: health.scores?.stress) }
        .sheet(isPresented: $showsHistory) { ScoreHistorySheet(kind: .stress, scores: health.scores) }
        .sheet(isPresented: $breathes) { MindBreatheSheet(length: 4 * 60) }
    }
}

/// Minutes since waking in each of the three bands, as one split bar and a
/// row per band.
private struct StressBandsCard: View {
    let minutes: [Double]?
    let wake: Date?

    @Environment(\.somaTheme) private var theme

    private static let bands: [(title: String, detail: String)] = [
        ("Low", "under 34"), ("Moderate", "34 to 66"), ("High", "67 and over"),
    ]

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color
        let total = max(1, minutes?.reduce(0, +) ?? 1)
        let caption = wake.map { "Waking hours, \(ScoreMath.clock($0)) to now" } ?? "Today"

        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                SomaCardHeader("Time in each band", caption: LocalizedStringResource(stringLiteral: caption))
                if let minutes {
                    GeometryReader { proxy in
                        let usable = proxy.size.width - 6
                        HStack(spacing: theme.metrics.spaceXS) {
                            ForEach(0..<3, id: \.self) { index in
                                Capsule().fill(hue.opacity(0.35 + 0.325 * Double(index)))
                                    .frame(width: max(0, usable * minutes[index] / total))
                            }
                        }
                    }
                    .frame(height: 8)
                    .padding(.vertical, theme.metrics.spaceM)
                    ScoreRows(Array(0..<3).map { ScoreBandRow(index: $0) }) { row in
                        HStack {
                            Circle().fill(hue.opacity(0.35 + 0.325 * Double(row.index)))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.bands[row.index].title).somaFont(type.body)
                                    .foregroundStyle(colors.inkPrimary.color)
                                Text(Self.bands[row.index].detail).somaFont(type.caption)
                                    .foregroundStyle(colors.inkSecondary.color)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(ScoreMath.duration(hours: minutes[row.index] / 60)).somaFont(type.rowValue)
                                    .foregroundStyle(colors.inkPrimary.color)
                                Text("\(Int((minutes[row.index] / total * 100).rounded()))%").somaFont(type.caption)
                                    .foregroundStyle(colors.inkSecondary.color)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text("No readings yet")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .padding(.top, theme.metrics.spaceM)
                }
            }
        }
    }
}

private struct ScoreBandRow: Identifiable {
    var id: Int { index }
    let index: Int
}

/// Reading your stress score: what it blends, what it is not, and how to
/// use it.
struct StressArticleSheet: View {
    let stress: Int?

    @Environment(\.somaTheme) private var theme
    @State private var measured = false

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        ScoreSheet(eyebrow: "Stress · 4 min read", title: "Reading your stress score") {
            Text("How a day of heartbeats becomes one number.")
                .somaFont(type.callout)
                .foregroundStyle(colors.inkSecondary.color)
            section("What the score blends",
                    "Your score starts from two morning signals, each against your own baseline: HRV and resting heart rate.",
                    "Through the day, a line follows your heart rate against its resting level every thirty minutes. A tired system on a busy day reads high; a rested one on a quiet day reads low.")
            section("Your body, not your mood",
                    "The score measures arousal, not unhappiness.",
                    "A hard run, a big presentation and an argument look much alike to your heart. The context is yours; the score only says how loaded the system is.")
            section("Using it well",
                    "High after a short night: protect the day.",
                    "Keep training easy and move the hard conversation to tomorrow. High on a rested body is capacity being used, which is what it is for.")
            ScoreSectionTitle(text: "Related")
            ScoreLinks(links: [ScoreLink(title: "How stress is measured") { measured = true }])
        }
        .sheet(isPresented: $measured) { StressMeasuredSheet(stress: stress) }
    }

    private func section(_ title: String, _ lead: String, _ rest: String) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.spaceS) {
            Text(title)
                .somaFont(theme.typography.cardTitle)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            ScoreParagraph(lead: lead, rest: rest)
        }
        .padding(.top, theme.metrics.spaceS)
    }
}
