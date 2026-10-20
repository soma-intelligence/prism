//
//  SomaMetricChart.swift
//  SomaUI
//

import SwiftUI

/// One slot on a metric's chart: an hour, a day, a week or a month.
public struct SomaChartBucket: Identifiable, Equatable, Sendable {
    /// Its place from the left, which is also what it morphs by: the third
    /// bar of a week becomes the third bar of a month.
    public var id: Int
    /// Nil when nothing was recorded in it: an empty slot draws nothing,
    /// never a zero.
    public var value: Double?
    /// The foot of a range drawn as a pill (diastolic under systolic); nil
    /// draws from the plot's foot.
    public var low: Double?
    /// The person's usual over this slot.
    public var band: ClosedRange<Double>?
    /// The label under the plot, when this slot carries one.
    public var axisLabel: String?
    /// When this slot was, as the head says it while a finger rests on it.
    public var readout: String
    /// The value as the head says it.
    public var valueText: String?
    /// What this slot's value means against the usual ("Above your usual"),
    /// shown under the number while a finger rests on it.
    public var note: String?
    /// The tone of that line's dot.
    public var tone: SomaCueTone

    public init(
        id: Int,
        value: Double?,
        low: Double? = nil,
        band: ClosedRange<Double>? = nil,
        axisLabel: String? = nil,
        readout: String,
        valueText: String? = nil,
        note: String? = nil,
        tone: SomaCueTone = .neutral
    ) {
        self.id = id
        self.value = value
        self.low = low
        self.band = band
        self.axisLabel = axisLabel
        self.readout = readout
        self.valueText = valueText
        self.note = note
        self.tone = tone
    }
}

/// How the values are drawn.
public enum SomaMetricChartStyle: Sendable, Equatable {
    /// A daily total or a night: bars from the foot.
    case bars
    /// A reading taken through the day: a soft curve with a fill under it.
    case line
    /// Readings taken now and then: dots, with a faint curve through them.
    case points
    /// A low and a high (blood pressure): a pill from one to the other.
    case ranges
}

/// The span's average, drawn as a quiet dotted line across the plot and
/// named in the key above it.
public struct SomaChartAverage: Equatable, Sendable {
    public var value: Double
    /// As the key says it: "Average 58 bpm".
    public var text: String

    public init(value: Double, text: String) {
        self.value = value
        self.text = text
    }
}

/// A metric's chart, the one that carries a page: the person's usual as a
/// calm band in the chart's hue, the span's average as a dotted line, the
/// values over them with the latest marked, and the highest and lowest
/// named where they sit. A small key above the plot says what the band and
/// the line are, so no fact has to repeat them under the chart.
///
/// It draws itself in when it arrives (bars rise one after another, a line
/// traces left to right) and, when the span changes, every value glides to
/// its new height and place rather than the chart blinking to the next one.
/// Under Reduce Motion it arrives drawn and a new span fades in.
///
/// Drag sideways across the plot, or tap it, to read one slot: a hairline
/// rule and a ringed dot follow the finger, and the slot is handed to
/// `selection`, so the page's head can show it (``SomaMetricStage`` does).
/// Lifting the finger lets go. VoiceOver reads the summary and steps through
/// slots with the adjustable action.
public struct SomaMetricChart: View {
    private let buckets: [SomaChartBucket]
    private let style: SomaMetricChartStyle
    private let hue: SomaHealthHue
    private let domain: ClosedRange<Double>
    private let usualLabel: String?
    private let average: SomaChartAverage?
    private let summary: String
    private let plotHeight: CGFloat?
    private let showsExtremes: Bool
    private let externalSelection: Binding<Int?>?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false
    @State private var ownSelection: Int?
    @State private var isScrubbing = false

    /// - Parameters:
    ///   - buckets: the span's slots, oldest first.
    ///   - domain: the values the plot's foot and top stand for.
    ///   - usualLabel: the band as the key names it: "Usual 56 to 58".
    ///   - average: the span's average, for the dotted line and the key.
    ///   - summary: what VoiceOver reads the chart as.
    ///   - plotHeight: the plot's height; nil takes `metricChartHeight`.
    ///   - showsExtremes: names the highest and lowest values on the plot.
    ///   - selection: the slot a finger rests on; nil keeps it inside.
    public init(
        buckets: [SomaChartBucket],
        style: SomaMetricChartStyle,
        hue: SomaHealthHue,
        domain: ClosedRange<Double>,
        usualLabel: String? = nil,
        average: SomaChartAverage? = nil,
        summary: String,
        plotHeight: CGFloat? = nil,
        showsExtremes: Bool = true,
        selection: Binding<Int?>? = nil
    ) {
        self.buckets = buckets
        self.style = style
        self.hue = hue
        self.domain = domain
        self.usualLabel = usualLabel
        self.average = average
        self.summary = summary
        self.plotHeight = plotHeight
        self.showsExtremes = showsExtremes
        self.externalSelection = selection
    }

    private var values: [Double?] { buckets.map(\.value) }
    private var isEmpty: Bool { buckets.allSatisfy { $0.value == nil } }
    private var latest: Int? { buckets.lastIndex { $0.value != nil } }
    private var selected: Int? { externalSelection.map(\.wrappedValue) ?? ownSelection }
    private var picked: SomaChartBucket? { selected.flatMap { buckets.indices.contains($0) ? buckets[$0] : nil } }
    private var hasBand: Bool { buckets.contains { $0.band != nil } }

    private func select(_ index: Int?) {
        if let externalSelection {
            externalSelection.wrappedValue = index
        } else {
            ownSelection = index
        }
    }

    /// What changes the drawn data, and so what a morph keys on.
    private var shape: [Double?] {
        buckets.map(\.value) + buckets.map(\.low) + [domain.lowerBound, domain.upperBound, average?.value]
    }

    public var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.chartLabelGap) {
            if usualLabel != nil || average != nil || plotHeight != nil {
                // A stage's chart keeps the key's line even when a span has
                // nothing to name (a day of a total), so the plot never jumps
                // as the span changes.
                key
                    .padding(.bottom, metrics.chartLabelGap)
            }
            plot
                .frame(height: plotHeight ?? metrics.metricChartHeight)
            axis
        }
        .onAppear { draw() }
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAdjustableAction { direction in
            let known = buckets.indices.filter { buckets[$0].value != nil }
            guard !known.isEmpty else { return }
            let current = selected ?? latest ?? known[known.count - 1]
            switch direction {
            case .increment: select(known.first { $0 > current } ?? current)
            case .decrement: select(known.last { $0 < current } ?? current)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        if let picked { return [picked.readout, picked.valueText, picked.note].compactMap { $0 }.joined(separator: ", ") }
        return [average?.text, usualLabel].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: - Key

    /// What the dotted line and the band are, in a line above the plot.
    private var key: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let swatch = metrics.metricChartKeySwatch

        return ZStack(alignment: .leading) {
            // Holds the line's height when there is nothing to name.
            Text(verbatim: " ")
                .hidden()
            HStack(spacing: metrics.cardSpacing) {
                if let average {
                    HStack(spacing: metrics.metricHeroSpacing * 1.5) {
                        SomaLevelShape(level: 0.5)
                            .stroke(colors.inkSecondary.color, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: metrics.metricChartAverageDash))
                            .frame(width: swatch, height: swatch / 2)
                        Text(average.text)
                            .somaRollingNumber(average.text)
                    }
                }
                if let usualLabel, hasBand {
                    HStack(spacing: metrics.metricHeroSpacing * 1.5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(bandTint.opacity(metrics.metricChartBandOpacity * 2))
                            .overlay {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(bandTint.opacity(metrics.metricChartBandEdgeOpacity), lineWidth: 0.5)
                            }
                            .frame(width: swatch, height: swatch * 0.6)
                        Text(usualLabel)
                    }
                }
            }
        }
        .somaFont(theme.typography.caption)
        .foregroundStyle(colors.inkSecondary.color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .animation(reduceMotion ? nil : theme.motion.numberRoll, value: average)
    }

    // MARK: - Plot

    private var plot: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                band(in: size)
                Rectangle()
                    .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.chartGridOpacity))
                    .frame(width: size.width, height: 0.5)
                    .offset(y: size.height - 0.5)
                averageLine
                switch style {
                case .bars, .ranges: bars(in: size)
                case .line: line(in: size)
                case .points: points(in: size)
                }
                extremes(in: size)
                rule(in: size)
                if isEmpty {
                    Text("Nothing recorded in this span")
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                }
            }
            // Under Reduce Motion a new span is a new plot that fades in over
            // the old one, rather than values travelling to their places.
            .id(reduceMotion ? AnyHashable(shape) : AnyHashable(0))
            .transition(.opacity)
            .contentShape(.rect)
            // A sideways drag here reads the chart, not the tab's parts.
            .somaClaimsSwipe()
            .simultaneousGesture(scrub(width: size.width))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    let index = SomaChartMath.nearestKnown(SomaChartMath.slot(at: tap.location.x / max(1, size.width), count: buckets.count), in: values)
                    withAnimation(reduceMotion ? nil : theme.motion.chartScrub) {
                        select(selected == index ? nil : index)
                    }
                }
            )
        }
        .animation(reduceMotion ? theme.motion.chartFade : theme.motion.chartMorph, value: shape)
    }

    /// Sideways drags read slots; a drag that starts upright is left to the
    /// page's scroll.
    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: theme.metrics.metricChartScrubReach)
            .onChanged { drag in
                if !isScrubbing {
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    isScrubbing = true
                }
                let slot = SomaChartMath.slot(at: drag.location.x / max(1, width), count: buckets.count)
                let index = SomaChartMath.nearestKnown(slot, in: values)
                guard index != selected else { return }
                withAnimation(reduceMotion ? nil : theme.motion.chartScrub) { select(index) }
            }
            .onEnded { _ in
                guard isScrubbing else { return }
                isScrubbing = false
                withAnimation(reduceMotion ? nil : theme.motion.chartScrub) { select(nil) }
            }
    }

    /// The band's tint: the chart's hue softened most of the way to the
    /// secondary ink, calm in both appearances.
    private var bandTint: Color {
        hue.color.mix(with: theme.colors.inkSecondary.color, by: theme.metrics.metricChartBandMix)
    }

    @ViewBuilder
    private func band(in size: CGSize) -> some View {
        let lower = buckets.map { $0.band?.lowerBound }
        let upper = buckets.map { $0.band?.upperBound }
        if lower.contains(where: { $0 != nil }) {
            let metrics = theme.metrics
            let low = SomaChartMath.curve(lower, domain: domain, count: metrics.metricChartSamples)
            let high = SomaChartMath.curve(upper, domain: domain, count: metrics.metricChartSamples)
            ZStack {
                SomaBandShape(lower: low, upper: high)
                    .fill(bandTint.opacity(metrics.metricChartBandOpacity))
                SomaCurveShape(curve: high, closed: false, spansWidth: true)
                    .stroke(bandTint.opacity(metrics.metricChartBandEdgeOpacity), lineWidth: 0.5)
                SomaCurveShape(curve: low, closed: false, spansWidth: true)
                    .stroke(bandTint.opacity(metrics.metricChartBandEdgeOpacity), lineWidth: 0.5)
            }
            .opacity(isDrawn ? 1 : 0)
            .transition(.opacity)
        }
    }

    /// The span's average as a dotted line across the plot.
    @ViewBuilder
    private var averageLine: some View {
        if let average, !isEmpty {
            let metrics = theme.metrics
            SomaLevelShape(level: SomaChartMath.height(average.value, in: domain))
                .stroke(
                    theme.colors.inkSecondary.color.opacity(metrics.metricChartAverageOpacity),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: metrics.metricChartAverageDash)
                )
                .opacity(isDrawn ? 1 : 0)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    /// The full hue for the slot being read (the latest, or the one under a
    /// finger); the rest take the hue softened toward the secondary ink, so
    /// history stays calm in both appearances instead of going muddy on a
    /// dark ground.
    private func tint(at index: Int) -> Color {
        let lead = selected ?? latest
        guard index != lead else { return hue.color }
        let metrics = theme.metrics
        return hue.color
            .mix(with: theme.colors.inkSecondary.color, by: metrics.metricChartContextMix)
            .opacity(metrics.metricChartContextOpacity)
    }

    private func bars(in size: CGSize) -> some View {
        let metrics = theme.metrics
        let count = buckets.count
        let width = SomaChartMath.barWidth(
            count: count, width: size.width, share: metrics.metricChartBarShare,
            minimum: metrics.metricChartBarMinWidth, maximum: metrics.metricChartBarMaxWidth
        )
        let stagger = theme.motion.chartStagger

        return ForEach(buckets) { bucket in
            if let value = bucket.value {
                let top = SomaChartMath.height(value, in: domain)
                let foot = style == .ranges ? SomaChartMath.height(bucket.low ?? value, in: domain) : 0
                let height = max(width * 0.5, CGFloat(top - foot) * size.height)
                let x = SomaChartMath.center(of: bucket.id, count: count) * size.width
                Capsule(style: .continuous)
                    .fill(tint(at: bucket.id))
                    .frame(width: width, height: height)
                    .clipShape(style == .bars ? AnyShape(UnevenRoundedRectangle(
                        topLeadingRadius: width / 2, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: width / 2, style: .continuous
                    )) : AnyShape(Capsule(style: .continuous)))
                    .scaleEffect(x: 1, y: isDrawn ? 1 : 0.001, anchor: .bottom)
                    .animation(
                        reduceMotion ? nil : theme.motion.chartDraw.delay(stagger * Double(bucket.id) / Double(max(1, count))),
                        value: isDrawn
                    )
                    .position(x: x, y: size.height - CGFloat(foot) * size.height - height / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)))
            }
        }
    }

    private func line(in size: CGSize) -> some View {
        let metrics = theme.metrics
        let curve = SomaChartMath.curve(values, domain: domain, count: metrics.metricChartSamples)
        let color = hue.color

        return ZStack(alignment: .topLeading) {
            if !curve.isEmpty {
                SomaCurveShape(curve: curve, closed: true)
                    .fill(LinearGradient(
                        colors: [color.opacity(metrics.metricChartFillOpacity), color.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: isDrawn ? 1 : 0, anchor: .leading)
                    }
                SomaCurveShape(curve: curve, closed: false)
                    .trim(from: 0, to: isDrawn ? 1 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: metrics.metricChartLine, lineCap: .round, lineJoin: .round))
            }
            dots(in: size, all: false)
        }
    }

    private func points(in size: CGSize) -> some View {
        let metrics = theme.metrics
        let curve = SomaChartMath.curve(values, domain: domain, count: metrics.metricChartSamples)

        return ZStack(alignment: .topLeading) {
            if !curve.isEmpty {
                SomaCurveShape(curve: curve, closed: false)
                    .trim(from: 0, to: isDrawn ? 1 : 0)
                    .stroke(hue.color.opacity(metrics.metricChartContextOpacity), style: StrokeStyle(lineWidth: metrics.chartStroke, lineCap: .round, lineJoin: .round))
            }
            dots(in: size, all: true)
        }
    }

    /// Every reading on a sparse chart; on a line, the latest and the one a
    /// finger rests on. The one being read wears a soft halo.
    private func dots(in size: CGSize, all: Bool) -> some View {
        let metrics = theme.metrics
        let count = buckets.count
        return ForEach(buckets) { bucket in
            if let value = bucket.value, all || bucket.id == latest || bucket.id == selected {
                let lead = bucket.id == (selected ?? latest)
                let diameter = lead ? metrics.metricChartEndDot : metrics.metricChartPoint
                ZStack {
                    if lead {
                        Circle()
                            .fill(hue.color.opacity(metrics.metricChartHaloOpacity))
                            .frame(width: diameter * metrics.metricChartHaloScale, height: diameter * metrics.metricChartHaloScale)
                    }
                    Circle()
                        .fill(all && !lead ? tint(at: bucket.id) : theme.colors.surface.color)
                        .overlay {
                            if !all || lead { Circle().strokeBorder(hue.color, lineWidth: metrics.metricChartLine) }
                        }
                        .frame(width: diameter, height: diameter)
                }
                .position(
                    x: SomaChartMath.center(of: bucket.id, count: count) * size.width,
                    y: (1 - SomaChartMath.height(value, in: domain)) * size.height
                )
                .opacity(isDrawn ? 1 : 0)
                .animation(
                    reduceMotion ? nil : theme.motion.chartDraw.delay(theme.motion.chartStagger * Double(bucket.id) / Double(max(1, count))),
                    value: isDrawn
                )
                .transition(.opacity)
            }
        }
    }

    /// The highest and lowest values before the latest, named where they
    /// sit; they step back
    /// while a finger reads the chart, when the head says the value instead.
    @ViewBuilder
    private func extremes(in size: CGSize) -> some View {
        if showsExtremes, style != .ranges, let marks = SomaChartMath.extremes(values, excluding: latest) {
            let metrics = theme.metrics
            let labelHeight = theme.typography.captionValue.size * 1.3
            let gap = metrics.metricChartExtremeGap
            let inset = metrics.metricChartLabelInset
            // On bars only the high is named: the low sits among taller
            // bars, where its label would lie across them.
            ForEach(style == .bars ? [marks.high] : [marks.high, marks.low], id: \.self) { index in
                if let value = buckets[index].value, let text = buckets[index].valueText {
                    let isHigh = index == marks.high
                    let markY = (1 - SomaChartMath.height(value, in: domain)) * size.height
                    let dot = metrics.metricChartEndDot / 2
                    // A bar's label sits on its top; a dot's above or under it.
                    let below = !isHigh && style != .bars
                    let y = below ? markY + dot + gap + labelHeight / 2 : markY - dot - gap - labelHeight / 2
                    let x = min(max(SomaChartMath.center(of: index, count: buckets.count) * size.width, inset), size.width - inset)
                    // A label that would sit on the latest mark gives way to it.
                    // A label held in from the edge would sit off its mark, and
                    // one beside the latest would sit on its line: both give way.
                    let held = abs(x - SomaChartMath.center(of: index, count: buckets.count) * size.width) > 1
                    let besideLatest = latest.map { abs($0 - index) <= 1 } ?? false
                    if !collidesWithLatest(x: x, y: y, in: size, labelHeight: labelHeight), !(held && besideLatest) {
                    Text(text)
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize()
                        .position(x: x, y: min(max(y, labelHeight / 2), size.height - labelHeight / 2))
                    }
                }
            }
            .opacity(isDrawn && selected == nil ? 1 : 0)
            .animation(reduceMotion ? nil : theme.motion.chartScrub, value: selected == nil)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Whether a label centred at `x`, `y` would cover the latest mark.
    private func collidesWithLatest(x: CGFloat, y: CGFloat, in size: CGSize, labelHeight: CGFloat) -> Bool {
        guard let latest, let value = buckets[latest].value else { return false }
        let markX = SomaChartMath.center(of: latest, count: buckets.count) * size.width
        let markY = (1 - SomaChartMath.height(value, in: domain)) * size.height
        let reach = theme.metrics.metricChartEndDot * theme.metrics.metricChartHaloScale / 2
        return abs(markX - x) < theme.metrics.metricChartLabelInset + reach
            && abs(markY - y) < labelHeight / 2 + reach
    }

    @ViewBuilder
    private func rule(in size: CGSize) -> some View {
        if let selected {
            Rectangle()
                .fill(theme.colors.inkPrimary.color.opacity(0.3))
                .frame(width: 1, height: size.height)
                .position(x: SomaChartMath.center(of: selected, count: buckets.count) * size.width, y: size.height / 2)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Labels

    private var axis: some View {
        GeometryReader { proxy in
            ForEach(buckets) { bucket in
                if let label = bucket.axisLabel {
                    Text(label)
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                        .fixedSize()
                        // Held in from the edges, so "12 AM" under the first
                        // hour is never cut in half.
                        .position(
                            x: min(max(SomaChartMath.center(of: bucket.id, count: buckets.count) * proxy.size.width, theme.metrics.metricChartLabelInset),
                                   proxy.size.width - theme.metrics.metricChartLabelInset),
                            y: proxy.size.height / 2
                        )
                }
            }
        }
        .frame(height: theme.typography.captionValue.size * 1.4)
        .animation(reduceMotion ? theme.motion.chartFade : theme.motion.chartMorph, value: buckets.map(\.axisLabel))
    }

    private func draw() {
        guard !isDrawn else { return }
        if reduceMotion {
            isDrawn = true
        } else {
            withAnimation(theme.motion.chartDraw) { isDrawn = true }
        }
    }
}


// MARK: - Shapes

/// A curve across the plot, open for the stroke or closed down to the foot
/// for the fill under it. Its samples interpolate, so it morphs.
struct SomaCurveShape: Shape {
    var curve: SomaChartCurve
    var closed: Bool
    /// Spread the samples across the whole width rather than between the
    /// first and last slots' centres, as the band's edges are.
    var spansWidth = false

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, SomaAnimatableVector> {
        get { AnimatablePair(AnimatablePair(curve.start, curve.end), SomaAnimatableVector(curve.samples)) }
        set {
            curve.start = newValue.first.first
            curve.end = newValue.first.second
            curve.samples = newValue.second.values
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let samples = curve.samples
        guard samples.count >= 2 else { return path }
        let start = spansWidth ? 0 : curve.start
        let end = spansWidth ? 1 : curve.end
        let points = samples.enumerated().map { index, value in
            CGPoint(
                x: rect.minX + (start + (end - start) * Double(index) / Double(samples.count - 1)) * rect.width,
                y: rect.minY + (1 - value) * rect.height
            )
        }
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed, let first = points.first, let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// A level line across the plot, at a share of its height from the foot.
struct SomaLevelShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.minY + (1 - level) * rect.height
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

/// The person's usual: the area between its lower and upper edges, carried
/// to the plot's sides so it reads as a ground rather than a shape.
struct SomaBandShape: Shape {
    var lower: SomaChartCurve
    var upper: SomaChartCurve

    var animatableData: AnimatablePair<SomaAnimatableVector, SomaAnimatableVector> {
        get { AnimatablePair(SomaAnimatableVector(lower.samples), SomaAnimatableVector(upper.samples)) }
        set {
            lower.samples = newValue.first.values
            upper.samples = newValue.second.values
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = min(lower.samples.count, upper.samples.count)
        guard count >= 2 else { return path }
        func point(_ index: Int, _ value: Double) -> CGPoint {
            CGPoint(x: rect.minX + Double(index) / Double(count - 1) * rect.width, y: rect.minY + (1 - value) * rect.height)
        }
        path.move(to: point(0, upper.samples[0]))
        for index in 1..<count { path.addLine(to: point(index, upper.samples[index])) }
        for index in stride(from: count - 1, through: 0, by: -1) { path.addLine(to: point(index, lower.samples[index])) }
        path.closeSubpath()
        return path
    }
}

/// Thirty days of a reading for the preview: a resting heart rate around its
/// usual, a gap where nothing was recorded.
private let previewHeartDays: [SomaChartBucket] = (0..<30).map { index in
    let value: Double? = index % 11 == 7 ? nil : 57 + Double((index * 7) % 9) - 4
    return SomaChartBucket(id: index, value: value, band: 54...60,
                           axisLabel: index % 7 == 0 ? "\(index + 1)" : nil,
                           readout: "Day \(index + 1)", valueText: value.map { "\(Int($0))" })
}

/// A week of steps as bars.
private let previewStepDays: [SomaChartBucket] = ["M", "T", "W", "T", "F", "S", "S"].enumerated().map { index, day in
    let value = [6_200.0, 8_900, 4_300, 10_400, 7_700, 12_100, 3_900][index]
    return SomaChartBucket(id: index, value: value, band: 5_500...9_000, axisLabel: day,
                           readout: day, valueText: value.formatted(.number.precision(.fractionLength(0))))
}

#Preview("Metric chart") {
    ZStack {
        SomaPreviewBackdrop()
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SomaMetricChart(buckets: previewHeartDays, style: .line, hue: .heart, domain: 48...66,
                                usualLabel: "Usual 54 to 60", average: SomaChartAverage(value: 57, text: "Average 57 bpm"),
                                summary: "Resting heart rate, last 30 days", plotHeight: 248)
                SomaMetricChart(buckets: previewStepDays, style: .bars, hue: .activity, domain: 0...13_000,
                                usualLabel: "Usual 5,500 to 9,000", average: SomaChartAverage(value: 7_643, text: "Average 7,643"),
                                summary: "Steps this week")
                SomaMetricChart(buckets: [], style: .points, hue: .body, domain: 0...1, summary: "No readings yet")
            }
            .padding()
        }
    }
}
