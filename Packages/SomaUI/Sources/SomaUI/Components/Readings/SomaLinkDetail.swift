//
//  SomaLinkDetail.swift
//  SomaUI
//
//  The pieces of a link's detail sheet: the headline, the two sides compared
//  at full width, the outcome in time with the driver days lit, the facts row
//  with its strength meter, and the gate's progress for a link still waiting.
//

import SwiftUI

// MARK: - Headline

/// The sheet's top: what the link says in plain words ("After a long night,
/// your morning energy is higher"), the effect large and signed in its
/// status colour with its unit spelled out, and the day counts small under
/// it.
public struct SomaLinkHeadline: View {
    private let title: String
    private let value: String?
    private let unit: String
    private let caption: String?
    private let tone: SomaLinkTone

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - title: the link as a sentence, or its plain name while it waits.
    ///   - value: the effect, signed: "\u{2212}11". Nil for a link still
    ///     waiting, which shows the title alone.
    ///   - unit: spelled out: "points", "minutes".
    ///   - caption: the day counts: "9 vs 41 nights".
    public init(title: String, value: String?, unit: String, caption: String?, tone: SomaLinkTone) {
        self.title = title
        self.value = value
        self.unit = unit
        self.caption = caption
        self.tone = tone
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.linkCardSpacing) {
            Text(verbatim: title)
                .somaFont(type.title)
                .foregroundStyle(colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)

            if let value {
                HStack(alignment: .firstTextBaseline, spacing: metrics.linkCardSpacing * 0.5) {
                    Text(verbatim: value)
                        .somaFont(type.display)
                        .foregroundStyle(tone.color(colors))
                    Text(verbatim: unit)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkSecondary.color)
                }
                .lineLimit(1)
            }

            if let caption {
                Text(verbatim: caption)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: [value.map { "\($0) \(unit)" }, caption].compactMap { $0 }.joined(separator: ", ")))
    }
}

// MARK: - Comparison

/// The two sides of a link at full width, on one shared scale: each day a
/// dot, the middle half of the days a faint box with the whole range as a
/// hairline through it, and each side's mean a solid mark. A bracket between
/// the two means carries the gap.
public struct SomaLinkComparison: View {
    private let high: [Double]
    private let low: [Double]
    private let highLabel: String
    private let lowLabel: String
    private let gap: String
    private let tone: SomaLinkTone

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - high: the outcome on each high (or tagged) day.
    ///   - low: the outcome on each low (or untagged) day.
    ///   - highLabel: the high row's name: "With", "Long".
    ///   - lowLabel: the low row's name: "Without", "Short".
    ///   - gap: the difference, as the headline states it: "−11 points".
    public init(high: [Double], low: [Double], highLabel: String, lowLabel: String, gap: String, tone: SomaLinkTone) {
        self.high = high
        self.low = low
        self.highLabel = highLabel
        self.lowLabel = lowLabel
        self.gap = gap
        self.tone = tone
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let row = metrics.linkDetailRowHeight
        let band = metrics.linkDetailGapHeight
        let height = row * 2 + band
        let scale = SomaPlotScale(values: high + low, desired: 4)
        let highColor = tone.color(colors)
        let lowColor = colors.inkSecondary.color
        let pen = SomaPen(theme)
        let inset = metrics.linkDetailDot

        HStack(alignment: .top, spacing: metrics.linkCardSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: highLabel)
                    .foregroundStyle(highColor)
                    .frame(height: row)
                Spacer().frame(height: band)
                Text(verbatim: lowLabel)
                    .foregroundStyle(lowColor)
                    .frame(height: row)
            }
            .somaFont(type.callout)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: metrics.linkDetailLabelWidth, alignment: .leading)

            VStack(spacing: metrics.chartLabelGap) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let domain = scale?.domain ?? 0...1
                    let x = { (value: Double) -> CGFloat in
                        let span = max(domain.upperBound - domain.lowerBound, .ulpOfOne)
                        return inset + (width - inset * 2) * CGFloat((value - domain.lowerBound) / span)
                    }
                    let highMean = Self.mean(high)
                    let lowMean = Self.mean(low)

                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            for tick in scale?.ticks ?? [] {
                                pen.vertical(context, x: x(tick), height: height)
                            }
                            Self.drawRow(context, values: high, centre: row / 2, row: row, color: highColor, x: x, metrics: metrics)
                            Self.drawRow(context, values: low, centre: row * 1.5 + band, row: row, color: lowColor, x: x, metrics: metrics)

                            guard let highMean, let lowMean else { return }
                            // The bracket: a dashed drop from each mean to the
                            // band's middle, and a rule between them.
                            let middle = row + band / 2
                            let ink = colors.inkPrimary.color
                            var drops = Path()
                            drops.move(to: CGPoint(x: x(highMean), y: row * 0.9))
                            drops.addLine(to: CGPoint(x: x(highMean), y: middle))
                            drops.move(to: CGPoint(x: x(lowMean), y: row + band + row * 0.1))
                            drops.addLine(to: CGPoint(x: x(lowMean), y: middle))
                            context.stroke(drops, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            var rule = Path()
                            rule.move(to: CGPoint(x: x(lowMean), y: middle))
                            rule.addLine(to: CGPoint(x: x(highMean), y: middle))
                            context.stroke(rule, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        }

                        if let highMean, let lowMean {
                            let centre = (x(highMean) + x(lowMean)) / 2
                            Text(verbatim: gap)
                                .somaFont(type.captionValue)
                                .foregroundStyle(colors.inkPrimary.color)
                                .padding(.horizontal, metrics.linkCardSpacing * 0.5)
                                .background(Capsule().fill(colors.surface.color))
                                .fixedSize()
                                .position(x: min(max(centre, width * 0.12), width * 0.88), y: row + band / 2)
                        }
                    }
                }
                .frame(height: height)

                if let scale {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        ForEach(scale.ticks, id: \.self) { tick in
                            let span = max(scale.domain.upperBound - scale.domain.lowerBound, .ulpOfOne)
                            Text(verbatim: scale.label(tick))
                                .fixedSize()
                                .position(x: inset + (width - inset * 2) * CGFloat((tick - scale.domain.lowerBound) / span),
                                          y: proxy.size.height / 2)
                        }
                    }
                    .frame(height: metrics.chartPlotInset * 3)
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(highLabel) against \(lowLabel)"))
        .accessibilityValue(Text(verbatim: "\(gap), \(high.count) and \(low.count) days"))
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The value a share of the way through the sorted values.
    static func quantile(_ sorted: [Double], _ share: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = share * Double(sorted.count - 1)
        let below = Int(position.rounded(.down))
        let above = min(below + 1, sorted.count - 1)
        return sorted[below] + (sorted[above] - sorted[below]) * (position - Double(below))
    }

    private static func drawRow(
        _ context: GraphicsContext,
        values: [Double],
        centre: CGFloat,
        row: CGFloat,
        color: Color,
        x: (Double) -> CGFloat,
        metrics: SomaMetrics
    ) {
        guard !values.isEmpty else { return }
        let sorted = values.sorted()

        // The whole range, a hairline through the row.
        var range = Path()
        range.move(to: CGPoint(x: x(sorted[0]), y: centre))
        range.addLine(to: CGPoint(x: x(sorted[sorted.count - 1]), y: centre))
        context.stroke(range, with: .color(color.opacity(0.45)), lineWidth: 1)

        // The middle half of the days.
        let first = x(quantile(sorted, 0.25))
        let third = x(quantile(sorted, 0.75))
        let box = CGRect(x: first, y: centre - row * 0.3, width: max(third - first, 1), height: row * 0.6)
        context.fill(Path(roundedRect: box, cornerRadius: row * 0.12), with: .color(color.opacity(metrics.linkDetailBoxOpacity)))

        // Each day, spread over a few lanes so close days stay apart; the
        // lanes follow the sorted order, so the same days land the same way.
        let dot = metrics.linkDetailDot
        let lanes: [CGFloat] = [0, -0.22, 0.22, -0.11, 0.11]
        for (index, value) in sorted.enumerated() {
            let y = centre + row * lanes[index % lanes.count]
            let rect = CGRect(x: x(value) - dot / 2, y: y - dot / 2, width: dot, height: dot)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(metrics.linkDetailDotOpacity)))
        }

        if let mean = mean(values) {
            let width = metrics.linkDetailMeanWidth
            let mark = CGRect(x: x(mean) - width / 2, y: centre - row * 0.4, width: width, height: row * 0.8)
            context.fill(Path(roundedRect: mark, cornerRadius: width / 2), with: .color(color))
        }
    }
}

// MARK: - Timeline

/// Which side of a link a day fell on, for lighting it in time.
public enum SomaLinkSide: Sendable, Hashable {
    /// A high or tagged day: shaded, its value a solid dot.
    case high
    /// A low day: its value a hollow dot.
    case low
    /// A day the link does not compare, or an untagged one: the line alone.
    case none
}

/// One day of a link's outcome in time.
public struct SomaLinkDay: Identifiable, Sendable, Hashable {
    public let date: Date
    /// The outcome that day in the shown unit, or nil when it was not measured.
    public let value: Double?
    public let side: SomaLinkSide

    public var id: Date { date }

    public init(date: Date, value: Double?, side: SomaLinkSide) {
        self.date = date
        self.value = value
        self.side = side
    }
}

/// The outcome over the last weeks as a line in its aspect's colour, with the
/// driver's days lit behind it, so the person sees when the link happened.
public struct SomaLinkTimeline: View {
    private let days: [SomaLinkDay]
    private let aspect: SomaAspect
    private let tone: SomaLinkTone
    private let xLabels: [String]
    private let legend: String?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - days: one entry per day, oldest first.
    ///   - aspect: the outcome's aspect, which colours the line.
    ///   - tone: the link's tone, which colours the lit days.
    ///   - xLabels: a few dates under the plot.
    ///   - legend: what a lit day is: "Alcohol nights".
    public init(days: [SomaLinkDay], aspect: SomaAspect, tone: SomaLinkTone, xLabels: [String], legend: String?) {
        self.days = days
        self.aspect = aspect
        self.tone = tone
        self.xLabels = xLabels
        self.legend = legend
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let lineColor = theme.aspects[aspect].identity.color
        let litColor = tone.color(colors)
        let days = days
        let highlight = metrics.linkDetailHighlightOpacity

        VStack(alignment: .leading, spacing: metrics.linkCardSpacing) {
            SomaPlot(scale: SomaPlotScale(values: days.compactMap(\.value)), xLabels: xLabels) { context, space, pen in
                let count = days.count
                let pitch = space.pitch(count)
                for (index, day) in days.enumerated() where day.side == .high {
                    let x = space.x(index, of: count)
                    let width = max(2, pitch * 0.7)
                    let rect = CGRect(x: x - width / 2, y: 0, width: width, height: space.size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(litColor.opacity(highlight)))
                }
                let points: [CGPoint?] = days.enumerated().map { index, day in
                    day.value.map { CGPoint(x: space.x(index, of: count), y: space.y($0)) }
                }
                pen.line(context, points, color: lineColor)
                for (index, day) in days.enumerated() {
                    guard let point = points[index] else { continue }
                    switch day.side {
                    case .high: pen.dot(context, at: point, color: litColor, filled: true)
                    case .low: pen.dot(context, at: point, color: pen.inkSecondary)
                    case .none: break
                    }
                }
            }

            if let legend {
                HStack(spacing: metrics.linkCardSpacing * 0.75) {
                    Circle()
                        .fill(litColor)
                        .frame(width: metrics.chartPointDiameter, height: metrics.chartPointDiameter)
                    Text(verbatim: legend)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: legend ?? ""))
        .accessibilityValue(Text(verbatim: "\(days.filter { $0.side == .high }.count) days lit"))
    }
}

// MARK: - Facts

/// One fact under a link: a label and a value, or a strength meter.
public struct SomaLinkFact: Identifiable, Sendable, Hashable {
    public let label: String
    public let value: String?
    /// Filled bars of the meter, when the fact is a strength.
    public let strength: Int?

    public var id: String { label }

    public init(_ label: String, value: String?) {
        self.label = label
        self.value = value
        self.strength = nil
    }

    public init(_ label: String, strength: Int) {
        self.label = label
        self.value = nil
        self.strength = strength
    }
}

/// The facts row under a link: three to a line, a small label over each value.
public struct SomaLinkFacts: View {
    private let facts: [SomaLinkFact]
    private let scale: Int

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - scale: how many bars a strength meter has.
    public init(_ facts: [SomaLinkFact], strengthScale scale: Int = SomaLinkStrengthMeter.defaultScale) {
        self.facts = facts
        self.scale = scale
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let columns = Array(repeating: GridItem(.flexible(), spacing: metrics.linkCardSpacing, alignment: .topLeading), count: 3)

        LazyVGrid(columns: columns, alignment: .leading, spacing: metrics.linkDetailSpacing * 0.75) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                    Text(verbatim: fact.label)
                        .somaFont(type.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let strength = fact.strength {
                        SomaLinkStrengthMeter(level: strength, of: scale)
                            .frame(height: type.rowValue.size * 1.25, alignment: .leading)
                    } else {
                        Text(verbatim: fact.value ?? "-")
                            .somaFont(type.rowValue)
                            .foregroundStyle(colors.inkPrimary.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: fact.label))
                .accessibilityValue(Text(verbatim: fact.strength.map { "\($0) of \(scale)" } ?? fact.value ?? "-"))
            }
        }
    }
}

/// How strong a link is, as a few rising bars: the filled ones in ink, the
/// rest recessed. Ink, not a status colour: strength is about the evidence,
/// not whether the move is good.
public struct SomaLinkStrengthMeter: View {
    public static let defaultScale = 4

    private let level: Int
    private let total: Int

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - level: bars filled, clamped to `0...total`.
    public init(level: Int, of total: Int = SomaLinkStrengthMeter.defaultScale) {
        self.total = max(1, total)
        self.level = min(max(0, level), self.total)
    }

    public var body: some View {
        let metrics = theme.metrics
        let ink = theme.colors.inkPrimary.color
        let height = metrics.linkMeterHeight

        HStack(alignment: .bottom, spacing: metrics.linkMeterSpacing) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: metrics.linkMeterBarWidth / 2, style: .continuous)
                    .fill(index < level ? ink : ink.opacity(metrics.hairlineOpacity * 1.5))
                    .frame(width: metrics.linkMeterBarWidth,
                           height: height * CGFloat(index + 1) / CGFloat(total))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(level) of \(total)"))
    }
}

// MARK: - Progress

/// How far a waiting link is toward its gate: the count in words over a bar.
public struct SomaLinkProgress: View {
    private let fraction: Double
    private let label: String

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - fraction: 0 to 1, clamped.
    ///   - label: the count in words: "3 of 5 nights with Sauna".
    public init(fraction: Double, label: String) {
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        self.label = label
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.linkCardSpacing) {
            Text(verbatim: label)
                .somaFont(theme.typography.callout)
                .foregroundStyle(colors.inkPrimary.color)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.surfaceRecessed.color)
                    Capsule()
                        .fill(colors.accent.color)
                        .frame(width: fraction > 0 ? max(metrics.linkProgressHeight, proxy.size.width * fraction) : 0)
                }
            }
            .frame(height: metrics.linkProgressHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
    }
}
