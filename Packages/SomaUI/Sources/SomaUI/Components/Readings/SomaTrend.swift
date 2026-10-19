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

/// A small line of recent values with a soft fill under it and a ring on the
/// last one, drawn at the end of a row. The usual band, when
/// there is one, sits behind it as a faint green strip, whatever the line's
/// hue. Gaps are skipped, not drawn
/// as zero.
public struct SomaSparkline: View {
    private let values: [Double?]
    private let tint: Color?
    private let band: ClosedRange<Double>?
    private let filled: Bool

    @Environment(\.somaTheme) private var theme

    /// - Parameter filled: the soft fill under the line; false draws the
    ///   line alone.
    public init(_ values: [Double?], tint: Color? = nil, band: ClosedRange<Double>? = nil, filled: Bool = true) {
        self.values = values
        self.tint = tint
        self.band = band
        self.filled = filled
    }

    public var body: some View {
        let color = tint ?? theme.colors.inkPrimary.color
        let pen = SomaPen(theme)
        let inset = theme.metrics.chartRingDiameter / 2 + 1
        // Days without a reading are skipped, not drawn as a break: a trend
        // this small reads as one continuous line, and a
        // week with two readings would otherwise be two stray strokes.
        let values: [Double] = values.compactMap { $0 }
        let band = band

        Canvas { context, size in
            let known = values + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
            guard let low = known.min(), let high = known.max(), values.count > 1 else { return }
            let span = high - low == 0 ? 1 : high - low
            let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * CGFloat((value - low) / span) }
            let points: [CGPoint?] = values.enumerated().map { index, value in
                CGPoint(x: plot.minX + plot.width * CGFloat(index) / CGFloat(values.count - 1), y: y(value))
            }
            if let band {
                pen.band(context, top: y(band.upperBound), bottom: y(band.lowerBound),
                         in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            if filled { pen.fill(context, points, floor: size.height, color: color) }
            pen.line(context, points, color: color)
            if let last = points.compactMap({ $0 }).last {
                pen.ring(context, at: last, color: color)
            }
        }
        .accessibilityHidden(true)
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
