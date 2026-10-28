//
//  SomaEnergyGauge.swift
//  SomaUI
//

import SwiftUI

// The energy bank's level, read at a glance: an upright cell filled from the
// foot in a calm tone for its level, the number large beside it, and the day
// under it as a row of bars, one an hour, green where the bank filled and
// sand where it drew down. A missing level is an empty cell and a dash, never
// a zero.

/// How big the gauge is drawn.
public enum SomaEnergyGaugeSize: Sendable {
    /// At the head of the energy page.
    case hero
    /// On a card among others.
    case compact
}

// MARK: - The cell

/// An upright pebble filled from the foot to the level, in the calm tone for
/// that level: clay, sand or sage.
///
/// When the level arrives or moves, the charge rises to it on a soft spring
/// and its surface sloshes once and settles, like water in a glass set down.
/// Under Reduce Motion the charge is simply at its level, its surface flat.
public struct SomaEnergyCell: View {
    private let level: Int?
    private let size: SomaEnergyGaugeSize

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var tilt: Double = 0

    /// - Parameter level: 0 to 100, or nil when there is none yet.
    public init(level: Int?, size: SomaEnergyGaugeSize = .hero) {
        self.level = level
        self.size = size
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let width = size == .hero ? metrics.energyCellWidth : metrics.energyCellCompactWidth
        let height = size == .hero ? metrics.energyCellHeight : metrics.energyCellCompactHeight
        let radius = width * metrics.energyCellRoundness
        let inset = width * metrics.energyCellInset
        let share = level.map { min(1, max(0, Double($0) / 100)) }
        let tint = SomaEnergyRamp.tone(at: share ?? 0).color

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(colors.surfaceRecessed.color)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5)
            if share != nil {
                SomaChargeShape(level: shown, tilt: tilt, slosh: metrics.energyCellSlosh)
                    .fill(tint)
                    .clipShape(RoundedRectangle(cornerRadius: radius - inset, style: .continuous))
                    .padding(inset)
            }
        }
        .frame(width: width, height: height)
        .onAppear { settle(to: share, animated: !reduceMotion) }
        .onChange(of: level) { _, _ in settle(to: share, animated: !reduceMotion) }
        .accessibilityHidden(true)
    }

    /// Rises (or falls) to the level, then lets the surface slosh and settle.
    private func settle(to share: Double?, animated: Bool) {
        let target = share ?? 0
        guard animated else {
            shown = target
            tilt = 0
            return
        }
        withAnimation(.spring(duration: theme.motion.breathDuration / 3, bounce: 0)) { shown = target }
        tilt = 1
        withAnimation(.spring(duration: theme.motion.breathDuration / 2, bounce: 0.6)) { tilt = 0 }
    }
}

/// The charge inside the cell: filled from the foot to `level`, its surface a
/// soft curve that tips by `tilt` (minus one to one) of the slosh.
public struct SomaChargeShape: Shape {
    public var level: Double
    public var tilt: Double
    public let slosh: CGFloat

    public init(level: Double, tilt: Double, slosh: CGFloat) {
        self.level = level
        self.tilt = tilt
        self.slosh = slosh
    }

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, tilt) }
        set {
            level = newValue.first
            tilt = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let share = CGFloat(min(1, max(0, level)))
        guard share > 0 else { return Path() }
        let surface = rect.maxY - rect.height * share
        let lean = rect.width * slosh * CGFloat(tilt)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: surface + lean))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: surface - lean),
                          control: CGPoint(x: rect.midX, y: surface - lean * 0.2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - The gauge

/// The level as the hero: the cell, the number large and light beside it with
/// "of 100", and one short line under the number.
public struct SomaEnergyGauge: View {
    private let level: Int?
    private let line: String?
    private let size: SomaEnergyGaugeSize

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - level: 0 to 100, or nil for a dash and an empty cell.
    ///   - line: one short line on what the level means now.
    public init(level: Int?, line: String?, size: SomaEnergyGaugeSize = .hero) {
        self.level = level
        self.line = line
        self.size = size
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        HStack(alignment: .center, spacing: size == .hero ? metrics.leadSpacing : metrics.cardSpacing) {
            SomaEnergyCell(level: level, size: size)
            VStack(alignment: .leading, spacing: size == .hero ? metrics.cardHeaderSpacing : 2) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.identityDotSpacing) {
                    SomaNumber(level.map(String.init), size == .hero ? type.bankFigure : type.metric)
                        .foregroundStyle(colors.inkPrimary.color)
                        .contentTransition(.numericText())
                    if level != nil {
                        Text("of 100")
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
                if let line {
                    Text(verbatim: line)
                        .somaFont(size == .hero ? type.body : type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Energy"))
        .accessibilityValue(Text(verbatim: [level.map { "\($0) of 100" } ?? "No level yet", line]
            .compactMap { $0 }.joined(separator: ". ")))
    }
}

// MARK: - The day

/// The day as a row of bars, one an hour from the span's start: each as tall
/// as the bank stood that hour, green where it filled and sand where it drew
/// down, the hours still to come a faint track. Under it the start, now and
/// the end, and what the day charged and drained.
public struct SomaEnergyTimeline: View {
    private let points: [SomaEnergyTimeline.Point]
    private let now: Double?
    private let ticks: [SomaEnergyTimeline.Tick]
    private let charged: Int?
    private let drained: Int?
    private let size: SomaEnergyGaugeSize

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    /// - Parameters:
    ///   - points: the bank's readings, at shares of the span from 0 to 1.
    ///   - now: where now falls on the span; the hours after it are to come.
    ///   - ticks: the clock labels under the row.
    ///   - charged: what sleep put back, in points.
    ///   - drained: what the day took, in points, signed or not.
    public init(points: [SomaEnergyTimeline.Point], now: Double?, ticks: [SomaEnergyTimeline.Tick],
                charged: Int?, drained: Int?, size: SomaEnergyGaugeSize = .hero) {
        self.points = points.sorted { $0.x < $1.x }
        self.now = now
        self.ticks = ticks
        self.charged = charged
        self.drained = drained
        self.size = size
    }

    /// One reading of the bank, at a share of the span from 0 to 1.
    public struct Point: Sendable, Equatable {
        public let x: Double
        /// 0 to 100.
        public let level: Double

        public init(x: Double, level: Double) {
            self.x = x
            self.level = level
        }
    }

    /// A clock label under the row, at a share of the span.
    public struct Tick: Sendable, Equatable, Identifiable {
        public var id: Double { x }
        public let x: Double
        public let label: String

        public init(x: Double, label: String) {
            self.x = x
            self.label = label
        }
    }

    /// One hour: the level it held, and whether the bank rose into it.
    public struct Slot: Sendable, Equatable {
        public let level: Double?
        public let isRising: Bool
        public let isToCome: Bool
    }

    /// The span cut into `count` equal slots, each the mean of the readings
    /// that fall in it. A slot with none is empty unless it sits between two
    /// that have one, which it takes the earlier of.
    nonisolated public static func slots(_ points: [SomaEnergyTimeline.Point], now: Double?, count: Int) -> [Slot] {
        guard count > 0 else { return [] }
        var sums = Array(repeating: 0.0, count: count)
        var counts = Array(repeating: 0, count: count)
        for point in points where point.x >= 0 && point.x <= 1 {
            let index = min(count - 1, Int(point.x * Double(count)))
            sums[index] += point.level
            counts[index] += 1
        }
        let last = counts.lastIndex { $0 > 0 }
        var levels: [Double?] = (0..<count).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
        if let last {
            var carried: Double?
            for index in 0...last {
                if let value = levels[index] { carried = value } else { levels[index] = carried }
            }
        }
        return (0..<count).map { index in
            let previous = index > 0 ? levels[index - 1] : nil
            let level = levels[index]
            let start = Double(index) / Double(count)
            let toCome = now.map { start > $0 } ?? false
            return Slot(level: toCome ? nil : level,
                        isRising: (level ?? 0) > (previous ?? level ?? 0) + 0.05,
                        isToCome: toCome)
        }
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let slots = Self.slots(points, now: now, count: metrics.energyTimelineSlots)
        let height = size == .hero ? metrics.energyTimelineHeight : metrics.energyTimelineCompactHeight

        VStack(alignment: .leading, spacing: metrics.chartLabelGap) {
            bars(slots)
                .frame(height: height)
                .mask(alignment: .leading) {
                    Rectangle().scaleEffect(x: isDrawn || reduceMotion ? 1 : 0, anchor: .leading)
                }

            if size == .hero, !ticks.isEmpty {
                GeometryReader { proxy in
                    ForEach(ticks) { tick in
                        Text(verbatim: tick.label)
                            .somaFont(type.captionValue)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize()
                            .position(x: min(proxy.size.width - 16, max(16, proxy.size.width * CGFloat(tick.x))),
                                      y: proxy.size.height / 2)
                    }
                }
                .frame(height: metrics.bankChartGlyphRow)
            }

            HStack(spacing: metrics.leadSpacing) {
                tally(title: "Charged", value: charged.map { "+\(abs($0))" }, tone: SomaEnergyRamp.charge.color)
                tally(title: "Drained", value: drained.map { "\u{2212}\(abs($0))" }, tone: SomaEnergyRamp.drain.color)
            }
        }
        .onAppear {
            guard !isDrawn else { return }
            if reduceMotion { isDrawn = true } else {
                withAnimation(.easeOut(duration: theme.motion.breathDuration / 4)) { isDrawn = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Energy through the day"))
        .accessibilityValue(Text(verbatim: [charged.map { "Charged \(abs($0))" }, drained.map { "drained \(abs($0))" }]
            .compactMap { $0 }.joined(separator: ", ")))
    }

    private func bars(_ slots: [Slot]) -> some View {
        let metrics = theme.metrics
        let track = theme.colors.surfaceRecessed.color
        let charge = SomaEnergyRamp.charge.color
        let drain = SomaEnergyRamp.drain.color
        let gap = metrics.energyTimelineGap
        let future = metrics.energyTimelineFutureOpacity

        return Canvas { context, size in
            guard !slots.isEmpty else { return }
            let width = (size.width - gap * CGFloat(slots.count - 1)) / CGFloat(slots.count)
            let radius = min(width / 2, 3)
            for (index, slot) in slots.enumerated() {
                let x = CGFloat(index) * (width + gap)
                let full = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: full, cornerRadius: radius, style: .continuous),
                             with: .color(track.opacity(slot.isToCome ? future : 1)))
                guard let level = slot.level else { continue }
                let barHeight = max(width, size.height * CGFloat(min(100, max(0, level)) / 100))
                let bar = CGRect(x: x, y: size.height - barHeight, width: width, height: barHeight)
                context.fill(Path(roundedRect: bar, cornerRadius: radius, style: .continuous),
                             with: .color(slot.isRising ? charge : drain))
            }
        }
    }

    private func tally(title: LocalizedStringResource, value: String?, tone: Color) -> some View {
        let metrics = theme.metrics
        return HStack(spacing: metrics.identityDotSpacing) {
            Circle()
                .fill(tone)
                .frame(width: metrics.identityDotDiameter, height: metrics.identityDotDiameter)
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
            SomaNumber(value, theme.typography.captionValue)
                .foregroundStyle(theme.colors.inkPrimary.color)
        }
    }
}

#Preview("Energy gauge") {
    let points = (0...40).map { index -> SomaEnergyTimeline.Point in
        let x = Double(index) / 60
        let level = x < 0.27 ? 20 + x / 0.27 * 55 : 75 - (x - 0.27) * 70
        return SomaEnergyTimeline.Point(x: x, level: level)
    }
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 24) {
            SomaEnergyGauge(level: 48, line: "Enough left for a quiet evening.")
            SomaCard {
                SomaEnergyTimeline(points: points, now: 40.0 / 60, ticks: [.init(x: 0, label: "22:00"), .init(x: 0.5, label: "10:00")],
                                   charged: 50, drained: 29)
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 12) {
                    SomaEnergyGauge(level: 82, line: "Plenty in the bank.", size: .compact)
                    SomaEnergyTimeline(points: points, now: 40.0 / 60, ticks: [], charged: 50, drained: 29, size: .compact)
                }
            }
            SomaEnergyGauge(level: nil, line: nil, size: .compact)
        }
        .padding()
    }
}
