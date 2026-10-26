//
//  SomaScoreDials.swift
//  SomaUI
//

import SwiftUI

/// Three scores as dials in one card: the same readings as
/// ``SomaScoreRings``, set the way the reference design heads its home page and drawn with
/// Flighty's restraint.
///
/// Each dial is a flat track and a fill of one width, in the aspect's colour,
/// with the number large and light in the middle and the name small under it.
/// Where the score has a range, a thin arc just outside the dial spans it, so a
/// value inside it, short of it or past it reads at a glance without a legend.
/// No glow, no gradient, no shadow: the colour and the number carry it.
/// Hairlines split the card into three equal columns.
public struct SomaScoreDials: View {
    /// Where the page a dial opens zooms out of: the namespace of the stack
    /// that pushes it, and the id the destination names for each aspect.
    public struct Zoom {
        let namespace: Namespace.ID
        let id: (SomaAspect) -> AnyHashable

        public init(namespace: Namespace.ID, id: @escaping (SomaAspect) -> AnyHashable) {
            self.namespace = namespace
            self.id = id
        }
    }

    private let scores: [SomaRingScore]
    private let zoom: Zoom?
    private let onSelect: ((SomaAspect) -> Void)?

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    public init(_ scores: [SomaRingScore], zoom: Zoom? = nil, onSelect: ((SomaAspect) -> Void)? = nil) {
        self.scores = scores
        self.zoom = zoom
        self.onSelect = onSelect
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let shape = RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)

        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                if index > 0 {
                    Rectangle()
                        .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(width: 1 / displayScale)
                }
                if let onSelect {
                    Button { onSelect(score.aspect) } label: {
                        SomaTodayDial(score: score).frame(maxWidth: .infinity).contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPress)
                    .modifier(SomaDialZoomSource(zoom: zoom, aspect: score.aspect))
                } else {
                    SomaTodayDial(score: score).frame(maxWidth: .infinity)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, metrics.cardPadding + 4)
        .background(shape.fill(colors.surface.color))
        .overlay(shape.strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
    }
}

/// Marks one dial as where its page zooms out of, on iOS. Elsewhere the push
/// is the ordinary one.
private struct SomaDialZoomSource: ViewModifier {
    let zoom: SomaScoreDials.Zoom?
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    func body(content: Content) -> some View {
#if os(iOS)
        if let zoom {
            content.matchedTransitionSource(id: zoom.id(aspect), in: zoom.namespace) { source in
                source.clipShape(.rect(cornerRadius: theme.metrics.cardCornerRadius, style: .continuous))
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

private struct SomaTodayDial: View {
    let score: SomaRingScore

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False until the dial first appears, so the fill sweeps in from nothing.
    @State private var hasAppeared = false

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let stroke = metrics.scoreDialStroke
        let rangeInset = metrics.scoreDialRangeStroke + metrics.scoreDialRangeGap
        let hue = theme.aspects[score.aspect].identity.color
        let fraction = score.value.map { min(1, max(0, Double($0) / 100)) } ?? 0
        let shown = (hasAppeared || reduceMotion) ? fraction : 0

        VStack(spacing: metrics.cardSpacing) {
            ZStack {
                if let range = score.range {
                    SomaDialRange(range: range, color: colors.inkSecondary.color, width: metrics.scoreDialRangeStroke)
                }

                Group {
                    Circle()
                        .inset(by: stroke / 2)
                        .stroke(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: stroke)
                    Circle()
                        .inset(by: stroke / 2)
                        .trim(from: 0, to: shown)
                        .stroke(hue, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(rangeInset)

                Text(score.value.map { "\($0)" } ?? "-")
                    .somaFont(theme.typography.metric)
                    .foregroundStyle(score.value == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .frame(width: metrics.scoreDialDiameter, height: metrics.scoreDialDiameter)

            Text(score.aspect.title)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
        }
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(theme.motion.reveal) { hasAppeared = true }
            }
        }
        // A spring, not an ease: a score that updates while the arc is still
        // drawing carries on from where it is rather than restarting.
        .animation(reduceMotion ? nil : theme.motion.standard, value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(score.aspect.title))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: Text {
        guard let value = score.value else { return Text("Not measured") }
        var read = Text("\(value)")
        switch score.trend {
        case .up: read = Text("\(read), rising")
        case .down: read = Text("\(read), falling")
        case nil: break
        }
        if let cue = score.cue { read = Text("\(read), \(Text(cue))") }
        if let range = score.range {
            read = Text("\(read), range \(Int(range.lowerBound.rounded())) to \(Int(range.upperBound.rounded()))")
        }
        return read
    }
}

/// The thin arc around a dial that spans its range, on the same clock as the
/// fill: twelve o'clock is zero, all the way round is 100.
private struct SomaDialRange: View {
    let range: ClosedRange<Double>
    let color: Color
    let width: CGFloat

    var body: some View {
        let low = min(1, max(0, range.lowerBound / 100))
        let high = min(1, max(low, range.upperBound / 100))

        Circle()
            .inset(by: width / 2)
            .trim(from: low, to: high)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .accessibilityHidden(true)
    }
}

#Preview("Score dials") {
    ZStack {
        SomaPreviewBackdrop()
        SomaScoreDials([
            SomaRingScore(aspect: .sleep, value: 87, trend: .up, range: 70...85),
            SomaRingScore(aspect: .mind, value: 25, trend: .down, range: 40...65),
            SomaRingScore(aspect: .activity, value: nil, range: 30...45),
        ])
        .padding()
    }
}
