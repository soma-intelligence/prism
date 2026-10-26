//
//  SomaScoreHalo.swift
//  SomaUI
//

import SwiftUI

/// Today's three scores as thin luminous halos: a hairline round a large
/// light number, glowing softly along its length and brightest at its head.
/// A small hollow dot on the track marks the person's usual.
///
/// Each dial is its own tap target and the source of the zoom into its
/// page. Under Reduce Motion the dials are drawn settled.
public struct SomaScoreHalo: View {
    private let scores: [SomaRingScore]
    private let zoom: Namespace.ID?
    private let zoomID: (SomaAspect) -> AnyHashable
    private let onSelect: ((SomaAspect) -> Void)?

    public init(
        _ scores: [SomaRingScore],
        zoom: Namespace.ID? = nil,
        zoomID: @escaping (SomaAspect) -> AnyHashable = { AnyHashable($0) },
        onSelect: ((SomaAspect) -> Void)? = nil
    ) {
        self.scores = scores
        self.zoom = zoom
        self.zoomID = zoomID
        self.onSelect = onSelect
    }

    public var body: some View {
        SomaScoreDialRow(scores: scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect) { score, shown, delay in
            SomaHaloDial(score: score, shown: shown, delay: delay)
        }
    }
}

/// One halo: the faint track, the glow under the line, the hairline, the
/// bright head and the usual's dot.
private struct SomaHaloDial: View {
    let score: SomaRingScore
    let shown: Bool
    let delay: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[score.aspect].identity.color
        let filled = shown ? (score.fraction ?? 0) : 0
        let line = StrokeStyle(lineWidth: metrics.scoreHaloStroke, lineCap: .round)

        ZStack {
            Circle()
                .stroke(hue.opacity(metrics.scoreTrackOpacity), lineWidth: metrics.scoreHaloStroke)
            // The glow: the same arc, wider and blurred, under the line.
            SomaArc(start: 0, length: filled)
                .stroke(hue, style: StrokeStyle(lineWidth: metrics.scoreHaloStroke * 2, lineCap: .round))
                .blur(radius: metrics.scoreHaloGlowBlur)
                .opacity(metrics.scoreHaloGlowOpacity)
            SomaArc(start: 0, length: filled)
                .stroke(hue, style: line)
            if let usual = score.usualFraction {
                SomaDialBead(share: usual) {
                    Circle()
                        .fill(theme.colors.canvas.color)
                        .overlay(Circle().strokeBorder(hue.opacity(metrics.scoreHaloGlowOpacity), lineWidth: 1))
                        .frame(width: metrics.scoreHaloUsualDot, height: metrics.scoreHaloUsualDot)
                }
                .opacity(shown ? 1 : 0)
            }
            // The head rides the same turn as the line, so it leads it.
            SomaDialBead(share: filled) {
                Circle()
                    .fill(hue)
                    .brightness(metrics.scoreHaloHeadLift)
                    .frame(width: metrics.scoreHaloHead, height: metrics.scoreHaloHead)
                    .shadow(color: hue, radius: metrics.scoreHaloHeadGlow)
            }
            .opacity(filled > 0 ? 1 : 0)
            SomaDialFigure(score: score, font: theme.typography.scoreDialFigureLarge, shown: shown)
        }
        .padding(metrics.scoreHaloHead / 2)
        .somaDialMotion(shown: shown, delay: delay, value: score.value)
    }
}

/// A mark carried round the dial's circle to `share` of the turn by a
/// rotation, so it moves in step with an arc drawn to the same share.
struct SomaDialBead<Mark: View>: View {
    let share: Double
    @ViewBuilder let mark: Mark

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            mark
                .offset(y: -radius)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .rotationEffect(.degrees(share * 360))
        }
    }
}

#Preview("Score halo") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaScoreHalo(SomaScoreStylePreview.scores, onSelect: { _ in })
            SomaScoreHalo(SomaScoreStylePreview.missing, onSelect: { _ in })
        }
        .padding()
    }
}
