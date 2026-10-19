//
//  MindStressDayChart.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Today's stress from midnight: the line takes the colour of
/// the zone it passes through, the three zones lie behind it as faint bands,
/// and a finger held on the plot scrubs it, the value and the time riding
/// in the header. A tap reads one half hour; a second tap lets it go.
struct MindStressDayChart: View {
    let samples: [MindStressSample]
    let dayStart: Date

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: MindStressSample?

    /// Two half hours apart or more breaks the line: nothing was read.
    private static let gap: TimeInterval = 45 * 60
    private static let day: TimeInterval = 24 * 60 * 60

    var body: some View {
        let metrics = theme.metrics
        let shown = selected ?? samples.last

        VStack(alignment: .leading, spacing: metrics.chartLabelGap * 2) {
            readout(shown, isScrubbing: selected != nil)

            HStack(alignment: .top, spacing: metrics.chartLabelGap) {
                VStack(spacing: metrics.chartLabelGap) {
                    plot
                        .frame(height: metrics.chartPlotHeight)
                    SomaAxisLabels(["00", "06", "12", "18", "24"])
                        .padding(.horizontal, metrics.chartPlotInset)
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

        return HStack(alignment: .firstTextBaseline, spacing: theme.metrics.trendMarkSpacing * 2) {
            Text(sample.map { MindLensFormat.whole($0.value) } ?? "-")
                .somaFont(type.metric)
                .foregroundStyle(colors.inkPrimary.color)
                .contentTransition(.numericText())
            if let sample {
                Text(sample.zone.title)
                    .somaFont(type.callout)
                    .foregroundStyle(sample.zone.color)
            }
            Spacer(minLength: 0)
            if let sample {
                Text(isScrubbing ? ScoreMath.clock(sample.start) : String(localized: "Now"))
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .animation(reduceMotion ? nil : theme.motion.selection, value: sample?.id)
    }

    // MARK: Plot

    private var plot: some View {
        let theme = theme
        let samples = samples
        let dayStart = dayStart
        let selected = selected
        let ticks: [Double] = [0, ScorePages.stressBands.moderate, ScorePages.stressBands.high, 100]
        let zones = MindZone.allCases.map { (range: $0.range, color: $0.color) }
        let gradient = Self.gradient
        let washGradient = Self.gradient(opacity: SomaPen(theme).fillOpacity * 1.6, fades: true)

        return Canvas { context, size in
            let pen = SomaPen(theme)
            let inset = theme.metrics.chartPlotInset
            let plot = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(value / 100) }
            func x(_ date: Date) -> CGFloat {
                let middle = date.addingTimeInterval(15 * 60).timeIntervalSince(dayStart)
                return plot.minX + plot.width * CGFloat(min(max(middle / Self.day, 0), 1))
            }

            // The zones, faint, behind everything.
            for zone in zones {
                let band = CGRect(x: 0, y: y(zone.range.upperBound), width: size.width,
                                  height: y(zone.range.lowerBound) - y(zone.range.upperBound))
                context.fill(Path(band), with: .color(zone.color.opacity(pen.bandOpacity * 0.45)))
            }
            for tick in ticks {
                pen.gridline(context, y: y(tick), to: size.width)
            }

            let shading = GraphicsContext.Shading.linearGradient(
                gradient, startPoint: CGPoint(x: 0, y: y(0)), endPoint: CGPoint(x: 0, y: y(100))
            )
            let wash = GraphicsContext.Shading.linearGradient(
                washGradient, startPoint: CGPoint(x: 0, y: y(0)), endPoint: CGPoint(x: 0, y: y(100))
            )

            for run in Self.runs(samples) {
                let points = run.map { CGPoint(x: x($0.start), y: y($0.value)) }
                guard let first = points.first, let last = points.last else { continue }
                if points.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: first.x - pen.point / 2, y: first.y - pen.point / 2,
                                                        width: pen.point, height: pen.point)), with: shading)
                    continue
                }
                var line = Path()
                line.move(to: first)
                for point in points.dropFirst() { line.addLine(to: point) }

                var area = line
                area.addLine(to: CGPoint(x: last.x, y: y(0)))
                area.addLine(to: CGPoint(x: first.x, y: y(0)))
                area.closeSubpath()
                context.fill(area, with: wash)
                context.stroke(line, with: shading,
                               style: StrokeStyle(lineWidth: pen.stroke * 1.4, lineCap: .round, lineJoin: .round))
            }

            if let latest = samples.last, selected == nil {
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
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(.rect)
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
        .accessibilityLabel("Stress today")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard !samples.isEmpty else { return }
            let index = selected.flatMap { samples.firstIndex(of: $0) } ?? samples.count - 1
            switch direction {
            case .increment: self.selected = samples[min(index + 1, samples.count - 1)]
            case .decrement: self.selected = samples[max(index - 1, 0)]
            @unknown default: break
            }
        }
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
        let time = dayStart.addingTimeInterval(fraction * Self.day - 15 * 60)
        guard let best = samples.min(by: { abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time)) }),
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
        guard let shown = selected ?? samples.last else { return Text("No reading yet") }
        return Text("\(MindLensFormat.whole(shown.value)), \(Text(shown.zone.title)), \(ScoreMath.clock(shown.start))")
    }

    // MARK: Arithmetic

    /// The samples cut where a reading is missing.
    static func runs(_ samples: [MindStressSample]) -> [[MindStressSample]] {
        var runs: [[MindStressSample]] = []
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if let last = runs.last?.last, sample.start.timeIntervalSince(last.start) < gap {
                runs[runs.count - 1].append(sample)
            } else {
                runs.append([sample])
            }
        }
        return runs
    }

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
                        .frame(width: metrics.miniOrbDiameter * 0.8, alignment: .trailing)
                    Text(minutes == nil ? "-" : MindLensFormat.duration(spent))
                        .somaFont(type.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
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
    ScrollView {
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
