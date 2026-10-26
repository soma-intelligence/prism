//
//  SomaScoreBezel.swift
//  SomaUI
//

import SwiftUI

/// Today's three scores as watch bezels: sixty fine ticks round each
/// dial, lit in the aspect's colour up to the score, the rest a faint row.
/// The person's usual is one longer tick in ink, so how today sits against
/// it reads at a glance, lit or not.
///
/// The ticks light one after another as the dial fills.
///
/// Each dial is its own tap target and the source of the zoom into its
/// page. Under Reduce Motion the dials are drawn settled.
public struct SomaScoreBezel: View {
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
            SomaBezelDial(score: score, shown: shown, delay: delay)
        }
    }
}

/// One bezel: the faint row of ticks, the lit ones over it, the usual's
/// tick and the number.
private struct SomaBezelDial: View {
    let score: SomaRingScore
    let shown: Bool
    let delay: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[score.aspect].identity.color
        let lit = shown ? (score.fraction ?? 0) : 0
        let tick = StrokeStyle(lineWidth: metrics.scoreBezelTickWidth, lineCap: .round)

        ZStack {
            SomaTicks(count: metrics.scoreBezelTicks, length: metrics.scoreBezelTickLength, upTo: 1)
                .stroke(hue.opacity(metrics.scoreBezelRestOpacity), style: tick)
            SomaTicks(count: metrics.scoreBezelTicks, length: metrics.scoreBezelTickLength, upTo: lit)
                .stroke(hue, style: tick)
            if let usual = score.usualFraction {
                SomaUsualTick(share: usual, length: metrics.scoreBezelUsualLength, inset: -metrics.scoreBezelUsualReach)
                    .stroke(
                        theme.colors.inkSecondary.color,
                        style: StrokeStyle(lineWidth: metrics.scoreBezelUsualWidth, lineCap: .round)
                    )
                    .opacity(shown ? 1 : 0)
            }
            SomaDialFigure(score: score, font: theme.typography.scoreDialFigure, shown: shown)
        }
        .padding(metrics.scoreBezelUsualReach + metrics.scoreBezelUsualWidth / 2)
        .somaDialMotion(shown: shown, delay: delay, value: score.value)
    }
}

/// A ring of radial ticks from twelve o'clock, clockwise, drawing only the
/// ones whose middle falls inside `upTo`: animated, the ticks light one by
/// one rather than sliding.
struct SomaTicks: Shape {
    let count: Int
    let length: CGFloat
    var upTo: Double

    var animatableData: Double {
        get { upTo }
        set { upTo = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<count {
            let share = Double(index) / Double(count)
            guard (Double(index) + 0.5) / Double(count) <= upTo else { break }
            path.move(to: SomaDialGeometry.point(share, radius: outer, centre: centre))
            path.addLine(to: SomaDialGeometry.point(share, radius: outer - length, centre: centre))
        }
        return path
    }
}

/// One radial tick at `share` of the turn, `inset` in from the rim.
struct SomaUsualTick: Shape {
    var share: Double
    let length: CGFloat
    let inset: CGFloat

    var animatableData: Double {
        get { share }
        set { share = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - inset
        var path = Path()
        path.move(to: SomaDialGeometry.point(share, radius: outer, centre: centre))
        path.addLine(to: SomaDialGeometry.point(share, radius: outer - length, centre: centre))
        return path
    }
}

#Preview("Score bezel") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaScoreBezel(SomaScoreStylePreview.scores, onSelect: { _ in })
            SomaScoreBezel(SomaScoreStylePreview.missing, onSelect: { _ in })
        }
        .padding()
    }
}
