//
//  SomaNightVitals.swift
//  SomaUI
//

import Foundation
import SwiftUI

/// One of the signals a watch reads through the night.
public enum SomaNightVital: Int, CaseIterable, Identifiable, Sendable {
    case heart, breathing, hrv, oxygen, noise

    public var id: Int { rawValue }

    /// The word on the toggle.
    public var title: LocalizedStringResource {
        switch self {
        case .heart: "Heart"
        case .breathing: "Breathing"
        case .hrv: "HRV"
        case .oxygen: "Oxygen"
        case .noise: "Noise"
        }
    }

    /// The card's title over the chart.
    public var heading: LocalizedStringResource {
        switch self {
        case .heart: "Sleeping heart rate"
        case .breathing: "Sleeping breathing rate"
        case .hrv: "Sleeping HRV"
        case .oxygen: "Sleeping blood oxygen"
        case .noise: "Noise in the room"
        }
    }

    /// What the numbers count.
    public var unit: String {
        switch self {
        case .heart: String(localized: "bpm")
        case .breathing: String(localized: "/min")
        case .hrv: String(localized: "ms")
        case .oxygen: "%"
        case .noise: String(localized: "dB")
        }
    }

    /// Whole beats, milliseconds and decibels; a decimal for breaths and
    /// oxygen.
    public var decimals: Int {
        switch self {
        case .breathing, .oxygen: 1
        case .heart, .hrv, .noise: 0
        }
    }

    /// The Health colour the line is drawn in.
    public var hue: SomaHealthHue {
        switch self {
        case .heart, .hrv: .heart
        case .breathing, .oxygen: .respiratory
        case .noise: .hearing
        }
    }

    /// What an empty chart says: what fills it.
    public var emptyMessage: LocalizedStringResource {
        switch self {
        case .heart: "No heart readings last night. Wear your watch to bed."
        case .breathing: "No breathing rate last night. Your watch counts it while you sleep."
        case .hrv: "No HRV last night. Your watch reads it a few times a night."
        case .oxygen: "No blood oxygen last night. Turn on Blood Oxygen in the Watch app to see it here."
        case .noise: "No sound levels last night. Your watch or phone hears the room when Noise is on."
        }
    }

    /// The quiet a bedroom should keep, in decibels: the line the noise card
    /// counts time above.
    public nonisolated static let quietNight: Double = 40
}

/// One reading through the night: when it began, when it ended (the same
/// instant for a spot reading) and its value.
public struct SomaNightReading: Sendable, Hashable {
    public let start: Date
    public let end: Date
    public let value: Double

    public init(start: Date, end: Date? = nil, value: Double) {
        self.start = start
        self.end = max(start, end ?? start)
        self.value = value
    }
}

/// The three numbers over a vital's chart.
public struct SomaNightVitalSummary: Sendable, Equatable {
    public var average: Double
    public var lowest: Double
    public var highest: Double
    /// Noise only: seconds louder than ``SomaNightVital/quietNight``.
    public var secondsAboveQuiet: TimeInterval?

    /// Nil when the night holds fewer than two readings, which is no curve.
    ///
    /// Noise is averaged as sound energy, not as plain decibels: a scale that
    /// is logarithmic would let the plain mean flatten the loud half hour
    /// the card is there to show.
    public nonisolated static func make(_ vital: SomaNightVital, readings: [SomaNightReading]) -> SomaNightVitalSummary? {
        let values = readings.map(\.value)
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return nil }
        guard vital == .noise else {
            return SomaNightVitalSummary(average: values.reduce(0, +) / Double(values.count), lowest: low, highest: high)
        }
        let energy = values.map { pow(10, $0 / 10) }.reduce(0, +) / Double(values.count)
        return SomaNightVitalSummary(average: 10 * log10(energy), lowest: low, highest: high,
                                     secondsAboveQuiet: secondsAbove(SomaNightVital.quietNight, readings: readings))
    }

    /// Seconds the readings spent above `level`. A reading that spans time
    /// counts its span; a spot reading counts up to the next one, half an
    /// hour at most, so a gap in the record is never read as noise.
    public nonisolated static func secondsAbove(_ level: Double, readings: [SomaNightReading]) -> TimeInterval {
        let sorted = readings.sorted { $0.start < $1.start }
        let reach: TimeInterval = 30 * 60
        var total: TimeInterval = 0
        for (index, reading) in sorted.enumerated() where reading.value > level {
            if reading.end > reading.start {
                total += reading.end.timeIntervalSince(reading.start)
            } else if index + 1 < sorted.count {
                total += min(reach, sorted[index + 1].start.timeIntervalSince(reading.start))
            }
        }
        return total
    }
}

/// The night's vitals on one card: a toggle over heart, breathing, HRV,
/// oxygen and noise, then the one the toggle names as three numbers and a
/// line from bed to waking, its average dashed across it.
///
/// Every vital keeps its place on the toggle, recorded or not, so the
/// control never changes shape from one night to the next; a vital the night
/// did not record says what would fill it. Switching crossfades the card,
/// and under Reduce Motion it simply changes.
public struct SomaNightVitals: View {
    private let readings: [SomaNightVital: [SomaNightReading]]
    private let window: DateInterval?
    private let labels: [String]

    @State private var chosen: SomaNightVital = .heart
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - readings: each vital's readings through the night, in any order.
    ///     Oxygen in percent, 0 to 100.
    ///   - window: bed to waking, the chart's span. Without it the span is
    ///     the readings' own.
    ///   - labels: spread under the chart, bed's clock first.
    ///   - initial: the vital shown first.
    public init(_ readings: [SomaNightVital: [SomaNightReading]], window: DateInterval?, labels: [String] = [],
                initial: SomaNightVital = .heart) {
        self.readings = readings.mapValues { $0.sorted { $0.start < $1.start } }
        self.window = window
        self.labels = labels
        self._chosen = State(initialValue: initial)
    }

    public var body: some View {
        let metrics = theme.metrics
        let vital = chosen

        VStack(spacing: metrics.cardSpacing) {
            SomaSegmentedControl(segments: SomaNightVital.allCases.map { SomaSegment(id: $0, title: $0.title) },
                                 selection: $chosen)
            SomaCard {
                card(vital)
                    .id(vital)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : theme.motion.fade, value: vital)
        }
    }

    private func card(_ vital: SomaNightVital) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let shown = readings[vital] ?? []
        let summary = SomaNightVitalSummary.make(vital, readings: shown)
        let number = { (value: Double?) in value.map { SomaFormat.number($0, decimals: vital.decimals) } }
        let third: SomaStat = if vital == .noise {
            SomaStat("Above \(Int(SomaNightVital.quietNight)) dB",
                     value: summary?.secondsAboveQuiet.map { SomaFormat.duration($0) })
        } else {
            SomaStat("Highest", value: number(summary?.highest), unit: LocalizedStringResource(stringLiteral: vital.unit))
        }

        return VStack(alignment: .leading, spacing: metrics.cardPadding) {
            SomaCardHeader(vital.heading)
            SomaStatRow([
                SomaStat("Average", value: number(summary?.average), unit: LocalizedStringResource(stringLiteral: vital.unit)),
                vital == .noise
                    ? SomaStat("Highest", value: number(summary?.highest), unit: LocalizedStringResource(stringLiteral: vital.unit))
                    : SomaStat("Lowest", value: number(summary?.lowest), unit: LocalizedStringResource(stringLiteral: vital.unit)),
                third,
            ])
            if let summary {
                plot(vital, readings: shown, average: summary.average)
            } else {
                SomaPlot(scale: nil, xLabels: labels) { _, _, _ in }
                    .overlay {
                        Text(vital.emptyMessage)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .multilineTextAlignment(.center)
                            .padding(metrics.cardPadding)
                    }
            }
            if vital == .noise, summary != nil {
                Text("Loud stretches can be snoring or the room around you. The watch hears the room, not where the sound came from.")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plot(_ vital: SomaNightVital, readings: [SomaNightReading], average: Double) -> some View {
        let hue = vital.hue.color
        let span = window ?? Self.span(readings)
        let scale = Self.scale(vital, readings: readings, average: average)
        let points = Self.fractions(readings, in: span)
        let dotted = readings.count <= Self.dotLimit

        return SomaPlot(scale: scale, xLabels: labels,
                        label: { $0.formatted(.number.precision(.fractionLength(0...1))) }) { context, space, pen in
            let mapped: [CGPoint?] = points.map { point in
                point.map { CGPoint(x: space.x(fraction: $0.x), y: space.y($0.y)) }
            }
            pen.rule(context, y: space.y(average), in: space.plot)
            pen.line(context, mapped, color: hue)
            if dotted {
                for point in mapped.compactMap({ $0 }) {
                    pen.dot(context, at: point, color: hue, filled: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(vital.heading))
        .accessibilityValue(Text("Average \(SomaFormat.number(average, decimals: vital.decimals)) \(vital.unit)"))
    }

    // MARK: Geometry

    /// Fewer readings than this, a night of spot checks, and each one is
    /// drawn as a dot on the line.
    nonisolated static let dotLimit = 24

    /// A gap longer than this, or than a few of the night's usual gaps,
    /// breaks the line rather than bridging a stretch nothing was read in.
    nonisolated static let longestBridge: TimeInterval = 90 * 60

    /// The readings' own span, for a night with no window.
    nonisolated static func span(_ readings: [SomaNightReading]) -> DateInterval {
        let start = readings.map(\.start).min() ?? .distantPast
        let end = readings.map(\.end).max() ?? start
        return DateInterval(start: start, end: max(start, end))
    }

    /// Each reading as a share of the way across `span` and its value, with
    /// nil where the line breaks.
    nonisolated static func fractions(_ readings: [SomaNightReading], in span: DateInterval) -> [(x: Double, y: Double)?] {
        let sorted = readings.sorted { $0.start < $1.start }
        let gaps = zip(sorted.dropFirst(), sorted).map { $0.start.timeIntervalSince($1.start) }.sorted()
        let usual = gaps.isEmpty ? 0 : gaps[(gaps.count - 1) / 2]
        let bridge = max(longestBridge, usual * 3)
        let length = max(span.duration, 1)
        var out: [(x: Double, y: Double)?] = []
        for (index, reading) in sorted.enumerated() {
            if index > 0, reading.start.timeIntervalSince(sorted[index - 1].start) > bridge { out.append(nil) }
            let x = min(1, max(0, reading.start.timeIntervalSince(span.start) / length))
            out.append((x, reading.value))
        }
        return out
    }

    /// Round ticks round the readings and their average. Oxygen stands on
    /// its own scale up to a hundred, at least four points tall, so a night
    /// that held between 96 and 97 reads as steady rather than as a swing.
    nonisolated static func scale(_ vital: SomaNightVital, readings: [SomaNightReading], average: Double) -> SomaPlotScale? {
        let values = readings.map(\.value)
        guard vital == .oxygen else { return SomaPlotScale(values: values, including: [average], desired: 3) }
        guard let lowest = (values + [average]).min() else { return nil }
        // Even points up to a short scale, fives past it, the floor on a tick.
        let reach = 100 - min(oxygenFloor, (lowest - 1).rounded(.down))
        let step: Double = reach <= 8 ? 2 : 5
        let low = max(0, 100 - (reach / step).rounded(.up) * step)
        return SomaPlotScale(domain: low...100, ticks: Array(stride(from: low, through: 100, by: step)))
    }

    /// The highest an oxygen scale starts, in percent.
    nonisolated static let oxygenFloor: Double = 96
}

#Preview("Night vitals") {
    let bed = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let wake = bed.addingTimeInterval(7.5 * 3600)
    let heart = (0..<30).map { index in
        SomaNightReading(start: bed.addingTimeInterval(Double(index) * 900),
                         value: 52 + 6 * exp(-Double(index) / 6) + Double(index % 3))
    }
    let oxygen = (0..<7).map { SomaNightReading(start: bed.addingTimeInterval(Double($0) * 3600 + 1800), value: 96 + Double($0 % 3)) }
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: SomaMetrics.standard.cardSpacing) {
            SomaNightVitals([.heart: heart, .oxygen: oxygen], window: DateInterval(start: bed, end: wake),
                            labels: ["23:10", "06:40"])
            SomaNightVitals([:], window: nil)
        }
        .padding()
    }
}
