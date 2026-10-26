import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// A week of values as one hairline, scaled to its own range, with a dot on
/// the latest value. A missing day breaks the line rather than dropping it to
/// zero.
public struct HairlineTrace: View {
    private let values: [Double?]
    private let showsNowDot: Bool
    private let dimmed: Bool
    private let aspect: SomaAspect?

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    public init(values: [Double?], showsNowDot: Bool = true) {
        self.init(values: values, showsNowDot: showsNowDot, dimmed: false)
    }

    /// `dimmed` draws the line and the dot in the secondary ink, for a stale
    /// snapshot.
    init(values: [Double?], showsNowDot: Bool, dimmed: Bool, aspect: SomaAspect? = nil) {
        self.values = values
        self.showsNowDot = showsNowDot
        self.dimmed = dimmed
        self.aspect = aspect
    }

    /// Each value placed on 0...1 between the series' lowest and highest. A
    /// flat series sits in the middle; a missing value stays missing.
    nonisolated static func normalised(_ values: [Double?]) -> [Double?] {
        let present = values.compactMap { $0 }
        guard let low = present.min(), let high = present.max() else {
            return values.map { _ in nil }
        }
        let span = high - low
        return values.map { value in
            guard let value else { return nil }
            return span > 0 ? (value - low) / span : 0.5
        }
    }

    public var body: some View {
        let ink = WidgetInk(theme: theme, mode: mode)
        let metrics = theme.metrics
        let points = Self.normalised(values)
        let stroke = dimmed ? ink.secondary : ink.mark(aspect)
        ZStack {
            TracePath(points: points)
                .stroke(stroke, style: StrokeStyle(
                    lineWidth: metrics.widgetTraceStroke, lineCap: .round, lineJoin: .round
                ))
                .widgetAccentable()
            if showsNowDot {
                NowDot(points: points, diameter: metrics.widgetNowDot)
                    .fill(stroke)
                    .widgetAccentable()
            }
        }
        .padding(metrics.widgetNowDot / 2)
        .accessibilityHidden(true)
    }
}

/// The trace's line, broken wherever a value is missing.
struct TracePath: Shape {
    var points: [Double?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var run: [CGPoint] = []
        for (index, point) in points.enumerated() {
            guard let point else {
                SmoothLine.add(run, to: &path)
                run = []
                continue
            }
            run.append(TracePath.location(index: index, value: point, count: points.count, in: rect))
        }
        SmoothLine.add(run, to: &path)
        return path
    }

    static func location(index: Int, value: Double, count: Int, in rect: CGRect) -> CGPoint {
        let step = count > 1 ? rect.width / CGFloat(count - 1) : 0
        let x = count > 1 ? rect.minX + step * CGFloat(index) : rect.midX
        return CGPoint(x: x, y: rect.maxY - rect.height * value)
    }
}

/// One smooth line through a run of points ordered left to right: a
/// monotone cubic, so every trace and the energy curve share one style and
/// the line never swings past the values it joins.
enum SmoothLine {
    static func add(_ points: [CGPoint], to path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        guard points.count > 1 else { return }
        let slopes = tangents(points)
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let third = (b.x - a.x) / 3
            path.addCurve(
                to: b,
                control1: CGPoint(x: a.x + third, y: a.y + slopes[i] * third),
                control2: CGPoint(x: b.x - third, y: b.y - slopes[i + 1] * third)
            )
        }
    }

    /// The slope at each point (Fritsch and Carlson): flat where the line
    /// turns or levels, limited elsewhere so the curve stays monotone between
    /// two points.
    static func tangents(_ points: [CGPoint]) -> [CGFloat] {
        let n = points.count
        guard n > 1 else { return Array(repeating: 0, count: n) }
        var secants: [CGFloat] = []
        for i in 0..<(n - 1) {
            let dx = points[i + 1].x - points[i].x
            secants.append(dx > 0 ? (points[i + 1].y - points[i].y) / dx : 0)
        }
        var slopes = [CGFloat](repeating: 0, count: n)
        slopes[0] = secants[0]
        slopes[n - 1] = secants[n - 2]
        for i in 1..<(n - 1) {
            let left = secants[i - 1], right = secants[i]
            slopes[i] = left * right <= 0 ? 0 : (left + right) / 2
        }
        for i in 0..<(n - 1) {
            let secant = secants[i]
            if secant == 0 {
                slopes[i] = 0
                slopes[i + 1] = 0
                continue
            }
            let alpha = slopes[i] / secant, beta = slopes[i + 1] / secant
            let length = alpha * alpha + beta * beta
            if length > 9 {
                let tau = 3 / length.squareRoot()
                slopes[i] = tau * alpha * secant
                slopes[i + 1] = tau * beta * secant
            }
        }
        return slopes
    }
}

/// The dot on the last value that is present.
struct NowDot: Shape {
    var points: [Double?]
    var diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let index = points.lastIndex(where: { $0 != nil }), let value = points[index] else {
            return Path()
        }
        let centre = TracePath.location(index: index, value: value, count: points.count, in: rect)
        return Path(ellipseIn: CGRect(
            x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter
        ))
    }
}

#Preview("Hairline trace") {
    HairlineTrace(values: SomaWidgetSnapshot.placeholder.hrv.series7)
        .frame(width: 160, height: 48)
        .padding()
}
