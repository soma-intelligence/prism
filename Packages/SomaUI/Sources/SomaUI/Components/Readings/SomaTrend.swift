//
//  SomaTrend.swift
//  SomaUI
//

import SwiftUI
import Charts

/// Where a reading sits against its normal range, as a status word.
public enum SomaReadingStatus: Sendable {
    case normal
    case above
    case below
    case alert(LocalizedStringResource)
    /// A direction rather than a judgement: "Increasing", "Stabilizing".
    case trend(LocalizedStringResource)
    /// A cue in the status word's place ("Highest in 30 days"), in the
    /// colour of where the reading sits: one line instead of two.
    case worded(LocalizedStringResource, SomaCueTone)
    /// No range to read it against yet.
    case none

    /// The status word: "Normal range", "Above normal".
    public var word: LocalizedStringResource? {
        switch self {
        case .normal: "Normal range"
        case .above: "Above normal"
        case .below: "Below normal"
        case .alert(let word), .trend(let word), .worded(let word, _): word
        case .none: nil
        }
    }

    var isNone: Bool {
        if case .none = self { return true }
        return false
    }

    public func color(_ colors: SomaColors) -> Color {
        switch self {
        case .normal: colors.statusNormal.color
        case .above, .below: colors.statusOut.color
        case .alert: colors.statusAlert.color
        case .trend, .none: colors.inkSecondary.color
        case .worded(_, let tone): tone.color(colors)
        }
    }
}

/// How a cue reads: good news, something to watch, or neither. It colours
/// the cue only where no status word already carries the colour.
public enum SomaCueTone: Sendable, Equatable {
    case good
    case watch
    case neutral

    public func color(_ colors: SomaColors) -> Color {
        switch self {
        case .good: colors.statusNormal.color
        case .watch: colors.statusOut.color
        case .neutral: colors.inkSecondary.color
        }
    }
}

// MARK: - Sparkline

/// A small line of recent values, drawn the way a metric's page draws its
/// chart (``SomaMetricChart``): the usual band as a quiet ground of ink, the
/// line bent through the known values in the metric's hue softened toward
/// grey, a fill that fades to nothing at the foot, and the latest value as a
/// dot in the full hue. Days without a reading are skipped, never drawn as
/// zero.
///
/// New values morph the line and the band into place on the theme's chart
/// spring rather than redrawing them; under Reduce Motion they swap.
public struct SomaSparkline: View {
    private let values: [Double?]
    private let tint: Color?
    private let band: ClosedRange<Double>?
    private let filled: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter filled: the soft fill under the line; false draws the
    ///   line alone.
    public init(_ values: [Double?], tint: Color? = nil, band: ClosedRange<Double>? = nil, filled: Bool = true) {
        self.values = values
        self.tint = tint
        self.band = band
        self.filled = filled
    }

    public var body: some View {
        let shape = SomaSparkShape.make(values, band: band, samples: theme.metrics.sparkSamples)
        SomaSparkPlot(shape: shape, tint: tint, filled: filled)
            .animation(reduceMotion ? nil : theme.motion.chartMorph, value: shape)
            .accessibilityHidden(true)
    }
}

/// A sparkline's shape as shares of its frame, apart from any size, so it
/// can be interpolated from one set of values to the next.
struct SomaSparkShape: Equatable, Sendable {
    /// The line's heights, 0 at the foot and 1 at the top, evenly spaced
    /// across the width. Empty with fewer than two readings.
    var samples: [Double]
    /// The usual band's foot and top, as shares; equal when there is none.
    var bandLow: Double
    var bandHigh: Double
    var hasBand: Bool
    /// One reading alone: drawn as its dot at the latest end.
    var isSingle: Bool

    /// - Parameter samples: how many points the line is drawn with; the
    ///   same for every sparkline, so any two interpolate point for point.
    static func make(_ values: [Double?], band: ClosedRange<Double>?, samples count: Int) -> SomaSparkShape {
        // A trend this small reads as one continuous line: a week with two
        // readings would otherwise be two stray strokes.
        let numbers = values.compactMap { $0 }
        guard numbers.count > 1 else {
            return SomaSparkShape(samples: [], bandLow: 0, bandHigh: 0, hasBand: false, isSingle: numbers.count == 1)
        }
        let all = numbers + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let low = all.min() ?? 0
        let high = all.max() ?? 1
        let pad = max((high - low) * 0.14, abs(high) * 0.002, 0.0001)
        let domain = (low - pad)...(high + pad)
        let curve = SomaChartMath.curve(numbers.map { Optional($0) }, domain: domain, count: count)
        return SomaSparkShape(
            samples: curve.samples,
            bandLow: band.map { SomaChartMath.height($0.lowerBound, in: domain) } ?? 0,
            bandHigh: band.map { SomaChartMath.height($0.upperBound, in: domain) } ?? 0,
            hasBand: band != nil,
            isSingle: false
        )
    }
}

/// The drawing behind ``SomaSparkline``: the band, the fill, the line and
/// the end dot are shapes over one ``SomaSparkShape``, so each is handed
/// every step between two shapes.
private struct SomaSparkPlot: View {
    let shape: SomaSparkShape
    let tint: Color?
    let filled: Bool

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = tint ?? colors.inkPrimary.color
        let line = hue.mix(with: colors.inkSecondary.color, by: metrics.sparkLineMix)
        let ground = colors.inkPrimary.color.opacity(metrics.metricChartBandOpacity * 1.4)
        let dot = metrics.sparkEndDot
        let inset = dot / 2 + 1

        ZStack {
            if shape.isSingle {
                // One reading: its dot alone, at the latest end.
                GeometryReader { proxy in
                    Circle()
                        .fill(hue)
                        .frame(width: dot, height: dot)
                        .position(x: proxy.size.width - dot, y: proxy.size.height / 2)
                }
            } else if shape.samples.count > 1 {
                if shape.hasBand {
                    SomaSparkPath(shape: shape, part: .band, inset: inset)
                        .fill(ground)
                }
                if filled {
                    SomaSparkPath(shape: shape, part: .area, inset: inset)
                        .fill(LinearGradient(colors: [hue.opacity(metrics.metricChartFillOpacity), hue.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                }
                SomaSparkPath(shape: shape, part: .line, inset: inset)
                    .stroke(line, style: StrokeStyle(lineWidth: metrics.sparkLine, lineCap: .round, lineJoin: .round))
                SomaSparkPath(shape: shape, part: .end(dot + 3), inset: inset)
                    .fill(colors.surface.color)
                SomaSparkPath(shape: shape, part: .end(dot), inset: inset)
                    .fill(hue)
            }
        }
    }
}

/// One part of a sparkline, drawn from its shape. Its samples and band
/// interpolate, so it morphs.
private struct SomaSparkPath: Shape {
    enum Part {
        case band, area, line
        /// The latest value's dot, this wide.
        case end(CGFloat)
    }

    var shape: SomaSparkShape
    let part: Part
    let inset: CGFloat

    var animatableData: AnimatablePair<SomaAnimatableVector, AnimatablePair<Double, Double>> {
        get { AnimatablePair(SomaAnimatableVector(shape.samples), AnimatablePair(shape.bandLow, shape.bandHigh)) }
        set {
            shape.samples = newValue.first.values
            shape.bandLow = newValue.second.first
            shape.bandHigh = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard shape.samples.count > 1 else { return path }
        let plot = rect.insetBy(dx: inset, dy: inset)
        func y(_ share: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(share) }
        let points = shape.samples.enumerated().map { index, share -> CGPoint in
            let along = Double(index) / Double(shape.samples.count - 1)
            return CGPoint(x: plot.minX + plot.width * CGFloat(along), y: y(share))
        }
        switch part {
        case .band:
            let top = y(shape.bandHigh)
            let bottom = y(shape.bandLow)
            let band = CGRect(x: rect.minX, y: min(top, bottom), width: rect.width, height: max(abs(bottom - top), 2))
            path.addRoundedRect(in: band, cornerSize: CGSize(width: min(band.height / 2, 3), height: min(band.height / 2, 3)))
        case .line:
            path.addLines(points)
        case .area:
            path.addLines(points)
            if let first = points.first, let last = points.last {
                path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
                path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
                path.closeSubpath()
            }
        case .end(let side):
            if let last = points.last {
                path.addEllipse(in: CGRect(x: last.x - side / 2, y: last.y - side / 2, width: side, height: side))
            }
        }
        return path
    }
}

// MARK: - Rows and tiles

/// One reading as a row: its name, then its status and value, the cue that
/// says what it means, and the trend on the trailing edge, drawn over the
/// usual band: the biomarker row.
public struct SomaTrendRow: View {
    private let title: LocalizedStringResource
    private let value: String?
    private let status: SomaReadingStatus
    private let cue: LocalizedStringResource?
    private let values: [Double?]
    private let band: ClosedRange<Double>?
    private let hue: SomaHealthHue?

    @Environment(\.somaTheme) private var theme

    /// - Parameter cue: a few words on what the value means ("3 days
    ///   rising"), set under the value. Never a sentence.
    public init(
        _ title: LocalizedStringResource,
        value: String?,
        status: SomaReadingStatus = .none,
        cue: LocalizedStringResource? = nil,
        values: [Double?],
        band: ClosedRange<Double>? = nil,
        hue: SomaHealthHue? = nil
    ) {
        self.title = title
        self.value = value
        self.status = status
        self.cue = cue
        self.values = values
        self.band = band
        self.hue = hue
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        HStack(spacing: metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                Text(title)
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                HStack(spacing: 6) {
                    if let word = status.word {
                        Text(word).foregroundStyle(status.color(colors))
                        Text(verbatim: "·").foregroundStyle(colors.inkSecondary.color)
                    }
                    Text(value ?? "-")
                        .foregroundStyle(colors.inkPrimary.color)
                        .somaRollingNumber(value)
                }
                .somaFont(theme.typography.caption)
                .lineLimit(1)
                if let cue {
                    Text(cue)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            SomaSparkline(values, tint: sparkTint, band: band)
                .frame(width: metrics.chartSparkHeight * 2.4, height: metrics.chartSparkHeight)
        }
        .padding(.horizontal, metrics.cardPadding)
        .padding(.vertical, metrics.cardPadding * 0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .accessibilityElement(children: .combine)
    }

    /// The metric's hue when it has one: a trend is never drawn in ink
    /// alone. The status keeps its colour on the word.
    private var sparkTint: Color {
        if let hue { return hue.color }
        switch status {
        case .normal, .trend, .none: return theme.colors.inkPrimary.color.opacity(0.85)
        default: return status.color(theme.colors)
        }
    }
}

/// A reading as a tile for a two column grid: a small title, the value large,
/// its status and the cue that says what it means, and the trend under it,
/// drawn over the usual band: the fitness tile.
public struct SomaTrendTile: View {
    private let title: LocalizedStringResource
    private let value: String?
    private let unit: String?
    private let status: SomaReadingStatus
    private let cue: LocalizedStringResource?
    private let values: [Double?]
    private let band: ClosedRange<Double>?
    private let hue: SomaHealthHue?

    @Environment(\.somaTheme) private var theme

    /// - Parameter cue: a few words on what the value means ("Highest in 30
    ///   days"), set under the status. Never a sentence.
    public init(
        _ title: LocalizedStringResource,
        value: String?,
        unit: String? = nil,
        status: SomaReadingStatus = .none,
        cue: LocalizedStringResource? = nil,
        values: [Double?],
        band: ClosedRange<Double>? = nil,
        hue: SomaHealthHue? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.status = status
        self.cue = cue
        self.values = values
        self.band = band
        self.hue = hue
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "-")
                    .somaFont(theme.typography.metricCompact)
                    .foregroundStyle(colors.inkPrimary.color)
                    .somaRollingNumber(value)
                if let unit, value != nil {
                    Text(unit)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            if let word = status.word {
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.color(colors))
                        .frame(width: metrics.chartPointDiameter, height: metrics.chartPointDiameter)
                    Text(word)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(status.color(colors))
                }
            }
            // The line is held even without a cue, so tiles side by side
            // keep one height.
            Group {
                if let cue {
                    Text(cue)
                } else {
                    Text(verbatim: " ").accessibilityHidden(true)
                }
            }
            .somaFont(theme.typography.caption)
            .foregroundStyle(colors.inkSecondary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            SomaSparkline(values, tint: hue?.color ?? (status.isNone ? nil : status.color(colors)), band: band)
                .frame(height: metrics.chartSparkHeight)
                .padding(.top, 4)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The detail chart

/// One dated value on a ``SomaRangeChart``.
public struct SomaChartPoint: Identifiable, Sendable, Hashable {
    public let date: Date
    public let value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A reading over a period: the normal range
/// as a soft green band, the values as a line with hollow dots, the average as
/// a dashed rule with its value in a pill, the scale on the trailing edge.
public struct SomaRangeChart: View {
    private let points: [SomaChartPoint]
    private let band: ClosedRange<Double>?
    private let average: Double?
    private let format: @Sendable (Double) -> String

    @Environment(\.somaTheme) private var theme

    public init(
        _ points: [SomaChartPoint],
        band: ClosedRange<Double>? = nil,
        average: Double? = nil,
        format: @escaping @Sendable (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
    ) {
        self.points = points
        self.band = band
        self.average = average
        self.format = format
    }

    public var body: some View {
        let colors = theme.colors
        let line = colors.statusNormal.color
        let ink = colors.inkSecondary.color

        Chart {
            if let band, let first = points.first?.date, let last = points.last?.date {
                RectangleMark(
                    xStart: .value("Start", first), xEnd: .value("End", last),
                    yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound)
                )
                .foregroundStyle(line.opacity(theme.metrics.chartBandOpacity))
            }
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(line)
                    .lineStyle(StrokeStyle(lineWidth: theme.metrics.chartStroke, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .symbol {
                        Circle()
                            .strokeBorder(line, lineWidth: 1.2)
                            .background(Circle().fill(colors.surface.color))
                            .frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
                    }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(ink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .overlay, alignment: .center) {
                        Text("Avg. \(format(average))")
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(colors.inkPrimary.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(line.opacity(0.35)))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(colors.inkPrimary.color.opacity(theme.metrics.chartGridOpacity))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(format(number)).somaFont(theme.typography.captionValue).foregroundStyle(ink)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .somaFont(theme.typography.caption)
                            .foregroundStyle(ink)
                    }
                }
            }
        }
    }

    private var domain: ClosedRange<Double> {
        var values = points.map(\.value)
        if let band { values += [band.lowerBound, band.upperBound] }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.15, 0.5)
        return (low - pad)...(high + pad)
    }
}

#Preview("Trend rows and tiles") {
    let wavy: [Double?] = [62, 61, 63, 60, 59, nil, 58, 57, 59, 56, 55, 54]
    ZStack {
    SomaPreviewBackdrop()
    ScrollView {
        VStack(spacing: 8) {
            SomaTrendRow("Resting heart rate", value: "54 bpm", status: .normal, values: wavy, band: 56...60, hue: .heart)
            SomaTrendRow("Body fat", value: "28.8 %", status: .above, cue: "4 days rising", values: wavy.reversed(), band: 56...60)
            SomaTrendRow("Lean mass", value: "55.7 kg", status: .trend("Increasing"), values: wavy)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SomaTrendTile("VO2 max", value: "40.1", status: .normal, values: wavy, hue: .activity)
                SomaTrendTile("Heart rate recovery", value: "48", unit: "bpm", status: .above, cue: "Highest in 30 days", values: wavy, band: 57...61)
            }
            SomaRangeChart(
                (0..<30).map { SomaChartPoint(date: Date(timeIntervalSince1970: 1_790_000_000 + Double($0) * 86_400), value: 17 + sin(Double($0)) * 0.8) },
                band: 16.8...18.2,
                average: 17.4
            )
            .frame(height: 220)
        }
        .padding(16)
    }
    }
}
