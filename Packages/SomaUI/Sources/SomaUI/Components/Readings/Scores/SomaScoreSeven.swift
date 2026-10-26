//
//  SomaScoreSeven.swift
//  SomaUI
//

import SwiftUI

/// Today's three scores as their last seven days: seven petals round the
/// number, each as long as that day's score, oldest just right of twelve
/// and today at the top in full colour. A fine dashed circle marks the
/// person's usual across all seven.
///
/// The petals grow out from the middle in the order of the days.
///
/// Each dial is its own tap target and the source of the zoom into its
/// page. Under Reduce Motion the dials are drawn settled.
public struct SomaScoreSeven: View {
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
            SomaSevenDial(score: score, shown: shown, delay: delay)
        }
    }
}

/// One seven day dial: a petal per day on its faint full length track, the
/// usual's dashed circle across them, the number in the middle.
private struct SomaSevenDial: View {
    let score: SomaRingScore
    let shown: Bool
    let delay: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[score.aspect].identity.color
        let days = score.lastSeven
        let slot = 1 / Double(days.count)

        ZStack {
            ForEach(days.indices, id: \.self) { index in
                // Oldest just right of twelve, today centred on it.
                let centre = Double(index + 1) * slot
                let isToday = index == days.count - 1
                let day = days[index].map { SomaRingScore.share($0) }
                let reach = day.map { max(metrics.scoreSevenFloor, $0) } ?? 0

                // A day with no score keeps a stub in the track's tint, so
                // the gap reads as a missing day rather than a broken dial.
                SomaPetal(centre: centre, width: slot, reach: shown ? (day == nil ? metrics.scoreSevenFloor : reach) : 0, metrics: metrics)
                    .fill(day == nil ? hue.opacity(metrics.scoreTrackOpacity) : (isToday ? hue : hue.opacity(metrics.scoreSevenPastOpacity)))
                    .somaDialMotion(
                        shown: shown,
                        delay: delay + Double(index) * theme.motion.scoreDayStep,
                        value: days[index]
                    )
            }
            if let usual = score.usualFraction {
                Circle()
                    .stroke(
                        theme.colors.inkSecondary.color.opacity(metrics.scoreSevenUsualOpacity),
                        style: StrokeStyle(
                            lineWidth: metrics.scoreSevenUsualWidth,
                            dash: [metrics.scoreSevenUsualDash, metrics.scoreSevenUsualDash]
                        )
                    )
                    .padding(SomaPetal.inset(reach: max(metrics.scoreSevenFloor, usual), in: metrics.scoreDialDiameter / 2, metrics: metrics))
                    .opacity(shown ? 1 : 0)
                    .somaDialMotion(shown: shown, delay: delay, value: score.usual)
            }
            SomaDialFigure(score: score, font: theme.typography.scoreDialFigureCompact, shown: shown)
        }
    }
}

/// One day's petal: an annular wedge from the dial's empty middle outwards,
/// `reach` of the way to the rim, softly rounded at its four corners.
struct SomaPetal: Shape {
    /// The middle of the petal, a share of the turn from twelve o'clock.
    let centre: Double
    /// The slot the petal sits in, a share of the turn; the petal leaves
    /// the theme's gap free inside it.
    let width: Double
    /// How far out it reaches, 0 at the middle to 1 at the rim.
    var reach: Double
    let metrics: SomaMetrics

    var animatableData: Double {
        get { reach }
        set { reach = newValue }
    }

    /// How far in from the rim a petal reaching `reach` ends, for a circle
    /// drawn at the same distance.
    static func inset(reach: Double, in radius: CGFloat, metrics: SomaMetrics) -> CGFloat {
        (radius - metrics.scoreSevenCore) * (1 - reach)
    }

    func path(in rect: CGRect) -> Path {
        let centrePoint = CGPoint(x: rect.midX, y: rect.midY)
        let rim = min(rect.width, rect.height) / 2
        let core = metrics.scoreSevenCore
        let corner = metrics.scoreSevenCorner
        let outer = core + (rim - core) * reach
        guard outer - core > corner * 2 else {
            // Too short to round: a sliver that grows into the petal.
            return outer > core ? sliver(centrePoint, core, outer) : Path()
        }
        // The petal drawn smaller by the corner, then stroked round by it,
        // gives the same outline with rounded corners.
        let inner = core + corner
        let reachOut = outer - corner
        let half = width / 2 - metrics.scoreSevenGapDegrees / 720
        let body = wedge(centrePoint, inner: inner, outer: reachOut, half: half, cornerAt: corner)
        return body.union(body.strokedPath(StrokeStyle(lineWidth: corner * 2, lineJoin: .round)))
    }

    private func wedge(_ centrePoint: CGPoint, inner: CGFloat, outer: CGFloat, half: Double, cornerAt corner: CGFloat) -> Path {
        // The sides pulled in by the corner's width at each radius, so the
        // gap between petals stays even from the middle to the rim.
        let innerHalf = half - Double(corner / inner) / (2 * .pi)
        let outerHalf = half - Double(corner / outer) / (2 * .pi)
        var path = Path()
        path.addArc(center: centrePoint, radius: outer,
                    startAngle: SomaDialGeometry.angle(centre - outerHalf),
                    endAngle: SomaDialGeometry.angle(centre + outerHalf), clockwise: false)
        path.addArc(center: centrePoint, radius: inner,
                    startAngle: SomaDialGeometry.angle(centre + innerHalf),
                    endAngle: SomaDialGeometry.angle(centre - innerHalf), clockwise: true)
        path.closeSubpath()
        return path
    }

    private func sliver(_ centrePoint: CGPoint, _ inner: CGFloat, _ outer: CGFloat) -> Path {
        let half = width / 2 - metrics.scoreSevenGapDegrees / 720
        let middle = (inner + outer) / 2
        var path = Path()
        path.addArc(center: centrePoint, radius: middle,
                    startAngle: SomaDialGeometry.angle(centre - half + Double(metrics.scoreSevenCorner / middle) / (2 * .pi)),
                    endAngle: SomaDialGeometry.angle(centre + half - Double(metrics.scoreSevenCorner / middle) / (2 * .pi)),
                    clockwise: false)
        return path.strokedPath(StrokeStyle(lineWidth: outer - inner, lineCap: .butt))
    }
}

#Preview("Score seven") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 32) {
            SomaScoreSeven(SomaScoreStylePreview.scores, onSelect: { _ in })
            SomaScoreSeven(SomaScoreStylePreview.missing, onSelect: { _ in })
        }
        .padding()
    }
}
