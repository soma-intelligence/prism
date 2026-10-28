//
//  SomaScoreRow.swift
//  SomaUI
//

import SwiftUI

/// Which way a value moved against the one it is compared with.
public enum SomaTrend: Sendable, Equatable, Codable {
    case up
    case down
}

/// One value in a row of scores: a small label over a large light
/// number, with a mark when it rose or fell.
public struct SomaScore: Identifiable, Sendable {
    public var id: SomaAspect { aspect }
    /// The aspect the value belongs to. Tapping the value sends the orb there.
    public var aspect: SomaAspect
    /// The number as it should read, or nil for a dash: not measured is not
    /// zero.
    public var value: String?
    /// What the number counts, set small beside it. Nil when the number
    /// explains itself.
    public var unit: LocalizedStringResource?
    /// Nil when it held steady, or when there is nothing to compare it with.
    public var trend: SomaTrend?
    /// A few words on what the value means against the person's usual
    /// ("8% under usual"), set under it. Never a sentence.
    public var cue: LocalizedStringResource?
    /// Colours the cue: good news, something to watch, or neither.
    public var cueTone: SomaCueTone

    public init(
        aspect: SomaAspect,
        value: String?,
        unit: LocalizedStringResource? = nil,
        trend: SomaTrend? = nil,
        cue: LocalizedStringResource? = nil,
        cueTone: SomaCueTone = .neutral
    ) {
        self.aspect = aspect
        self.value = value
        self.unit = unit
        self.trend = trend
        self.cue = cue
        self.cueTone = cueTone
    }
}

/// Three values under a hairline, each taking an equal share of the width.
///
/// A value that rose or fell carries a small mark in the secondary ink: a
/// direction, never an alert. The number itself stays in the primary ink, so
/// the mark is the only thing that moves.
public struct SomaScoreRow: View {
    private let scores: [SomaScore]
    private let onSelect: ((SomaAspect) -> Void)?

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    public init(_ scores: [SomaScore], onSelect: ((SomaAspect) -> Void)? = nil) {
        self.scores = scores
        self.onSelect = onSelect
    }

    public var body: some View {
        let metrics = theme.metrics

        VStack(spacing: metrics.heroSpacing) {
            Rectangle()
                .fill(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                .frame(height: 1 / displayScale)

            HStack(alignment: .top, spacing: 0) {
                ForEach(scores) { score in
                    if let onSelect {
                        Button {
                            onSelect(score.aspect)
                        } label: {
                            SomaScoreView(score: score)
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Not a disabled button: that would dim the numbers
                        // as if they were unavailable.
                        SomaScoreView(score: score)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private struct SomaScoreView: View {
    let score: SomaScore

    @Environment(\.somaTheme) private var theme

    var body: some View {
        // The aspect's glyph in its category ink says what the number is
        // before the label is read, the way Health leads a reading with its
        // category. The label stays, so the glyph is hidden from VoiceOver.
        VStack(spacing: theme.metrics.cardHeaderSpacing * 2) {
            SomaGlyph(aspect: score.aspect, size: .inline, tinted: true)
                .accessibilityHidden(true)
            SomaStatView(
                label: score.aspect.title, value: score.value, unit: score.unit, trend: score.trend,
                cue: score.cue, cueTone: score.cueTone
            )
        }
    }
}

/// The small triangle beside a value that rose or fell.
///
/// A direction, not an alert: the mark is in the secondary ink unless the
/// caller says which side is the better one, and then it takes the status
/// tone of that side (green on the better side, amber on the other). It is
/// never red: red is kept for real alerts.
public struct SomaTrendMark: View {
    private let trend: SomaTrend
    private let better: SomaBetterSide

    @Environment(\.somaTheme) private var theme

    /// - Parameter better: which way is good news for this reading; neither
    ///   by default, which keeps the mark neutral.
    public init(trend: SomaTrend, better: SomaBetterSide = .neither) {
        self.trend = trend
        self.better = better
    }

    public var body: some View {
        SomaTriangle(pointsUp: trend == .up)
            .fill(better.tone(trend == .up ? .above : .below).color(theme.colors))
            .frame(width: theme.metrics.trendMarkWidth, height: theme.metrics.trendMarkHeight)
            .accessibilityHidden(true)
    }
}

struct SomaTriangle: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Score row") {
    ZStack {
        SomaPreviewBackdrop()
        SomaScoreRow([
            SomaScore(aspect: .sleep, value: "7:12", trend: .up, cue: "Highest in 30 days", cueTone: .good),
            SomaScore(aspect: .mind, value: "38", unit: "ms", trend: .down, cue: "12% under usual", cueTone: .watch),
            SomaScore(aspect: .activity, value: nil),
        ])
        .padding()
    }
}
