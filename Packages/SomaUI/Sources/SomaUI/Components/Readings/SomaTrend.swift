//
//  SomaTrend.swift
//  SomaUI
//

import SwiftUI
import Charts

/// Which side of a reading's usual is the good one: higher for HRV or heart
/// rate recovery, lower for resting heart rate, neither for a reading that is
/// only different (body weight, a respiratory rate).
public enum SomaBetterSide: Sendable, Equatable {
    case higher
    case lower
    case neither

    /// How a reading on `side` of its usual reads: good news on the better
    /// side, worth a watch on the other, neutral when neither is better.
    public func tone(_ side: SomaUsualSide) -> SomaCueTone {
        switch (self, side) {
        case (.higher, .above), (.lower, .below): .good
        case (.higher, .below), (.lower, .above): .watch
        case (.neither, _): .neutral
        }
    }
}

/// Which side of the usual a reading fell on.
public enum SomaUsualSide: Sendable, Equatable {
    case above
    case below
}

/// Where a reading sits against the person's usual range, as a status word.
///
/// Prefer ``outside(_:better:)`` to `above` and `below`: it colours the word
/// by whether that side is the good one, so heart rate recovery above its
/// usual reads green and resting heart rate above its usual reads amber.
/// `above` and `below` carry no direction and read amber whichever way.
public enum SomaReadingStatus: Sendable {
    case normal
    /// Above the usual, with no word on whether that is good.
    case above
    /// Below the usual, with no word on whether that is good.
    case below
    /// Outside the usual on `side`, toned by which side is `better`: the word
    /// stays "Above your usual" or "Below your usual", its colour tells the
    /// truth about it.
    case outside(SomaUsualSide, better: SomaBetterSide)
    case alert(LocalizedStringResource)
    /// A direction rather than a judgement: "Increasing", "Stabilizing".
    case trend(LocalizedStringResource)
    /// A cue in the status word's place ("Highest in 30 days"), in the
    /// colour of where the reading sits: one line instead of two.
    case worded(LocalizedStringResource, SomaCueTone)
    /// No range to read it against yet.
    case none

    /// The status word: "Within your usual", "Above your usual". Wellness
    /// words, never a clinical "normal".
    public var word: LocalizedStringResource? {
        switch self {
        case .normal: "Within your usual"
        case .above, .outside(.above, _): "Above your usual"
        case .below, .outside(.below, _): "Below your usual"
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
        case .outside(let side, let better): better.tone(side).color(colors)
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

/// A small line of recent values, as Apple Health draws a trend at
/// the end of a row: a smooth line in the metric's hue and a solid dot on the
/// last value. The usual band, when there is one, sits behind it as a faint
/// neutral strip: the status word already says where the reading sits, so the
/// band never needs a colour of its own (a green block read as a widget,
/// owner 2026-10-23). Gaps are skipped, not drawn as zero.
///
/// One layer under the line at most (2026-10-27): the band when there is one,
/// else the fade when asked for, never both, so a row never reads as a
/// coloured box. A band that covers most of the plot says nothing about where
/// the line sits and is left out.
public struct SomaSparkline: View {
    private let values: [Double?]
    private let tint: Color?
    private let band: ClosedRange<Double>?
    private let filled: Bool
    private let eased: Bool

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - filled: a fade under the line; off by default.
    ///   - eased: the tile's treatment: the days averaged down to a few
    ///     points (``SomaMetrics/sparkEasedPoints``) and softened, so a
    ///     month reads as its shape rather than its daily noise, and a faint
    ///     halo round the last value. Off by default.
    public init(_ values: [Double?], tint: Color? = nil, band: ClosedRange<Double>? = nil, filled: Bool = false, eased: Bool = false) {
        self.values = values
        self.tint = tint
        self.band = band
        self.filled = filled
        self.eased = eased
    }

    public var body: some View {
        let color = tint ?? theme.colors.inkPrimary.color
        let metrics = theme.metrics
        let surface = theme.colors.surface.color
        let dot = metrics.chartPointDiameter + 1
        let inset = dot / 2 + 2
        // Days without a reading are skipped, not drawn as a break: a trend
        // this small reads as one continuous line, and a week with two
        // readings would otherwise be two stray strokes.
        let known: [Double] = values.compactMap { $0 }
        let values = eased ? Self.eased(known, points: metrics.sparkEasedPoints) : known
        let band = band
        let eased = eased
        let halo = metrics.chartRingDiameter + 4
        let bandInk = theme.colors.inkPrimary.color.opacity(metrics.sparkBandOpacity)

        Canvas { context, size in
            let known = values + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
            guard let low = known.min(), let high = known.max(), !values.isEmpty else { return }
            // One reading: a dot at the end of a hairline, so the row still
            // says where it sits rather than leaving a hole.
            if values.count == 1 {
                let span = high - low == 0 ? 1 : high - low
                let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                let y = plot.maxY - plot.height * CGFloat((values[0] - low) / span)
                var rule = Path()
                rule.move(to: CGPoint(x: plot.minX, y: y))
                rule.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(rule, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                context.fill(Path(ellipseIn: CGRect(x: plot.maxX - dot / 2, y: y - dot / 2, width: dot, height: dot)), with: .color(color))
                return
            }
            let span = high - low == 0 ? 1 : high - low
            let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * CGFloat((value - low) / span) }
            let points = values.enumerated().map { index, value in
                CGPoint(x: plot.minX + plot.width * CGFloat(index) / CGFloat(values.count - 1), y: y(value))
            }

            // The usual band behind the line as a neutral strip, so a value
            // outside it shows at a glance; left out when it fills most of
            // the plot, where it would only tint the whole chart.
            var drewBand = false
            if let band {
                let top = y(band.upperBound), bottom = y(band.lowerBound)
                if (bottom - top) / max(1, plot.height) <= metrics.sparkBandMaxShare {
                    let slab = CGRect(x: plot.minX, y: top, width: plot.width, height: max(1, bottom - top))
                    context.fill(Path(roundedRect: slab, cornerRadius: metrics.sparkBandRadius), with: .color(bandInk))
                    drewBand = true
                }
            }

            let line = Self.smooth(points)
            if filled, !drewBand, let first = points.first, let last = points.last {
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: size.height))
                area.addLine(to: CGPoint(x: first.x, y: size.height))
                area.closeSubpath()
                // Eased, the fade starts at the line's own peak rather than the
                // plot's top, so a flat month still shows its wash.
                let top = eased ? points.map(\.y).min() ?? plot.minY : plot.minY
                let opacity = eased ? metrics.chartFillOpacity : 0.2
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
            }
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: metrics.chartStroke, lineCap: .round, lineJoin: .round))

            if let last = points.last, eased {
                context.fill(Path(ellipseIn: CGRect(x: last.x - halo / 2, y: last.y - halo / 2, width: halo, height: halo)),
                             with: .color(color.opacity(metrics.chartHaloOpacity)))
                context.fill(Path(ellipseIn: CGRect(x: last.x - dot / 2, y: last.y - dot / 2, width: dot, height: dot)),
                             with: .color(color))
            } else if let last = points.last {
                let halo = dot + 3
                context.fill(Path(ellipseIn: CGRect(x: last.x - halo / 2, y: last.y - halo / 2, width: halo, height: halo)),
                             with: .color(surface))
                context.fill(Path(ellipseIn: CGRect(x: last.x - dot / 2, y: last.y - dot / 2, width: dot, height: dot)),
                             with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    /// The readings averaged into at most `points` buckets, then each inner
    /// point weighed with its neighbours (one, two, one), so day to day
    /// noise drops out and the month's shape stays. The ends are kept as
    /// read: the dot on the last value is the value the tile prints.
    static func eased(_ values: [Double], points: Int) -> [Double] {
        guard let latest = values.last else { return [] }
        var series = values
        if values.count > points, points > 1 {
            let size = Double(values.count) / Double(points)
            series = (0..<points).map { index in
                let lower = Int(Double(index) * size)
                let upper = index == points - 1 ? values.count : max(lower + 1, Int(Double(index + 1) * size))
                let bucket = values[lower..<upper]
                return bucket.reduce(0, +) / Double(bucket.count)
            }
        }
        guard series.count > 3 else { return series }
        var softened = series
        for index in 1..<(series.count - 1) {
            softened[index] = (series[index - 1] + 2 * series[index] + series[index + 1]) / 4
        }
        softened[softened.count - 1] = latest
        return softened
    }

    /// A Catmull-Rom curve through the points, drawn as cubic Béziers, so a
    /// week of readings reads as one gesture rather than a zigzag. Its
    /// handles are clamped to the neighbours' heights, so the curve never
    /// overshoots a value it passes through.
    static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let low = min(p1.y, p2.y)
            let high = max(p1.y, p2.y)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: min(max(p1.y + (p2.y - p0.y) / 6, low), high))
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: min(max(p2.y - (p3.y - p1.y) / 6, low), high))
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
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
                if filled, !shape.hasBand {
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
            // A plain field across the plot, as the metric page draws it:
            // rounded, a thin band read as a slider's track.
            let band = CGRect(x: rect.minX, y: min(top, bottom), width: rect.width, height: max(abs(bottom - top), 2))
            path.addRect(band)
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

    /// The readings averaged into at most `points` buckets, then each inner
    /// point weighed with its neighbours (one, two, one), so day to day
    /// noise drops out and the month's shape stays. The ends are kept as
    /// read: the dot on the last value is the value the tile prints.
    static func eased(_ values: [Double], points: Int) -> [Double] {
        guard let latest = values.last else { return [] }
        var series = values
        if values.count > points, points > 1 {
            let size = Double(values.count) / Double(points)
            series = (0..<points).map { index in
                let lower = Int(Double(index) * size)
                let upper = index == points - 1 ? values.count : max(lower + 1, Int(Double(index + 1) * size))
                let bucket = values[lower..<upper]
                return bucket.reduce(0, +) / Double(bucket.count)
            }
        }
        guard series.count > 3 else { return series }
        var softened = series
        for index in 1..<(series.count - 1) {
            softened[index] = (series[index - 1] + 2 * series[index] + series[index + 1]) / 4
        }
        softened[softened.count - 1] = latest
        return softened
    }

    /// A Catmull-Rom curve through the points, drawn as cubic Béziers, so a
    /// week of readings reads as one gesture rather than a zigzag. Its
    /// handles are clamped to the neighbours' heights, so the curve never
    /// overshoots a value it passes through.
    static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            let low = min(p1.y, p2.y)
            let high = max(p1.y, p2.y)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: min(max(p1.y + (p2.y - p0.y) / 6, low), high))
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: min(max(p2.y - (p3.y - p1.y) / 6, low), high))
            path.addCurve(to: p2, control1: c1, control2: c2)
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
    private let chart: SomaTrendTile.Chart
    private let symbol: String?
    private let prominent: Bool
    private let opens: Bool

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - cue: a few words on what the value means ("3 days rising"), set
    ///     under the value. Never a sentence.
    ///   - chart: a line for a level, bars for a count that adds up over
    ///     the day, steps (owner, 2026-10-24).
    ///   - symbol: a glyph beside the title, used by the prominent layout.
    ///   - prominent: the reference design's layout: a quiet title with its glyph, the
    ///     value large, and the status under it with its mark (owner,
    ///     2026-10-25, the Sleep page).
    ///   - opens: draws the arrow that says the row opens something.
    public init(
        _ title: LocalizedStringResource,
        value: String?,
        status: SomaReadingStatus = .none,
        cue: LocalizedStringResource? = nil,
        values: [Double?],
        band: ClosedRange<Double>? = nil,
        hue: SomaHealthHue? = nil,
        chart: SomaTrendTile.Chart = .line,
        symbol: String? = nil,
        prominent: Bool = false,
        opens: Bool = false
    ) {
        self.chart = chart
        self.symbol = symbol
        self.prominent = prominent
        self.opens = opens
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

        HStack(alignment: .center, spacing: metrics.cardSpacing) {
            if prominent { prominentText } else { plainText }
            Spacer(minLength: metrics.spaceS)
            // The trend takes a real share of the row, about a third of a
            // phone's width, tall enough for the line to show its shape.
            Group {
                switch chart {
                case .line: SomaSparkline(values, tint: sparkTint, band: band, filled: !prominent || band == nil)
                case .bars: SomaSparkBars(values, tint: sparkTint)
                }
            }
            .frame(width: metrics.chartSparkHeight * 3.4, height: metrics.chartSparkHeight * 1.45)
        }
        .overlay(alignment: .topTrailing) {
            if opens {
                Image(systemName: "arrow.right")
                    .font(.system(size: metrics.browseChevronSize, weight: .medium))
                    .foregroundStyle(colors.inkSecondary.color)
                    .offset(y: -metrics.spaceS)
            }
        }
        .padding(.horizontal, metrics.cardPadding)
        .padding(.vertical, metrics.spaceM)
        // Every row one height, cue or not, so a list of them reads as one
        // even column of cards.
        .frame(maxWidth: .infinity, minHeight: metrics.trendRowMinHeight, alignment: .leading)
        .somaLitSurface()
        .accessibilityElement(children: .combine)
    }

    /// the reference design's card: the title quiet with its glyph, the value large, the
    /// status under it behind its mark.
    private var prominentText: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        return VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
            HStack(spacing: metrics.spaceS) {
                if let symbol {
                    Image(systemName: symbol).imageScale(.small)
                }
                Text(title).lineLimit(1)
            }
            .somaFont(theme.typography.callout)
            .foregroundStyle(colors.inkSecondary.color)
            SomaNumber(value, theme.typography.metric)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let word = status.word {
                HStack(spacing: metrics.spaceS) {
                    Image(systemName: statusMark)
                        .imageScale(.small)
                    Text(word).lineLimit(1)
                }
                .somaFont(theme.typography.callout)
                .foregroundStyle(status.color(colors))
            }
        }
    }

    private var statusMark: String {
        switch status {
        case .above, .outside(.above, _): "arrow.up.circle.fill"
        case .below, .outside(.below, _): "arrow.down.circle.fill"
        case .alert: "exclamationmark.circle.fill"
        default: "checkmark.circle.fill"
        }
    }

    private var plainText: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        return VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                Text(title)
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                // The word and the value on one line where they fit, one
                // under the other where they do not: a row in one column of
                // an unfolded foldable cut both to "Above nor...".
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.metrics.spaceS) {
                        if let word = status.word {
                            Text(word).foregroundStyle(status.color(colors))
                            Text(verbatim: "·").foregroundStyle(colors.inkSecondary.color)
                        }
                        SomaNumber(value, theme.typography.caption)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
                    VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                        if let word = status.word {
                            Text(word).foregroundStyle(status.color(colors))
                        }
                        SomaNumber(value, theme.typography.caption)
                            .foregroundStyle(colors.inkPrimary.color)
                    }
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
    }

    /// The metric's hue when it has one: a trend is never drawn in ink
    /// alone. The status keeps its colour on the word.
    private var sparkTint: Color {
        if let hue { return hue.color }
        switch status {
        case .normal, .trend, .none, .outside(_, .neither): return theme.colors.inkPrimary.color.opacity(0.85)
        default: return status.color(theme.colors)
        }
    }
}

/// A reading as a tile for a two column grid, as Apple Fitness sets
/// one: a quiet title, the value large with its unit small beside it, one
/// status line, and the month at the foot.
///
/// Every tile is one height and its chart sits on one baseline, so a grid of
/// them reads as rows rather than a staircase. The value never wraps: it
/// scales down before it would. The tile carries one tint, and the tint
/// means something: the status colour when the reading is judged against a
/// band, else the aspect's identity hue, never a colour per metric.
public struct SomaTrendTile: View {
    /// How the month is drawn.
    public enum Chart: Sendable {
        /// An eased line with a fade under it: a reading taken as a level,
        /// a heart rate, a speed.
        case line
        /// One bar a day: a count that adds up over the day, steps.
        case bars
    }

    private let title: LocalizedStringResource
    private let value: String?
    private let unit: String?
    private let status: SomaReadingStatus
    private let cue: LocalizedStringResource?
    private let values: [Double?]
    private let band: ClosedRange<Double>?
    private let aspect: SomaAspect?
    private let chart: Chart

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - cue: a few words on what the value means ("Highest in 30 days"),
    ///     set after the status word where the tile is wide enough, and
    ///     always read aloud. Never a sentence.
    ///   - aspect: whose identity hue the tile wears when its status is not
    ///     a judgement (a direction, or no status yet). Ink without one.
    public init(
        _ title: LocalizedStringResource,
        value: String?,
        unit: String? = nil,
        status: SomaReadingStatus = .none,
        cue: LocalizedStringResource? = nil,
        values: [Double?],
        band: ClosedRange<Double>? = nil,
        aspect: SomaAspect? = nil,
        chart: Chart = .line
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.status = status
        self.cue = cue
        self.values = values
        self.band = band
        self.aspect = aspect
        self.chart = chart
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let tint = tint

        VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
            Text(title)
                .somaFont(theme.typography.eyebrow)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
            SomaNumber(value, theme.typography.metricCompact, unit: unit, unitSpec: theme.typography.caption)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
            .minimumScaleFactor(0.6)
            statusLine(dot: tint)
            Spacer(minLength: metrics.spaceS)
            Group {
                switch chart {
                case .line:
                    SomaSparkline(values, tint: tint, band: band, filled: true, eased: true)
                case .bars:
                    SomaSparkBars(values, tint: tint)
                }
            }
            .frame(height: metrics.trendTileChartHeight)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.trendTileMinHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: spokenValue))
    }

    /// One line, always held so tiles side by side keep their chart on one
    /// baseline: the dot and the status word, then the cue where it fits.
    @ViewBuilder
    private func statusLine(dot: Color) -> some View {
        let colors = theme.colors
        let word = status.word
        let mark = HStack(spacing: theme.metrics.spaceXS) {
            Circle()
                .fill(dot)
                .frame(width: theme.metrics.chartPointDiameter, height: theme.metrics.chartPointDiameter)
            if let word {
                Text(word).foregroundStyle(status.color(colors))
            } else if let cue {
                Text(cue).foregroundStyle(colors.inkSecondary.color)
            }
        }
        Group {
            if word == nil && cue == nil {
                Text(verbatim: " ").accessibilityHidden(true)
            } else if let cue, word != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.metrics.spaceXS) {
                        mark
                        Text(verbatim: "·").foregroundStyle(colors.inkSecondary.color)
                        Text(cue).foregroundStyle(colors.inkSecondary.color)
                    }
                    mark
                }
            } else {
                mark
            }
        }
        .somaFont(theme.typography.caption)
        .lineLimit(1)
    }

    /// The tile's one colour: where the reading sits when it is judged
    /// against a band, else the aspect's hue.
    private var tint: Color {
        let colors = theme.colors
        let neutral = aspect.map { theme.aspects[$0].identity.color } ?? colors.inkPrimary.color
        switch status {
        case .normal, .above, .below, .alert: return status.color(colors)
        case .outside(let side, let better) where better != .neither: return better.tone(side).color(colors)
        case .worded(_, let tone) where tone != .neutral: return tone.color(colors)
        default: return neutral
        }
    }

    /// What VoiceOver reads after the title: the value and its unit, the
    /// status and the cue, the cue included even where the line had no room.
    private var spokenValue: String {
        let reading = value.map { value in unit.map { "\(value) \($0)" } ?? value } ?? SomaFormat.notMeasured
        let parts = [reading, status.word.map { String(localized: $0) }, cue.map { String(localized: $0) }]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

/// A month of daily counts as thin bars, oldest first: the past days soft in
/// the tile's tint, the latest one full, as Apple Health marks the day it is
/// about. Bars stand on zero, since a count is read from nothing; a day with
/// no reading leaves its slot empty.
struct SomaSparkBars: View {
    private let values: [Double?]
    private let tint: Color

    @Environment(\.somaTheme) private var theme

    init(_ values: [Double?], tint: Color) {
        self.values = values
        self.tint = tint
    }

    var body: some View {
        let metrics = theme.metrics
        // The month the tile is about, even when a sparse reading was handed
        // a year of days.
        let days = Array(values.suffix(30))
        let latest = days.lastIndex { $0 != nil }

        Canvas { context, size in
            guard let high = days.compactMap({ $0 }).max(), high > 0, !days.isEmpty else { return }
            let gap = metrics.sparkBarGap
            let width = max(1, (size.width - gap * CGFloat(days.count - 1)) / CGFloat(days.count))
            let radius = min(metrics.chartThinBarRadius, width / 2)
            for (index, value) in days.enumerated() {
                guard let value, value > 0 else { continue }
                let height = max(radius * 2, size.height * CGFloat(value / high))
                let bar = CGRect(x: CGFloat(index) * (width + gap), y: size.height - height, width: width, height: height)
                let shade = index == latest ? tint : tint.opacity(metrics.chartContextBarOpacity)
                context.fill(Path(roundedRect: bar, cornerRadius: radius), with: .color(shade))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A trend tile's chart: the sparkline, and the usual band's edges named
/// on its trailing side the way a metric page names them.
struct SomaTrendTileChart: View {
    let values: [Double?]
    let band: ClosedRange<Double>?
    let value: String?
    let tint: Color?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let shape = SomaSparkShape.make(values, band: band, samples: metrics.sparkSamples)
        let labelled = shape.hasBand && shape.samples.count > 1

        HStack(spacing: metrics.trendTileLabelGap) {
            SomaSparkline(values, tint: tint, band: band)
            if labelled, let band {
                GeometryReader { proxy in
                    let inset = metrics.sparkEndDot / 2 + 1
                    let plot = proxy.size.height - inset * 2
                    let high = inset + plot * (1 - shape.bandHigh)
                    let low = inset + plot * (1 - shape.bandLow)
                    // Two labels closer than a line apart would collide:
                    // they part around the band's middle.
                    let line = metrics.trendTileLabelLine
                    let gap = max(0, line - (low - high)) / 2
                    // Kept inside the chart's height, the pair moving
                    // together so they never meet.
                    let top = min(max(high - gap, line / 2), proxy.size.height - line * 1.5)
                    let bottom = max(min(low + gap, proxy.size.height - line / 2), top + line)
                    ZStack(alignment: .topLeading) {
                        label(band.upperBound).position(x: proxy.size.width / 2, y: top)
                        label(band.lowerBound).position(x: proxy.size.width / 2, y: bottom)
                    }
                }
                .frame(width: metrics.trendTileLabelWidth)
                .accessibilityHidden(true)
            }
        }
    }

    private func label(_ number: Double) -> some View {
        Text(Self.format(number, like: value))
            .somaFont(theme.typography.captionValue)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// A band edge in the value's own precision: "4.8" beside "5.1", "62"
    /// beside "66", grouped like the value ("7,168").
    nonisolated static func format(_ number: Double, like value: String?) -> String {
        let decimals = value.flatMap { text -> Int? in
            guard let dot = text.lastIndex(where: { $0 == "." || $0 == "," }),
                  text[text.index(after: dot)...].allSatisfy(\.isNumber),
                  text.distance(from: dot, to: text.endIndex) <= 3 else { return nil }
            return text.distance(from: dot, to: text.endIndex) - 1
        } ?? 0
        return number.formatted(.number.precision(.fractionLength(decimals)))
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
                            .padding(.horizontal, theme.metrics.spaceS)
                            .padding(.vertical, theme.metrics.spaceXS)
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
                SomaTrendTile("VO2 max", value: "43.4", unit: "ml/kg/min", status: .trend("Increasing"), values: wavy, aspect: .body)
                SomaTrendTile("Heart rate recovery", value: "48", unit: "bpm", status: .above, cue: "Highest in 30 days", values: wavy, band: 57...61)
                SomaTrendTile("Resting heart rate", value: "66", unit: "bpm", status: .normal, cue: "Highest in 30 days", values: wavy, band: 54...62)
                SomaTrendTile("Steps", value: "4,296", unit: "steps", status: .trend("Stabilizing"), values: wavy.map { $0.map { $0 * 120 } },
                              aspect: .body, chart: .bars)
            }
            SomaRangeChart(
                (0..<30).map { SomaChartPoint(date: Date(timeIntervalSince1970: 1_790_000_000 + Double($0) * 86_400), value: 17 + sin(Double($0)) * 0.8) },
                band: 16.8...18.2,
                average: 17.4
            )
            .frame(height: 220)
        }
        .padding(SomaMetrics.standard.spaceL)
    }
    }
}
