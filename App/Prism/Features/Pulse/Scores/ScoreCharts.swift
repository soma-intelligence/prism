//
//  ScoreCharts.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

// The plots the score pages draw. Each is driven by its inputs and the theme;
// a plot with nothing to show still draws its frame and says what fills it,
// so the card keeps its shape.

/// What a plot with no data says in its frame.
struct ScoreEmptyPlot: View {
    let message: LocalizedStringResource

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let pen = SomaPen(theme)
        Canvas { context, size in
            for share in [0.0, 0.5, 1.0] {
                pen.gridline(context, y: 0.5 + (size.height - 1) * share, to: size.width)
            }
        }
        .overlay {
            Text(message)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(height: metrics.scorePlotHeight * 0.7)
    }
}

// MARK: - Daily bars

/// One thin bar a day over the usual band in faint green, the average as a
/// dashed rule. The last bar is today's, in full colour.
struct ScoreDayBars: View {
    let values: [Double?]
    let aspect: SomaAspect
    var band: ClosedRange<Double>?
    var ceiling: Double = 100
    var labels: [String] = []

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let top = max(ceiling, values.compactMap { $0 }.max() ?? 0)
        let average = ScoreMath.mean(values)
        let values = values
        let band = band

        SomaPlot(scale: SomaPlotScale(fixed: 0...top), xLabels: labels, height: theme.metrics.scorePlotHeight) { context, space, pen in
            if let band {
                pen.band(context, top: space.y(band.upperBound), bottom: space.y(band.lowerBound), in: space.plot)
            }
            let pitch = space.pitch(values.count)
            for (index, value) in values.enumerated() {
                let x = space.slot(index, of: values.count)
                guard let value else { continue }
                let isLast = index == values.count - 1
                pen.bar(context, x: x, top: space.y(value), floor: space.floor, pitch: pitch,
                        color: hue.opacity(isLast ? 1 : pen.contextOpacity))
            }
            if let average {
                pen.rule(context, y: space.y(average), in: space.plot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Daily values"))
        .accessibilityValue(Text(average.map { "Average \(Int($0.rounded()))" } ?? "No values yet"))
    }
}

/// Labels spread under a plot, first at the leading edge, last at the
/// trailing.
struct ScoreAxis: View {
    let labels: [String]

    var body: some View {
        SomaAxisLabels(labels)
    }
}

// MARK: - Stems against the usual

/// Each day as a stem from the usual line: above for a day that ran higher.
/// The day inside the wobble is hollow, a day outside it filled.
struct ScoreStems: View {
    let deviations: [Double?]
    let aspect: SomaAspect
    var wobble: Double = 3

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let reach = max(10, deviations.compactMap { $0.map(abs) }.max() ?? 10)
        let deviations = deviations
        let wobble = wobble

        SomaPlot(scale: SomaPlotScale(values: [-reach, reach], desired: 3), height: theme.metrics.scorePlotHeight,
                 label: { $0.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false))) }) { context, space, pen in
            pen.band(context, top: space.y(wobble), bottom: space.y(-wobble), in: space.plot)
            let pitch = space.pitch(deviations.count)
            for (index, value) in deviations.enumerated() {
                guard let value else { continue }
                let x = space.slot(index, of: deviations.count)
                var stem = Path()
                stem.move(to: CGPoint(x: x, y: space.y(0)))
                stem.addLine(to: CGPoint(x: x, y: space.y(value)))
                context.stroke(stem, with: .color(hue.opacity(0.7)), lineWidth: min(1.5, pitch * 0.3))
                pen.dot(context, at: CGPoint(x: x, y: space.y(value)), color: hue, filled: abs(value) > wobble)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Each day against your usual"))
    }
}

// MARK: - A line through the day

/// A line over a span of the clock, with an optional band, the part after
/// `solidUntil` dashed, a ring at the last solid point and faint windows
/// named over the plot.
struct ScoreDayLine: View {
    struct Window: Identifiable {
        var id: String { title }
        var title: String
        var start: Double
        var end: Double
        var aspect: SomaAspect
    }

    /// x from 0 to 1 across the span, y in the plot's units.
    let points: [(x: Double, y: Double)]
    let aspect: SomaAspect
    var range: ClosedRange<Double> = 0...100
    var band: ClosedRange<Double>?
    var solidUntil: Double?
    var windows: [Window] = []
    var labels: [String] = []
    var marker: (x: Double, y: Double)?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let aspects = theme.aspects
        let points = points
        let range = range
        let band = band
        let solidUntil = solidUntil
        let windows = windows
        let marker = marker

        SomaPlot(scale: SomaPlotScale(fixed: range),
                 marks: windows.map { SomaPlot.Mark(fraction: $0.start, label: $0.title) },
                 xLabels: labels, height: theme.metrics.scorePlotHeight) { context, space, pen in
            func clamp(_ value: Double) -> Double { min(max(value, range.lowerBound), range.upperBound) }
            for window in windows {
                let x0 = space.x(fraction: window.start)
                let rect = CGRect(x: x0, y: space.plot.minY, width: max(2, space.x(fraction: window.end) - x0), height: space.plot.height)
                context.fill(Path(rect), with: .color(aspects[window.aspect].identity.color.opacity(pen.bandOpacity)))
            }
            if let band {
                pen.band(context, top: space.y(band.upperBound), bottom: space.y(band.lowerBound), in: space.plot)
            }
            let split = solidUntil ?? 1
            let mapped = points.map { CGPoint(x: space.x(fraction: $0.x), y: space.y(clamp($0.y))) }
            let solid = zip(points, mapped).filter { $0.0.x <= split }.map(\.1)
            let later = zip(points, mapped).filter { $0.0.x > split }.map(\.1)
            pen.line(context, solid, color: hue)
            if !later.isEmpty {
                pen.line(context, (solid.last.map { [$0] } ?? []) + later, color: hue.opacity(0.6), dashed: true)
            }
            let ring = marker.map { CGPoint(x: space.x(fraction: $0.x), y: space.y(clamp($0.y))) } ?? (solidUntil == nil ? nil : solid.last)
            if let ring { pen.ring(context, at: ring, color: hue) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Line through the day"))
    }
}

// MARK: - Stacked nights

/// Nights as stacked columns in the stage shades, deep at the foot, then core
/// and REM, the need drawn across them as a dashed rule.
struct ScoreStageColumns: View {
    struct Night: Identifiable {
        var id: Int
        var label: String
        var deep: Double?
        var core: Double?
        var rem: Double?
    }

    let nights: [Night]
    let need: Double
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let top = max(need + 1, nights.map { ($0.deep ?? 0) + ($0.core ?? 0) + ($0.rem ?? 0) }.max() ?? 0)
        let shades = (deep: SomaSleepStage.deep.color(theme), core: SomaSleepStage.core.color(theme), rem: SomaSleepStage.rem.color(theme))
        let nights = nights
        let need = need
        let slotted = nights.count <= 10
        let labels = slotted ? nights.map(\.label) : [nights.first?.label ?? "", nights.last?.label ?? ""]

        VStack(alignment: .leading, spacing: theme.metrics.chartLabelGap * 2) {
            SomaPlot(scale: SomaPlotScale(values: [0, top]), xLabels: labels, labelsUnderBars: slotted, height: theme.metrics.scorePlotHeight,
                     label: { "\($0.formatted(.number.precision(.fractionLength(0...1))))h" }) { context, space, pen in
                let pitch = space.pitch(nights.count)
                let width = min(pitch * 0.5, pen.barWidth * 2)
                for (index, night) in nights.enumerated() {
                    let x = space.slot(index, of: nights.count)
                    var base = space.floor
                    for (hours, color) in [(night.deep, shades.deep), (night.core, shades.core), (night.rem, shades.rem)] {
                        guard let hours, hours > 0 else { continue }
                        let segment = space.floor - space.y(hours)
                        let rect = CGRect(x: x - width / 2, y: base - segment, width: width, height: max(segment - 1, 1))
                        context.fill(Path(roundedRect: rect, cornerRadius: min(pen.barRadius, segment / 2)), with: .color(color))
                        base -= segment
                    }
                }
                pen.rule(context, y: space.y(need), in: space.plot)
            }
            HStack(spacing: 12) {
                legend("Deep", shades.deep)
                legend("Core", shades.core)
                legend("REM", shades.rem)
                legend("Need \(ScoreMath.duration(hours: need))", nil)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time asleep each night, by stage"))
    }

    private func legend(_ title: String, _ color: Color?) -> some View {
        HStack(spacing: 5) {
            if let color {
                Circle().fill(color)
                    .frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
            } else {
                Rectangle()
                    .stroke(theme.colors.inkSecondary.color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: theme.metrics.chartPointDiameter * 2, height: 1)
            }
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
    }
}

// MARK: - A sparkline row

/// One signal over the last nights, as a biomarker row: its name, a
/// sparkline over its usual band ending in a ring, and the latest value.
struct ScoreSparkRow: View {
    let title: String
    let values: [Double?]
    let usual: ScoringUsual?
    let latest: String?
    let aspect: SomaAspect
    var isOff = false

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let tint = isOff ? colors.statusOut.color : theme.aspects[aspect].identity.color

        HStack(spacing: metrics.moveRowGap) {
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .frame(width: 76, alignment: .leading)
            SomaSparkline(values, tint: tint, band: usual.map { $0.low...max($0.low, $0.high) })
                .frame(height: metrics.chartSparkHeight)
            Text(latest ?? "-")
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(isOff ? colors.statusOut.color : colors.inkPrimary.color)
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(latest ?? "No reading"))
    }
}

// MARK: - The day on a clock

/// Twenty four hours on a ring, midnight at the top: the sleep window in the
/// sleep aspect, the rest of the day in the mind aspect, and ticks for wind
/// down and now.
struct ScoreClockRing: View {
    let sleepStart: Double
    let sleepEnd: Double
    let windDown: Double
    let now: Double

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let diameter = metrics.scoreRingDiameter
        let stroke = metrics.scoreRingStroke
        let share: (Double) -> Double = { ScoreMath.HealthStatsClock.wrap($0) / 24 }
        let sleepFrom = share(sleepStart)
        let rawTo = share(sleepEnd)
        let sleepTo = rawTo < sleepFrom ? rawTo + 1 : rawTo

        ZStack {
            Circle()
                .stroke(theme.aspects[.mind].identity.color.opacity(0.45), lineWidth: stroke)
            ScoreArc(start: -90 + sleepFrom * 360, sweep: (sleepTo - sleepFrom) * 360)
                .stroke(theme.aspects[.sleep].identity.color, style: StrokeStyle(lineWidth: stroke))
            GeometryReader { proxy in
                let radius = (proxy.size.width) / 2
                ForEach([(windDown, colors.inkPrimary.color), (now, colors.onOrb.color)], id: \.0) { hour, color in
                    let angle = Angle.degrees(-90 + share(hour) * 360).radians
                    Circle()
                        .fill(color)
                        .overlay(Circle().strokeBorder(colors.canvas.color, lineWidth: 2))
                        .frame(width: stroke * 0.8, height: stroke * 0.8)
                        .position(x: radius + radius * cos(angle), y: radius + radius * sin(angle))
                }
            }
            ForEach([(0.0, "00"), (6.0, "06"), (12.0, "12"), (18.0, "18")], id: \.0) { hour, label in
                let angle = Angle.degrees(-90 + hour / 24 * 360).radians
                let r = diameter / 2 - stroke * 1.6
                Text(verbatim: label)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .offset(x: r * cos(angle), y: r * sin(angle))
            }
            VStack(spacing: 2) {
                Text(ScoreMath.clock(windDown))
                    .somaFont(type.metric)
                    .foregroundStyle(colors.inkPrimary.color)
                Text("wind down")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .frame(width: diameter, height: diameter)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your day on a clock"))
        .accessibilityValue(Text("Sleep \(ScoreMath.clock(sleepStart)) to \(ScoreMath.clock(sleepEnd)), wind down \(ScoreMath.clock(windDown))"))
    }
}

// MARK: - Lanes

/// Today on lanes from midnight: sleep, workouts, and each half hour of
/// stress in the high band, with now as a line.
struct ScoreDayLanes: View {
    let sleep: [ScoringNightWindow]
    let moves: [ScoringNightWindow]
    let peaks: [Date]
    let now: Date
    let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let type = theme.typography
        let day = Calendar.current.startOfDay(for: now)
        let x: (Date, CGFloat) -> CGFloat = { date, width in
            width * CGFloat(min(1, max(0, date.timeIntervalSince(day) / 86_400)))
        }
        let lanes: [(LocalizedStringResource, SomaAspect, [ScoringNightWindow])] = [
            ("Sleep", .sleep, sleep),
            ("Move", .activity, moves),
            ("Stress", aspect, peaks.map { ScoringNightWindow(start: $0, end: $0.addingTimeInterval(1800)) }),
        ]

        VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                        Text(lane.0).frame(maxHeight: .infinity)
                    }
                }
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .frame(width: 44, alignment: .leading)
                Canvas { context, size in
                    let row = size.height / CGFloat(lanes.count)
                    for share in stride(from: 0.0, through: 1.0, by: 0.25) {
                        var grid = Path()
                        grid.move(to: CGPoint(x: size.width * share, y: 0))
                        grid.addLine(to: CGPoint(x: size.width * share, y: size.height))
                        context.stroke(grid, with: .color(colors.inkPrimary.color.opacity(theme.metrics.chartGridOpacity)), lineWidth: 0.5)
                    }
                    for (index, lane) in lanes.enumerated() {
                        let hue = theme.aspects[lane.1].identity.color
                        for span in lane.2 {
                            let from = x(span.start, size.width), to = x(span.end, size.width)
                            guard to > from else { continue }
                            let thickness = theme.metrics.chartThinBarWidth * 2
                            let rect = CGRect(x: from, y: row * (CGFloat(index) + 0.5) - thickness / 2, width: max(3, to - from), height: thickness)
                            context.fill(Path(roundedRect: rect, cornerRadius: theme.metrics.chartThinBarRadius), with: .color(hue))
                        }
                    }
                    var line = Path()
                    line.move(to: CGPoint(x: x(now, size.width), y: 0))
                    line.addLine(to: CGPoint(x: x(now, size.width), y: size.height))
                    context.stroke(line, with: .color(colors.inkSecondary.color), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .frame(height: theme.metrics.scorePlotHeight * 0.8)
            ScoreAxis(labels: ["00", "06", "12", "18", "24"])
                .padding(.leading, 52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Today on lanes: sleep, movement and stress peaks"))
    }
}
