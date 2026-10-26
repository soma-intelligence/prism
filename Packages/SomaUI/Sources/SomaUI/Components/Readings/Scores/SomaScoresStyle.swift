//
//  SomaScoresStyle.swift
//  SomaUI
//

import SwiftUI

/// The ways Today's three scores can be drawn under the orb.
///
/// ``rings`` is what ships. The others are radial proposals the owner
/// compares side by side in a Debug build (`-today.scores <name>`): each
/// draws three separate dials in a row, takes the same scores, the same zoom
/// and the same tap, and marks the person's usual its own way.
public enum SomaScoresStyle: String, CaseIterable, Identifiable, Sendable {
    /// Three compact rings, the number in each: ``SomaScoreRings``.
    case rings
    /// A watch bezel of fine ticks lit up to the score, the usual a longer
    /// tick: ``SomaScoreBezel``.
    case bezel
    /// An open arch on a soft gradient, the name in its gap:
    /// ``SomaScoreArch``.
    case arch
    /// A hairline halo with a glowing head and a large light number:
    /// ``SomaScoreHalo``.
    case halo
    /// Today's ring over a thin inner ring drawn to the usual:
    /// ``SomaScoreEcho``.
    case echo
    /// The last seven days as seven petals round the number, today's in
    /// full colour: ``SomaScoreSeven``.
    case seven
    /// A ring in three zones with a bead riding at the score:
    /// ``SomaScoreZones``.
    case zones

    public var id: String { rawValue }

    /// The name the gallery and the comparison board print.
    public var title: LocalizedStringResource {
        switch self {
        case .rings: "Rings"
        case .bezel: "Bezel"
        case .arch: "Arch"
        case .halo: "Halo"
        case .echo: "Echo"
        case .seven: "Seven"
        case .zones: "Zones"
        }
    }
}

/// Today's three scores in the chosen ``SomaScoresStyle``.
///
/// Every style takes the same inputs: the scores, the namespace each score
/// marks itself in as the source of the zoom into its page, the id that
/// zoom goes by, and what a tap does.
public struct SomaTodayScores: View {
    private let style: SomaScoresStyle
    private let scores: [SomaRingScore]
    private let zoom: Namespace.ID?
    private let zoomID: (SomaAspect) -> AnyHashable
    private let onSelect: ((SomaAspect) -> Void)?

    public init(
        _ scores: [SomaRingScore],
        style: SomaScoresStyle,
        zoom: Namespace.ID? = nil,
        zoomID: @escaping (SomaAspect) -> AnyHashable = { AnyHashable($0) },
        onSelect: ((SomaAspect) -> Void)? = nil
    ) {
        self.style = style
        self.scores = scores
        self.zoom = zoom
        self.zoomID = zoomID
        self.onSelect = onSelect
    }

    public var body: some View {
        switch style {
        case .rings: SomaScoreRings(scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect)
        case .bezel: SomaScoreBezel(scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect)
        case .arch: SomaScoreArch(scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect)
        case .halo: SomaScoreHalo(scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect)
        case .echo: SomaScoreEcho(scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect)
        case .seven: SomaScoreSeven(scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect)
        case .zones: SomaScoreZones(scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect)
        }
    }
}

// MARK: - What every style reads off a score

extension SomaRingScore {
    /// The score as a share of 100, nil when it was not measured.
    var fraction: Double? {
        value.map { Self.share($0) }
    }

    /// The usual as a share of 100.
    var usualFraction: Double? {
        usual.map { Self.share($0) }
    }

    /// The number as printed, nil for a dash.
    var figure: String? {
        value.map { "\($0)" }
    }

    /// What VoiceOver reads after the aspect's name.
    var spoken: Text {
        guard let value else { return Text("Not measured") }
        guard let cue else { return Text("\(value)") }
        return Text("\(value), \(Text(cue))")
    }

    /// The last seven days, padded at the front with empty days, today
    /// always last.
    var lastSeven: [Int?] {
        let last = Array(week.suffix(7))
        return Array(repeating: nil, count: 7 - last.count) + last
    }

    static func share(_ value: Int) -> Double {
        min(1, max(0, Double(value) / 100))
    }
}

// MARK: - Three dials in a row

/// Three dials side by side, each a tap target that opens its score's page,
/// with the name under the dial unless the dial carries it itself.
///
/// The row owns the arrival: once a score is there to draw, every dial is
/// told it is shown, with its own small delay so the three fill a beat
/// apart. Under Reduce Motion each dial is shown settled from the start.
struct SomaScoreDialRow<Dial: View>: View {
    let scores: [SomaRingScore]
    let zoom: Namespace.ID?
    let zoomID: (SomaAspect) -> AnyHashable
    let onSelect: ((SomaAspect) -> Void)?
    /// True when the dial draws the aspect's name inside itself.
    var namesInside = false
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
                        if !namesInside {
                            SomaDialName(aspect: score.aspect)
                        }
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
        Text(figure ?? "-")
            .somaFont(font)
            .foregroundStyle(theme.colors.inkPrimary.color)
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

/// The aspect's name, small and quiet, under a dial or inside it.
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

/// The scores every style's preview draws: a good night, a middling mind,
/// a fair day, each with its usual and its week.
enum SomaScoreStylePreview {
    static let scores: [SomaRingScore] = [
        SomaRingScore(aspect: .sleep, value: 87, trend: .up, usual: 78, week: [72, 80, 76, nil, 83, 79, 87]),
        SomaRingScore(aspect: .mind, value: 41, trend: .down, usual: 58, week: [61, 55, 64, 52, 47, 50, 41]),
        SomaRingScore(aspect: .activity, value: 68, trend: .up, usual: 52, week: [52, 38, 61, 44, 30, 47, 68]),
    ]

    static let missing: [SomaRingScore] = [
        SomaRingScore(aspect: .sleep, value: 87, trend: .up, usual: 78, week: [72, 80, 76, nil, 83, 79, 87]),
        SomaRingScore(aspect: .mind, value: nil, usual: 58),
        SomaRingScore(aspect: .activity, value: 4, trend: .down),
    ]
}

#Preview("Every score style") {
    ScrollView {
        VStack(spacing: 40) {
            ForEach(SomaScoresStyle.allCases) { style in
                VStack(alignment: .leading, spacing: 12) {
                    Text(style.title)
                    SomaTodayScores(SomaScoreStylePreview.scores, style: style, onSelect: { _ in })
                    SomaTodayScores(SomaScoreStylePreview.missing, style: style, onSelect: { _ in })
                }
            }
        }
        .padding()
    }
    .background(SomaPreviewBackdrop())
}
