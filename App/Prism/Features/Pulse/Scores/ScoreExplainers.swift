//
//  ScoreExplainers.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

// The sheets behind the score pages' info buttons and "How your score is
// built" rows, on SomaUI's explainer: the picture first, a short title, a
// few rows of glyph, term and line, what moved the number today, and the
// ranges as coloured bands. Every weight, cap and threshold here is the
// engine's (HealthScoring) or the app's (ScoreMath.Band); none is invented.

// MARK: - Shared

enum ScoreExplainerKit {
    /// The three bands every 0 to 100 score shares: under 34, 34 to 66, 67
    /// and over (``ScoreMath/Band``).
    static func bands(_ low: String, _ middle: String, _ high: String,
                      higherIsBetter: Bool?) -> [SomaExplainerBand] {
        let tones: [SomaExplainerBand.Tone]
        switch higherIsBetter {
        case true?: tones = [.poor, .fair, .good]
        case false?: tones = [.good, .fair, .poor]
        case nil: tones = [.light, .middle, .strong]
        }
        return [
            SomaExplainerBand(low, 0...34, tone: tones[0]),
            SomaExplainerBand(middle, 34...67, tone: tones[1]),
            SomaExplainerBand(high, 67...100, tone: tones[2]),
        ]
    }

    /// The ring's fill for a score, or a quiet tenth when there is none yet.
    static func fraction(_ value: Int?) -> Double {
        value.map { Double($0) / 100 } ?? 0
    }

    static func todayLabel(_ value: Int?, _ word: String = "Today") -> String? {
        value.map { "\(word), \($0)" }
    }
}

extension SomaHealthHue {
    /// The data hue that sits closest to an aspect, for a glyph on an
    /// explainer.
    init(_ aspect: SomaAspect) {
        switch aspect {
        case .heart: self = .heart
        case .sleep: self = .sleep
        case .mind: self = .mind
        case .activity: self = .activity
        case .body: self = .body
        case .gut: self = .nutrition
        }
    }
}

// MARK: - The page guide

/// How to read a score page: the five things every one of them does, shown
/// once on the first visit and from the info button after.
struct ScoreGuideSheet: View {
    let eyebrow: String
    var aspect: SomaAspect = .mind

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let hue = SomaHealthHue(aspect)
        let type = theme.typography
        let colors = theme.colors

        SomaExplainer(eyebrow: eyebrow, title: "Reading a score", summary: "Five things on every score page.",
                      aspect: aspect, onClose: { dismiss() }) {
            SomaExplainerRing(fraction: 0.7, caption: "0 to 100", aspect: aspect)
        } content: {
            SomaExplainerSection(nil) {
                SomaExplainerRow(symbol: "circle.dashed", hue: hue, term: "The ring", line: "Today, from 0 to 100.")
                SomaExplainerRow(symbol: "text.alignleft", hue: hue, term: "The sentence", line: "What it means, then why, in grey.")
                SomaExplainerRow(symbol: "arrow.left.and.right", hue: hue, term: "Your usual", line: "Every line sits on your own range.")
                SomaExplainerRow(symbol: "chart.bar.fill", hue: hue, term: "Over time", line: "Weeks and months, a row away.")
                SomaExplainerRow(symbol: "checkmark.circle.fill", hue: hue, term: "One move", line: "The one thing that fits today.")
            }
            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .somaFont(type.body)
                    .foregroundStyle(colors.onAccent.color)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: theme.metrics.chromeCapsuleHeight)
                    .background(Capsule().fill(colors.accent.color))
            }
            .buttonStyle(SomaGlassPressStyle())
        }
    }
}

// MARK: - Recovery

/// How recovery is built: fifty to start from, then each signal's signed
/// points against your own usual, each held under its cap.
struct RecoveryBuiltSheet: View {
    let page: ScorePages.Recovery

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let value = page.lead.value

        SomaExplainer(title: "Recovery", summary: "How ready you are for load today. Starts at 50; each signal adds or takes.",
                      aspect: .heart, onClose: { dismiss() }) {
            SomaExplainerRing(fraction: ScoreExplainerKit.fraction(value), value: value.map(String.init),
                              caption: page.lead.word ?? "After seven nights", aspect: .heart)
        } content: {
            if !page.terms.isEmpty {
                SomaExplainerMoves("What moved it today", moves: page.terms.map { term in
                    SomaExplainerMove(title: term.title, value: ScoreMath.signed(term.points), detail: term.detail,
                                      hue: Self.hue(term.title), shape: .signed(term.points / max(1, term.cap)))
                })
            }
            SomaExplainerSection("How it’s built") {
                SomaExplainerRow(symbol: "waveform.path.ecg", hue: .heart, term: "HRV",
                                 line: "Above your usual adds.", trailing: "±28")
                SomaExplainerRow(symbol: "heart.fill", hue: .vitals, term: "Resting heart rate",
                                 line: "Below your usual adds.", trailing: "±20")
                SomaExplainerRow(symbol: "moon.fill", hue: .sleep, term: "Sleep",
                                 line: "Last night’s score against 50.", trailing: "±16")
                SomaExplainerRow(symbol: "figure.walk", hue: .nutrition, term: "A light yesterday",
                                 line: "Gives a little back.", trailing: "+4")
            }
            SomaExplainerRanges("Ranges", bands: ScoreExplainerKit.bands("Run down", "Partly", "Recovered", higherIsBetter: true),
                                aspect: .heart, marker: value.map(Double.init),
                                markerLabel: ScoreExplainerKit.todayLabel(value))
            if !page.missing.isEmpty {
                SomaExplainerNote("No \(ListFormatter.localizedString(byJoining: page.missing).lowercased()) today, so it was left out, not guessed.")
            }
            SomaExplainerNote("Softened near 100. Shown after seven nights. A wellness signal, not a diagnosis.")
        }
    }

    private static func hue(_ title: String) -> SomaHealthHue {
        switch title {
        case "HRV": .heart
        case "Resting heart rate": .vitals
        case "Sleep": .sleep
        default: .nutrition
        }
    }
}

// MARK: - Sleep

/// How the sleep score is built: up to six parts at the engine's weights,
/// drawn as a donut, and what each earned last night.
struct SleepBuiltSheet: View {
    let score: Int?
    let parts: [ScoringSleepPart]

    @Environment(\.dismiss) private var dismiss

    /// The engine's weights (40, 15, 15, 10, 10, 5 over 95), as shares of
    /// 100, for the donut before a night is scored.
    private static let weights: [(kind: ScoringSleepPart.Kind, weight: Double)] = [
        (.duration, 40), (.efficiency, 15), (.deep, 15), (.rem, 10), (.continuity, 10), (.dip, 5),
    ]
    private static let standard: [(ScoringSleepPart.Kind, Double)] = weights.map { item in
        (item.kind, item.weight / 95 * 100)
    }

    var body: some View {
        let shown = parts.isEmpty ? Self.standard.map { Self.part($0.0, share: $0.1) }
            : parts.map { Self.part($0.kind, share: $0.share) }

        SomaExplainer(title: "Sleep", summary: "Six parts, each against your own need. A part with no data hands its weight to the others.",
                      aspect: .sleep, onClose: { dismiss() }) {
            SomaExplainerDonut(parts: shown, value: score.map(String.init),
                               caption: score.map(ScorePages.sleepWord) ?? "After seven nights")
        } content: {
            SomaExplainerSection("How it’s built") {
                ForEach(shown) { SomaExplainerRow($0) }
            }
            if !parts.isEmpty {
                SomaExplainerMoves("Last night", moves: parts.map { part in
                    let look = Self.part(part.kind, share: part.share)
                    return SomaExplainerMove(title: look.title,
                                             value: "\(Int(part.points.rounded())) of \(Int(part.share.rounded()))",
                                             hue: look.hue, shape: .filled(part.credit))
                })
            }
            SomaExplainerRanges("Ranges", bands: [
                SomaExplainerBand("Short", 0...60, tone: .poor),
                SomaExplainerBand("Fair", 60...80, tone: .fair),
                SomaExplainerBand("Restored", 80...100, tone: .good),
            ], aspect: .sleep, marker: score.map(Double.init), markerLabel: ScoreExplainerKit.todayLabel(score, "Last night"))
            SomaExplainerNote("The score is the sum. Shown after seven nights.")
        }
    }

    static func part(_ kind: ScoringSleepPart.Kind, share: Double) -> SomaExplainerPart {
        switch kind {
        case .duration:
            SomaExplainerPart(title: "Duration", symbol: "clock.fill", hue: .sleep, weight: share, line: "Time asleep against your need.")
        case .efficiency:
            SomaExplainerPart(title: "Efficiency", symbol: "bed.double.fill", hue: .cycle, weight: share, line: "Asleep against in bed.")
        case .deep:
            SomaExplainerPart(title: "Deep sleep", symbol: "moon.zzz.fill", hue: .hearing, weight: share, line: "Its share, for your age.")
        case .rem:
            SomaExplainerPart(title: "REM", symbol: "sparkles", hue: .symptoms, weight: share, line: "18 to 25 percent of the night.")
        case .continuity:
            SomaExplainerPart(title: "Interruptions", symbol: "alarm.fill", hue: .respiratory, weight: share, line: "Each waking costs 8 percent of it.")
        case .dip:
            SomaExplainerPart(title: "Heart rate dip", symbol: "heart.fill", hue: .heart, weight: share, line: "Asleep against your resting rate.")
        }
    }
}

// MARK: - Strain

/// How strain is built: each minute in a heart rate zone counts by its zone,
/// on a curve that gets harder to climb, today's minutes as the bars.
struct StrainBuiltSheet: View {
    let page: ScorePages.Strain
    let target: ClosedRange<Int>?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let value = page.lead.value
        let loads = page.zones.map { $0.minutes * Double($0.id) }
        let top = max(1, loads.max() ?? 1)
        let zoneHues: [SomaHealthHue] = [.respiratory, .nutrition, .mobility, .activity, .heart]

        SomaExplainer(title: "Strain", summary: "The load your heart carried today. Resets at midnight.",
                      aspect: .activity, onClose: { dismiss() }) {
            SomaExplainerRing(fraction: ScoreExplainerKit.fraction(value), value: value.map(String.init),
                              caption: page.lead.word ?? "No movement yet", aspect: .activity)
        } content: {
            if loads.contains(where: { $0 > 0 }) {
                SomaExplainerMoves("What moved it today", moves: page.zones.map { zone in
                    SomaExplainerMove(title: "Zone \(zone.id)", value: SomaFormat.duration(zone.minutes * 60),
                                      detail: "\(zone.bpm), each minute ×\(zone.id)",
                                      hue: zoneHues[max(0, min(4, zone.id - 1))],
                                      shape: .filled(zone.minutes * Double(zone.id) / top))
                })
            }
            SomaExplainerSection("How it’s built") {
                SomaExplainerRow(symbol: "heart.fill", hue: .heart, term: "Heart rate zones",
                                 line: "A minute in zone 5 counts five times one in zone 1.")
                SomaExplainerRow(symbol: "flame.fill", hue: .activity, term: "Active energy",
                                 line: "Stands in where heart rate is missing.")
                SomaExplainerRow(symbol: "chart.line.flattrend.xyaxis", hue: .mobility, term: "Harder near the top",
                                 line: "A day at your usual load reads about 20.")
                if let target {
                    SomaExplainerRow(symbol: "scope", hue: .nutrition, term: "Today’s target",
                                     line: "Set by recovery.", trailing: "\(target.lowerBound) to \(target.upperBound)")
                }
            }
            SomaExplainerRanges("Ranges", bands: ScoreExplainerKit.bands("Light", "Moderate", "Hard", higherIsBetter: nil),
                                aspect: .activity, marker: value.map(Double.init),
                                markerLabel: ScoreExplainerKit.todayLabel(value))
            SomaExplainerNote("Soma’s strain runs 0 to 100, against your own history.")
        }
    }
}

// MARK: - Stress

/// How stress is measured: the morning's two signals at their weights, what
/// the line through the day counts and leaves out, and the bands.
struct StressMeasuredSheet: View {
    let stress: Int?

    @Environment(\.dismiss) private var dismiss

    private static let parts = [
        SomaExplainerPart(title: "HRV", symbol: "waveform.path.ecg", hue: .mind, weight: 60,
                          line: "Lower than your usual raises it."),
        SomaExplainerPart(title: "Resting heart rate", symbol: "heart.fill", hue: .heart, weight: 40,
                          line: "Higher than your usual raises it."),
    ]

    var body: some View {
        SomaExplainer(title: "Stress", summary: "A signal from your body, not a verdict on your day.",
                      aspect: .mind, onClose: { dismiss() }) {
            SomaExplainerDonut(parts: Self.parts, value: stress.map(String.init),
                               caption: stress.map(ScorePages.stressWord) ?? "No reading")
        } content: {
            SomaExplainerSection("Each morning") {
                ForEach(Self.parts) { SomaExplainerRow($0) }
            }
            SomaExplainerSection("Through the day") {
                SomaExplainerRow(symbol: "clock.fill", hue: .mind, term: "Every 30 minutes",
                                 line: "Heart rate against its resting level.")
                SomaExplainerRow(symbol: "moon.fill", hue: .other, term: "Sleep", line: "Not counted.")
                SomaExplainerRow(symbol: "figure.run", hue: .other, term: "Workouts", line: "Not counted in the daily score.")
            }
            SomaExplainerRanges("Ranges", bands: ScoreExplainerKit.bands("Low", "Moderate", "High", higherIsBetter: false),
                                aspect: .mind, marker: stress.map(Double.init),
                                markerLabel: ScoreExplainerKit.todayLabel(stress))
            SomaExplainerNote("With one signal, Soma uses that one. A physiological signal, not a diagnosis.")
        }
    }
}

// MARK: - Energy

/// How the bank works: what charges it, what spends it, and where today's
/// points went.
struct EnergyInfoSheet: View {
    let page: ScorePages.Energy

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let value = page.lead.value
        let reach = max(10, Double(page.ledger.map { abs($0.points) }.max() ?? 10))

        SomaExplainer(title: "Energy", summary: "Sleep charges it; living spends it. A model, not a measurement.",
                      aspect: .mind, onClose: { dismiss() }) {
            SomaExplainerRing(fraction: ScoreExplainerKit.fraction(value), value: value.map(String.init),
                              caption: page.lead.word ?? "After a night", aspect: .mind)
        } content: {
            if !page.ledger.isEmpty {
                SomaExplainerMoves("Where it went today", moves: page.ledger.map { entry in
                    SomaExplainerMove(title: entry.title, value: ScoreMath.signed(Double(entry.points)), detail: entry.span,
                                      hue: entry.title == "Sleep" ? .sleep : .mind,
                                      shape: .signed(Double(entry.points) / reach))
                })
            }
            SomaExplainerSection("How it’s built") {
                SomaExplainerRow(symbol: "moon.fill", hue: .sleep, term: "Sleep charges",
                                 line: "More for a better and longer night.")
                SomaExplainerRow(symbol: "sun.max.fill", hue: .mobility, term: "Waking hours spend",
                                 line: "About 29 over a 16 hour day.")
                SomaExplainerRow(symbol: "figure.run", hue: .activity, term: "Strain spends",
                                 line: "More for a harder day.")
                SomaExplainerRow(symbol: "waveform.path.ecg", hue: .mind, term: "Stress tilts it",
                                 line: "A tense day costs more, a calm one less.")
            }
            SomaExplainerRanges("Ranges", bands: ScoreExplainerKit.bands("Low", "Easy", "Full", higherIsBetter: true),
                                aspect: .mind, marker: value.map(Double.init),
                                markerLabel: ScoreExplainerKit.todayLabel(value, "Now"))
        }
    }
}

#Preview("Sleep explainer") {
    SleepBuiltSheet(score: 78, parts: [])
}
