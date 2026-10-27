//
//  SomaScoreZones.swift
//  SomaUI
//

import SwiftUI

/// Today's three scores as rings in three zones, low, fair and high, with
/// a bead riding at the score. The band fills zone by zone behind the bead,
/// each zone a step deeper in the aspect's colour.
///
/// Where a score has a range, a thin arc in the secondary ink just outside
/// the band spans it, so a value inside it, short of it or past it reads at
/// a glance without a legend. Without a range, a short ink tick across the
/// band marks the person's usual, if there is one. A missing score is a
/// dash over an empty track, with no bead.
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

/// One zoned ring: the range arc outside it, the three zones' track, the
/// band filled zone by zone to the score, the usual's tick across it when
/// there is no range, and the bead at the score.
private struct SomaZonesDial: View {
    let score: SomaRingScore
    let shown: Bool
    let delay: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let ink = theme.colors.inkSecondary.color
        let hue = theme.aspects[score.aspect].identity.color
        let filled = shown ? (score.fraction ?? 0) : 0
        let band = StrokeStyle(lineWidth: metrics.scoreZonesStroke, lineCap: .butt)
        let gap = metrics.scoreZonesGapDegrees / 360
        // The range arc keeps the outer rim whether a score has a range or
        // not, so the three rings in a row are always one size.
        let rangeWidth = metrics.scoreDialRangeStroke
        let ringInset = rangeWidth + metrics.scoreZonesRangeClearance + metrics.scoreZonesBead / 2

        ZStack {
            if let range = score.rangeShares {
                SomaRangeArc(from: range.lowerBound, to: range.upperBound)
                    .stroke(ink, style: StrokeStyle(lineWidth: rangeWidth, lineCap: .round))
                    .padding(rangeWidth / 2)
                    .opacity(shown ? 1 : 0)
            }
            ZStack {
                SomaZoneBand(gap: gap, upTo: 1)
                    .stroke(hue.opacity(metrics.scoreTrackOpacity), style: band)
                // Each zone a step deeper than the one before, so a high score
                // reads as the colour gathering, not just the band growing.
                ForEach(0..<3, id: \.self) { zone in
                    SomaZoneBand(gap: gap, upTo: filled, only: zone)
                        .stroke(hue.opacity(metrics.scoreZonesDepth[zone]), style: band)
                }
                if score.range == nil, let usual = score.usualFraction {
                    SomaUsualTick(
                        share: usual,
                        length: metrics.scoreZonesUsualLength,
                        inset: -metrics.scoreZonesUsualLength / 2
                    )
                    .stroke(ink, style: StrokeStyle(lineWidth: metrics.scoreZonesUsualWidth, lineCap: .round))
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
            }
            .padding(ringInset)
            SomaDialFigure(score: score, font: theme.typography.scoreDialFigure, shown: shown)
        }
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

/// The thin arc that spans a score's range, on the dial's clock: twelve
/// o'clock is zero, all the way round is 100. Empty for a range with no
/// width, so a degenerate range never draws a stray dot.
struct SomaRangeArc: Shape {
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard to > from else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: SomaDialGeometry.point(from, radius: radius, centre: centre))
        path.addArc(center: centre, radius: radius,
                    startAngle: SomaDialGeometry.angle(from), endAngle: SomaDialGeometry.angle(to), clockwise: false)
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

#Preview("Score zones") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaScoreZones(SomaScoreZonesPreview.ranged, onSelect: { _ in })
            SomaScoreZones(SomaScoreZonesPreview.usual, onSelect: { _ in })
            SomaScoreZones(SomaScoreZonesPreview.missing, onSelect: { _ in })
        }
        .padding()
    }
}
