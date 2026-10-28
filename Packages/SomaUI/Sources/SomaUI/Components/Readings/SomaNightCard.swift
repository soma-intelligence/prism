//
//  SomaNightCard.swift
//  SomaUI
//

import SwiftUI

/// Last night as a card: the sleep glyph and its name, the time asleep, one
/// short line, then the night itself as the hero, stage by stage from bed to
/// wake, with the four stages named under it in their colours.
///
/// No score: the score belongs to the page the card opens. A night with no
/// stages keeps the card's shape and says what it is waiting for.
///
/// The night draws itself in from bed to wake the first time the card
/// appears; under Reduce Motion it is simply there.
public struct SomaNightCard: View {
    private let runs: [SomaStageRun]
    private let asleep: TimeInterval?
    private let bed: String?
    private let wake: String?
    private let line: String?
    private let empty: LocalizedStringResource

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    /// - Parameters:
    ///   - runs: the night's stages, in any order.
    ///   - asleep: seconds asleep, awake left out. Nil reads as a dash.
    ///   - bed: the clock at bed, under a moon at the night's start.
    ///   - wake: the clock at waking, under a sun at its end.
    ///   - line: one short line on what the night was like.
    ///   - empty: what the card says when the night has no stages.
    public init(
        runs: [SomaStageRun],
        asleep: TimeInterval?,
        bed: String?,
        wake: String?,
        line: String?,
        empty: LocalizedStringResource
    ) {
        self.runs = runs
        self.asleep = asleep
        self.bed = bed
        self.wake = wake
        self.line = line
        self.empty = empty
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                    HStack(spacing: metrics.identityDotSpacing) {
                        SomaAspectGlyph(.sleep, style: .caption)
                        Text("Last night")
                            .somaFont(type.eyebrow)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: metrics.identityDotSpacing) {
                        SomaNumber(asleep.map(SomaSleepClock.short), type.metricCompact)
                            .foregroundStyle(colors.inkPrimary.color)
                        if asleep != nil {
                            Text("asleep")
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                    }
                    if let line {
                        Text(verbatim: line)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)

                if runs.isEmpty {
                    Text(empty)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(maxWidth: .infinity, minHeight: metrics.hypnogramTallLaneHeight * 2)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.hypnogramBlockRadius * 2, style: .continuous)
                                .fill(colors.surfaceRecessed.color)
                        )
                } else {
                    SomaHypnogram(runs: runs, bed: bed, wake: wake, laneHeight: metrics.hypnogramLaneHeight)
                        .mask(alignment: .leading) {
                            Rectangle().scaleEffect(x: isDrawn || reduceMotion ? 1 : 0, anchor: .leading)
                        }
                    legend
                }
            }
        }
        .onAppear {
            guard !isDrawn else { return }
            if reduceMotion {
                isDrawn = true
            } else {
                withAnimation(.easeOut(duration: theme.motion.breathDuration / 4)) { isDrawn = true }
            }
        }
    }

    /// The four stages, each a dot in its colour and its name.
    private var legend: some View {
        let metrics = theme.metrics
        return HStack(spacing: metrics.cardSpacing) {
            ForEach(SomaSleepStage.allCases, id: \.self) { stage in
                HStack(spacing: metrics.identityDotSpacing) {
                    Circle()
                        .fill(stage.color(theme))
                        .frame(width: metrics.identityDotDiameter, height: metrics.identityDotDiameter)
                    Text(stage.title)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Night card") {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let stages: [SomaSleepStage] = [.awake, .core, .deep, .core, .rem, .core, .deep, .core, .awake, .rem, .core, .rem, .awake]
    let runs = stages.enumerated().map { index, stage in
        SomaStageRun(stage: stage, start: start + Double(index) * 2_100, end: start + Double(index + 1) * 2_100)
    }
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 16) {
            SomaNightCard(runs: runs, asleep: 6.6 * 3_600, bed: "23:34", wake: "06:39",
                          line: "Deep sleep came first, and it held.", empty: "Stages draw here.")
            SomaNightCard(runs: [], asleep: nil, bed: nil, wake: nil, line: nil,
                          empty: "Stages draw here from a night your watch records.")
        }
        .padding()
    }
}
