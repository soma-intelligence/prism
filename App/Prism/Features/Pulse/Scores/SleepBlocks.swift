//
//  SleepBlocks.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

// The five blocks the Sleep page took from the earlier app's sleep sheet
// (owner, 2026-10-28): how you felt on waking, the fourteen night debt, the
// time it took to fall asleep, the night's vitals on one toggle, and who
// recorded the night.

/// How the night felt on waking, rated one to ten: the morning rating Track
/// keeps (``TrackLogStore``), against this morning. Tapping it opens the
/// rating; unrated, it asks for one.
struct SleepFeltCard: View {
    let open: () -> Void

    @Environment(\.somaTheme) private var theme
    private let log = TrackLogStore.shared

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let rating = log.wakeRating(on: .now)

        Button(action: open) {
            SomaCard {
                HStack(spacing: metrics.spaceM) {
                    VStack(alignment: .leading, spacing: metrics.spaceXS) {
                        Text("How you felt")
                            .somaFont(type.eyebrow)
                            .foregroundStyle(colors.inkSecondary.color)
                        Text(rating.map { TrackWakeView.words[$0 - 1] } ?? String(localized: "Not rated"))
                            .somaFont(type.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text(rating.map { "\($0) of 10, on waking" } ?? String(localized: "Tap to rate how you woke"))
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    Spacer(minLength: metrics.spaceS)
                    SomaMoon(lit: Double(rating ?? 0) / 10)
                        .frame(width: metrics.sleepFeltMoon, height: metrics.sleepFeltMoon)
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(rating == nil ? "Rates how you woke" : "Changes how you rated waking"))
    }
}

/// The debt over fourteen nights as its own tile: the debt now, in a few
/// words, then the debt carried each night with each night's shortfall under
/// it. Tapping it opens the debt in full.
struct SleepDebtTile: View {
    let scores: SomaScores?
    let open: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let debt = ScorePages.debt(scores)
        let series = SleepDebtSeries.make(scores?.detail ?? SomaScores.Detail())

        Button(action: open) {
            SomaCard {
                VStack(alignment: .leading, spacing: metrics.cardPadding) {
                    HStack(alignment: .firstTextBaseline) {
                        SomaCardHeader("Sleep debt", caption: "Last 14 nights")
                        Image(systemName: "chevron.right")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: metrics.spaceXS) {
                        SomaNumber(debt.value, type.metric)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text(debt.headline)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    SomaSleepDebtChart(debt: series.debt, shortfall: series.shortfall,
                                       labels: series.isEmpty ? [] : ["14 nights ago", "Last night"])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityHint(Text("Opens your sleep debt"))
    }
}

/// How long sleep took to come, on the earlier app's fast to late scale.
/// The page shows it only for a night that measured it.
struct SleepFallAsleepCard: View {
    let latency: TimeInterval

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardPadding) {
                SomaCardHeader("Time to fall asleep")
                SomaFallAsleepScale(latency: latency)
            }
        }
    }
}

/// The night's vitals: heart, breathing, HRV, blood oxygen and the room's
/// noise from bed to waking, one at a time.
struct SleepNightVitals: View {
    let night: SleepNightSummary?
    let inputs: ScoreDetailInputs?
    var calendar: Calendar = .current

    var body: some View {
        let vitals = inputs?.lastNightVitals ?? ScoreDetailInputs.NightVitals()
        SomaNightVitals(
            [
                .heart: Self.readings(inputs?.lastNightBeats ?? []),
                .breathing: Self.readings(vitals.breathing),
                .hrv: Self.readings(vitals.hrv),
                .oxygen: Self.readings(vitals.oxygen),
                .noise: Self.readings(vitals.sound),
            ],
            window: night.map { DateInterval(start: $0.bed, end: max($0.bed, $0.wake)) },
            labels: night.map { [ScoreMath.clock($0.bed, calendar: calendar), ScoreMath.clock($0.wake, calendar: calendar)] } ?? [],
            initial: Self.initial
        )
    }

    /// Heart first. In a debug build `-sleep.vital oxygen` (or breathing,
    /// hrv, noise) opens on another, for screenshots.
    static var initial: SomaNightVital {
#if DEBUG
        if let name = UserDefaults.standard.string(forKey: "sleep.vital"),
           let vital = SomaNightVital.allCases.first(where: { "\($0)" == name }) {
            return vital
        }
#endif
        return .heart
    }

    static func readings(_ values: [ScoringTimedValue]) -> [SomaNightReading] {
        values.map { SomaNightReading(start: $0.start, end: $0.end, value: $0.value) }
    }
}

/// Who recorded the night and where it came from, at the foot of the page:
/// the source Apple Health names for most of the night's sleep, and the
/// morning it ended.
struct SleepSourceFooter: View {
    let source: String?
    let night: SleepNightSummary?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(spacing: metrics.spaceXS) {
            if let source {
                HStack(spacing: metrics.spaceXS) {
                    Image(systemName: Self.symbol(source))
                        .accessibilityHidden(true)
                    Text("Recorded by \(source)")
                }
                .somaFont(type.callout)
                .foregroundStyle(colors.inkSecondary.color)
            }
            Text(night.map { "Synced from Apple Health · \($0.wake.formatted(.dateTime.weekday(.wide).month(.wide).day()))" }
                 ?? String(localized: "No night in Apple Health yet"))
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, metrics.spaceS)
        .accessibilityElement(children: .combine)
    }

    /// The device the name points to: a watch, a phone, or a bed for an app
    /// or a mattress sensor.
    static func symbol(_ source: String) -> String {
        let name = source.lowercased()
        if name.contains("watch") { return "applewatch" }
        if name.contains("iphone") { return "iphone" }
        return "bed.double"
    }
}
