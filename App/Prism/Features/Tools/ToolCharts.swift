//
//  ToolCharts.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The half ring a scored tool opens with: the track, the score's share of it
/// painted in the aspect's orb colours, a knob at the end, and the number,
/// its state and how it moved in the middle.
///
/// A missing score leaves the ring empty and reads as a dash, never a zero.
struct ToolGauge: View {
    let aspect: SomaAspect
    /// 0 to 1, or nil when there is nothing to score.
    let fraction: Double?
    let display: String?
    let state: String?
    let delta: String?
    /// The delta says things got worse: the mark points down in danger.
    let deltaIsWorse: Bool
    var lowLabel = "0"
    var highLabel = "100"

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    /// The ring runs from 210 degrees round through the top to minus 30, open
    /// at the bottom like a dial.
    private static let startAngle = 150.0
    private static let sweep = 240.0

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let width = metrics.orbDiameter * 1.35
        let line = metrics.orbDiameter * 0.14
        let stops = theme.aspects[aspect].orb.stops.map(\.color)

        VStack(spacing: metrics.cardHeaderSpacing) {
            ZStack {
                ToolArc(start: Self.startAngle, sweep: Self.sweep, fraction: 1)
                    .stroke(colors.surfaceRecessed.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                if fraction != nil {
                    ToolArc(start: Self.startAngle, sweep: Self.sweep, fraction: shown)
                        .stroke(AngularGradient(colors: stops + stops.prefix(1), center: .center),
                                style: StrokeStyle(lineWidth: line, lineCap: .round))
                    ToolArcKnob(start: Self.startAngle, sweep: Self.sweep, fraction: shown, diameter: line * 0.55)
                        .fill(colors.inkPrimary.color)
                }
                VStack(spacing: 4) {
                    Text(display ?? "-")
                        .somaFont(type.display)
                        .foregroundStyle(colors.inkPrimary.color)
                    if let state {
                        Text(state)
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    if let delta {
                        HStack(spacing: metrics.trendMarkSpacing) {
                            SomaTrendMark(trend: deltaIsWorse ? .down : .up)
                            Text(delta)
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                    }
                }
                .padding(.top, line)
            }
            .frame(width: width, height: width * 0.8)

            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .somaFont(type.caption)
            .foregroundStyle(colors.inkSecondary.color)
            .frame(width: width * 0.95)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([display, state, delta].compactMap { $0 }.joined(separator: ", ")))
        .onAppear { settle() }
        .onChange(of: fraction) { settle() }
    }

    private func settle() {
        let target = min(max(fraction ?? 0, 0), 1)
        if reduceMotion {
            shown = target
        } else {
            withAnimation(theme.motion.fold) { shown = target }
        }
    }
}

/// An arc of `sweep` degrees from `start`, clockwise, of which `fraction` is
/// drawn.
struct ToolArc: Shape {
    var start: Double
    var sweep: Double
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height / 0.8) / 2 * 0.86
        let centre = CGPoint(x: rect.midX, y: rect.minY + rect.width / 2)
        var path = Path()
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(start), endAngle: .degrees(start + sweep * max(fraction, 0.0001)),
                    clockwise: false)
        return path
    }
}

/// The knob at the end of a ``ToolArc``.
struct ToolArcKnob: Shape {
    var start: Double
    var sweep: Double
    var fraction: Double
    var diameter: CGFloat

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height / 0.8) / 2 * 0.86
        let centre = CGPoint(x: rect.midX, y: rect.minY + rect.width / 2)
        let angle = Angle.degrees(start + sweep * fraction).radians
        let point = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        return Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                      width: diameter, height: diameter))
    }
}

/// A day curve: evenly spaced values over a span, an optional dashed line to
/// stay under, a ring at now with the projection past it dashed, and labels
/// along the bottom.
struct ToolCurveChart: View {
    let aspect: SomaAspect
    /// Oldest first; nil breaks the line.
    let values: [Double?]
    /// The y axis top. The bottom is zero.
    let top: Double
    /// A reference line, such as the bedtime threshold or the UV that needs
    /// cover.
    var threshold: Double? = nil
    /// Where now falls, 0 to 1 across the span. The curve past it is drawn
    /// fainter, as a projection.
    var now: Double? = nil
    var xLabels: [String] = []
    /// Top first, spread evenly down to zero. Empty uses round ticks.
    var yLabels: [String] = []

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let out = theme.colors.statusOut.color
        let values = values
        let top = max(top, .ulpOfOne)
        let threshold = threshold
        let now = now
        let yLabels = yLabels
        let scale = yLabels.count >= 2
            ? SomaPlotScale(domain: 0...top, ticks: (0..<yLabels.count).map { top * (1 - Double($0) / Double(yLabels.count - 1)) })
            : SomaPlotScale(fixed: 0...top)

        SomaPlot(scale: values.count > 1 ? scale : nil, xLabels: xLabels, height: theme.metrics.chartCompactPlotHeight,
                 label: yLabels.count >= 2 ? { value in
                     yLabels[min(max(Int(((1 - value / top) * Double(yLabels.count - 1)).rounded()), 0), yLabels.count - 1)]
                 } : nil) { context, space, pen in
            if let threshold {
                pen.rule(context, y: space.y(min(threshold, top)), in: space.plot, color: out)
            }
            let nowIndex = now.map { Int((Double(values.count - 1) * min(max($0, 0), 1)).rounded()) }
            let points = values.enumerated().map { index, value in
                value.map { CGPoint(x: space.x(index, of: values.count), y: space.y(min(max($0, 0), top))) }
            }
            let past: [CGPoint?] = points.enumerated().map { index, point in
                if let nowIndex, index > nowIndex { return nil }
                return point
            }
            let future: [CGPoint?] = points.enumerated().map { index, point in
                guard let nowIndex, index >= nowIndex else { return nil }
                return point
            }
            pen.line(context, past, color: hue)
            pen.line(context, future, color: hue.opacity(0.6), dashed: true)
            if now != nil, let last = past.compactMap({ $0 }).last {
                pen.ring(context, at: last, color: hue)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Thirty (or any number of) days as a line over the usual band in faint
/// green, a ring on today, the scale on the trailing edge and the first and
/// last day under it: the history card most tools close on.
struct ToolHistoryChart: View {
    let aspect: SomaAspect
    let values: [Double?]
    let band: ClosedRange<Double>?
    let firstLabel: String
    var middleLabel: String? = nil

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let values = values
        let band = band

        SomaPlot(scale: SomaPlotScale(values: values.compactMap { $0 }, including: band.map { [$0.lowerBound, $0.upperBound] } ?? []),
                 xLabels: [firstLabel, middleLabel, String(localized: "Today")].compactMap { $0 },
                 height: theme.metrics.chartCompactPlotHeight) { context, space, pen in
            if let band {
                pen.band(context, top: space.y(band.upperBound), bottom: space.y(band.lowerBound), in: space.plot)
            }
            let points = values.enumerated().map { index, value in
                value.map { CGPoint(x: space.x(index, of: values.count), y: space.y($0)) }
            }
            pen.line(context, points, color: hue)
            if let last = points.compactMap({ $0 }).last { pen.ring(context, at: last, color: hue) }
        }
        .accessibilityHidden(true)
    }
}

/// Stacked thin bars, one per day: each a stack of parts in the aspect's hue
/// at falling strengths, over the target band in faint green.
struct ToolStackedBars: View {
    struct Bar: Identifiable {
        var id: String { label }
        var label: String
        /// Bottom first.
        var parts: [Double]
    }

    let aspect: SomaAspect
    let bars: [Bar]
    let top: Double
    var target: ClosedRange<Double>? = nil

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let bars = bars
        let target = target

        SomaPlot(scale: bars.isEmpty || top <= 0 ? nil : SomaPlotScale(fixed: 0...top),
                 xLabels: bars.map(\.label), labelsUnderBars: true,
                 height: theme.metrics.chartCompactPlotHeight) { context, space, pen in
            if let target {
                pen.band(context, top: space.y(target.upperBound), bottom: space.y(target.lowerBound), in: space.plot)
            }
            let pitch = space.pitch(bars.count)
            let width = min(pitch * 0.5, pen.barWidth * 2)
            for (index, bar) in bars.enumerated() {
                let x = space.slot(index, of: bars.count)
                var base = space.floor
                for (partIndex, part) in bar.parts.enumerated() where part > 0 {
                    let height = space.floor - space.y(part)
                    let rect = CGRect(x: x - width / 2, y: base - height, width: width, height: max(height - 1, 0))
                    context.fill(Path(roundedRect: rect, cornerRadius: min(pen.barRadius, height / 2)),
                                 with: .color(hue.opacity(max(1 - 0.28 * Double(partIndex), 0.2))))
                    base -= height
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A 24 hour clock: a ring with the windows of the day as arcs, the hours at
/// the four quarters, and the next window's time in the middle.
struct ToolDayDial: View {
    struct Span: Identifiable {
        var id: String
        /// Clock hours, 0 to 24.
        var start: Double
        var end: Double
        var aspect: SomaAspect
    }

    let spans: [Span]
    /// The current clock hour, marked with a dot.
    let nowHour: Double
    let centre: String
    let caption: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let side = metrics.orbDiameter * 1.1
        let line = metrics.orbDiameter * 0.08

        ZStack {
            Circle()
                .stroke(theme.colors.surfaceRecessed.color, lineWidth: line)
            ForEach(spans) { span in
                let length = (span.end - span.start + 24).truncatingRemainder(dividingBy: 24)
                Circle()
                    .trim(from: 0, to: max(length / 24, 0.005))
                    .stroke(theme.aspects[span.aspect].identity.color,
                            style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(span.start / 24 * 360 - 90))
            }
            GeometryReader { geometry in
                let radius = geometry.size.width / 2
                let angle = Angle.degrees(nowHour / 24 * 360 - 90).radians
                let dot = metrics.chartDotDiameter + 2
                Circle()
                    .fill(theme.colors.inkPrimary.color)
                    .frame(width: dot, height: dot)
                    .position(x: radius + radius * cos(angle), y: radius + radius * sin(angle))
            }
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                let angle = Angle.degrees(Double(hour) / 24 * 360 - 90).radians
                let reach = side / 2 - line * 2
                Text(String(format: "%02d", hour))
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .offset(x: reach * cos(angle), y: reach * sin(angle))
            }
            VStack(spacing: 2) {
                Text(centre)
                    .somaFont(theme.typography.title)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                if let caption {
                    Text(caption)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
        }
        .frame(width: side, height: side)
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.cardSpacing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([centre, caption].compactMap { $0 }.joined(separator: ", ")))
    }
}

/// Horizontal spans on a clock axis, one row each: the work and free nights of
/// Social Jetlag, the closed stretch of Evening Close, the days of a trip.
struct ToolSpanRows: View {
    struct Row: Identifiable {
        var id: String { label }
        var label: String
        /// Hours on the axis, may run past 24.
        var start: Double
        var end: Double
        /// A mark inside the span, such as mid-sleep.
        var mark: Double?
        var strength: Double = 1
    }

    let aspect: SomaAspect
    let rows: [Row]
    /// The axis, in hours, possibly past 24.
    let axis: ClosedRange<Double>
    let ticks: [Double]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let from = x(row.start, width), to = x(row.end, width)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(theme.aspects[aspect].identity.color.opacity(row.strength))
                                .frame(width: max(to - from, 2), height: metrics.chartThinBarWidth * 2)
                                .offset(x: from)
                            if let mark = row.mark {
                                Rectangle()
                                    .fill(theme.colors.inkPrimary.color)
                                    .frame(width: 1.5, height: metrics.chartThinBarWidth * 3)
                                    .offset(x: x(mark, width) - 1)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: metrics.chartDotDiameter * 3.2)
                }
            }
            GeometryReader { geometry in
                ForEach(ticks, id: \.self) { tick in
                    Text(ToolFormat.hourLabel(tick))
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize()
                        .position(x: x(tick, geometry.size.width), y: geometry.size.height / 2)
                }
            }
            .frame(height: metrics.chartDotDiameter * 3)
        }
        .accessibilityHidden(true)
    }

    private func x(_ hour: Double, _ width: CGFloat) -> CGFloat {
        let span = max(axis.upperBound - axis.lowerBound, 1)
        return width * CGFloat((min(max(hour, axis.lowerBound), axis.upperBound) - axis.lowerBound) / span)
    }
}
