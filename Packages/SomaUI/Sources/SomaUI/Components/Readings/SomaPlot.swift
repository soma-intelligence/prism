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

/// Which part of a ``SomaPlot`` draws. A pager draws the plot on its pages
/// and the scale once, held still over them, so the numbers never slide
/// into the middle with a page (owner, 2026-10-24). Both keep the same
/// layout, so the held scale sits on the pages' gridlines.
public enum SomaPlotPart: Sendable {
    case all
    /// The grid, the marks and the labels under them; the scale's room kept
    /// but empty.
    case plot
    /// The scale alone, in the place the whole plot would put it.
    case scale
}

private struct SomaPlotPartKey: EnvironmentKey {
    static let defaultValue: SomaPlotPart = .all
}

public extension EnvironmentValues {
    var somaPlotPart: SomaPlotPart {
        get { self[SomaPlotPartKey.self] }
        set { self[SomaPlotPartKey.self] = newValue }
    }
}

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
    @Environment(\.somaPlotPart) private var part

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

        HStack(alignment: .plotTop, spacing: metrics.chartLabelGap) {
            VStack(spacing: metrics.chartLabelGap) {
                if !marks.isEmpty {
                    // Labels that would touch drop to the next line rather
                    // than overlap, so the strip grows a line per crowd.
                    SomaPlotMarkLanes(fractions: marks.map(\.fraction), inset: inset, gap: metrics.chartLabelGap) {
                        ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                            Text(verbatim: mark.label)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .frame(minHeight: metrics.chartPlotInset * 3, alignment: .bottom)
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
                .alignmentGuide(.plotTop) { $0[.top] }
                .opacity(part == .scale ? 0 : 1)

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
            .opacity(part == .scale ? 0 : 1)

            if showsScale, let scale {
                ZStack(alignment: .leading) {
                    ForEach(scale.ticks, id: \.self) { tick in
                        Text(verbatim: label?(tick) ?? scale.label(tick))
                            .fixedSize()
                            .offset(y: offset(of: tick, in: scale, height: plotHeight, inset: inset))
                    }
                }
                .frame(height: plotHeight)
                .alignmentGuide(.plotTop) { $0[.top] }
                .somaFont(theme.typography.captionValue)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .opacity(part == .plot ? 0 : 1)
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

extension VerticalAlignment {
    /// The top of a plot's drawing area, so the scale beside it lines up
    /// with the plot however tall the mark labels above it grow.
    private enum PlotTop: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
    }

    static let plotTop = VerticalAlignment(PlotTop.self)
}

/// The words over a plot, each at its share of the way across. A word that
/// would touch the one before it on a line drops to the next line, so two
/// meals an hour apart read as two words, never as one smudge.
struct SomaPlotMarkLanes: Layout {
    let fractions: [Double]
    let inset: CGFloat
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let (_, lanes) = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: height(lanes: lanes, subviews: subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (starts, lanes) = arrange(width: bounds.width, subviews: subviews)
        let line = lineHeight(subviews)
        let used = (lanes.max() ?? 0) + 1
        for (index, subview) in subviews.enumerated() {
            // The first line sits nearest the plot; later ones stack above.
            let row = CGFloat(used - 1 - lanes[index])
            subview.place(at: CGPoint(x: bounds.minX + starts[index], y: bounds.minY + row * line),
                          proposal: .unspecified)
        }
    }

    /// Where each word starts, kept inside the strip, and its line.
    private func arrange(width: CGFloat, subviews: Subviews) -> ([CGFloat], [Int]) {
        let span = max(width - inset * 2, 0)
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let starts = zip(fractions, widths).map { fraction, word in
            min(inset + span * CGFloat(min(max(fraction, 0), 1)), max(width - word, 0))
        }
        return (starts, Self.lanes(starts: starts, widths: widths, gap: gap))
    }

    private func lineHeight(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
    }

    private func height(lanes: [Int], subviews: Subviews) -> CGFloat {
        guard let last = lanes.max() else { return 0 }
        return CGFloat(last + 1) * lineHeight(subviews)
    }

    /// The line each word takes, in reading order: the first line it fits
    /// on, a gap clear of the word already there, or a new line under the
    /// rest. Pure, so the rule is tested without drawing.
    ///
    /// - Parameters:
    ///   - starts: where each word begins, in points.
    ///   - widths: how wide each word is.
    /// - Returns: a line per word, 0 the first.
    static func lanes(starts: [CGFloat], widths: [CGFloat], gap: CGFloat) -> [Int] {
        var ends: [CGFloat] = []
        var lanes = Array(repeating: 0, count: starts.count)
        for index in starts.indices.sorted(by: { starts[$0] < starts[$1] }) {
            let start = starts[index]
            let end = start + (index < widths.count ? widths[index] : 0)
            if let free = ends.firstIndex(where: { $0 + gap <= start }) {
                lanes[index] = free
                ends[free] = end
            } else {
                lanes[index] = ends.count
                ends.append(end)
            }
        }
        return lanes
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
    private let ends: (bed: String?, wake: String?)?
    private let showsLaneTitles: Bool
    private let bleeds: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Where the finger reads the night, 0 to 1 by time. Nil when not
    /// reading.
    @State private var scrub: CGFloat?
    /// Latched once a drag reads as a vertical scroll, so the page keeps it.
    @State private var scrubIsScroll = false

    /// Clock labels under the plot and the lane names beside it, unless
    /// `laneTitles` is off, for a strip too small to carry them.
    public init(runs: [SomaStageRun], xLabels: [String] = [], laneHeight: CGFloat? = nil, laneTitles: Bool = true) {
        self.runs = runs.sorted { $0.start < $1.start }
        self.xLabels = xLabels
        self.laneHeight = laneHeight
        self.ends = nil
        self.showsLaneTitles = laneTitles
        self.bleeds = false
    }

    /// Full width, the night's two ends under it: bed under a moon, wake under
    /// a sun. A missing time is the drawn missing mark.
    public init(runs: [SomaStageRun], bed: String?, wake: String?, laneHeight: CGFloat? = nil) {
        self.runs = runs.sorted { $0.start < $1.start }
        self.xLabels = []
        self.laneHeight = laneHeight
        self.ends = (bed, wake)
        self.showsLaneTitles = false
        self.bleeds = false
    }

    /// The night leading a page, the way the earlier app's sleep sheet led
    /// with it: full bleed on the night's sky, no card, no lane names and no
    /// axis, ringed blocks and hairline seams, read with a sideways drag.
    /// The page gives the bed and wake times elsewhere.
    public init(fullBleed runs: [SomaStageRun]) {
        self.runs = runs.sorted { $0.start < $1.start }
        self.xLabels = []
        self.laneHeight = nil
        self.ends = nil
        self.showsLaneTitles = false
        self.bleeds = true
    }

    public var body: some View {
        let metrics = theme.metrics
        let lane = laneHeight ?? (ends == nil ? metrics.hypnogramLaneHeight : metrics.hypnogramTallLaneHeight)

        if bleeds {
            SomaBleedNight(runs: runs)
        } else if let ends {
            night(lane: lane, ends: ends)
        } else {
            compact(lane: lane)
        }
    }

    // MARK: The night, as a card's subject

    /// The night as one chart, after the earlier app's: each lane named on the leading
    /// edge with the time spent in it, slim blocks joined by fine steps, the
    /// clock under it from bed to wake, and a readout over it that a
    /// sideways drag turns into the stage and time under the finger, the
    /// block there lit and the others dimmed.
    private func night(lane: CGFloat, ends: (bed: String?, wake: String?)) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let read = scrub.flatMap { reading(at: $0) }

        return VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            // The readout: the night's span at rest, the stage under the
            // finger while reading.
            HStack(alignment: .firstTextBaseline, spacing: metrics.spaceS) {
                if let read {
                    Circle().fill(read.stage.color(theme)).frame(width: 8, height: 8)
                    Text(read.stage.title)
                        .somaFont(type.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Text(verbatim: Self.clock(read.date))
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                } else {
                    Text("Stages")
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                Spacer(minLength: 0)
            }
            .frame(height: type.cardTitle.size * 1.4)
            .animation(reduceMotion ? nil : theme.motion.quick, value: read?.stage)

            // A copy of the earlier app's night chart (owner, 2026-10-24): the lanes
            // named against an axis on the left, tall blocks ringed in a
            // dark shade of their colour, and links that carry that ring
            // from one block to the next as one outline.
            let gutter = metrics.hypnogramLaneLabelWidth
            let height = lane * CGFloat(SomaSleepStage.allCases.count)
            VStack(spacing: metrics.chartLabelGap) {
                GeometryReader { proxy in
                    let layout = NightLayout(runs: runs, size: CGSize(width: proxy.size.width, height: height),
                                             lane: lane, gutter: gutter, metrics: metrics)
                    ZStack(alignment: .topLeading) {
                        nightChart(layout, lit: read?.run)

                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(SomaSleepStage.allCases, id: \.self) { stage in
                                Text(stage.title)
                                    .somaFont(type.caption)
                                    .foregroundStyle(colors.inkSecondary.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.trailing, metrics.spaceXS)
                                    .frame(width: gutter, height: lane, alignment: .topTrailing)
                            }
                        }
                        .accessibilityHidden(true)

                        if let scrub {
                            Rectangle()
                                .fill(colors.inkPrimary.color.opacity(0.5))
                                .frame(width: 1)
                                .offset(x: layout.plotX + scrub * layout.plotWidth)
                        }
                    }
                    .contentShape(.rect)
                    .simultaneousGesture(scrubGesture(width: proxy.size.width, gutter: layout.plotX))
                }
                .frame(height: height)

                // Bed under the night's first edge, wake under its last.
                HStack {
                    SomaNumber(ends.bed, type.captionValue)
                    Spacer(minLength: 0)
                    SomaNumber(ends.wake, type.captionValue)
                }
                .foregroundStyle(colors.inkSecondary.color)
                .padding(.leading, gutter)
                .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: read?.run)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages"))
        .accessibilityValue(Text(summary))
    }

    /// The stretch, stage and moment under the finger.
    private struct Reading: Equatable {
        let run: Int
        let stage: SomaSleepStage
        let date: Date
    }

    private func reading(at share: CGFloat) -> Reading? {
        guard let first = runs.first?.start, let last = runs.map(\.end).max() else { return nil }
        let date = first.addingTimeInterval(last.timeIntervalSince(first) * Double(min(max(share, 0), 1)))
        guard let index = runs.lastIndex(where: { $0.start <= date }) else { return nil }
        return Reading(run: index, stage: runs[index].stage, date: date)
    }

    private func scrubGesture(width: CGFloat, gutter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !scrubIsScroll else { return }
                if scrub == nil, abs(value.translation.height) > abs(value.translation.width) {
                    scrubIsScroll = true
                    return
                }
                scrub = min(max((value.location.x - gutter) / max(width - gutter, 1), 0), 1)
            }
            .onEnded { _ in
                scrub = nil
                scrubIsScroll = false
            }
    }

    /// 23:40, on the 24 hour clock whatever the locale, the way the bed and
    /// wake times beside it are written. A format style with the hour's
    /// day period left out still counts to twelve in a 12 hour locale, which
    /// put a 18:21 sunset at 06:21.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: Compact, among other readings

    private func compact(lane: CGFloat) -> some View {
        let metrics = theme.metrics

        return HStack(alignment: .top, spacing: metrics.chartLabelGap) {
            VStack(spacing: metrics.chartLabelGap) {
                plot(lane: lane)
                    .frame(height: lane * CGFloat(SomaSleepStage.allCases.count))

                if !xLabels.isEmpty {
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

    /// The compact strip's canvas.
    private func plot(lane: CGFloat) -> some View {
        let pen = SomaPen(theme)
        let shades = Dictionary(uniqueKeysWithValues: SomaSleepStage.allCases.map { ($0, $0.color(theme)) })
        let runs = runs
        return Canvas { context, size in
            compactPlot(context, size: size, lane: lane, pen: pen, shades: shades, runs: runs)
        }
    }

    /// Where everything on the night chart sits.
    private struct NightLayout {
        struct Block {
            let index: Int
            let stage: SomaSleepStage
            let rect: CGRect
        }

        /// A link: a line in the rims' shade from the middle of one block to
        /// the middle of the next, standing in the gap between them and
        /// passing behind both, as the earlier app draws it.
        struct Link {
            let upper: SomaSleepStage
            let lower: SomaSleepStage
            let rect: CGRect
        }

        let size: CGSize
        let axisX: CGFloat
        let plotX: CGFloat
        let plotWidth: CGFloat
        let blocks: [Block]
        let links: [Link]

        init(runs: [SomaStageRun], size: CGSize, lane: CGFloat, gutter: CGFloat, metrics: SomaMetrics) {
            self.size = size
            axisX = gutter
            plotX = gutter + metrics.hypnogramPlotInset
            plotWidth = max(size.width - plotX - metrics.hypnogramPlotInset, 1)
            guard let first = runs.first?.start, let last = runs.map(\.end).max() else {
                blocks = []; links = []
                return
            }
            let span = max(last.timeIntervalSince(first), 1)
            let plotX = plotX, plotWidth = plotWidth
            func x(_ date: Date) -> CGFloat { plotX + plotWidth * CGFloat(date.timeIntervalSince(first) / span) }
            func mid(_ stage: SomaSleepStage) -> CGFloat { lane * (CGFloat(stage.rawValue) + 0.5) }
            let height = lane * metrics.hypnogramNightBlockShare
            let minimum = metrics.hypnogramNightMinBlockWidth

            // A block never starts inside the one before it, which a short
            // run widened to the minimum would otherwise reach into, and two
            // blocks in a row keep a gap between them for the link to stand
            // in.
            var blocks: [Block] = []
            var reach = -CGFloat.infinity
            for (index, run) in runs.enumerated() {
                // A short gap to the stretch before is closed, so the two
                // blocks meet on one seam.
                let closes = index > 0 && run.start.timeIntervalSince(runs[index - 1].end) < 120
                let x0 = closes ? reach : max(x(run.start), reach)
                let width = max(x(run.end) - x0, minimum)
                reach = x0 + width
                let gap = metrics.hypnogramNightBlockGap / 2
                blocks.append(Block(index: index, stage: run.stage,
                                    rect: CGRect(x: x0 + gap, y: mid(run.stage) - height / 2,
                                                 width: max(width - gap * 2, 2), height: height)))
            }
            var links: [Link] = []
            for index in blocks.indices.dropFirst() {
                let previous = runs[index - 1], next = runs[index]
                guard previous.stage != next.stage, next.start.timeIntervalSince(previous.end) < 120 else { continue }
                let goingDown = next.stage.rawValue > previous.stage.rawValue
                let upper = blocks[goingDown ? index - 1 : index]
                let lower = blocks[goingDown ? index : index - 1]
                // In the seam between the two blocks, from the middle of the
                // upper to the middle of the lower, so the line touches both
                // sides and never hangs under one block into empty lane, as
                // the reference design draws it (owner, 2026-10-25: the stalk out of the
                // block's foot read as broken).
                let seam = (blocks[index - 1].rect.maxX + blocks[index].rect.minX) / 2
                let width = metrics.hypnogramLinkWidth
                links.append(Link(upper: upper.stage, lower: lower.stage,
                                  rect: CGRect(x: seam - width / 2, y: upper.rect.midY,
                                               width: width, height: lower.rect.midY - upper.rect.midY)))
            }
            self.blocks = blocks
            self.links = links
        }
    }

    /// The chart in one canvas: axes, links, then blocks, on the card's own
    /// ground (owner, 2026-10-24: no sky behind it).
    private func nightChart(_ layout: NightLayout, lit: Int?) -> some View {
        let metrics = theme.metrics
        let pen = SomaPen(theme)
        let dark = colorScheme == .dark
        let shades = Dictionary(uniqueKeysWithValues: SomaSleepStage.allCases.map { ($0, $0.color(theme)) })
        let fallback = theme.colors.inkSecondary.color
        // The shade a block is ringed in: its colour sunk most of the way
        // into the card, which gives the earlier app's slate, navy and brown rims, a
        // step lighter than the ground. The links are all in REM's, the earlier app's
        // slate, whatever they join.
        let ground = theme.colors.surface.color
        func rim(_ stage: SomaSleepStage) -> Color {
            dark ? shades[stage, default: fallback].mix(with: ground, by: metrics.hypnogramRimShade)
                : shades[stage, default: fallback].mix(with: .black, by: metrics.hypnogramRimShade * 0.6)
        }
        let linkShade = rim(.rem)
        return Canvas { context, size in
            // The axes: left and foot, a hairline on the right.
            var axes = Path()
            axes.move(to: CGPoint(x: layout.axisX + 0.5, y: 0))
            axes.addLine(to: CGPoint(x: layout.axisX + 0.5, y: size.height - 0.5))
            axes.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(axes, with: .color(pen.grid), lineWidth: 1)
            var right = Path()
            right.move(to: CGPoint(x: size.width - 0.5, y: 0))
            right.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
            context.stroke(right, with: .color(pen.grid.opacity(0.5)), lineWidth: 0.5)

            // The links first, behind everything, then the rims, then the
            // fills.
            let ring = metrics.hypnogramRimWidth
            func fill(_ stage: SomaSleepStage) -> Color { shades[stage, default: fallback] }
            func shape(_ rect: CGRect, corner: CGFloat) -> Path {
                Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
            }
            func isLit(_ index: Int) -> Bool { lit == nil || lit == index }

            for link in layout.links {
                context.fill(Path(link.rect), with: .color(linkShade))
            }
            for block in layout.blocks {
                let corner = min(metrics.hypnogramNightBlockRadius, block.rect.width / 2, block.rect.height / 2)
                context.fill(shape(block.rect, corner: corner),
                             with: .color(rim(block.stage).opacity(isLit(block.index) ? 1 : 0.4)))
            }
            for block in layout.blocks {
                let corner = min(metrics.hypnogramNightBlockRadius, block.rect.width / 2, block.rect.height / 2)
                let inner = block.rect.insetBy(dx: min(ring, block.rect.width / 4), dy: ring)
                let innerCorner = min(max(corner - ring, 2), inner.width / 2, inner.height / 2)
                context.fill(shape(inner, corner: innerCorner),
                             with: .color(fill(block.stage).opacity(isLit(block.index) ? 1 : 0.35)))
            }
        }
        .allowsHitTesting(false)
    }

    /// The compact strip among other readings: a faint grid, slim blocks and
    /// a hairline step between them.
    private func compactPlot(_ context: GraphicsContext, size: CGSize, lane: CGFloat, pen: SomaPen,
                             shades: [SomaSleepStage: Color], runs: [SomaStageRun]) {
        let metrics = theme.metrics
        let lanes = SomaSleepStage.allCases
        let block = lane * metrics.hypnogramBlockShare
        let radius = metrics.hypnogramBlockRadius
        let connector = metrics.hypnogramConnectorWidth

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
            context.fill(Path(roundedRect: rect, cornerRadius: min(radius, width / 2, block / 2), style: .continuous),
                         with: .color(shades[run.stage, default: pen.inkSecondary]))
        }
    }

    private var summary: String {
        let minutes = Dictionary(grouping: runs, by: \.stage).mapValues { stretch in
            Int(stretch.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        }
        let stages = SomaSleepStage.allCases.compactMap { stage in
            minutes[stage].map { "\(String(localized: stage.title)) \($0) min" }
        }.joined(separator: ", ")
        guard let ends else { return stages }
        let missing = SomaFormat.notMeasured
        return "\(ends.bed ?? missing) to \(ends.wake ?? missing). " + stages
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
