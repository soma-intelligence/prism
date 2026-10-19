//
//  MindDetailPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Mind · detail: the Mind score on its arc, what moved it against the usual,
/// the last fourteen days, and a breathing session.
///
/// The score is `SomaScores.mind` (recovery, or calm when recovery is
/// missing). Every row is read from Apple Health against the person's own
/// middle half of days, and renders a dash until there is one.
struct MindDetailPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var inputs: MindInputs?
    @State private var extras = MindJourneyExtras()
    @State private var isBreathing = false

    var body: some View {
        let calendar = Calendar.current
        let words = PulseWording(calendar: calendar, locale: .current)
        let base = inputs ?? MindInputs(now: Date())
        let signals = MindSignals.make(
            heartRateVariability: base.heartRateVariability, restingHeartRate: base.restingHeartRate,
            respiratory: extras.respiratory, sleep: base.sleep, peaks: base.today?.peaks ?? [],
            now: base.now, calendar: calendar, words: words
        )
        let scores = health.scores
        let score = scores?.mind
        let series = Array((scores?.mindSeries ?? []).suffix(14))
        let change = MindScoreWords.againstLastWeek(scores?.mindSeries ?? [])
        let metrics = theme.metrics

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing) {
                MindGauge(score: score, word: MindScoreWords.word(score), change: change)
                    .padding(.top, metrics.heroTopPadding)

                SomaPageHero(eyebrow: nil, title: MindScoreWords.headline(score), reason: nil)

                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    MindRowsCard(
                        title: "What moved it",
                        caption: "Against your usual",
                        rows: [signals.hrv, signals.resting, signals.breathing, signals.peaks, signals.sleep]
                    ) { row in
                        if row.kind == .hrv {
                            NavigationLink(value: MindRoute.hrv) { MindSignalRowView(row: row) }
                                .buttonStyle(.plain)
                        } else {
                            MindSignalRowView(row: row)
                        }
                    }

                    SomaChartCard(
                        eyebrow: "Mind score · last 14 days",
                        value: score.map { "\($0)" },
                        unit: "today",
                        note: series.compactMap { $0 }.count < 3
                            ? "The line fills in once Apple Health holds a week of nights and heart readings."
                            : "The band is your usual, the middle half of these days."
                    ) {
                        SomaBandLine(aspect: .mind, values: series, band: MindUsual.range(series.compactMap { $0 }))
                            .frame(height: metrics.aspectChartHeight * 1.6)
                    }

                    SomaActionCard(
                        eyebrow: "Right now",
                        title: "Breathe for 10 minutes",
                        detail: signals.hrvBaseline.map { "Brings your HRV back toward \(words.whole($0)) ms." } ?? "Ten slow minutes. Soma measures what they do for you.",
                        actionTitle: "Start",
                        action: { isBreathing = true }
                    ) {
                        SomaOrb(aspect: .mind, scale: .mini)
                    }

                    MindHealthStatus(status: health.status)
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .aspectWash(.mind)
        .navigationTitle("Mind")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $isBreathing) { MindBreatheSession() }
    }

    private func load() async {
        async let scores: Void = health.loadScores()
        async let more = MindJourneyLoad.extras(health)
        inputs = await MindLoad.inputs(health)
        extras = await more
        await scores
    }
}

/// The Mind score on an arc from 0 to 100, with its word and its move against
/// last week.
struct MindGauge: View {
    let score: Int?
    let word: String
    let change: Double?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        let colors = theme.colors
        let type = theme.typography
        let hue = theme.aspects[.mind].identity.color
        let line = theme.metrics.chartTrackHeight * 5
        let share = Double(score ?? 0) / 100

        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                MindArc()
                    .stroke(colors.surfaceRecessed.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                if score != nil {
                    MindArc()
                        .trim(from: 0, to: shown)
                        .stroke(hue, style: StrokeStyle(lineWidth: line, lineCap: .round))
                }
                VStack(spacing: 2) {
                    Text(score.map { "\($0)" } ?? "-")
                        .somaFont(type.display)
                        .foregroundStyle(colors.inkPrimary.color)
                    Text(word)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                    if let change, Int(change.rounded()) != 0 {
                        HStack(spacing: 4) {
                            SomaTrendMark(trend: change > 0 ? .up : .down)
                            Text("\(abs(Int(change.rounded()))) \(change > 0 ? "above" : "below") last week")
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                    }
                }
            }
            .padding(line / 2)
            .aspectRatio(1.9, contentMode: .fit)
            .padding(.horizontal, theme.metrics.pagePadding)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mind score")
        .accessibilityValue(score.map { "\($0) of 100, \(word)" } ?? "Not read yet")
        .onAppear {
            if reduceMotion { shown = share } else {
                withAnimation(.easeOut(duration: theme.motion.pressDuration * 6)) { shown = share }
            }
        }
        .onChange(of: score) { _, _ in shown = share }
    }
}

/// The top half of a circle, from the left end round to the right, sitting on
/// the bottom edge of its frame.
struct MindArc: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height)
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return path
    }
}
