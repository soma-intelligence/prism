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
    /// When this slot was, as the readout says it while a finger rests on it.
    public var readout: String
    /// The value as the readout says it.
    public var valueText: String?

    public init(
        id: Int,
        value: Double?,
        low: Double? = nil,
        band: ClosedRange<Double>? = nil,
        axisLabel: String? = nil,
        readout: String,
        valueText: String? = nil
    ) {
        self.id = id
        self.value = value
        self.low = low
        self.band = band
        self.axisLabel = axisLabel
        self.readout = readout
        self.valueText = valueText
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

/// A metric's chart: the person's usual as a quiet band of ink behind, the
/// values over it in the category's hue, the latest one full and the rest quieter,
/// and a readout above that names the span until a finger reads one slot.
///
/// It draws itself in when it arrives (bars rise one after another, a line
/// traces left to right) and, when the span changes, every value glides to
/// its new height and place rather than the chart blinking to the next one.
/// Under Reduce Motion it arrives drawn and a new span fades in.
///
/// Drag sideways across the plot, or tap it, to read one slot; the readout
/// and a hairline rule follow the finger, and lifting it lets go. VoiceOver
/// reads the summary and steps through slots with the adjustable action.
public struct SomaMetricChart: View {
    private let buckets: [SomaChartBucket]
    private let style: SomaMetricChartStyle
    private let hue: SomaHealthHue
    private let domain: ClosedRange<Double>
    private let bandLabels: (low: String, high: String)?
    private let summaryLabel: String
    private let summaryValue: String?
    private let unit: String?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false
    @State private var selected: Int?
    @State private var isScrubbing = false

    /// - Parameters:
    ///   - buckets: the span's slots, oldest first.
    ///   - domain: the values the plot's foot and top stand for.
    ///   - bandLabels: the usual's edges as the gutter names them.
    ///   - summaryLabel: what the readout says with no slot picked, such as
    ///     "Average, Sep 20 to Oct 19".
    ///   - summaryValue: the span's number for that line, nil for a dash.
    ///   - unit: set small after any number the readout shows.
    public init(
        buckets: [SomaChartBucket],
        style: SomaMetricChartStyle,
        hue: SomaHealthHue,
        domain: ClosedRange<Double>,
        bandLabels: (low: String, high: String)? = nil,
        summaryLabel: String,
        summaryValue: String?,
        unit: String? = nil
    ) {
        self.buckets = buckets
        self.style = style
        self.hue = hue
        self.domain = domain
        self.bandLabels = bandLabels
        self.summaryLabel = summaryLabel
        self.summaryValue = summaryValue
        self.unit = unit
    }

    private var values: [Double?] { buckets.map(\.value) }
    private var isEmpty: Bool { buckets.allSatisfy { $0.value == nil } }
    private var latest: Int? { buckets.lastIndex { $0.value != nil } }
    private var picked: SomaChartBucket? { selected.flatMap { buckets.indices.contains($0) ? buckets[$0] : nil } }

    /// What changes the drawn data, and so what a morph keys on.
    private var shape: [Double?] { buckets.map(\.value) + buckets.map(\.low) + [domain.lowerBound, domain.upperBound] }

    public var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
            readout
            HStack(alignment: .top, spacing: metrics.chartLabelGap) {
                VStack(spacing: metrics.chartLabelGap) {
                    plot
                        .frame(height: metrics.metricChartHeight)
                    axis
                }
                gutter
                    .frame(width: metrics.metricChartGutter, height: metrics.metricChartHeight, alignment: .leading)
            }
        }
        .onAppear { draw() }
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summaryLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAdjustableAction { direction in
            let known = buckets.indices.filter { buckets[$0].value != nil }
            guard !known.isEmpty else { return }
            let current = selected ?? latest ?? known[known.count - 1]
            switch direction {
            case .increment: selected = known.first { $0 > current } ?? current
            case .decrement: selected = known.last { $0 < current } ?? current
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        if let picked { return [picked.readout, picked.valueText, unit].compactMap { $0 }.joined(separator: " ") }
        return [summaryValue ?? "-", unit].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - Readout

    private var readout: some View {
        let colors = theme.colors
        let label = picked?.readout ?? summaryLabel
        let value = picked == nil ? summaryValue : picked?.valueText

        return VStack(alignment: .leading, spacing: theme.metrics.metricFactSpacing) {
            Text(label)
                .somaFont(theme.typography.caption)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
                .contentTransition(.opacity)
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.scoreLabelSpacing * 2) {
                Text(value ?? "-")
                    .somaFont(theme.typography.metricFact)
                    .foregroundStyle(colors.inkPrimary.color)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let unit, value != nil {
                    Text(unit)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
        }
        .animation(reduceMotion ? nil : theme.motion.chartScrub, value: label)
        .animation(reduceMotion ? nil : theme.motion.numberRoll, value: value)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                switch style {
                case .bars, .ranges: bars(in: size)
                case .line: line(in: size)
                case .points: points(in: size)
                }
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
            .simultaneousGesture(scrub(width: size.width))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    let index = SomaChartMath.nearestKnown(SomaChartMath.slot(at: tap.location.x / max(1, size.width), count: buckets.count), in: values)
                    withAnimation(reduceMotion ? nil : theme.motion.chartScrub) {
                        selected = selected == index ? nil : index
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
                withAnimation(reduceMotion ? nil : theme.motion.chartScrub) { selected = index }
            }
            .onEnded { _ in
                guard isScrubbing else { return }
                isScrubbing = false
                withAnimation(reduceMotion ? nil : theme.motion.chartScrub) { selected = nil }
            }
    }

    @ViewBuilder
    private func band(in size: CGSize) -> some View {
        let lower = buckets.map { $0.band?.lowerBound }
        let upper = buckets.map { $0.band?.upperBound }
        if lower.contains(where: { $0 != nil }) {
            SomaBandShape(
                lower: SomaChartMath.curve(lower, domain: domain, count: theme.metrics.metricChartSamples),
                upper: SomaChartMath.curve(upper, domain: domain, count: theme.metrics.metricChartSamples)
            )
            .fill(theme.colors.inkPrimary.color.opacity(theme.metrics.metricChartBandOpacity))
            .opacity(isDrawn ? 1 : 0)
            .transition(.opacity)
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
    /// finger rests on.
    private func dots(in size: CGSize, all: Bool) -> some View {
        let metrics = theme.metrics
        let count = buckets.count
        return ForEach(buckets) { bucket in
            if let value = bucket.value, all || bucket.id == latest || bucket.id == selected {
                let lead = bucket.id == (selected ?? latest)
                let diameter = lead ? metrics.metricChartEndDot : metrics.metricChartPoint
                Circle()
                    .fill(all && !lead ? tint(at: bucket.id) : theme.colors.surface.color)
                    .overlay {
                        if !all || lead { Circle().strokeBorder(hue.color, lineWidth: metrics.metricChartLine) }
                    }
                    .frame(width: diameter, height: diameter)
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

    /// The usual's two edges on the trailing side, or the plot's top and
    /// foot when there is no usual yet.
    private var gutter: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let latestBand = latest.flatMap { buckets[$0].band } ?? buckets.compactMap(\.band).last
            let labelHeight = theme.typography.captionValue.size * 1.3
            if let bandLabels, let latestBand {
                let high = (1 - SomaChartMath.height(latestBand.upperBound, in: domain)) * height
                let low = (1 - SomaChartMath.height(latestBand.lowerBound, in: domain)) * height
                if low - high < labelHeight {
                    label(bandLabels.high, y: (high + low) / 2, height: height)
                } else {
                    label(bandLabels.high, y: high, height: height)
                    label(bandLabels.low, y: low, height: height)
                }
            }
        }
        .opacity(isDrawn ? 1 : 0)
    }

    private func label(_ text: String, y: CGFloat, height: CGFloat) -> some View {
        Text(text)
            .somaFont(theme.typography.captionValue)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: theme.metrics.metricChartGutter, alignment: .leading)
            .position(x: theme.metrics.metricChartGutter / 2, y: min(max(y, 8), height - 8))
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
        let points = samples.enumerated().map { index, value in
            CGPoint(
                x: rect.minX + (curve.start + (curve.end - curve.start) * Double(index) / Double(samples.count - 1)) * rect.width,
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
                                bandLabels: ("54", "60"), summaryLabel: "Average, last 30 days",
                                summaryValue: "57", unit: "bpm")
                SomaMetricChart(buckets: previewStepDays, style: .bars, hue: .activity, domain: 0...13_000,
                                summaryLabel: "Average, this week", summaryValue: "7,643", unit: "steps")
                SomaMetricChart(buckets: [], style: .points, hue: .body, domain: 0...1,
                                summaryLabel: "No readings yet", summaryValue: nil)
            }
            .padding()
        }
    }
}
