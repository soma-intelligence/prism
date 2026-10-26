//
//  SomaScoreZones.swift
//  SomaUI
//

import SwiftUI

/// Today's three scores as rings in three zones, low, fair and high, with
/// a bead riding at the score. The band fills zone by zone behind the bead;
/// a short ink tick across the band marks the person's usual.
///
/// Each dial is its own tap target and the source of the zoom into its
/// page. Under Reduce Motion the dials are drawn settled.
public struct SomaScoreZones: View {
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
            SomaZonesDial(score: score, shown: shown, delay: delay)
        }
    }
}

/// One zoned ring: the three zones' track, the band filled zone by zone to
/// the score, the usual's tick across it and the bead at the score.
private struct SomaZonesDial: View {
    let score: SomaRingScore
    let shown: Bool
    let delay: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[score.aspect].identity.color
        let filled = shown ? (score.fraction ?? 0) : 0
        let band = StrokeStyle(lineWidth: metrics.scoreZonesStroke, lineCap: .butt)
        let gap = metrics.scoreZonesGapDegrees / 360

        ZStack {
            SomaZoneBand(gap: gap, upTo: 1)
                .stroke(hue.opacity(metrics.scoreTrackOpacity), style: band)
            // Each zone a step deeper than the one before, so a high score
            // reads as the colour gathering, not just the band growing.
            ForEach(0..<3, id: \.self) { zone in
                SomaZoneBand(gap: gap, upTo: filled, only: zone)
                    .stroke(hue.opacity(metrics.scoreZonesDepth[zone]), style: band)
            }
            if let usual = score.usualFraction {
                SomaUsualTick(
                    share: usual,
                    length: metrics.scoreZonesUsualLength,
                    inset: -metrics.scoreZonesUsualLength / 2
                )
                .stroke(
                    theme.colors.inkSecondary.color,
                    style: StrokeStyle(lineWidth: metrics.scoreZonesUsualWidth, lineCap: .round)
                )
                .opacity(shown ? 1 : 0)
            }
            SomaDialBead(share: filled) {
                Circle()
                    .fill(hue)
                    .padding(metrics.scoreZonesBeadRim)
                    .background(Circle().fill(theme.colors.canvas.color))
                    .frame(width: metrics.scoreZonesBead, height: metrics.scoreZonesBead)
            }
            .opacity(score.value == nil ? 0 : 1)
            SomaDialFigure(score: score, font: theme.typography.scoreDialFigure, shown: shown)
        }
        .padding(metrics.scoreZonesBead / 2)
        .somaDialMotion(shown: shown, delay: delay, value: score.value)
    }
}

/// The ring cut into three equal zones with a gap between each, drawn from
/// twelve o'clock up to `upTo`: animated, it fills one zone after the next
/// and steps over the gaps.
struct SomaZoneBand: Shape {
    /// The gap between two zones, a share of the turn.
    let gap: Double
    var upTo: Double
    /// One zone alone, 0 to 2, or nil for all three.
    var only: Int? = nil

    var animatableData: Double {
        get { upTo }
        set { upTo = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for zone in 0..<3 where only == nil || only == zone {
            let start = Double(zone) / 3 + gap / 2
            let end = min(Double(zone + 1) / 3 - gap / 2, upTo)
            guard end > start else { continue }
            path.move(to: SomaDialGeometry.point(start, radius: radius, centre: centre))
            path.addArc(center: centre, radius: radius,
                        startAngle: SomaDialGeometry.angle(start), endAngle: SomaDialGeometry.angle(end), clockwise: false)
        }
        return path
    }
}

#Preview("Score zones") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaScoreZones(SomaScoreStylePreview.scores, onSelect: { _ in })
            SomaScoreZones(SomaScoreStylePreview.missing, onSelect: { _ in })
        }
        .padding()
    }
}
