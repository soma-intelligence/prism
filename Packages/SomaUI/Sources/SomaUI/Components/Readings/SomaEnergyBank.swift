//
//  SomaEnergyBank.swift
//  SomaUI
//

import SwiftUI

// The energy bank's events and weeks: the events that moved the day as
// signed bars, and the weeks as ranges from the evening low to the morning
// high. The level itself is ``SomaEnergyGauge``, the day ``SomaEnergyTimeline``.
//
// Every piece reads its colours off `SomaEnergyRamp.calm`, the theme's status
// colours and the sleep and activity hues; a missing value is a dash or an
// empty track, never a zero.

/// What a band on the day's curve, or an event in the list under it, stands
/// for. Each kind carries its own hue and nothing else.
public enum SomaBankMark: Sendable, Hashable {
    case sleep
    case workout
    case peak
    case day

    func tint(_ theme: SomaTheme) -> Color {
        switch self {
        case .sleep: theme.colors.sleepStages.core.color
        case .workout: SomaHealthHue.activity.color
        case .peak: SomaHealthHue.mind.color
        case .day: SomaEnergyRamp.calm.value(at: 0.55).color
        }
    }
}

/// A level as a number with its sign: plus, the true minus, or a dash when
/// there is none.
enum SomaBankSigned {
    static func text(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\u{2212}\(-value)" }
        return "0"
    }
}

// MARK: - Battery

/// The bank now: the level large and light, and under it a slim battery on
/// its side, a hairline rim with one solid fill in the ramp's colour for that
/// level. No gradient, glow or bolt: the colour and the number carry it. It
/// replaced a fat glowing battery with the number inside (owner, 2026-10-24).
///
/// With no level the battery is empty and the number is a dash: an empty
/// charge at zero would say the bank is flat, which is a reading.
public struct SomaBankBattery: View {
    private let level: Int?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    /// - Parameter level: 0 to 100, or nil when there is none yet.
    public init(level: Int?) {
        self.level = level
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let share = level.map { min(1, max(0, Double($0) / 100)) }
        let tint = SomaEnergyRamp.standard.value(at: share ?? 0).color
        let width = metrics.bankBatteryWidth
        let height: CGFloat = 30
        let inset: CGFloat = 3
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let shown = (hasAppeared || reduceMotion) ? (share ?? 0) : 0

        VStack(spacing: metrics.cardSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: level.map(String.init) ?? "-")
                    .somaFont(type.bankFigure)
                    .contentTransition(.numericText())
                if level != nil {
                    Text(verbatim: "%")
                        .somaFont(type.bankFigureUnit)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        SomaNumber(level.map(String.init), type.bankFigure)
                            .contentTransition(.numericText())
                        if level != nil {
                            Text(verbatim: "%")
                                .somaFont(type.bankFigureUnit)
                        }
                    }
                }
                .frame(width: width, height: height)
                Capsule()
                    .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 2))
                    .frame(width: 3, height: height * 0.36)
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion { hasAppeared = true } else {
                withAnimation(theme.motion.reveal) { hasAppeared = true }
            }
        }
        .animation(reduceMotion ? nil : theme.motion.standard, value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Energy bank"))
        .accessibilityValue(Text(level.map { "\($0) percent" } ?? "No level yet"))
    }
}

// MARK: - Charged and drained

/// One of the two tiles under the battery: a signed level, green when it
/// added to the bank and red when it took from it.
public struct SomaBankDelta: View {
    private let value: Int?
    private let title: LocalizedStringResource

    @Environment(\.somaTheme) private var theme

    public init(value: Int?, title: LocalizedStringResource) {
        self.value = value
        self.title = title
    }

    public var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let tone: Color = switch value {
        case .some(let v) where v > 0: colors.statusNormal.color
        case .some(let v) where v < 0: colors.statusAlert.color
        default: colors.inkSecondary.color
        }

        VStack(spacing: 4) {
            Text(verbatim: value == nil ? "-" : SomaBankSigned.text(value) + "%")
                .somaFont(theme.typography.bankDelta)
                .foregroundStyle(tone)
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .fill(colors.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The day

/// The bank through the day: one smooth curve coloured by its own level, a
/// soft fill of the same colours under it, the night shaded, each workout
/// and the peak window as a band with its glyph above, and a dot at now.
///
/// Positions are shares of the plotted span, 0 at its leading edge and 1 at
/// its trailing one, so the page decides where the day starts. With fewer
/// than two points the plot keeps its grid and draws no curve.
public struct SomaBankDayChart: View {
    /// One reading of the bank.
    public struct Point: Sendable, Equatable {
        public let x: Double
        /// 0 to 100.
        public let level: Double

        public init(x: Double, level: Double) {
            self.x = x
            self.level = level
        }
    }

    /// A span shaded behind the curve.
    public struct Band: Sendable, Equatable, Identifiable {
        public var id: String { "\(mark)\(start)" }
        public let mark: SomaBankMark
        public let start: Double
        public let end: Double
        public let symbol: String

        public init(mark: SomaBankMark, start: Double, end: Double, symbol: String) {
            self.mark = mark
            self.start = start
            self.end = end
            self.symbol = symbol
        }
    }

    /// A label on the time axis.
    public struct Tick: Sendable, Equatable, Identifiable {
        public var id: Double { x }
        public let x: Double
        public let label: String

        public init(x: Double, label: String) {
            self.x = x
            self.label = label
        }
    }

    private let points: [Point]
    private let bands: [Band]
    private let now: Double?
    private let ticks: [Tick]

    @Environment(\.somaTheme) private var theme

    public init(points: [Point], bands: [Band], now: Double?, ticks: [Tick]) {
        self.points = points.sorted { $0.x < $1.x }
        self.bands = bands
        self.now = now
        self.ticks = ticks
    }

    private static let levels: [Double] = [0, 25, 50, 75, 100]

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let gutter = metrics.bankChartGutter

        VStack(spacing: theme.metrics.spaceS) {
            GeometryReader { proxy in
                let width = proxy.size.width - gutter
                ForEach(bands) { band in
                    Image(systemName: band.symbol)
                        .somaFont(type.caption)
                        .foregroundStyle(band.mark.tint(theme))
                        .position(x: width * CGFloat((band.start + band.end) / 2), y: proxy.size.height / 2)
                }
            }
            .frame(height: metrics.bankChartGlyphRow)

            GeometryReader { proxy in
                let width = proxy.size.width - gutter
                let height = proxy.size.height
                ZStack(alignment: .topLeading) {
                    plot
                    ForEach(Self.levels.filter { $0.truncatingRemainder(dividingBy: 50) == 0 }, id: \.self) { level in
                        Text(verbatim: "\(Int(level))")
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                            .position(x: width + gutter / 2 + 2, y: height * CGFloat(1 - level / 100))
                    }
                }
            }
            .frame(height: metrics.bankChartHeight)

            GeometryReader { proxy in
                let width = proxy.size.width - gutter
                ForEach(ticks) { tick in
                    Text(verbatim: tick.label)
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize()
                        .position(x: min(width - 14, max(16, width * CGFloat(tick.x))), y: proxy.size.height / 2)
                }
            }
            .frame(height: metrics.bankChartGlyphRow)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Energy through the day"))
        .accessibilityValue(Text(points.last.map { "\(Int($0.level.rounded())) now" } ?? "No curve yet"))
    }

    private var plot: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let ramp = Gradient(stops: SomaEnergyRamp.standard.gradientStops)
        let gutter = metrics.bankChartGutter
        let lastTint = SomaEnergyRamp.standard.value(at: (points.last?.level ?? 0) / 100).color
        let theme = theme

        return Canvas { context, size in
            let plot = CGRect(x: 0, y: 0, width: size.width - gutter, height: size.height)
            func x(_ share: Double) -> CGFloat { plot.minX + plot.width * CGFloat(min(1, max(0, share))) }
            func y(_ level: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(min(100, max(0, level)) / 100) }
            let top = CGPoint(x: 0, y: plot.minY)
            let bottom = CGPoint(x: 0, y: plot.maxY)

            for band in bands {
                let tint = band.mark.tint(theme)
                let rect = CGRect(x: x(band.start), y: plot.minY,
                                  width: max(3, x(band.end) - x(band.start)), height: plot.height)
                context.fill(Path(rect), with: .color(tint.opacity(metrics.bankChartBandOpacity)))
                context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: metrics.bankChartBandCap)),
                             with: .color(tint))
            }

            for level in Self.levels {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y(level)))
                line.addLine(to: CGPoint(x: plot.maxX, y: y(level)))
                context.stroke(line, with: .color(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * (level == 0 ? 1.6 : 1))),
                               style: StrokeStyle(lineWidth: 0.5, dash: level == 0 ? [] : [2, 3]))
            }

            if let now {
                var line = Path()
                line.move(to: CGPoint(x: x(now), y: plot.minY))
                line.addLine(to: CGPoint(x: x(now), y: plot.maxY))
                context.stroke(line, with: .color(colors.inkSecondary.color.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            let screen = points.map { CGPoint(x: x($0.x), y: y($0.level)) }
            guard screen.count >= 2, let first = screen.first, let last = screen.last else { return }
            let curve = Self.smooth(screen)
            var area = curve
            area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
            area.addLine(to: CGPoint(x: first.x, y: plot.maxY))
            area.closeSubpath()

            context.drawLayer { layer in
                layer.opacity = metrics.bankChartFillOpacity
                layer.fill(area, with: .linearGradient(ramp, startPoint: bottom, endPoint: top))
                layer.blendMode = .destinationOut
                let crest = screen.map(\.y).min() ?? plot.minY
                layer.fill(area, with: .linearGradient(
                    Gradient(colors: [colors.inkPrimary.color.opacity(0), colors.inkPrimary.color.opacity(0.92)]),
                    startPoint: CGPoint(x: 0, y: crest), endPoint: bottom))
            }

            context.stroke(curve, with: .linearGradient(ramp, startPoint: bottom, endPoint: top),
                           style: StrokeStyle(lineWidth: metrics.bankChartLine, lineCap: .round, lineJoin: .round))

            let dot = metrics.bankChartNowDot
            context.fill(Path(ellipseIn: CGRect(x: last.x - dot, y: last.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(lastTint.opacity(0.22)))
            context.fill(Path(ellipseIn: CGRect(x: last.x - dot / 2, y: last.y - dot / 2, width: dot, height: dot)),
                         with: .color(lastTint))
            context.stroke(Path(ellipseIn: CGRect(x: last.x - dot / 2, y: last.y - dot / 2, width: dot, height: dot)),
                           with: .color(colors.surface.color), lineWidth: 2)
        }
    }

    /// A monotone cubic through the points: smooth, and never overshooting a
    /// reading, so the curve does not invent a peak the bank never reached.
    static func smooth(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        let n = p.count
        guard n > 2 else {
            if n == 2 { path.addLine(to: p[1]) }
            return path
        }
        var d = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = p[i + 1].x - p[i].x
            d[i] = dx == 0 ? 0 : (p[i + 1].y - p[i].y) / dx
        }
        var m = [CGFloat](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) {
            m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2
        }
        for i in 0..<(n - 1) {
            guard d[i] != 0 else {
                m[i] = 0
                m[i + 1] = 0
                continue
            }
            let a = m[i] / d[i]
            let b = m[i + 1] / d[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                m[i] = t * a * d[i]
                m[i + 1] = t * b * d[i]
            }
        }
        for i in 0..<(n - 1) {
            let dx = (p[i + 1].x - p[i].x) / 3
            path.addCurve(to: p[i + 1],
                          control1: CGPoint(x: p[i].x + dx, y: p[i].y + m[i] * dx),
                          control2: CGPoint(x: p[i + 1].x - dx, y: p[i + 1].y - m[i + 1] * dx))
        }
        return path
    }
}

// MARK: - What moved it

/// One event that charged or drained the bank: its glyph on a disc of its
/// hue, its name and span, a bar as long as its share of the day's largest
/// move, and the signed number. Sage adds, sand takes.
public struct SomaBankEntryRow: View {
    private let mark: SomaBankMark
    private let symbol: String
    private let title: String
    private let span: String?
    private let points: Int?
    private let scale: Int

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - points: what it moved the bank by, or nil when there is no reading.
    ///   - scale: the largest move in the list, which fills the bar.
    public init(mark: SomaBankMark, symbol: String, title: String, span: String?, points: Int?, scale: Int) {
        self.mark = mark
        self.symbol = symbol
        self.title = title
        self.span = span
        self.points = points
        self.scale = max(1, scale)
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography
        let tint = mark.tint(theme)
        let tone: Color = switch points {
        case .some(let v) where v > 0: SomaEnergyRamp.charge.color
        case .some(let v) where v < 0: SomaEnergyRamp.drain.color
        default: colors.inkSecondary.color
        }
        let share = points.map { min(1, Double(abs($0)) / Double(scale)) } ?? 0

        HStack(spacing: metrics.spaceM) {
            // The bare glyph in its column; no tinted disc behind it.
            Image(systemName: symbol)
                .somaFont(type.callout)
                .foregroundStyle(tint)
                .frame(width: metrics.bankEntryGlyph, height: metrics.bankEntryGlyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                if let span {
                    Text(verbatim: span)
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ZStack(alignment: .leading) {
                Capsule().fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                if share > 0 {
                    Capsule().fill(tone)
                        .frame(width: max(metrics.bankEntryBarHeight, metrics.bankEntryBarWidth * share))
                }
            }
            .frame(width: metrics.bankEntryBarWidth, height: metrics.bankEntryBarHeight)
            Text(verbatim: SomaBankSigned.text(points))
                .somaFont(type.rowValue)
                .foregroundStyle(points == nil ? colors.inkSecondary.color : colors.inkPrimary.color)
                .frame(width: metrics.bankEntryValueColumn, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [title, span].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(Text(verbatim: SomaBankSigned.text(points)))
    }
}

// MARK: - History

/// The bank over weeks: each day a bar from its evening low to its morning
/// high, coloured by level, so a run of short clay bars is a run of short
/// nights and a tall sage one a day that started full.
///
/// A day with nothing recorded keeps an empty stub on the floor.
public struct SomaBankHistory: View {
    /// One day, oldest first.
    public struct Day: Sendable, Equatable {
        public let high: Double?
        public let low: Double?

        public init(high: Double?, low: Double?) {
            self.high = high
            self.low = low
        }
    }

    private let days: [Day]

    @Environment(\.somaTheme) private var theme

    public init(days: [Day]) {
        self.days = days
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let ramp = Gradient(stops: SomaEnergyRamp.calm.gradientStops)
        let days = days

        Canvas { context, size in
            guard !days.isEmpty else { return }
            let gap = metrics.bankHistoryBarGap
            let width = max(2, (size.width - gap * CGFloat(days.count - 1)) / CGFloat(days.count))
            func y(_ level: Double) -> CGFloat { size.height - size.height * CGFloat(min(100, max(0, level)) / 100) }

            for level in [0.0, 50, 100] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(level)))
                line.addLine(to: CGPoint(x: size.width, y: y(level)))
                context.stroke(line, with: .color(colors.inkPrimary.color.opacity(metrics.hairlineOpacity)),
                               style: StrokeStyle(lineWidth: 0.5, dash: level == 0 ? [] : [2, 3]))
            }

            for (index, day) in days.enumerated() {
                let x = CGFloat(index) * (width + gap)
                let values = [day.high, day.low].compactMap { $0 }
                guard let top = values.max(), let floor = values.min() else {
                    let stub = CGRect(x: x, y: size.height - width, width: width, height: width)
                    context.fill(Path(roundedRect: stub, cornerRadius: width / 2),
                                 with: .color(colors.inkPrimary.color.opacity(metrics.hairlineOpacity)))
                    continue
                }
                let rect = CGRect(x: x, y: y(top), width: width, height: max(width, y(floor) - y(top)))
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                             with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: size.height),
                                                   endPoint: CGPoint(x: 0, y: 0)))
            }
        }
        .frame(height: metrics.bankHistoryHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Energy by day, morning high to evening low"))
    }
}

private let previewHistory: [SomaBankHistory.Day] = (0..<30).map { index -> SomaBankHistory.Day in
    if index % 9 == 4 { return SomaBankHistory.Day(high: nil, low: nil) }
    let high = 50.0 + Double((index * 17) % 45)
    let low = 8.0 + Double((index * 11) % 30)
    return SomaBankHistory.Day(high: high, low: low)
}

#Preview("Energy bank") {
    ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            VStack(spacing: 16) {
                SomaEnergyGauge(level: 14, line: "Running low.")
                SomaCard {
                    VStack(spacing: 12) {
                        SomaBankEntryRow(mark: .sleep, symbol: "moon.stars.fill", title: "Sleep",
                                         span: "23:34 to 06:39", points: 36, scale: 36)
                        SomaBankEntryRow(mark: .workout, symbol: "figure.walk", title: "Outdoor walk",
                                         span: "09:16 to 09:58", points: -7, scale: 36)
                        SomaBankEntryRow(mark: .day, symbol: "sun.max.fill", title: "Afternoon",
                                         span: nil, points: nil, scale: 36)
                    }
                }
                SomaCard {
                    SomaBankHistory(days: previewHistory)
                }
            }
            .padding()
        }
    }
}
