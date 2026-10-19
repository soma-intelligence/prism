//
//  PulseYearCharts.swift
//  Prism
//

import SwiftUI
import SomaUI

/// A year of nights as a wheel: one spoke a week, round from the top like a
/// clock face, and the week’s nights along it from Monday near the centre to
/// Sunday at the rim. Each night is a dot, larger and brighter the longer it
/// was, so a season of long nights shows as a bright sector.
struct PulseYearSpiral: View {
    let year: PulseTrends.Year

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[.sleep].identity.color

        GeometryReader { geometry in
            let size = geometry.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 - metrics.pulseGlowDiameter / 2 + 4
            let inner = outer * 0.4
            let count = year.nights.count
            let firstRow = year.firstRow
            let position: (Int) -> CGPoint = { index in
                Self.point(index, count: count, firstRow: firstRow, centre: centre, inner: inner, outer: outer)
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let known = year.nights.compactMap { $0 }
                    let low = known.min() ?? 0
                    let high = known.max() ?? 1
                    let spread = max(high - low, 0.5)
                    let range = metrics.pulseNightDotRange

                    // A soft light over the month that ran longest.
                    if let peak = peakCentre(position) {
                        let glow = outer * 0.9
                        context.fill(Path(ellipseIn: CGRect(x: peak.x - glow / 2, y: peak.y - glow / 2, width: glow, height: glow)),
                                     with: .radialGradient(Gradient(colors: [hue.opacity(0.25), hue.opacity(0)]),
                                                           center: peak, startRadius: 0, endRadius: glow / 2))
                    }

                    for (index, hours) in year.nights.enumerated() {
                        let point = position(index)
                        let diameter: CGFloat
                        let colour: Color
                        if let hours {
                            let share = CGFloat((hours - low) / spread)
                            diameter = range.lowerBound + (range.upperBound - range.lowerBound) * share
                            colour = hue.opacity(0.35 + 0.65 * Double(share))
                        } else {
                            diameter = 1.5
                            colour = colors.inkSecondary.color.opacity(0.25)
                        }
                        context.fill(Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                                            width: diameter, height: diameter)),
                                     with: .color(colour))
                    }

                    // Last night, on the rim, with the glow the one point a
                    // chart is about carries.
                    if let last = year.nights.indices.last, year.nights[last] != nil {
                        let point = position(last)
                        let glow = metrics.pulseGlowDiameter
                        context.fill(Path(ellipseIn: CGRect(x: point.x - glow / 2, y: point.y - glow / 2, width: glow, height: glow)),
                                     with: .radialGradient(Gradient(colors: [hue.opacity(0.6), hue.opacity(0)]),
                                                           center: point, startRadius: 0, endRadius: glow / 2))
                        let dot = metrics.chartDotDiameter + 2
                        let ring = CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)
                        context.fill(Path(ellipseIn: ring), with: .color(hue))
                        context.stroke(Path(ellipseIn: ring), with: .color(colors.surface.color), lineWidth: 1.5)
                    }
                }

                if let label = year.peakLabel, let peak = peakCentre(position) {
                    Text(label)
                        .somaFont(theme.typography.pulseAxis)
                        .foregroundStyle(colors.inkPrimary.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(colors.surface.color.opacity(0.85)))
                        .fixedSize()
                        .position(peak)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("A year of sleep, one dot a night")
        .accessibilityValue(year.average.map { "\($0) average" } ?? "No nights yet")
    }

    private func peakCentre(_ position: (Int) -> CGPoint) -> CGPoint? {
        guard !year.peakNights.isEmpty else { return nil }
        let points = year.peakNights.map(position)
        return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                       y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }

    /// Night `index` of `count`: its week's spoke, round from twelve, and its
    /// weekday's place along it, Monday innermost.
    static func point(_ index: Int, count: Int, firstRow: Int, centre: CGPoint, inner: CGFloat, outer: CGFloat) -> CGPoint {
        let slot = index + firstRow
        let weeks = max((count - 1 + firstRow) / 7 + 1, 1)
        let radius = inner + (outer - inner) * CGFloat(slot % 7) / 6
        let angle = Double(slot / 7) / Double(weeks) * 2 * .pi - .pi / 2
        return CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
    }
}

/// The year's days as a grid, one row a weekday and one column a week. Trends
/// draws it as dots in an aspect's hue, each as large as the day's value;
/// Environment, which has no aspect, as squares in shades of ink. A soft
/// light can mark a run of weeks, such as the longest streak.
struct PulseYearGridView: View {
    enum Style: Equatable {
        case dots(SomaAspect)
        case squares
    }

    let grid: PulseYearGrid
    let style: Style
    /// Where each level starts, lowest first: a day under the first is level
    /// zero, one at or over the last is the top level.
    let levels: [Double]
    var glowColumns: ClosedRange<Int>? = nil

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let rowPitch = metrics.pulseHeatRowPitch
        let gridHeight = metrics.pulseHeatMonthRow + rowPitch * 7
        let top = levels.count

        VStack(alignment: .trailing, spacing: 12) {
            GeometryReader { geometry in
                let columns = max(grid.weeks.count, 1)
                let room = geometry.size.width - metrics.pulseHeatLabelColumn
                let pitch = min(room / CGFloat(columns), metrics.pulseHeatMaxColumnPitch)
                let left = metrics.pulseHeatLabelColumn
                let gridTop = metrics.pulseHeatMonthRow
                let largest = min(pitch, rowPitch) - 1.5
                let centre: (Int, Int) -> CGPoint = { column, row in
                    CGPoint(x: left + pitch * (CGFloat(column) + 0.5), y: gridTop + rowPitch * (CGFloat(row) + 0.5))
                }

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        if let glow = glowColumns, case .dots(let aspect) = style {
                            let hue = theme.aspects[aspect].identity.color
                            let from = centre(glow.lowerBound, 3)
                            let to = centre(glow.upperBound, 3)
                            let width = max(to.x - from.x + pitch * 4, pitch * 6)
                            let rect = CGRect(x: (from.x + to.x) / 2 - width / 2, y: gridTop - 4,
                                              width: width, height: rowPitch * 7 + 8)
                            context.fill(Path(ellipseIn: rect),
                                         with: .radialGradient(Gradient(colors: [hue.opacity(0.22), hue.opacity(0)]),
                                                               center: CGPoint(x: rect.midX, y: rect.midY),
                                                               startRadius: 0, endRadius: width / 2))
                        }

                        for (column, week) in grid.weeks.enumerated() {
                            for (row, cell) in week.enumerated() {
                                let level: Int?
                                switch cell {
                                case .outside: continue
                                case .missing: level = nil
                                case .value(let value): level = Self.level(value, levels: levels)
                                }
                                let point = centre(column, row)
                                let shape = mark(level: level, top: top, largest: largest, at: point)
                                context.fill(shape.path, with: .color(shape.colour))
                            }
                        }

                        let point = centre(grid.todayColumn, grid.todayRow)
                        let ring = largest + 1.5
                        let outline = CGRect(x: point.x - ring / 2, y: point.y - ring / 2, width: ring, height: ring)
                        switch style {
                        case .dots:
                            context.stroke(Path(ellipseIn: outline), with: .color(colors.inkSecondary.color), lineWidth: 1)
                        case .squares:
                            context.stroke(Path(roundedRect: outline, cornerRadius: 1.5), with: .color(colors.inkSecondary.color), lineWidth: 1)
                        }
                    }

                    ForEach(grid.months, id: \.column) { month in
                        Text(month.label)
                            .somaFont(type.pulseAxis)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize()
                            .offset(x: left + pitch * CGFloat(month.column), y: 0)
                    }

                    ForEach(Array(["Mon", "Wed", "Fri"].enumerated()), id: \.offset) { index, day in
                        Text(day)
                            .somaFont(type.pulseAxis)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize()
                            .frame(width: left, alignment: .leading)
                            .position(x: left / 2, y: centre(0, index * 2).y)
                    }
                }
            }
            .frame(height: gridHeight)

            legend(largest: min(metrics.pulseHeatMaxColumnPitch, rowPitch) - 1.5)
        }
    }

    /// The mark for one day: nil level is a day with nothing recorded.
    private func mark(level: Int?, top: Int, largest: CGFloat, at point: CGPoint) -> (path: Path, colour: Color) {
        let colors = theme.colors
        switch style {
        case .dots(let aspect):
            let hue = theme.aspects[aspect].identity.color
            guard let level, level > 0 else {
                let faint = colors.inkSecondary.color.opacity(level == nil ? 0.3 : 0.4)
                return (Path(ellipseIn: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)), faint)
            }
            let diameter = largest * CGFloat(level + 1) / CGFloat(top + 1)
            return (Path(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                           width: diameter, height: diameter)), hue)
        case .squares:
            let side = largest
            let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
            let path = Path(roundedRect: rect, cornerRadius: 1.5)
            guard let level else { return (path, colors.surfaceRecessed.color) }
            let share = 0.15 + 0.85 * Double(level) / Double(max(top, 1))
            return (path, colors.inkPrimary.color.opacity(share))
        }
    }

    private func legend(largest: CGFloat) -> some View {
        let top = levels.count
        return HStack(spacing: 5) {
            Text("Less")
            ForEach(0...top, id: \.self) { level in
                let shape = mark(level: level, top: top, largest: largest,
                                 at: CGPoint(x: largest / 2, y: largest / 2))
                Canvas { context, _ in context.fill(shape.path, with: .color(shape.colour)) }
                    .frame(width: largest, height: largest)
            }
            Text("More")
        }
        .somaFont(theme.typography.pulseAxis)
        .foregroundStyle(theme.colors.inkSecondary.color)
        .accessibilityHidden(true)
    }

    /// The level of `value`: how many of `levels` it reaches.
    static func level(_ value: Double, levels: [Double]) -> Int {
        levels.filter { value >= $0 }.count
    }
}

extension SomaTypography {
    /// Axis labels and day letters: the eyebrow's size, untracked and in
    /// regular weight, with digits that hold their column.
    var pulseAxis: SomaFontSpec {
        var spec = eyebrow
        spec.tracking = 0
        spec.weight = .regular
        spec.digits = .tabular
        return spec
    }
}
