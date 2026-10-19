//
//  SomaDayClock.swift
//  SomaUI
//

import SwiftUI

/// A 24 hour clock with one span drawn on it: a fast, a window. Midnight sits
/// at the top, noon at the foot.
///
/// Drag the start knob to move the span, the end knob to lengthen or shorten
/// it. A second, thinner band inside the track marks a window to set it
/// against (the usual night's sleep), and a dot on the rim says where now is.
/// Once the span is running, `progress` fills the part already behind.
public struct SomaDayClock<Center: View>: View {
    @Binding private var start: Double
    @Binding private var length: Double
    private let lengthRange: ClosedRange<Double>
    private let snap: Double
    private let band: ClosedRange<Double>?
    private let now: Double?
    private let progress: Double?
    private let aspect: SomaAspect
    private let isEditable: Bool
    private let center: Center

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - start: the span's first hour, 0..<24.
    ///   - length: its length in hours.
    ///   - lengthRange: how short and long the end knob can make it.
    ///   - snap: the grid both knobs land on, in hours.
    ///   - band: a window to set the span against, as clock hours; `from`
    ///     may be later than `to` for a window across midnight.
    ///   - now: the clock hour now, for the dot on the rim.
    ///   - progress: the share of the span already behind, once it runs.
    ///   - aspect: whose hue the span wears.
    ///   - isEditable: whether the knobs can be dragged.
    public init(
        start: Binding<Double>,
        length: Binding<Double>,
        lengthRange: ClosedRange<Double> = 1...23.5,
        snap: Double = 0.25,
        band: (from: Double, to: Double)? = nil,
        now: Double? = nil,
        progress: Double? = nil,
        aspect: SomaAspect = .gut,
        isEditable: Bool = true,
        @ViewBuilder center: () -> Center
    ) {
        self._start = start
        self._length = length
        self.lengthRange = lengthRange
        self.snap = snap
        self.band = band.map { $0.from...($0.to < $0.from ? $0.to + 24 : $0.to) }
        self.now = now
        self.progress = progress.map { min(max($0, 0), 1) }
        self.aspect = aspect
        self.isEditable = isEditable
        self.center = center()
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = theme.aspects[aspect].identity.color
        let track = metrics.clockTrackWidth

        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side / 2 - metrics.cardSpacing * 3.5
            let end = start + length

            ZStack {
                // Hour ticks round the outside.
                Canvas { context, _ in
                    for hour in 0..<24 {
                        let isQuarter = hour % 6 == 0
                        var tick = Path()
                        let outer = radius + track + metrics.cardSpacing * (isQuarter ? 1.6 : 1.3)
                        tick.move(to: point(middle, radius + track + metrics.cardSpacing * 0.8, Double(hour)))
                        tick.addLine(to: point(middle, outer, Double(hour)))
                        context.stroke(tick, with: .color(colors.inkSecondary.color.opacity(0.6)), lineWidth: 1)
                    }
                }

                Circle()
                    .stroke(colors.surface.color, lineWidth: track)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(middle)

                if let progress {
                    arc(middle, radius, from: start, to: end)
                        .stroke(hue.opacity(0.35), style: StrokeStyle(lineWidth: track, lineCap: .round))
                    arc(middle, radius, from: start, to: start + length * progress)
                        .stroke(hue, style: StrokeStyle(lineWidth: track, lineCap: .round))
                } else {
                    arc(middle, radius, from: start, to: end)
                        .stroke(hue, style: StrokeStyle(lineWidth: track, lineCap: .round))
                }

                if let band {
                    arc(middle, radius - track - metrics.cardSpacing, from: band.lowerBound, to: band.upperBound)
                        .stroke(theme.aspects[.sleep].identity.color, style: StrokeStyle(lineWidth: metrics.clockBandWidth, lineCap: .round))
                }

                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .somaFont(theme.typography.captionValue)
                        .foregroundStyle(colors.inkSecondary.color)
                        .position(point(middle, radius - track - metrics.cardSpacing * 2.6, Double(hour)))
                }

                if let now, !Self.near(now, start), !Self.near(now, end) {
                    Circle()
                        .fill(colors.inkPrimary.color)
                        .frame(width: metrics.aspectDotSize, height: metrics.aspectDotSize)
                        .position(point(middle, radius, now))
                    Text("Now")
                        .somaFont(theme.typography.tabLabel)
                        .foregroundStyle(colors.inkSecondary.color)
                        .position(point(middle, radius + track + metrics.cardSpacing * 3, now))
                }

                timeLabel(start).position(point(middle, radius + track + metrics.cardSpacing * 3.4, start))
                timeLabel(end).position(point(middle, radius + track + metrics.cardSpacing * 3.4, end))

                knob(at: point(middle, radius, start), around: middle) { hour in
                    start = snapped(hour)
                }
                knob(at: point(middle, radius, end), around: middle) { hour in
                    var span = (snapped(hour) - start).truncatingRemainder(dividingBy: 24)
                    if span < 0 { span += 24 }
                    length = min(max(span, lengthRange.lowerBound), lengthRange.upperBound)
                }

                center.position(middle)
            }
            .coordinateSpace(.named(Self.space))
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: metrics.clockDiameter + metrics.cardSpacing * 8)
        .sensoryFeedback(.selection, trigger: start)
        .sensoryFeedback(.selection, trigger: length)
    }

    private static var space: String { "soma.dayClock" }

    private func knob(at position: CGPoint, around middle: CGPoint, move: @escaping (Double) -> Void) -> some View {
        SomaKnob()
            .frame(width: theme.metrics.minimumTapTarget, height: theme.metrics.minimumTapTarget)
            .contentShape(.circle)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { drag in move(hour(of: drag.location, around: middle)) }
            )
            .opacity(isEditable ? 1 : 0)
            .allowsHitTesting(isEditable)
            .position(position)
    }

    /// The clock hour at a point, read from the centre of the clock.
    private func hour(of location: CGPoint, around centre: CGPoint) -> Double {
        let angle = atan2(Double(location.x - centre.x), Double(centre.y - location.y))
        let hour = angle / (2 * .pi) * 24
        return hour < 0 ? hour + 24 : hour
    }

    /// Whether two clock hours sit within an hour of each other, so their
    /// labels would overlap.
    static func near(_ lhs: Double, _ rhs: Double) -> Bool {
        let gap = abs((lhs - rhs).truncatingRemainder(dividingBy: 24))
        return min(gap, 24 - gap) < 1
    }

    private func snapped(_ hour: Double) -> Double {
        var value = (hour / snap).rounded() * snap
        value = value.truncatingRemainder(dividingBy: 24)
        return value < 0 ? value + 24 : value
    }

    private func point(_ middle: CGPoint, _ radius: CGFloat, _ hour: Double) -> CGPoint {
        let angle = hour / 24 * 2 * .pi
        return CGPoint(x: middle.x + radius * CGFloat(sin(angle)), y: middle.y - radius * CGFloat(cos(angle)))
    }

    private func arc(_ middle: CGPoint, _ radius: CGFloat, from: Double, to: Double) -> Path {
        Path { path in
            let steps = max(2, Int(abs(to - from) * 8))
            for index in 0...steps {
                let hour = from + (to - from) * Double(index) / Double(steps)
                let p = point(middle, radius, hour)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }

    private func timeLabel(_ hour: Double) -> some View {
        var wrapped = hour.truncatingRemainder(dividingBy: 24)
        if wrapped < 0 { wrapped += 24 }
        let minutes = Int((wrapped * 60).rounded())
        return Text(String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60))
            .somaFont(theme.typography.captionValue)
            .foregroundStyle(theme.colors.inkPrimary.color)
    }
}

#Preview("Day clock") {
    @Previewable @State var start = 20.0
    @Previewable @State var length = 14.0
    ZStack {
        SomaPreviewBackdrop()
        SomaDayClock(start: $start, length: $length, band: (23.25, 7), now: 18) {
            SomaReadout("\(Int(length))", unit: "h")
        }
        .padding()
    }
}
