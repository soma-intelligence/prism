//
//  TrackWakeView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Rating dial, sleep feeling: how the night felt on waking, as a moon that
/// fills from drained to fully rested. Set beside the night Soma measured,
/// when there is one. Kept in ``TrackLogStore`` against the morning's day:
/// Apple Health has no type for it.
struct TrackWakeView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int?

    private let log = TrackLogStore.shared

    static let words = [
        "Drained", "Very tired", "Tired", "Groggy", "So-so",
        "Fair", "Mostly rested", "Rested", "Well rested", "Fully rested",
    ]

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        TrackEntryPage(title: "Last night", scrolls: false) {
            Text("How did you wake?")
                .somaFont(type.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)

            SomaMoon(lit: Double(rating ?? 0) / 10, glows: rating != nil)
                .frame(width: metrics.moonDiameter, height: metrics.moonDiameter)
                .animation(theme.motion.selection, value: rating)

            VStack(spacing: metrics.spaceXS) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.readoutUnitGap) {
                    SomaReadout(rating.map { "\($0)" }, unit: "of 10")
                }
                Text(rating.map { Self.words[$0 - 1] } ?? "Tap a moon")
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkSecondary.color)
            }

            SomaMoonScale(value: $rating, low: Self.words[0], high: Self.words[9])

            TrackNote(lead: scoreLine)
        } footer: {
            SomaActionButton("Save") {
                log.setWakeRating(rating, on: .now)
                dismiss()
            }
            .disabled(rating == nil)
        }
        .onAppear { rating = log.wakeRating(on: .now) }
        .task { await health.loadScores() }
    }

    private var scoreLine: String {
        guard let score = health.scores?.sleep else {
            return "Soma scores the night after seven nights of sleep in Apple Health."
        }
        return "Soma scored the night \(score)."
    }
}

#if DEBUG
#Preview("Wake") {
    NavigationStack { TrackWakeView() }
        .environment(HealthDashboard())
}
#endif
