import Foundation
import SwiftUI
import WidgetKit
import SomaUI
import SomaWidgetKit

/// Where the energy curve's moments sit across the Strain widget.
public enum EnergyAxis {
    public static let energyLabel = "Energy"
    public static let stressLabel = "Stress"

    /// How far across the axis `now` sits, clamped to 0...1. When `start` is
    /// not before `end`, the curve's own first and last points stand in; with
    /// no span at all, now sits at the end.
    public static func nowFraction(
        curve: [SomaWidgetSnapshot.EnergyPoint],
        start: Date,
        end: Date,
        now: Date
    ) -> Double {
        var lower = start
        var upper = end
        if upper <= lower {
            guard let first = curve.first?.date, let last = curve.last?.date, last > first else { return 1 }
            lower = first
            upper = last
        }
        let fraction = now.timeIntervalSince(lower) / upper.timeIntervalSince(lower)
        guard fraction.isFinite else { return 1 }
        return min(max(fraction, 0), 1)
    }

    /// The axis the curve is drawn on: from bedtime, or the curve's first point
    /// without a sleep band, to the last timeline entry, so the now dot has
    /// room to move after the curve ends; or to now, once the snapshot is
    /// older than the timeline, so the dot is not pinned at the edge. Nil when
    /// there is nothing to draw.
    public static func bounds(_ snapshot: SomaWidgetSnapshot, now: Date) -> ClosedRange<Date>? {
        guard let start = snapshot.sleepBand?.lowerBound ?? snapshot.energyCurve.first?.date else { return nil }
        let end = max(snapshot.generatedAt.addingTimeInterval(StrainTimeline.horizon), now)
        guard end > start else { return nil }
        return start...end
    }

    /// The energy level at a moment: between two points it is read off the
    /// line joining them; before the first and after the last it holds.
    public static func level(curve: [SomaWidgetSnapshot.EnergyPoint], at date: Date) -> Double? {
        guard let first = curve.first, let last = curve.last else { return nil }
        if date <= first.date { return first.level }
        if date >= last.date { return last.level }
        for (a, b) in zip(curve, curve.dropFirst()) where date >= a.date && date <= b.date {
            let span = b.date.timeIntervalSince(a.date)
            guard span > 0 else { return b.level }
            let t = date.timeIntervalSince(a.date) / span
            return a.level + (b.level - a.level) * t
        }
        return last.level
    }

    /// The curve's points on the axis, as fractions across it; a point outside
    /// the axis is left out rather than piled up at an edge.
    public static func linePoints(_ snapshot: SomaWidgetSnapshot, axis: ClosedRange<Date>) -> [(x: Double, level: Double)] {
        snapshot.energyCurve
            .filter { axis.contains($0.date) }
            .map { (nowFraction(curve: [], start: axis.lowerBound, end: axis.upperBound, now: $0.date), $0.level) }
    }

    /// Where the now dot sits: the header's own `energyNow` from the last
    /// point on (the level after it is held), the curve's level before it.
    /// No dot when the header has no number.
    public static func dotLevel(_ snapshot: SomaWidgetSnapshot, now: Date) -> Double? {
        guard let energy = snapshot.energyNow, energy.isFinite else { return nil }
        guard let last = snapshot.energyCurve.last, now < last.date else { return energy }
        return level(curve: snapshot.energyCurve, at: now) ?? energy
    }

    /// What VoiceOver reads for the Strain widget, with the age when stale.
    public static func accessibility(_ snapshot: SomaWidgetSnapshot, _ freshness: Freshness) -> String {
        let reading = "\(energyLabel) \(ScoreText.value(snapshot.energyNow)), \(stressLabel) \(ScoreText.value(snapshot.stress.value))"
        guard let age = StaleAge.text(freshness) else { return reading }
        return "\(reading), \(age)"
    }
}

/// The energy curve as a line through 0...100, on the axis fractions given.
struct EnergyLineShape: Shape {
    /// x on 0...1 across the axis, level on 0...100.
    var points: [(x: Double, level: Double)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        SmoothLine.add(points.map { EnergyLineShape.location(x: $0.x, level: $0.level, in: rect) }, to: &path)
        return path
    }

    static func location(x: Double, level: Double, in rect: CGRect) -> CGPoint {
        let height = min(max(level, 0), 100) / 100
        return CGPoint(x: rect.minX + rect.width * x, y: rect.maxY - rect.height * height)
    }
}

/// A band of the axis, full height, between two fractions.
struct BandShape: Shape {
    var lower: Double
    var upper: Double

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX + rect.width * lower,
            y: rect.minY,
            width: rect.width * max(upper - lower, 0),
            height: rect.height
        ))
    }
}

/// A dot of a given diameter at a point of the axis.
struct AxisDotShape: Shape {
    var x: Double
    var level: Double
    var diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = EnergyLineShape.location(x: x, level: level, in: rect)
        return Path(ellipseIn: CGRect(
            x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter
        ))
    }
}

/// Bedtime to now: last night as a faint block, the energy curve over it and
/// after it, and a dot where now is.
struct EnergyChart: View {
    let snapshot: SomaWidgetSnapshot
    let now: Date
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let metrics = theme.metrics
        let ink = WidgetInk(theme: theme, mode: mode)
        let stroke = ink.value(freshness)
        ZStack {
            if let axis = EnergyAxis.bounds(snapshot, now: now) {
                let curve = snapshot.energyCurve
                let fraction = { (date: Date) in
                    EnergyAxis.nowFraction(curve: curve, start: axis.lowerBound, end: axis.upperBound, now: date)
                }
                if let band = snapshot.sleepBand {
                    BandShape(lower: fraction(band.lowerBound), upper: fraction(band.upperBound))
                        .fill(ink.primary.opacity(metrics.widgetBandOpacity))
                }
                EnergyLineShape(points: EnergyAxis.linePoints(snapshot, axis: axis))
                    .stroke(stroke, style: StrokeStyle(
                        lineWidth: metrics.widgetTraceStroke, lineCap: .round, lineJoin: .round
                    ))
                    .widgetAccentable()
                if let level = EnergyAxis.dotLevel(snapshot, now: now) {
                    // After the last point the level is held, not measured:
                    // a faint line carries it to the dot.
                    if let last = curve.last, now > last.date {
                        EnergyLineShape(points: [(fraction(last.date), last.level), (fraction(now), level)])
                            .stroke(ink.track, style: StrokeStyle(
                                lineWidth: metrics.widgetTraceStroke, lineCap: .round
                            ))
                    }
                    AxisDotShape(x: fraction(now), level: level, diameter: metrics.widgetNowDot)
                        .fill(stroke)
                        .widgetAccentable()
                }
            }
        }
        .padding(metrics.widgetNowDot / 2)
        .accessibilityHidden(true)
    }
}

/// Energy now as a big number with its word.
private struct EnergyHeader: View {
    let snapshot: SomaWidgetSnapshot
    let number: SomaFontSpec
    let freshness: Freshness

    @Environment(\.somaTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.metrics.widgetRowGap) {
            NumberWithUnit(text: ScoreText.value(snapshot.energyNow), unit: nil, number: number, freshness: freshness)
            ValueLabel(EnergyAxis.energyLabel)
        }
    }
}

/// The medium Strain widget: energy now over the bedtime to now curve, and
/// stress today as a small figure over its week.
public struct StrainMedium: View {
    private let snapshot: SomaWidgetSnapshot?
    private let now: Date

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        Group {
            switch WidgetDisplay(snapshot: snapshot, now: now) {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                if let snapshot {
                    let metrics = theme.metrics
                    VStack(spacing: metrics.widgetLabelSpacing) {
                        HStack(alignment: .firstTextBaseline, spacing: metrics.widgetColumnSpacing) {
                            VStack(alignment: .leading, spacing: metrics.widgetLabelSpacing) {
                                EnergyHeader(snapshot: snapshot, number: theme.typography.widgetValue, freshness: freshness)
                                EnergyChart(snapshot: snapshot, now: now, freshness: freshness)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Stress as one group: number and word on the
                            // energy number's baseline, its week right under.
                            VStack(alignment: .leading, spacing: metrics.widgetLabelSpacing) {
                                HStack(alignment: .firstTextBaseline, spacing: metrics.widgetRowGap) {
                                    NumberWithUnit(
                                        text: ScoreText.value(snapshot.stress.value),
                                        unit: nil,
                                        number: theme.typography.widgetFigure,
                                        freshness: freshness
                                    )
                                    ValueLabel(EnergyAxis.stressLabel)
                                }
                                HairlineTrace(values: snapshot.stress.series7, showsNowDot: true, dimmed: freshness != .fresh)
                                    .frame(height: metrics.widgetTraceHeight)
                            }
                            .frame(width: metrics.widgetSideColumn, alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                        StaleFooter(freshness: freshness)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(EnergyAxis.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.score(.strain).url)
    }
}

/// The large Strain widget: energy and its curve full width, stress and its
/// week full width under it.
public struct StrainLarge: View {
    private let snapshot: SomaWidgetSnapshot?
    private let now: Date

    @Environment(\.somaTheme) private var theme

    public init(snapshot: SomaWidgetSnapshot?, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    public var body: some View {
        Group {
            switch WidgetDisplay(snapshot: snapshot, now: now) {
            case .empty:
                WidgetEmpty()
            case .data(let freshness):
                if let snapshot {
                    let metrics = theme.metrics
                    VStack(alignment: .leading, spacing: metrics.widgetBlockSpacing) {
                        VStack(alignment: .leading, spacing: metrics.widgetLabelSpacing) {
                            EnergyHeader(snapshot: snapshot, number: theme.typography.widgetHero, freshness: freshness)
                            EnergyChart(snapshot: snapshot, now: now, freshness: freshness)
                        }
                        .frame(maxHeight: .infinity)
                        VStack(alignment: .leading, spacing: metrics.widgetLabelSpacing) {
                            HStack(alignment: .firstTextBaseline, spacing: metrics.widgetRowGap) {
                                NumberWithUnit(
                                    text: ScoreText.value(snapshot.stress.value),
                                    unit: nil,
                                    number: theme.typography.widgetValue,
                                    freshness: freshness
                                )
                                ValueLabel(EnergyAxis.stressLabel)
                            }
                            HairlineTrace(values: snapshot.stress.series7, showsNowDot: true, dimmed: freshness != .fresh)
                                .frame(height: metrics.widgetTraceHeightLarge)
                        }
                        StaleFooter(freshness: freshness)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(EnergyAxis.accessibility(snapshot, freshness)))
                }
            }
        }
        .widgetURL(WidgetLink.score(.strain).url)
    }
}

#Preview("Strain medium") {
    StrainMedium(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 170)
}

#Preview("Strain medium, two hours on") {
    StrainMedium(
        snapshot: .placeholder,
        now: SomaWidgetSnapshot.placeholder.generatedAt.addingTimeInterval(2 * 3600)
    )
    .padding(16)
    .frame(width: 364, height: 170)
}

#Preview("Strain large") {
    StrainLarge(snapshot: .placeholder, now: SomaWidgetSnapshot.placeholder.generatedAt)
        .padding(16)
        .frame(width: 364, height: 382)
}
