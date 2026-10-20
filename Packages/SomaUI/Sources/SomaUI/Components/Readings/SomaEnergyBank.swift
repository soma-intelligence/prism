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

        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: symbol)
                    .somaFont(type.callout)
                    .foregroundStyle(tint)
            }
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
