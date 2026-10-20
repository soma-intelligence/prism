//
//  MindStressDayChart.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Stress across the whole day, last night first: the night lies on a faint
/// ground of the sleep hue with a moon and its word, the day follows it, and
/// one line on one scale runs through both, taking the colour of the zone it
/// passes through over the three zones as faint bands. A finger held on the
/// plot scrubs it, the value and the time riding in the header. A tap reads
/// one half hour; a second tap lets it go.
struct MindStressDayChart: View {
    let samples: [MindStressSample]
    let dayStart: Date
    /// Last night, read on the same scale. Nil draws the day alone.
    var night: MindStressNight? = nil

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: MindStressSample?

    /// Two half hours apart or more breaks the line: nothing was read.
    private static let gap: TimeInterval = 45 * 60

    private var axis: MindStressAxis { MindStressAxis(dayStart: dayStart, night: night) }

    /// Night and day together, oldest first.
    private var all: [MindStressSample] { (night?.samples ?? []) + samples }

    var body: some View {
        let metrics = theme.metrics
        let shown = selected ?? samples.last ?? night?.samples.last
        let axis = axis

        VStack(alignment: .leading, spacing: metrics.chartLabelGap * 2) {
            readout(shown, isScrubbing: selected != nil)

            HStack(alignment: .top, spacing: metrics.chartLabelGap) {
                VStack(spacing: metrics.chartLabelGap) {
                    plot
                        .frame(height: metrics.chartPlotHeight)
                    hours(axis)
                }
                scale
                    .frame(height: metrics.chartPlotHeight)
            }
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }

    // MARK: Header

    private func readout(_ sample: MindStressSample?, isScrubbing: Bool) -> some View {
        let type = theme.typography
        let colors = theme.colors
        let asleep = sample.map { axis.isNight($0.start) } ?? false
        let when: String? = sample.map { sample in
            if isScrubbing { return ScoreMath.clock(sample.start) }
            return asleep ? String(localized: "Last night") : String(localized: "Now")
        }

        return HStack(alignment: .firstTextBaseline, spacing: theme.metrics.trendMarkSpacing * 2) {
            Text(sample.map { MindLensFormat.whole($0.value) } ?? "-")
                .somaFont(type.metric)
                .foregroundStyle(colors.inkPrimary.color)
                .somaRollingNumber(sample.map { MindLensFormat.whole($0.value) }, holdsWidth: true)
            if let sample {
                Text(sample.zone.title)
                    .somaFont(type.callout)
                    .foregroundStyle(sample.zone.color)
            }
            Spacer(minLength: 0)
            if let when {
                HStack(spacing: theme.metrics.trendMarkSpacing) {
                    if asleep {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(theme.aspects[.sleep].identity.color)
                            .accessibilityHidden(true)
                    }
                    Text(when)
                }
                .somaFont(type.captionValue)
                .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .animation(reduceMotion ? nil : theme.motion.selection, value: sample?.id)
    }

    // MARK: Plot

    private var plot: some View {
        let theme = theme
        let axis = axis
        let all = all
        let selected = selected
        let ticks: [Double] = [0, ScorePages.stressBands.moderate, ScorePages.stressBands.high, 100]
        let zones = MindZone.allCases.map { (range: $0.range, color: $0.color) }
        let pen = SomaPen(theme)
        let inset = theme.metrics.chartPlotInset
        let slots = MindStressSlots(all, dayStart: dayStart, night: night)
        let line = LinearGradient(gradient: Self.gradient, startPoint: .bottom, endPoint: .top)
        let wash = LinearGradient(gradient: Self.gradient(opacity: pen.fillOpacity * 1.6, fades: true),
                                  startPoint: .bottom, endPoint: .top)
        let sleepHue = theme.aspects[.sleep].identity.color

        return ZStack(alignment: .topLeading) {
            // The zones, faint, behind everything; the night's ground over
            // them, so the night reads as its own stretch of the day.
            Canvas { context, size in
                let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(value / 100) }
                for zone in zones {
                    let band = CGRect(x: 0, y: y(zone.range.upperBound), width: size.width,
                                      height: y(zone.range.lowerBound) - y(zone.range.upperBound))
                    context.fill(Path(band), with: .color(zone.color.opacity(pen.bandOpacity * 0.45)))
                }
                if let span = axis.nightSpan {
                    let left = plot.minX + plot.width * CGFloat(span.lowerBound)
                    let right = plot.minX + plot.width * CGFloat(span.upperBound)
                    let ground = Path(roundedRect: CGRect(x: left, y: 0, width: max(right - left, 1), height: size.height),
                                      cornerRadius: inset)
                    // The card's own ground first, so the zones stop at the
                    // night rather than tinting it.
                    context.fill(ground, with: .color(pen.surface))
                    context.fill(ground, with: .color(sleepHue.opacity(pen.bandOpacity)))
                    pen.vertical(context, x: right, height: size.height, color: sleepHue.opacity(theme.metrics.chartNightEdgeOpacity))
                }
                for tick in ticks {
                    pen.gridline(context, y: y(tick), to: size.width)
                }
            }

            // The line and the light under it morph from one read to the next.
            Group {
                MindStressLineShape(slots: slots, axis: axis, part: .area).fill(wash)
                MindStressLineShape(slots: slots, axis: axis, part: .line)
                    .stroke(line, style: StrokeStyle(lineWidth: pen.stroke * 1.4, lineCap: .round, lineJoin: .round))
                MindStressLineShape(slots: slots, axis: axis, part: .dots(pen.point)).fill(line)
            }
            .padding(inset)
            .animation(reduceMotion ? nil : theme.motion.chartMorph, value: slots)

            Canvas { context, size in
                let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(value / 100) }
                func x(_ date: Date) -> CGFloat {
                    plot.minX + plot.width * CGFloat(axis.fraction(date.addingTimeInterval(15 * 60)))
                }
                if let latest = all.last, selected == nil {
                    pen.ring(context, at: CGPoint(x: x(latest.start), y: y(latest.value)), color: latest.zone.color)
                }
                if let selected {
                    let point = CGPoint(x: x(selected.start), y: y(selected.value))
                    pen.vertical(context, x: point.x, height: size.height, color: pen.inkSecondary)
                    let outer = pen.ring * 1.3
                    context.fill(Path(ellipseIn: CGRect(x: point.x - outer / 2, y: point.y - outer / 2, width: outer, height: outer)),
                                 with: .color(pen.surface))
                    let inner = pen.ring
                    context.fill(Path(ellipseIn: CGRect(x: point.x - inner / 2, y: point.y - inner / 2, width: inner, height: inner)),
                                 with: .color(selected.zone.color))
                }
            }

            parts(axis)
        }
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(.rect)
                    .somaClaimsSwipe()
                    .gesture(scrub(width: proxy.size.width))
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            let hit = nearest(to: value.location.x, width: proxy.size.width)
                            self.selected = hit == self.selected ? nil : hit
                        }
                    )
                    #if os(macOS)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): self.selected = nearest(to: location.x, width: proxy.size.width)
                        case .ended: self.selected = nil
                        }
                    }
                    #endif
            }
        }
        .accessibilityElement()
        .accessibilityLabel(night == nil ? "Stress today" : "Stress, last night and today")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let all = self.all
            guard !all.isEmpty else { return }
            let index = selected.flatMap { all.firstIndex(of: $0) } ?? all.count - 1
            switch direction {
            case .increment: self.selected = all[min(index + 1, all.count - 1)]
            case .decrement: self.selected = all[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }

    /// "Night" with its moon over the night's ground, "Day" after waking.
    @ViewBuilder
    private func parts(_ axis: MindStressAxis) -> some View {
        if let span = axis.nightSpan {
            let inset = theme.metrics.chartPlotInset
            let gap = theme.metrics.trendMarkSpacing
            GeometryReader { proxy in
                let width = proxy.size.width - inset * 2
                HStack(spacing: gap) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(theme.aspects[.sleep].identity.color)
                    Text("Night")
                }
                .fixedSize()
                .offset(x: inset * 2 + width * CGFloat(span.lowerBound), y: inset * 2)
                Text("Day")
                    .fixedSize()
                    .offset(x: inset * 3 + width * CGFloat(span.upperBound), y: inset * 2)
            }
            .somaFont(theme.typography.captionValue)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The clock hours under the plot, each where its hour falls.
    private func hours(_ axis: MindStressAxis) -> some View {
        let inset = theme.metrics.chartPlotInset
        return GeometryReader { proxy in
            let width = proxy.size.width - inset * 2
            ForEach(axis.ticks, id: \.label) { tick in
                Text(verbatim: tick.label)
                    .fixedSize()
                    .position(x: inset + width * CGFloat(tick.fraction), y: proxy.size.height / 2)
            }
        }
        .frame(height: theme.typography.captionValue.size * 1.4)
        .somaFont(theme.typography.captionValue)
        .foregroundStyle(theme.colors.inkSecondary.color)
        .accessibilityHidden(true)
    }

    /// Held, then dragged: the scroll keeps a quick swipe, the chart keeps a
    /// finger that rests first.
    private func scrub(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    selected = nearest(to: drag.location.x, width: width)
                }
            }
    }

    private func nearest(to locationX: CGFloat, width: CGFloat) -> MindStressSample? {
        let inset = theme.metrics.chartPlotInset
        let fraction = Double((locationX - inset) / max(width - inset * 2, 1))
        let time = axis.date(at: fraction).addingTimeInterval(-15 * 60)
        guard let best = all.min(by: { abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time)) }),
              abs(best.start.timeIntervalSince(time)) < Self.gap else { return nil }
        return best
    }

    private var scale: some View {
        GeometryReader { proxy in
            let inset = theme.metrics.chartPlotInset
            let height = proxy.size.height - inset * 2
            ForEach([0.0, 50, 100], id: \.self) { tick in
                Text(verbatim: MindLensFormat.whole(tick))
                    .fixedSize()
                    .position(x: proxy.size.width / 2, y: inset + height * CGFloat(1 - tick / 100))
            }
        }
        .frame(width: theme.metrics.miniOrbDiameter / 2)
        .somaFont(theme.typography.captionValue)
        .foregroundStyle(theme.colors.inkSecondary.color)
        .accessibilityHidden(true)
    }

    private var accessibilityValue: Text {
        guard let shown = selected ?? samples.last ?? night?.samples.last else { return Text("No reading yet") }
        let part = axis.isNight(shown.start) ? String(localized: "asleep") : ""
        return Text("\(MindLensFormat.whole(shown.value)), \(Text(shown.zone.title)), \(ScoreMath.clock(shown.start)) \(part)")
    }

    // MARK: Arithmetic

    /// The zones up the plot, from the foot (0) to the top (100), with a
    /// short blend at each border so the line turns colour as it crosses.
    static var gradient: Gradient { gradient(opacity: 1) }

    /// - Parameter opacity: at the top of the plot; with `fades`, the
    ///   colour thins toward the foot, so the wash under the line reads as
    ///   light rather than as a block.
    static func gradient(opacity: Double, fades: Bool = false) -> Gradient {
        let blend = 0.04
        let moderate = ScorePages.stressBands.moderate / 100
        let high = ScorePages.stressBands.high / 100
        func stop(_ zone: MindZone, _ location: Double) -> Gradient.Stop {
            let alpha = fades ? opacity * (0.15 + 0.85 * location) : opacity
            return .init(color: zone.color.opacity(alpha), location: location)
        }
        return Gradient(stops: [
            stop(.low, 0),
            stop(.low, moderate - blend),
            stop(.medium, moderate + blend),
            stop(.medium, high - blend),
            stop(.high, high + blend),
            stop(.high, 1),
        ])
    }
}

/// Where the chart's day begins and ends: at the start of last night when it
/// began before midnight (on the half hour, at most
/// ``MindNightStress/earliestBefore`` back), else at midnight; always to the
/// next midnight. Every x on the chart is a share of this span.
nonisolated struct MindStressAxis: Equatable, Sendable {
    var start: Date
    var end: Date
    /// Last night's window, when there is one.
    var night: ClosedRange<Date>?

    init(dayStart: Date, night: MindStressNight?) {
        let earliest = dayStart.addingTimeInterval(-MindNightStress.earliestBefore)
        var start = dayStart
        if let night {
            let from = max(night.start, earliest)
            let halfHours = (from.timeIntervalSince(dayStart) / MindNightStress.span).rounded(.down)
            start = min(dayStart, dayStart.addingTimeInterval(halfHours * MindNightStress.span))
        }
        self.start = start
        self.end = dayStart.addingTimeInterval(24 * 60 * 60)
        self.night = night.flatMap { $0.end > $0.start ? max($0.start, start)...$0.end : nil }
    }

    var length: TimeInterval { end.timeIntervalSince(start) }

    /// A moment as a share of the span, held to 0...1.
    func fraction(_ date: Date) -> Double {
        min(max(date.timeIntervalSince(start) / max(length, 1), 0), 1)
    }

    /// The moment a share of the span stands for.
    func date(at fraction: Double) -> Date {
        start.addingTimeInterval(min(max(fraction, 0), 1) * length)
    }

    /// The night as shares of the span.
    var nightSpan: ClosedRange<Double>? {
        night.map { fraction($0.lowerBound)...fraction($0.upperBound) }
    }

    /// Whether a half hour starting at `date` belongs to the night: its
    /// middle falls inside it, the same rule the night is read with.
    func isNight(_ date: Date) -> Bool {
        guard let night else { return false }
        return night.contains(date.addingTimeInterval(MindNightStress.span / 2))
    }

    /// The clock hours under the plot: every six hours from midnight, and
    /// the evening hour the night began on when that is far enough before
    /// midnight for the two labels to stand apart.
    var ticks: [(label: String, fraction: Double)] {
        var out: [(String, Double)] = []
        let dayStart = end.addingTimeInterval(-24 * 60 * 60)
        let before = dayStart.timeIntervalSince(start)
        if before >= 4 * 60 * 60 {
            let hours = Int((before / 3_600).rounded(.down))
            let label = String(format: "%02d", 24 - hours)
            out.append((label, fraction(dayStart.addingTimeInterval(-Double(hours) * 3_600))))
        }
        for hour in stride(from: 0, through: 24, by: 6) {
            out.append((String(format: "%02d", hour), fraction(dayStart.addingTimeInterval(Double(hour) * 3_600))))
        }
        return out
    }
}

/// The stress line on a fixed grid of half hours, from six hours before
/// midnight to the end of the day, as shares of the plot's height: the same
/// length every day, so one read's line interpolates into the next point for
/// point. A half hour with no reading carries its nearest neighbour's height,
/// so a line growing into it rises from where it was rather than from the
/// foot.
struct MindStressSlots: Equatable, Sendable {
    /// Six hours of evening, then enough half hours for the longest day a
    /// clock change makes.
    static let before = Int(MindNightStress.earliestBefore / MindNightStress.span)
    static let count = before + 50

    var heights: [Double]
    /// Which half hours hold a reading. Not interpolated: a reading that
    /// arrives shows at once, at its neighbour's height, and settles.
    var present: [Bool]
    /// Which half hours belong to the night: the line breaks where the night
    /// gives way to the day.
    var asleep: [Bool]

    init(heights: [Double], present: [Bool], asleep: [Bool]? = nil) {
        self.heights = heights
        self.present = present
        self.asleep = asleep ?? Array(repeating: false, count: present.count)
    }

    /// - Parameter samples: night and day together.
    init(_ samples: [MindStressSample], dayStart: Date, night: MindStressNight? = nil) {
        let origin = dayStart.addingTimeInterval(-Double(Self.before) * MindNightStress.span)
        let axis = MindStressAxis(dayStart: dayStart, night: night)
        var heights = [Double?](repeating: nil, count: Self.count)
        for sample in samples {
            let slot = Int((sample.start.timeIntervalSince(origin) / MindNightStress.span).rounded())
            guard heights.indices.contains(slot) else { continue }
            heights[slot] = min(max(sample.value / 100, 0), 1)
        }
        present = heights.map { $0 != nil }
        asleep = (0..<Self.count).map { axis.isNight(origin.addingTimeInterval(Double($0) * MindNightStress.span)) }
        let known = heights.indices.filter { heights[$0] != nil }
        self.heights = heights.indices.map { index in
            if let height = heights[index] { return height }
            guard let nearest = known.min(by: { abs($0 - index) < abs($1 - index) }) else { return 0 }
            return heights[nearest] ?? 0
        }
    }

    /// The start of half hour `slot`.
    static func date(_ slot: Int, dayStart: Date) -> Date {
        dayStart.addingTimeInterval(Double(slot - before) * MindNightStress.span)
    }

    /// The half hours that hold readings, cut where one is missing and where
    /// the night meets the day.
    var runs: [[Int]] {
        var runs: [[Int]] = []
        for slot in present.indices where present[slot] {
            if let last = runs.last?.last, last == slot - 1, asleep[last] == asleep[slot] {
                runs[runs.count - 1].append(slot)
            } else {
                runs.append([slot])
            }
        }
        return runs
    }
}

/// One part of the stress line, drawn from its slots: the line, the light
/// under it, or the lone half hours as dots. The heights interpolate.
struct MindStressLineShape: Shape {
    enum Part {
        case line, area
        /// A reading with no neighbour, as a dot this wide.
        case dots(CGFloat)
    }

    var slots: MindStressSlots
    let axis: MindStressAxis
    let part: Part

    var animatableData: SomaAnimatableVector {
        get { SomaAnimatableVector(slots.heights) }
        set { slots.heights = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dayStart = axis.end.addingTimeInterval(-24 * 60 * 60)
        func point(_ slot: Int) -> CGPoint {
            let height = slots.heights.indices.contains(slot) ? slots.heights[slot] : 0
            let middle = MindStressSlots.date(slot, dayStart: dayStart).addingTimeInterval(MindNightStress.span / 2)
            return CGPoint(x: rect.minX + rect.width * axis.fraction(middle), y: rect.maxY - rect.height * height)
        }
        for run in slots.runs {
            let points = run.map(point)
            guard let first = points.first, let last = points.last else { continue }
            switch part {
            case .dots(let side):
                if points.count == 1 {
                    path.addEllipse(in: CGRect(x: first.x - side / 2, y: first.y - side / 2, width: side, height: side))
                }
            case .line:
                if points.count > 1 { path.addLines(points) }
            case .area:
                guard points.count > 1 else { continue }
                path.addLines(points)
                path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
                path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
                path.closeSubpath()
            }
        }
        return path
    }
}

/// Today's minutes in each zone, high first: a bar in
/// the zone's colour, the share, and the time spent.
struct MindStressZones: View {
    let minutes: [MindZone: Double]?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let total = minutes?.values.reduce(0, +) ?? 0

        VStack(spacing: metrics.cardHeaderSpacing + 4) {
            ForEach(MindZone.allCases.reversed()) { zone in
                let spent = minutes?[zone] ?? 0
                let share = total > 0 ? spent / total : 0
                HStack(spacing: metrics.cardSpacing) {
                    Text(zone.title)
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkPrimary.color)
                        .frame(width: metrics.miniOrbDiameter, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(zone.color.opacity(metrics.chartBandOpacity))
                            if share > 0 {
                                Capsule()
                                    .fill(zone.color)
                                    .frame(width: max(proxy.size.width * share, proxy.size.height))
                            }
                        }
                    }
                    .frame(height: metrics.chartThinBarWidth)
                    Text(minutes == nil ? "-" : "\(Int((share * 100).rounded()))%")
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkPrimary.color)
                        .somaRollingNumber(minutes == nil ? nil : "\(Int((share * 100).rounded()))%")
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: metrics.miniOrbDiameter * 0.8, alignment: .trailing)
                    Text(minutes == nil ? "-" : MindLensFormat.duration(spent))
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .somaRollingNumber(minutes == nil ? nil : MindLensFormat.duration(spent))
                        .frame(width: metrics.miniOrbDiameter, alignment: .trailing)
                }
                .padding(.horizontal, metrics.cardPadding)
                .padding(.vertical, metrics.cardPadding * 0.75)
                .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview("Stress today") {
    SomaPageScroll {
        VStack(spacing: 16) {
            SomaCard {
                MindStressDayChart(samples: MindLensModel.preview.stress, dayStart: MindLensModel.preview.dayStart)
            }
            MindStressZones(minutes: MindLensModel.preview.zoneMinutes)
        }
        .padding()
    }
    .somaTheme(.standard)
}
#endif
