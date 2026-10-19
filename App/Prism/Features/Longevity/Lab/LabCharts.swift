//
//  LabCharts.swift
//  Prism
//
//  The lab pages' charts, drawn from the theme: the half ring an age is read
//  on, a line over time with its usual band, a column of cuff readings, and
//  the diverging bars of what moved a number.
//

import SwiftUI
import SomaUI

/// A half ring from `range.lowerBound` to `range.upperBound`, filled to the
/// estimate in the aspect's hue, with a tick at your calendar age.
struct LabAgeGauge: View {
    let estimate: Double?
    let age: Double?
    var range: ClosedRange<Double> = 20...80
    var aspect: SomaAspect = .body
    var caption: String?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        let hue = theme.aspects[aspect].identity.color
        let lineWidth = theme.metrics.chartTrackHeight * 4
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height * 2)
                let radius = side / 2 - lineWidth / 2
                let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height)
                ZStack {
                    arc(from: 0, to: 1, radius: radius, centre: centre)
                        .stroke(theme.colors.surfaceRecessed.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    if estimate != nil {
                        arc(from: 0, to: shown, radius: radius, centre: centre)
                            .stroke(hue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                    if let age {
                        let inner = point(fraction(age), radius: radius, centre: centre)
                        let outer = point(fraction(age), radius: radius + lineWidth * 0.8, centre: centre)
                        Path { path in path.move(to: inner); path.addLine(to: outer) }
                            .stroke(theme.colors.inkPrimary.color, lineWidth: theme.metrics.chartMarkerWidth)
                        Text(verbatim: LabMath.format(age, decimals: 0) ?? "")
                            .somaFont(theme.typography.captionValue)
                            .foregroundStyle(theme.colors.inkSecondary.color)
                            .position(point(fraction(age), radius: radius + lineWidth * 1.6, centre: centre))
                    }
                    VStack(spacing: 2) {
                        Text(estimate.flatMap { LabMath.format($0, decimals: 0) } ?? "-")
                            .somaFont(theme.typography.display)
                            .foregroundStyle(theme.colors.inkPrimary.color)
                        if let caption {
                            Text(caption)
                                .somaFont(theme.typography.body)
                                .foregroundStyle(theme.colors.inkSecondary.color)
                        }
                    }
                    .position(x: centre.x, y: centre.y - radius * 0.35)
                }
            }
            .frame(height: 170)
            HStack {
                Text(verbatim: LabMath.format(range.lowerBound, decimals: 0) ?? "")
                Spacer()
                Text(verbatim: LabMath.format(range.upperBound, decimals: 0) ?? "")
            }
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
        }
        .onAppear { settle() }
        .onChange(of: estimate) { settle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Age gauge"))
        .accessibilityValue(Text(estimate.flatMap { LabMath.format($0, decimals: 0) } ?? "Not measured"))
    }

    private func settle() {
        let target = estimate.map(fraction) ?? 0
        if reduceMotion { shown = target } else { withAnimation(theme.motion.tabEntrance) { shown = target } }
    }

    private func fraction(_ value: Double) -> Double {
        min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private func point(_ fraction: Double, radius: CGFloat, centre: CGPoint) -> CGPoint {
        let angle = Double.pi * (1 - fraction)
        return CGPoint(x: centre.x + radius * cos(angle), y: centre.y - radius * sin(angle))
    }

    private func arc(from: Double, to: Double, radius: CGFloat, centre: CGPoint) -> Path {
        Path { path in
            path.addArc(center: centre, radius: radius,
                        startAngle: .degrees(180 + 180 * from), endAngle: .degrees(180 + 180 * max(from, to)),
                        clockwise: false)
        }
    }
}

/// Points over time: the usual band in
/// faint green, the values as a line with hollow dots, a ring on the latest,
/// the scale on the trailing edge.
struct LabLineChart: View {
    let points: [LabPoint]
    var band: ClosedRange<Double>?
    var aspect: SomaAspect = .body
    var isFlagged = false
    /// Extra values the scale must include, such as a target line.
    var reference: Double?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = isFlagged ? theme.colors.statusOut.color : theme.aspects[aspect].identity.color
        let points = points
        let band = band
        let reference = reference
        let scale = SomaPlotScale(values: points.map(\.value),
                                  including: [band?.lowerBound, band?.upperBound, reference].compactMap { $0 })

        SomaPlot(scale: scale, xLabels: axis, height: theme.metrics.chartCompactPlotHeight) { context, space, pen in
            guard let first = points.first?.date, let last = points.last?.date else { return }
            let span = max(last.timeIntervalSince(first), 1)
            func x(_ date: Date) -> CGFloat {
                points.count < 2 ? space.plot.midX : space.x(fraction: date.timeIntervalSince(first) / span)
            }
            if let band {
                pen.band(context, top: space.y(band.upperBound), bottom: space.y(band.lowerBound), in: space.plot)
            }
            if let reference {
                pen.rule(context, y: space.y(reference), in: space.plot)
            }
            let mapped = points.map { CGPoint(x: x($0.date), y: space.y($0.value)) }
            pen.line(context, mapped, color: hue)
            if mapped.count <= 40 {
                for point in mapped.dropLast() { pen.dot(context, at: point, color: hue) }
            }
            if let latest = mapped.last { pen.ring(context, at: latest, color: hue) }
        }
        .accessibilityHidden(true)
    }

    private var axis: [String] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        if points.count < 3 { return [first.labDay, last.labDay] }
        return [first.labDay, first.addingTimeInterval(last.timeIntervalSince(first) / 2).labDay, last.labDay]
    }
}

/// Cuff readings as thin columns from diastolic to systolic, the 120 and 80
/// lines dashed behind them and the latest in full colour.
struct LabPressureChart: View {
    let readings: [PressureReading]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.heart].identity.color
        let readings = readings
        let lo = min(60, readings.map(\.diastolic).min() ?? 60) - 5
        let hi = max(140, readings.map(\.systolic).max() ?? 140) + 5

        SomaPlot(scale: SomaPlotScale(values: [lo, hi]), height: theme.metrics.chartPlotHeight) { context, space, pen in
            guard !readings.isEmpty else { return }
            for mark in [80.0, 120.0] {
                pen.rule(context, y: space.y(mark), in: space.plot)
            }
            let pitch = space.pitch(readings.count)
            for (index, reading) in readings.enumerated() {
                let isLast = index == readings.count - 1
                pen.span(context, x: space.slot(index, of: readings.count), top: space.y(reading.systolic),
                         bottom: space.y(reading.diastolic), pitch: pitch,
                         color: hue.opacity(isLast ? 1 : pen.contextOpacity))
            }
        }
        .accessibilityHidden(true)
    }
}

/// What moved a number: one bar per contributor either side of zero, the
/// signed amount at the end.
struct LabContributors: View {
    struct Item: Identifiable {
        let id: String
        var label: String
        /// Signed; negative is the good side for an age.
        var amount: Double
        var text: String
    }

    let items: [Item]
    var aspect: SomaAspect = .body

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let widest = max(items.map { abs($0.amount) }.max() ?? 1, 0.1)
        VStack(spacing: theme.metrics.bodyRowSpacing) {
            ForEach(items) { item in
                HStack(spacing: theme.metrics.cardSpacing) {
                    Text(item.label)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkPrimary.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { proxy in
                        let half = proxy.size.width / 2
                        let length = half * CGFloat(abs(item.amount) / widest)
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity))
                                .frame(width: 1)
                                .offset(x: half)
                            Capsule()
                                .fill(item.amount > 0 ? theme.colors.danger.color : theme.aspects[aspect].identity.color)
                                .frame(width: max(length, 2), height: theme.metrics.chartTrackHeight)
                                .offset(x: item.amount > 0 ? half : half - length)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: theme.metrics.aspectChartWidth)
                    Text(item.text)
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(item.amount > 0 ? theme.colors.danger.color : theme.colors.inkPrimary.color)
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
