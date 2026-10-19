//
//  SomaScoreRings.swift
//  SomaUI
//

import SwiftUI

/// One score as a ring: the aspect it belongs to, a 0 to 100 value or nil,
/// which way it moved, and what it means against the person's usual, read
/// aloud rather than printed.
public struct SomaRingScore: Identifiable, Sendable {
    public var id: SomaAspect { aspect }
    public var aspect: SomaAspect
    /// 0 to 100, or nil for a dash and an empty track.
    public var value: Int?
    public var trend: SomaTrend?
    /// "Lowest in 30 days": the accessibility value, never printed.
    public var cue: LocalizedStringResource?

    public init(aspect: SomaAspect, value: Int?, trend: SomaTrend? = nil, cue: LocalizedStringResource? = nil) {
        self.aspect = aspect
        self.value = value
        self.trend = trend
        self.cue = cue
    }
}

/// Three scores as compact rings, as the head of a home page: each
/// drawn to its value in the aspect's colour over a faint track of the same
/// colour, the number in the middle with a small mark when it moved, the
/// name under it.
public struct SomaScoreRings: View {
    private let scores: [SomaRingScore]
    private let onSelect: ((SomaAspect) -> Void)?

    @Environment(\.somaTheme) private var theme

    public init(_ scores: [SomaRingScore], onSelect: ((SomaAspect) -> Void)? = nil) {
        self.scores = scores
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.metrics.cardSpacing) {
            ForEach(scores) { score in
                if let onSelect {
                    Button { onSelect(score.aspect) } label: {
                        SomaScoreRing(score: score).frame(maxWidth: .infinity).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    SomaScoreRing(score: score).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct SomaScoreRing: View {
    let score: SomaRingScore

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False until the ring first appears, so the fill grows from nothing.
    @State private var hasAppeared = false

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[score.aspect].identity.color
        let diameter = metrics.minimumTapTarget * 1.55
        let stroke: CGFloat = 5
        let fraction = score.value.map { min(1, max(0, Double($0) / 100)) } ?? 0
        let shown = (hasAppeared || reduceMotion) ? fraction : 0

        VStack(spacing: metrics.scoreLabelSpacing + 2) {
            ZStack {
                Circle()
                    .stroke(hue.opacity(0.15), lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(hue, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                HStack(alignment: .center, spacing: 2) {
                    Text(score.value.map { "\($0)" } ?? "-")
                        .somaFont(theme.typography.rowValue)
                        .foregroundStyle(colors.inkPrimary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let trend = score.trend, score.value != nil {
                        SomaTrendMark(trend: trend)
                    }
                }
                .padding(.horizontal, stroke * 2)
            }
            .frame(width: diameter, height: diameter)

            Text(score.aspect.title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
        }
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: theme.motion.pressDuration * 6)) { hasAppeared = true }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: theme.motion.pressDuration * 4), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(score.aspect.title))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: Text {
        guard let value = score.value else { return Text("Not measured") }
        guard let cue = score.cue else { return Text("\(value)") }
        return Text("\(value), \(Text(cue))")
    }
}

#Preview("Score rings") {
    ZStack {
        SomaPreviewBackdrop()
        SomaScoreRings([
            SomaRingScore(aspect: .sleep, value: 87, trend: .up),
            SomaRingScore(aspect: .mind, value: 25, trend: .down),
            SomaRingScore(aspect: .activity, value: nil),
        ])
        .padding()
    }
}
