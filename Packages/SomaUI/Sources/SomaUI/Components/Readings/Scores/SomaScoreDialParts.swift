//
//  SomaScoreDialParts.swift
//  SomaUI
//

import SwiftUI

// MARK: - What a dial reads off a score

extension SomaRingScore {
    /// The score as a share of 100, nil when it was not measured.
    var fraction: Double? {
        value.map { Self.share($0) }
    }

    /// The usual as a share of 100, nil when there is none.
    var usualFraction: Double? {
        usual.map { Self.share($0) }
    }

    /// The number as printed, nil for a dash.
    var figure: String? {
        value.map { "\($0)" }
    }

    /// The range as shares of 100, low end first, nil when there is none.
    var rangeShares: ClosedRange<Double>? {
        range.map { range in
            let low = min(1, max(0, range.lowerBound / 100))
            return low...min(1, max(low, range.upperBound / 100))
        }
    }

    /// What VoiceOver reads after the aspect's name: the number, which way
    /// it moved, what it means against the usual, and the range.
    var spoken: Text {
        guard let value else { return Text("Not measured") }
        var read = Text("\(value)")
        switch trend {
        case .up: read = Text("\(read), rising")
        case .down: read = Text("\(read), falling")
        case nil: break
        }
        if let cue { read = Text("\(read), \(Text(cue))") }
        if let range {
            read = Text("\(read), range \(Int(range.lowerBound.rounded())) to \(Int(range.upperBound.rounded()))")
        }
        return read
    }

    static func share(_ value: Int) -> Double {
        min(1, max(0, Double(value) / 100))
    }
}

// MARK: - Three dials in a row

/// Three dials side by side, each a tap target that opens its score's page,
/// with the name under the dial.
///
/// The row owns the arrival: once a score is there to draw, every dial is
/// told it is shown, with its own small delay so the three fill a beat
/// apart. Under Reduce Motion each dial is shown settled from the start.
struct SomaScoreDialRow<Dial: View>: View {
    let scores: [SomaRingScore]
    let zoom: Namespace.ID?
    let zoomID: (SomaAspect) -> AnyHashable
    let onSelect: ((SomaAspect) -> Void)?
    @ViewBuilder let dial: (_ score: SomaRingScore, _ shown: Bool, _ delay: Double) -> Dial

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        let metrics = theme.metrics
        let shown = arrived || reduceMotion

        HStack(alignment: .top, spacing: metrics.cardSpacing) {
            ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                SomaScoreSlot(score: score, zoom: zoom, zoomID: zoomID, onSelect: onSelect) {
                    VStack(spacing: metrics.scoreDialLabelSpacing) {
                        dial(score, shown, reduceMotion ? 0 : Double(index) * theme.motion.scoreArrivalStep)
                            .frame(width: metrics.scoreDialDiameter, height: metrics.scoreDialDiameter)
                        SomaDialName(aspect: score.aspect)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .somaScoreArrival($arrived, for: scores)
    }
}

/// One score as a tap target: a button that opens its page, marked as the
/// source of the zoom into it, read as one element. Without `onSelect` the
/// score is shown alone, not as a disabled button that would dim it.
struct SomaScoreSlot<Content: View>: View {
    let score: SomaRingScore
    let zoom: Namespace.ID?
    let zoomID: (SomaAspect) -> AnyHashable
    let onSelect: ((SomaAspect) -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        if let onSelect {
            Button { onSelect(score.aspect) } label: {
                content
                    .contentShape(.rect)
                    .zoomSource(zoomID(score.aspect), in: zoom)
            }
            .buttonStyle(.somaGlassPress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(score.aspect.title))
            .accessibilityValue(score.spoken)
            .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(score.aspect.title))
                .accessibilityValue(score.spoken)
        }
    }
}

/// The number in the middle of a dial, centred on its own, with the trend
/// mark hung off its trailing edge so the mark never pushes the number off
/// the dial's axis. It rolls in from a dash as the dial fills, and to each
/// new value after that.
struct SomaDialFigure: View {
    let score: SomaRingScore
    let font: SomaFontSpec
    /// False until the dial starts to fill.
    let shown: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let figure = shown ? score.figure : nil
        let colors = theme.colors
        Text(figure ?? "-")
            .somaFont(font)
            // A score that was not measured is a quiet dash, not a number.
            .foregroundStyle(score.value == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
            .somaRollingNumber(figure)
            .lineLimit(1)
            .overlay(alignment: .trailing) {
                if let trend = score.trend, figure != nil {
                    SomaTrendMark(trend: trend)
                        .offset(x: theme.metrics.trendMarkWidth + theme.metrics.scoreDialMarkSpacing)
                }
            }
    }
}

/// The aspect's name, small and quiet, under a dial.
struct SomaDialName: View {
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Text(aspect.title)
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .lineLimit(1)
    }
}

extension View {
    /// Starts a row's arrival once it shows with at least one score to
    /// draw, so the dials fill with their values rather than as empty
    /// tracks that a late read then fills.
    func somaScoreArrival(_ arrived: Binding<Bool>, for scores: [SomaRingScore]) -> some View {
        let ready = scores.contains { $0.value != nil }
        return task(id: ready) {
            guard ready, !arrived.wrappedValue else { return }
            arrived.wrappedValue = true
        }
    }

    /// How a dial moves: filling on the arrival spring after its delay, and
    /// easing to a new value in place. Still under Reduce Motion.
    func somaDialMotion(shown: Bool, delay: Double, value: Int?) -> some View {
        modifier(SomaDialMotion(shown: shown, delay: delay, value: value))
    }
}

private struct SomaDialMotion: ViewModifier {
    let shown: Bool
    let delay: Double
    let value: Int?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : theme.motion.scoreArrival.delay(delay), value: shown)
            .animation(reduceMotion ? nil : theme.motion.scoreChange, value: value)
    }
}

// MARK: - Geometry

/// Angles round a dial, measured the way a clock reads: a share of the turn
/// from twelve o'clock, clockwise.
enum SomaDialGeometry {
    /// The point at `share` of the turn on a circle of `radius` round
    /// `centre`.
    static func point(_ share: Double, radius: CGFloat, centre: CGPoint) -> CGPoint {
        let angle = (share * 360 - 90) * .pi / 180
        return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
    }

    /// The same share as an angle for SwiftUI's arcs, which start at three
    /// o'clock.
    static func angle(_ share: Double) -> Angle {
        .degrees(share * 360 - 90)
    }
}

/// The scores the dials' previews draw: a good night, a middling mind, a
/// fair day, the way Today hands them over (with a range), the way a caller
/// with only the usual does, and with a score missing.
enum SomaScoreZonesPreview {
    static let ranged: [SomaRingScore] = [
        SomaRingScore(aspect: .sleep, value: 87, trend: .up, range: 70...85),
        SomaRingScore(aspect: .mind, value: 41, trend: .down, range: 48...68),
        SomaRingScore(aspect: .activity, value: 68, trend: .up, range: 55...75),
    ]

    static let usual: [SomaRingScore] = [
        SomaRingScore(aspect: .sleep, value: 87, trend: .up, usual: 78),
        SomaRingScore(aspect: .mind, value: 41, trend: .down, usual: 58),
        SomaRingScore(aspect: .activity, value: 68, trend: .up, usual: 52),
    ]

    static let missing: [SomaRingScore] = [
        SomaRingScore(aspect: .sleep, value: 87, trend: .up, range: 70...85),
        SomaRingScore(aspect: .mind, value: nil, range: 48...68),
        SomaRingScore(aspect: .activity, value: 4, trend: .down),
    ]
}
