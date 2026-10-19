//
//  SomaPlot.swift
//  SomaUI
//
//  The one frame every chart in the app draws in, so they read as one family:
//  a hairline grid on three or four round ticks, the scale on the trailing
//  edge, a few labels under the plot, and a pen that draws lines, hollow
//  dots, thin bars, the normal band and the average the same way each time.
//

import SwiftUI

// MARK: - Scale

/// A value axis with round ticks: the domain is snapped to them, so the top
/// and bottom hairlines sit on the plot's edges and every label is a round
/// number.
public struct SomaPlotScale: Sendable, Equatable {
    public let domain: ClosedRange<Double>
    public let ticks: [Double]
    public let step: Double

    /// A scale round `values`, widened to take in `including` (a band, a
    /// target), from zero when `fromZero` is set, as bars want.
    public init?(values: [Double], including: [Double] = [], fromZero: Bool = false, desired: Int = 4) {
        var all = values + including
        if fromZero { all.append(0) }
        guard var low = all.min(), var high = all.max() else { return nil }
        if high - low < .ulpOfOne {
            let room = max(abs(high) * 0.1, 1)
            low -= room
            high += room
            if fromZero { low = min(0, low + room) }
        }
        self.init(fitting: low...high, desired: desired)
    }

    /// Ticks the caller names, evenly or not, on a domain it names.
    public init(domain: ClosedRange<Double>, ticks: [Double]) {
        self.domain = domain
        self.ticks = ticks
        self.step = ticks.count > 1 ? abs(ticks[1] - ticks[0]) : 1
    }

    /// Round ticks inside a fixed domain, such as a score's 0 to 100.
    public init(fixed domain: ClosedRange<Double>, desired: Int = 3) {
        let step = Self.niceStep((domain.upperBound - domain.lowerBound) / Double(max(desired - 1, 1)))
        var ticks: [Double] = []
        var tick = (domain.lowerBound / step).rounded(.up) * step
        while tick <= domain.upperBound + step * 1e-6 {
            ticks.append(tick)
            tick += step
        }
        if ticks.count < 3 {
            // Round numbers left too few lines: the ends and the middle.
            let middle = (domain.lowerBound + domain.upperBound) / 2
            ticks = [domain.lowerBound, middle, domain.upperBound]
            self.step = middle - domain.lowerBound
        } else {
            self.step = step
        }
        self.domain = domain
        self.ticks = ticks
    }

    private init(fitting range: ClosedRange<Double>, desired: Int) {
        let span = range.upperBound - range.lowerBound
        var step = Self.niceStep(span / Double(max(desired - 1, 1)))
        var low = (range.lowerBound / step).rounded(.down) * step
        var high = (range.upperBound / step).rounded(.up) * step
        // Never more than five lines: a busy grid is the first thing that
        // makes a chart look generated.
        while (high - low) / step > 4.01 {
            step = Self.niceStep(step * 1.5)
            low = (range.lowerBound / step).rounded(.down) * step
            high = (range.upperBound / step).rounded(.up) * step
        }
        if (high - low) / step < 1.99 {
            step /= 2
        }
        var ticks: [Double] = []
        var tick = low
        while tick <= high + step * 1e-6 {
            ticks.append(abs(tick) < step * 1e-6 ? 0 : tick)
            tick += step
        }
        self.domain = low...high
        self.ticks = ticks
        self.step = step
    }

    /// The tick's label, with as many decimals as the step needs.
    public func label(_ value: Double) -> String {
        var decimals = 0
        while decimals < 2, abs(step * pow(10, Double(decimals)) - (step * pow(10, Double(decimals))).rounded()) > 1e-6 {
            decimals += 1
        }
        return value.formatted(.number.precision(.fractionLength(decimals)).grouping(.automatic))
    }

    static func niceStep(_ rough: Double) -> Double {
        guard rough > 0, rough.isFinite else { return 1 }
        let power = pow(10, (log10(rough)).rounded(.down))
        let fraction = rough / power
        let nice: Double = switch fraction {
        case ..<1.5: 1
        case ..<2.25: 2
        case ..<3.5: 2.5
        case ..<7.5: 5
        default: 10
        }
        return nice * power
    }
}

// MARK: - Space

/// Where a plot draws: a value to a y, an index to an x, inside the plot's
/// inset so a ring on the edge keeps its whole circle.
public struct SomaPlotSpace: Sendable {
    public let size: CGSize
    public let plot: CGRect
    public let domain: ClosedRange<Double>

    public init(size: CGSize, domain: ClosedRange<Double>, inset: CGFloat) {
        self.size = size
        self.domain = domain
        // insetBy returns the null rect when the inset swallows the size.
        let dx = min(inset, size.width / 2)
        let dy = min(inset, size.height / 2)
        self.plot = CGRect(x: dx, y: dy, width: size.width - dx * 2, height: size.height - dy * 2)
    }

    public func y(_ value: Double) -> CGFloat {
        let span = max(domain.upperBound - domain.lowerBound, .ulpOfOne)
        return plot.maxY - plot.height * CGFloat((value - domain.lowerBound) / span)
    }

    /// The index-th of `count` points, the first on the leading edge and the
    /// last on the trailing one.
    public func x(_ index: Int, of count: Int) -> CGFloat {
        count > 1 ? plot.minX + plot.width * CGFloat(index) / CGFloat(count - 1) : plot.midX
    }

    /// A share of the way across, 0 to 1.
    public func x(fraction: Double) -> CGFloat {
        plot.minX + plot.width * CGFloat(min(max(fraction, 0), 1))
    }

    /// The width each of `count` bars has to itself.
    public func pitch(_ count: Int) -> CGFloat {
        plot.width / CGFloat(max(count, 1))
    }

    /// The centre of the index-th of `count` bars.
    public func slot(_ index: Int, of count: Int) -> CGFloat {
        plot.minX + pitch(count) * (CGFloat(index) + 0.5)
    }

    /// The plot's floor, where bars stand.
    public var floor: CGFloat { y(max(domain.lowerBound, min(0, domain.upperBound))) }
}

// MARK: - Pen

/// Draws the marks every chart shares, the same way each time. Built from the
/// theme in a view's body and handed to its canvas.
public struct SomaPen: Sendable {
    public let grid: Color
    public let ink: Color
    public let inkSecondary: Color
    public let surface: Color
    public let normal: Color
    public let stroke: CGFloat
    public let point: CGFloat
    public let ring: CGFloat
    public let barWidth: CGFloat
    public let barRadius: CGFloat
    public let bandOpacity: Double
    public let fillOpacity: Double
    public let contextOpacity: Double

    public init(_ theme: SomaTheme) {
        let metrics = theme.metrics
        let colors = theme.colors
        grid = colors.inkPrimary.color.opacity(metrics.chartGridOpacity)
        ink = colors.inkPrimary.color
        inkSecondary = colors.inkSecondary.color
        surface = colors.surface.color
        normal = colors.statusNormal.color
        stroke = metrics.chartStroke
        point = metrics.chartPointDiameter
        ring = metrics.chartRingDiameter
        barWidth = metrics.chartThinBarWidth
        barRadius = metrics.chartThinBarRadius
        bandOpacity = metrics.chartBandOpacity
        fillOpacity = metrics.chartFillOpacity
        contextOpacity = metrics.chartContextBarOpacity
    }

    /// A hairline across the plot at `y`.
    public func gridline(_ context: GraphicsContext, y: CGFloat, from x0: CGFloat = 0, to x1: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y))
        path.addLine(to: CGPoint(x: x1, y: y))
        context.stroke(path, with: .color(grid), lineWidth: 0.5)
    }

    /// A vertical hairline, for an hour or a now.
    public func vertical(_ context: GraphicsContext, x: CGFloat, height: CGFloat, color: Color? = nil, dashed: Bool = false) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: height))
        context.stroke(path, with: .color(color ?? grid),
                       style: StrokeStyle(lineWidth: color == nil ? 0.5 : 1, dash: dashed ? [2, 3] : []))
    }

    /// The normal range as a faint band, in the status green unless told.
    public func band(_ context: GraphicsContext, top: CGFloat, bottom: CGFloat, in plot: CGRect, color: Color? = nil) {
        let rect = CGRect(x: plot.minX, y: min(top, bottom), width: plot.width, height: max(abs(bottom - top), 1))
        context.fill(Path(rect), with: .color((color ?? normal).opacity(bandOpacity)))
    }

    /// A band that moves point by point, upper and lower edge each a line.
    public func band(_ context: GraphicsContext, upper: [CGPoint], lower: [CGPoint], color: Color? = nil) {
        guard upper.count >= 2, upper.count == lower.count else { return }
        var path = Path()
        path.addLines(upper)
        for point in lower.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        context.fill(path, with: .color((color ?? normal).opacity(bandOpacity)))
    }

    /// A dashed rule, the average or a limit.
    public func rule(_ context: GraphicsContext, y: CGFloat, in plot: CGRect, color: Color? = nil) {
        var path = Path()
        path.move(to: CGPoint(x: plot.minX, y: y))
        path.addLine(to: CGPoint(x: plot.maxX, y: y))
        context.stroke(path, with: .color((color ?? inkSecondary).opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    /// A line through the points, broken where a point is missing.
    public func line(_ context: GraphicsContext, _ points: [CGPoint?], color: Color, dashed: Bool = false, width: CGFloat? = nil) {
        var path = Path()
        var open = false
        for point in points {
            guard let point else { open = false; continue }
            if open { path.addLine(to: point) } else { path.move(to: point); open = true }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(
            lineWidth: width ?? stroke, lineCap: .round, lineJoin: .round, dash: dashed ? [3, 4] : []
        ))
    }

    /// The soft fill under a line, fading to nothing at `floor`: the one
    /// gradient a chart is allowed.
    public func fill(_ context: GraphicsContext, _ points: [CGPoint?], floor: CGFloat, color: Color) {
        var runs: [[CGPoint]] = [[]]
        for point in points {
            if let point { runs[runs.count - 1].append(point) } else if !(runs.last?.isEmpty ?? true) { runs.append([]) }
        }
        let top = points.compactMap { $0?.y }.min() ?? 0
        for run in runs where run.count >= 2 {
            var path = Path()
            path.move(to: CGPoint(x: run[0].x, y: floor))
            path.addLines(run)
            path.addLine(to: CGPoint(x: run[run.count - 1].x, y: floor))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(
                Gradient(colors: [color.opacity(fillOpacity), color.opacity(0)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: floor)
            ))
        }
    }

    /// A small hollow dot on a value.
    public func dot(_ context: GraphicsContext, at centre: CGPoint, color: Color, filled: Bool = false) {
        let rect = CGRect(x: centre.x - point / 2, y: centre.y - point / 2, width: point, height: point)
        context.fill(Path(ellipseIn: rect), with: .color(filled ? color : surface))
        context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(color), lineWidth: 1.2)
    }

    /// The ring that ends a line: the latest value, hollow.
    public func ring(_ context: GraphicsContext, at centre: CGPoint, color: Color) {
        let rect = CGRect(x: centre.x - ring / 2, y: centre.y - ring / 2, width: ring, height: ring)
        context.fill(Path(ellipseIn: rect), with: .color(surface))
        context.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(color), lineWidth: 2)
    }

    /// A thin bar standing on `floor`, its top end rounded a little.
    public func bar(_ context: GraphicsContext, x: CGFloat, top: CGFloat, floor: CGFloat, pitch: CGFloat, color: Color) {
        let width = barWidth(pitch: pitch)
        let height = max(floor - top, 1)
        let rect = CGRect(x: x - width / 2, y: floor - height, width: width, height: height)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: min(barRadius, height / 2), topTrailingRadius: min(barRadius, height / 2), style: .continuous
        )
        context.fill(shape.path(in: rect), with: .color(color))
    }

    /// A bar from one value to another, a pressure reading say.
    public func span(_ context: GraphicsContext, x: CGFloat, top: CGFloat, bottom: CGFloat, pitch: CGFloat, color: Color) {
        let width = barWidth(pitch: pitch)
        let rect = CGRect(x: x - width / 2, y: min(top, bottom), width: width, height: max(abs(bottom - top), width))
        context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
    }

    /// Thin, whatever the room: half the pitch at most.
    public func barWidth(pitch: CGFloat) -> CGFloat {
        max(1.5, min(barWidth, pitch * 0.5))
    }
}

// MARK: - The frame

/// A chart in the house style: the plot with its hairline grid, the scale on
/// the trailing edge and the labels under it. The caller draws its marks in
/// `draw` with the space and the pen.
///
/// With no scale (nothing measured yet) the grid still stands, so the card
/// keeps its shape and the dash in the headline says why.
public struct SomaPlot: View {
    /// A word over the plot at a share of the way across: a window's name, a
    /// workout, marked over the day.
    public struct Mark: Sendable, Hashable {
        public let fraction: Double
        public let label: String

        public init(fraction: Double, label: String) {
            self.fraction = fraction
            self.label = label
        }
    }

    private let scale: SomaPlotScale?
    private let marks: [Mark]
    private let xLabels: [String]
    private let labelsUnderBars: Bool
    private let height: CGFloat?
    private let showsScale: Bool
    private let label: (@Sendable (Double) -> String)?
    private let draw: (GraphicsContext, SomaPlotSpace, SomaPen) -> Void

    @Environment(\.somaTheme) private var theme

    public init(
        scale: SomaPlotScale?,
        marks: [Mark] = [],
        xLabels: [String] = [],
        labelsUnderBars: Bool = false,
        height: CGFloat? = nil,
        showsScale: Bool = true,
        label: (@Sendable (Double) -> String)? = nil,
        draw: @escaping (GraphicsContext, SomaPlotSpace, SomaPen) -> Void
    ) {
        self.scale = scale
        self.marks = marks
        self.xLabels = xLabels
        self.labelsUnderBars = labelsUnderBars
        self.height = height
        self.showsScale = showsScale
        self.label = label
        self.draw = draw
    }

    public var body: some View {
        let metrics = theme.metrics
        let plotHeight = height ?? metrics.chartPlotHeight
        let inset = metrics.chartPlotInset
        let pen = SomaPen(theme)
        let scale = scale
        let draw = draw

        HStack(alignment: .top, spacing: metrics.chartLabelGap) {
            VStack(spacing: metrics.chartLabelGap) {
                if !marks.isEmpty {
                    GeometryReader { proxy in
                        let width = proxy.size.width - inset * 2
                        ForEach(marks, id: \.self) { mark in
                            Text(verbatim: mark.label)
                                .lineLimit(1)
                                .fixedSize()
                                .offset(x: inset + width * CGFloat(min(max(mark.fraction, 0), 1)))
                        }
                    }
                    .frame(height: metrics.chartPlotInset * 3)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .accessibilityHidden(true)
                }
                Canvas { context, size in
                    let domain = scale?.domain ?? 0...1
                    let space = SomaPlotSpace(size: size, domain: domain, inset: inset)
                    let ticks = scale?.ticks ?? [0, 0.5, 1]
                    for tick in ticks {
                        pen.gridline(context, y: space.y(tick), to: size.width)
                    }
                    guard scale != nil else { return }
                    draw(context, space, pen)
                }
                .frame(height: plotHeight)

                if !xLabels.isEmpty {
                    if labelsUnderBars {
                        HStack(spacing: 0) {
                            ForEach(Array(xLabels.enumerated()), id: \.offset) { _, label in
                                Text(verbatim: label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .padding(.horizontal, inset)
                        .accessibilityHidden(true)
                    } else {
                        SomaAxisLabels(xLabels)
                            .padding(.horizontal, inset)
                    }
                }
            }

            if showsScale, let scale {
                ZStack(alignment: .leading) {
                    ForEach(scale.ticks, id: \.self) { tick in
                        Text(verbatim: label?(tick) ?? scale.label(tick))
                            .fixedSize()
                            .offset(y: offset(of: tick, in: scale, height: plotHeight, inset: inset))
                    }
                }
                .frame(height: plotHeight)
                .padding(.top, marks.isEmpty ? 0 : metrics.chartPlotInset * 3 + metrics.chartLabelGap)
                .somaFont(theme.typography.captionValue)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .accessibilityHidden(true)
            }
        }
    }

    /// From the column's centre to the tick's hairline.
    private func offset(of tick: Double, in scale: SomaPlotScale, height: CGFloat, inset: CGFloat) -> CGFloat {
        let space = SomaPlotSpace(size: CGSize(width: inset * 4, height: height), domain: scale.domain, inset: inset)
        return space.y(tick) - height / 2
    }
}

/// Labels spread under a plot: the first on the leading edge, the last on the
/// trailing one, the rest evenly between.
public struct SomaAxisLabels: View {
    private let labels: [String]

    @Environment(\.somaTheme) private var theme

    public init(_ labels: [String]) {
        self.labels = labels
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if index > 0 { Spacer(minLength: 2) }
                Text(verbatim: label)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .somaFont(theme.typography.captionValue)
        .foregroundStyle(theme.colors.inkSecondary.color)
        .accessibilityHidden(true)
    }
}

// MARK: - Hypnogram

/// The four stages of sleep, awake at the top of a hypnogram and deep at its
/// foot.
public enum SomaSleepStage: Int, CaseIterable, Sendable {
    case awake, rem, core, deep

    public var title: LocalizedStringResource {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        }
    }

    /// The stage's own colour, from the theme's sleep stage palette: a warm
    /// awake over three asleep shades that darken with depth.
    public func color(_ theme: SomaTheme) -> Color {
        let palette = theme.colors.sleepStages
        return switch self {
        case .awake: palette.awake.color
        case .rem: palette.rem.color
        case .core: palette.core.color
        case .deep: palette.deep.color
        }
    }

    /// The stage named the way HealthKit's export and the scoring engine
    /// name it; light and unspecified sleep read as core.
    public init?(name: String) {
        switch name.lowercased() {
        case "awake", "inbed": self = .awake
        case "rem": self = .rem
        case "core", "asleep", "light", "unspecified", "asleepunspecified": self = .core
        case "deep": self = .deep
        default: return nil
        }
    }
}

/// One stretch of one stage.
public struct SomaStageRun: Sendable, Hashable {
    public let stage: SomaSleepStage
    public let start: Date
    public let end: Date

    public init(stage: SomaSleepStage, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }
}

/// A night drawn as a lane per stage, awake on top and deep
/// at the foot, each stretch a rounded block in its stage's colour, and a thin
/// line joining one stretch to the next that fades from one colour into the
/// other, over a faint grid.
///
/// Two ways to label it: clock labels spread under the plot with the lanes
/// named on the trailing edge, or, where it is the card's subject, the bedtime
/// under a moon on the leading edge and the wake time under a sun on the
/// trailing one, the lanes left to the stage colours.
public struct SomaHypnogram: View {
    private let runs: [SomaStageRun]
    private let xLabels: [String]
    private let laneHeight: CGFloat?
    private let ends: (bed: String, wake: String)?
    private let showsLaneTitles: Bool

    @Environment(\.somaTheme) private var theme

    /// Clock labels under the plot and the lane names beside it.
    public init(runs: [SomaStageRun], xLabels: [String] = [], laneHeight: CGFloat? = nil) {
        self.runs = runs.sorted { $0.start < $1.start }
        self.xLabels = xLabels
        self.laneHeight = laneHeight
        self.ends = nil
        self.showsLaneTitles = true
    }

    /// Full width, the night's two ends under it: bed under a moon, wake under
    /// a sun. A missing time reads as a dash.
    public init(runs: [SomaStageRun], bed: String?, wake: String?, laneHeight: CGFloat? = nil) {
        self.runs = runs.sorted { $0.start < $1.start }
        self.xLabels = []
        self.laneHeight = laneHeight
        self.ends = (bed ?? "-", wake ?? "-")
        self.showsLaneTitles = false
    }

    public var body: some View {
        let metrics = theme.metrics
        let lane = laneHeight ?? (ends == nil ? metrics.hypnogramLaneHeight : metrics.hypnogramTallLaneHeight)

        HStack(alignment: .top, spacing: metrics.chartLabelGap) {
            VStack(spacing: metrics.chartLabelGap) {
                plot(lane: lane)
                    .frame(height: lane * CGFloat(SomaSleepStage.allCases.count))

                if let ends {
                    HStack {
                        endChip(symbol: "moon.fill", time: ends.bed)
                        Spacer(minLength: metrics.chartLabelGap)
                        endChip(symbol: "sun.max.fill", time: ends.wake)
                    }
                    .accessibilityHidden(true)
                } else if !xLabels.isEmpty {
                    SomaAxisLabels(xLabels)
                }
            }

            if showsLaneTitles {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SomaSleepStage.allCases, id: \.self) { stage in
                        Text(stage.title)
                            .frame(height: lane)
                    }
                }
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .fixedSize()
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages"))
        .accessibilityValue(Text(summary))
    }

    private func plot(lane: CGFloat) -> some View {
        let metrics = theme.metrics
        let lanes = SomaSleepStage.allCases
        let pen = SomaPen(theme)
        let shades = Dictionary(uniqueKeysWithValues: lanes.map { ($0, $0.color(theme)) })
        let runs = runs
        let block = lane * metrics.hypnogramBlockShare
        let radius = metrics.hypnogramBlockRadius
        let connector = metrics.hypnogramConnectorWidth

        return Canvas { context, size in
            for index in 0...lanes.count {
                let y = index == lanes.count ? size.height - 0.25 : CGFloat(index) * lane + 0.25
                pen.gridline(context, y: y, to: size.width)
            }
            guard let first = runs.first?.start, let last = runs.map(\.end).max() else { return }
            let span = max(last.timeIntervalSince(first), 1)
            func x(_ date: Date) -> CGFloat { size.width * CGFloat(date.timeIntervalSince(first) / span) }
            func mid(_ stage: SomaSleepStage) -> CGFloat { lane * (CGFloat(stage.rawValue) + 0.5) }

            // The joins first, so the blocks sit on top of them. Each runs from
            // the middle of one block to the middle of the next and fades from
            // the first stage's colour into the second's.
            for (previous, next) in zip(runs, runs.dropFirst()) where previous.stage != next.stage {
                guard next.start.timeIntervalSince(previous.end) < 120 else { continue }
                let stepX = min(max(x(next.start), connector / 2), size.width - connector / 2)
                let from = CGPoint(x: stepX, y: mid(previous.stage))
                let to = CGPoint(x: stepX, y: mid(next.stage))
                var step = Path()
                step.move(to: from)
                step.addLine(to: to)
                let colors = [shades[previous.stage, default: pen.inkSecondary], shades[next.stage, default: pen.inkSecondary]]
                context.stroke(step, with: .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to),
                               lineWidth: connector)
            }
            for run in runs {
                let x0 = x(run.start)
                let width = max(x(run.end) - x0, connector * 2)
                let rect = CGRect(x: x0, y: mid(run.stage) - block / 2, width: width, height: block)
                context.fill(Path(roundedRect: rect, cornerRadius: min(radius, width / 2), style: .continuous),
                             with: .color(shades[run.stage, default: pen.inkSecondary]))
            }
        }
    }

    private func endChip(symbol: String, time: String) -> some View {
        let metrics = theme.metrics
        return HStack(spacing: metrics.hypnogramEndPadding / 2) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(verbatim: time)
        }
        .somaFont(theme.typography.captionValue)
        .foregroundStyle(theme.colors.inkPrimary.color)
        .padding(.horizontal, metrics.hypnogramEndPadding)
        .padding(.vertical, metrics.hypnogramEndPadding / 2)
        .background(
            RoundedRectangle(cornerRadius: metrics.hypnogramBlockRadius, style: .continuous)
                .fill(theme.colors.surfaceRecessed.color)
        )
        .fixedSize()
    }

    private var summary: String {
        let minutes = Dictionary(grouping: runs, by: \.stage).mapValues { stretch in
            Int(stretch.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        }
        let stages = SomaSleepStage.allCases.compactMap { stage in
            minutes[stage].map { "\(String(localized: stage.title)) \($0) min" }
        }.joined(separator: ", ")
        guard let ends else { return stages }
        return "\(ends.bed) to \(ends.wake). " + stages
    }
}

#Preview("Plot and hypnogram") {
    let values: [Double?] = [61, 63, 60, nil, 58, 59, 62, 64, 61, 60, 58, 57]
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let stages: [SomaSleepStage] = [.awake, .core, .deep, .core, .rem, .core, .deep, .core, .awake, .rem, .core, .rem, .awake]
    let runs = stages.enumerated().map { index, stage in
        SomaStageRun(stage: stage, start: start + Double(index) * 2_100, end: start + Double(index + 1) * 2_100)
    }
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 16) {
            SomaCard {
                SomaPlot(scale: SomaPlotScale(values: values.compactMap { $0 }, including: [57, 63]),
                         xLabels: ["Sep 2", "Sep 9", "Sep 17", "Sep 24"]) { context, space, pen in
                    let points = values.enumerated().map { index, value in
                        value.map { CGPoint(x: space.x(index, of: values.count), y: space.y($0)) }
                    }
                    pen.band(context, top: space.y(63), bottom: space.y(57), in: space.plot)
                    pen.line(context, points, color: pen.normal)
                    for point in points.compactMap({ $0 }).dropLast() { pen.dot(context, at: point, color: pen.normal) }
                    if let last = points.compactMap({ $0 }).last { pen.ring(context, at: last, color: pen.normal) }
                }
            }
            SomaCard {
                SomaHypnogram(runs: runs, xLabels: ["23:34", "06:39"])
            }
            SomaCard {
                SomaHypnogram(runs: runs, bed: "23:34", wake: "06:39")
            }
        }
        .padding()
    }
}
