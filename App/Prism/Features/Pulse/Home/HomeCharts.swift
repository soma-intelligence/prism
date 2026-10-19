//
//  HomeCharts.swift
//  Prism
//
//  The charts of the pages Today opens, from the gallery's families: a trend
//  line over its usual band (01), the hypnogram (13), stages (04), the day in
//  lanes (20), hourly bars (02), the meal response (29) and the cycle (19).
//  Each draws what it is given and nothing more: a gap is a gap.
//

import SwiftUI
import SomaUI
import HealthExportCore

// MARK: - Trend line over its usual band (gallery 01)

/// One value per step as a line in the aspect's hue over the usual band in
/// faint green, a hollow ring on the last value. A nil breaks the line.
struct HomeTrendChart: View {
    let values: [Double?]
    let band: ClosedRange<Double>?
    let aspect: SomaAspect
    /// Under the plot: the first, middle and last step.
    let axis: [String]
    /// Decimals on the value labels.
    var decimals = 0

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let values = values
        let band = band

        SomaPlot(scale: scale, xLabels: axis) { context, space, pen in
            if let band {
                pen.band(context, top: space.y(band.upperBound), bottom: space.y(band.lowerBound), in: space.plot)
            }
            let points = values.enumerated().map { index, value in
                value.map { CGPoint(x: space.x(index, of: values.count), y: space.y($0)) }
            }
            pen.line(context, points, color: hue)
            let known = points.compactMap { $0 }
            if known.count <= 14 {
                for point in known.dropLast() { pen.dot(context, at: point, color: hue) }
            }
            if let last = known.last { pen.ring(context, at: last, color: hue) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    /// Round ticks round the values and the band.
    private var scale: SomaPlotScale? {
        SomaPlotScale(values: values.compactMap { $0 }, including: band.map { [$0.lowerBound, $0.upperBound] } ?? [])
    }

    private func label(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    private var accessibilitySummary: String {
        guard let last = values.last(where: { $0 != nil }) ?? nil else { return "No readings yet." }
        return "Latest \(label(last))" + (band.map { ", usual \(label($0.lowerBound)) to \(label($0.upperBound))" } ?? "")
    }
}

/// Labels spread under a chart, the first on the leading edge and the last on
/// the trailing one.
struct HomeAxis: View {
    let labels: [String]

    var body: some View {
        SomaAxisLabels(labels)
    }
}

// MARK: - The day in lanes (gallery 20)

/// One lane of the day: stretches and moments on a 24 hour track.
struct HomeLane: Identifiable {
    enum Mark {
        case span(Date, Date)
        case moment(Date, planned: Bool)
    }

    let title: String
    let aspect: SomaAspect
    let marks: [Mark]

    var id: String { title }
}

/// The day from midnight to midnight in lanes, with a line on now.
struct HomeDayLanes: View {
    let lanes: [HomeLane]
    let now: Date
    let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let day = calendar.startOfDay(for: now)
        let rowHeight = metrics.miniOrbDiameter * 0.9
        let aspects = theme.aspects

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lanes) { lane in
                        Text(lane.title).frame(height: rowHeight)
                    }
                }
                .somaFont(theme.typography.captionValue)
                .foregroundStyle(colors.inkSecondary.color)

                Canvas { context, size in
                    func x(_ date: Date) -> CGFloat {
                        size.width * CGFloat(min(max(date.timeIntervalSince(day) / 86_400, 0), 1))
                    }
                    let hairline = colors.inkPrimary.color.opacity(metrics.chartGridOpacity)
                    for hour in stride(from: 0, through: 24, by: 6) {
                        var line = Path()
                        let lineX = size.width * CGFloat(hour) / 24
                        line.move(to: CGPoint(x: lineX, y: 0))
                        line.addLine(to: CGPoint(x: lineX, y: size.height))
                        context.stroke(line, with: .color(hairline), lineWidth: 0.5)
                    }
                    for (row, lane) in lanes.enumerated() {
                        let midY = CGFloat(row) * rowHeight + rowHeight / 2
                        let hue = aspects[lane.aspect].identity.color
                        for mark in lane.marks {
                            switch mark {
                            case .span(let start, let end):
                                let rect = CGRect(x: x(start), y: midY - metrics.chartThinBarWidth,
                                                  width: max(x(end) - x(start), 3), height: metrics.chartThinBarWidth * 2)
                                context.fill(Path(roundedRect: rect, cornerRadius: metrics.chartThinBarRadius), with: .color(hue))
                            case .moment(let date, let planned):
                                let dot = metrics.chartPointDiameter + 1
                                let rect = CGRect(x: x(date) - dot / 2, y: midY - dot / 2, width: dot, height: dot)
                                if planned {
                                    context.fill(Path(ellipseIn: rect), with: .color(colors.surface.color))
                                    context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(hue), lineWidth: 1.2)
                                } else {
                                    context.fill(Path(ellipseIn: rect), with: .color(hue))
                                }
                            }
                        }
                    }
                    var nowLine = Path()
                    nowLine.move(to: CGPoint(x: x(now), y: 0))
                    nowLine.addLine(to: CGPoint(x: x(now), y: size.height))
                    context.stroke(nowLine, with: .color(colors.inkSecondary.color), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                .frame(height: rowHeight * CGFloat(max(lanes.count, 1)))
            }
            HomeAxis(labels: ["00", "06", "12", "18", "24"])
                .padding(.leading, metrics.miniOrbDiameter * 1.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Today in lanes, now at \(HomeFormat.clock(now, calendar: calendar))."))
    }
}

// MARK: - Hourly bars (gallery 02)

/// The day's hours as thin bars: stood in the activity hue, missed as a short
/// grey stub, the hour running hollow, the rest of the day a faint stub on the
/// floor.
struct HomeStandBars: View {
    let hours: [HomeStandHour]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.activity].identity.color
        let out = colors.inkSecondary.color
        let hours = hours

        VStack(alignment: .leading, spacing: metrics.chartLabelGap) {
            Canvas { context, size in
                let pen = SomaPen(theme)
                let floor = size.height - 0.5
                pen.gridline(context, y: floor, to: size.width)
                pen.gridline(context, y: 0.5, to: size.width)
                let pitch = size.width / CGFloat(max(hours.count, 1))
                let stub = metrics.chartThinBarWidth
                for (index, hour) in hours.enumerated() {
                    let x = pitch * (CGFloat(index) + 0.5)
                    switch hour {
                    case .stood:
                        pen.bar(context, x: x, top: 1, floor: floor, pitch: pitch, color: hue)
                    case .missed:
                        pen.bar(context, x: x, top: floor - stub, floor: floor, pitch: pitch, color: out)
                    case .now:
                        let width = pen.barWidth(pitch: pitch)
                        let rect = CGRect(x: x - width / 2, y: 1, width: width, height: floor - 1)
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: pen.barRadius),
                                       with: .color(hue), lineWidth: 1)
                    case .open:
                        pen.bar(context, x: x, top: floor - stub / 2, floor: floor, pitch: pitch, color: pen.grid)
                    }
                }
            }
            .frame(height: metrics.chartCompactPlotHeight * 0.6)
            HomeAxis(labels: ["00", "06", "12", "18", "23"])
            HStack(spacing: 14) {
                legend("Stood", hue)
                legend("Missed", out)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(hours.filter { $0 == .stood }.count) hours stood today."))
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
    }
}

// MARK: - Meal response (gallery 29)

/// Glucose above its level before each meal, over the three hours after:
/// the meals in faint lines, one of them drawn out.
struct HomeMealCurves: View {
    let responses: [HomeMealResponse]
    let highlighted: Int?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.gut].identity.color
        let top = max(responses.map(\.rise).max() ?? 0, 20)
        let responses = responses
        let highlighted = highlighted

        SomaPlot(scale: SomaPlotScale(values: [0, top]), xLabels: ["0", "1 h", "2 h", "3 h"],
                 height: theme.metrics.chartCompactPlotHeight) { context, space, pen in
            func point(_ minutes: Double, _ above: Double) -> CGPoint {
                CGPoint(x: space.x(fraction: minutes / 180), y: space.y(max(above, 0)))
            }
            for (index, response) in responses.enumerated() where index != highlighted {
                pen.line(context, [point(0, 0)] + response.curve.map { point($0.minutes, $0.above) },
                         color: pen.inkSecondary.opacity(0.35), width: 1)
            }
            if let highlighted, responses.indices.contains(highlighted) {
                let points = [point(0, 0)] + responses[highlighted].curve.map { point($0.minutes, $0.above) }
                pen.fill(context, points, floor: space.floor, color: hue)
                pen.line(context, points, color: hue)
                if let peak = points.min(by: { $0.y < $1.y }) { pen.ring(context, at: peak, color: hue) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Glucose after \(responses.count) meals."))
    }
}

// MARK: - Cycle (gallery 19)

/// The cycle as a track from day one to its usual length: the period, the
/// fertile days around ovulation, and a line on today.
struct HomeCycleTrack: View {
    let cycle: HomeCycle
    let periodDays: Int

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.heart].identity.color
        let length = max(cycle.length ?? 28, cycle.day)
        let height = metrics.chartSparkHeight

        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                func x(_ day: Double) -> CGFloat { size.width * CGFloat((day - 1) / Double(length)) }
                let thickness = metrics.chartThinBarWidth * 1.5
                let track = CGRect(x: 0, y: (size.height - thickness) / 2, width: size.width, height: thickness)
                context.fill(Path(roundedRect: track, cornerRadius: track.height / 2), with: .color(colors.surfaceRecessed.color))
                let period = CGRect(x: 0, y: track.minY, width: x(Double(periodDays) + 1), height: track.height)
                context.fill(Path(roundedRect: period, cornerRadius: track.height / 2), with: .color(hue))
                if let usual = cycle.length {
                    let ovulation = Double(usual - 14)
                    let fertile = CGRect(x: x(ovulation - 4), y: track.minY, width: x(ovulation + 2) - x(ovulation - 4), height: track.height)
                    context.fill(Path(roundedRect: fertile, cornerRadius: track.height / 2), with: .color(hue.opacity(0.35)))
                }
                var today = Path()
                today.move(to: CGPoint(x: x(Double(cycle.day) + 0.5), y: 0))
                today.addLine(to: CGPoint(x: x(Double(cycle.day) + 0.5), y: size.height))
                context.stroke(today, with: .color(colors.inkPrimary.color), lineWidth: 1.5)
            }
            .frame(height: height)
            HomeAxis(labels: ["1", "\(length / 2)", "\(length)"])
            HStack(spacing: 14) {
                legend("Period", hue)
                if cycle.length != nil { legend("Fertile window", hue.opacity(0.35)) }
                legend("Today", colors.inkPrimary.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Day \(cycle.day) of \(cycle.length.map(String.init) ?? "an unknown length")."))
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
        }
    }
}

// MARK: - Measure against its usual

/// A measure against its usual band, the row the gallery's `rows` draws:
/// Longevity's own ``EnvironmentMeasureRow``, fed from a marker series.
struct HomeMeasureRow: View {
    let name: String
    let unit: String
    var decimals = 0
    let latest: Double?
    let band: ClosedRange<Double>?
    /// Whether a value above the band is the worse side.
    var higherIsWorse = true

    var body: some View {
        EnvironmentMeasureRow(
            name: name,
            detail: band.map { "usual \(format($0.lowerBound)) to \(format($0.upperBound))" } ?? "Usual range after five days",
            value: latest.map { "\(format($0))\(unit.isEmpty ? "" : " " + unit)" },
            isWorse: isWorse,
            rail: rail
        )
    }

    private var isWorse: Bool {
        guard let latest, let band else { return false }
        return higherIsWorse ? latest > band.upperBound : latest < band.lowerBound
    }

    private var rail: EnvironmentMeasureRow.Rail? {
        guard let latest else { return nil }
        let points = [latest] + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
        guard let low = points.min(), let high = points.max() else { return nil }
        let pad = max((high - low) * 0.6, decimals == 0 ? 2 : 0.2)
        return EnvironmentMeasureRow.Rail(range: (low - pad)...(high + pad), band: band, value: latest)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }
}
