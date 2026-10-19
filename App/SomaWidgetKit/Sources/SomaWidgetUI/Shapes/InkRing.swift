import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// A thin ring: a track in faint ink all the way round, and the value in full
/// ink from twelve o'clock. A nil fraction draws the track alone, never an
/// empty value that could read as zero.
///
/// Fills the largest square its frame holds. Only the value stroke is
/// accentable, so a tinted home screen tints the reading and not the track.
public struct InkRing: View {
    private let fraction: Double?
    private let lineWidth: CGFloat
    private let dimmed: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    public init(fraction: Double?, lineWidth: CGFloat) {
        self.init(fraction: fraction, lineWidth: lineWidth, dimmed: false)
    }

    /// `dimmed` draws the value in the secondary ink, for a stale snapshot.
    init(fraction: Double?, lineWidth: CGFloat, dimmed: Bool) {
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.lineWidth = lineWidth
        self.dimmed = dimmed
    }

    public var body: some View {
        let ink = WidgetInk(theme: theme, mode: mode)
        ZStack {
            RingArc(fraction: 1)
                .stroke(ink.track, style: StrokeStyle(lineWidth: lineWidth))
            if let fraction, fraction > 0 {
                RingArc(fraction: fraction)
                    .stroke(dimmed ? ink.secondary : ink.primary,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .widgetAccentable()
            }
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// An arc from twelve o'clock clockwise, `fraction` of the way round, on the
/// largest circle the rect holds.
struct RingArc: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        if fraction >= 1 {
            path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: radius * 2, height: radius * 2))
            return path
        }
        path.addArc(
            center: centre,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        return path
    }
}

#Preview("Ink ring") {
    HStack {
        InkRing(
            fraction: ScoreText.fraction(SomaWidgetSnapshot.placeholder.recovery.value),
            lineWidth: SomaTheme.standard.metrics.widgetRingStrokeSmall
        )
        // Edge case: no score, the track alone.
        InkRing(fraction: nil, lineWidth: SomaTheme.standard.metrics.widgetRingStrokeSmall)
    }
    .frame(width: 240, height: 120)
}
