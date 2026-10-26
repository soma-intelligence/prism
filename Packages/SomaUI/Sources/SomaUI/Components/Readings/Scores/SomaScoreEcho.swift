//
//  SomaScoreEcho.swift
//  SomaUI
//

import SwiftUI

/// Today's three scores as a ring and its echo: today's band outside, the
/// person's usual as a thin ring just inside it, so the gap between the two
/// ends says more or less than usual before the number does.
///
/// Each dial is its own tap target and the source of the zoom into its
/// page. Under Reduce Motion the dials are drawn settled.
public struct SomaScoreEcho: View {
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
            SomaEchoDial(score: score, shown: shown, delay: delay)
        }
    }
}

/// One echo: today's band on its track outside, the usual's thin ring on
/// its own track inside, the number in the middle.
private struct SomaEchoDial: View {
    let score: SomaRingScore
    let shown: Bool
    let delay: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[score.aspect].identity.color
        let filled = shown ? (score.fraction ?? 0) : 0
        let usual = shown ? (score.usualFraction ?? 0) : 0
        let outer = metrics.scoreEchoStroke
        let inner = metrics.scoreEchoInnerStroke
        // From the middle of today's band to the middle of the usual's.
        let step = outer / 2 + metrics.scoreEchoGap + inner / 2

        ZStack {
            Circle()
                .stroke(hue.opacity(metrics.scoreTrackOpacity), lineWidth: outer)
            SomaArc(start: 0, length: filled)
                .stroke(hue, style: StrokeStyle(lineWidth: outer, lineCap: .round))

            ZStack {
                Circle()
                    .stroke(hue.opacity(metrics.scoreTrackOpacity), lineWidth: inner)
                SomaArc(start: 0, length: usual)
                    .stroke(hue.opacity(metrics.scoreQuietOpacity), style: StrokeStyle(lineWidth: inner, lineCap: .round))
            }
            .padding(step)

            SomaDialFigure(score: score, font: theme.typography.scoreDialFigure, shown: shown)
        }
        .padding(outer / 2)
        .somaDialMotion(shown: shown, delay: delay, value: score.value)
    }
}

#Preview("Score echo") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaScoreEcho(SomaScoreStylePreview.scores, onSelect: { _ in })
            SomaScoreEcho(SomaScoreStylePreview.missing, onSelect: { _ in })
        }
        .padding()
    }
}
