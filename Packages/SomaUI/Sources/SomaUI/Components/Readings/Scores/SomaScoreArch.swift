//
//  SomaScoreArch.swift
//  SomaUI
//

import SwiftUI

/// Today's three scores as open arches: three quarters of a circle on a
/// soft gradient that deepens into the aspect's colour, the gap at the
/// bottom holding the name. A short ink notch across the band marks the
/// person's usual.
///
/// Each dial is its own tap target and the source of the zoom into its
/// page. Under Reduce Motion the dials are drawn settled.
public struct SomaScoreArch: View {
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
        SomaScoreDialRow(scores: scores, zoom: zoom, zoomID: zoomID, onSelect: onSelect, namesInside: true) { score, shown, delay in
            SomaArchDial(score: score, shown: shown, delay: delay)
        }
    }
}

/// One arch: the track, the gradient band to the score, the usual's notch,
/// the number above the middle and the name in the gap.
private struct SomaArchDial: View {
    let score: SomaRingScore
    let shown: Bool
    let delay: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[score.aspect].identity.color
        let span = metrics.scoreArchSpan
        let filled = shown ? (score.fraction ?? 0) : 0
        // The arch opens at six o'clock: it starts as far left of six as
        // it ends right of it.
        let start = 0.5 + (1 - span) / 2
        let band = StrokeStyle(lineWidth: metrics.scoreArchStroke, lineCap: .round)
        let gradient = AngularGradient(
            colors: [hue.opacity(metrics.scoreArchGradientFloor), hue],
            center: .center,
            // A little wider than the arch, so the round caps at either end
            // take the gradient's own ends and not its wrap.
            startAngle: SomaDialGeometry.angle(start - (1 - span) / 8),
            endAngle: SomaDialGeometry.angle(start + span + (1 - span) / 8)
        )

        ZStack {
            SomaArc(start: start, length: span)
                .stroke(hue.opacity(metrics.scoreTrackOpacity), style: band)
            SomaArc(start: start, length: span * filled)
                .stroke(gradient, style: band)
                .opacity(filled > 0 ? 1 : 0)
            if let usual = score.usualFraction {
                SomaUsualTick(
                    share: start + span * usual,
                    length: metrics.scoreArchNotchLength,
                    inset: -metrics.scoreArchNotchLength / 2
                )
                .stroke(
                    theme.colors.inkSecondary.color,
                    style: StrokeStyle(lineWidth: metrics.scoreArchNotchWidth, lineCap: .round)
                )
                .opacity(shown ? 1 : 0)
            }
            SomaDialFigure(score: score, font: theme.typography.scoreDialFigure, shown: shown)
                .offset(y: -metrics.scoreArchFigureLift)
        }
        .padding(metrics.scoreArchStroke / 2)
        .overlay(alignment: .bottom) {
            SomaDialName(aspect: score.aspect)
                .offset(y: metrics.scoreArchNameDrop)
        }
        .somaDialMotion(shown: shown, delay: delay, value: score.value)
    }
}

/// An arc on the dial's circle from `start`, a share of the turn from
/// twelve o'clock, running clockwise for `length` of the turn.
struct SomaArc: Shape {
    var start: Double
    var length: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, length) }
        set { (start, length) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard length > 0 else { return path }
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: SomaDialGeometry.angle(start),
            endAngle: SomaDialGeometry.angle(start + length),
            clockwise: false
        )
        return path
    }
}

#Preview("Score arch") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaScoreArch(SomaScoreStylePreview.scores, onSelect: { _ in })
            SomaScoreArch(SomaScoreStylePreview.missing, onSelect: { _ in })
        }
        .padding()
    }
}
