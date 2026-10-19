//
//  SomaLinkCard.swift
//  SomaUI
//

import SwiftUI

/// How a stated link reads against its outcome: in its favour, against it, or
/// neither (a reading with no better side, like a bedtime).
public enum SomaLinkTone: Sendable, Equatable {
    case good
    case cost
    case neutral
}

extension SomaLinkTone {
    func color(_ colors: SomaColors) -> Color {
        switch self {
        case .good: colors.statusNormal.color
        case .cost: colors.statusOut.color
        case .neutral: colors.inkPrimary.color
        }
    }
}

/// One cause and its effect, set like a metric card: the driver and
/// the outcome as the title, the effect large and signed in its status
/// colour, the high and low days as a paired strip beside it, and the day
/// counts under them.
///
/// "Alcohol → Sleep, −11 pts, 12 vs 30 nights."
public struct SomaLinkCard: View {
    private let driver: String
    private let outcome: String
    private let value: String
    private let unit: String
    private let caption: String
    private let tone: SomaLinkTone
    private let high: [Double]
    private let low: [Double]

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - driver: what moves: "Alcohol".
    ///   - outcome: what it moves: "Sleep".
    ///   - value: the effect, signed: "−11".
    ///   - unit: its unit: "pts".
    ///   - caption: the day counts: "12 vs 30 nights".
    ///   - tone: whether the move is in the outcome's favour.
    ///   - high: the outcome on each high (or tagged) day.
    ///   - low: the outcome on each low (or untagged) day.
    public init(
        driver: String,
        outcome: String,
        value: String,
        unit: String,
        caption: String,
        tone: SomaLinkTone,
        high: [Double],
        low: [Double]
    ) {
        self.driver = driver
        self.outcome = outcome
        self.value = value
        self.unit = unit
        self.caption = caption
        self.tone = tone
        self.high = high
        self.low = low
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.linkCardSpacing) {
                HStack(spacing: metrics.linkCardSpacing * 0.75) {
                    Text(driver)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(colors.inkSecondary.color)
                    Text(outcome)
                }
                .somaFont(type.cardTitle)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)

                HStack(alignment: .center, spacing: metrics.linkCardSpacing * 2) {
                    HStack(alignment: .firstTextBaseline, spacing: metrics.linkCardSpacing * 0.5) {
                        Text(value)
                            .somaFont(type.metric)
                            .foregroundStyle(tone.color(colors))
                        Text(unit)
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Spacer(minLength: 0)

                    SomaLinkStrip(high: high, low: low, tone: tone)
                        .frame(width: metrics.linkStripWidth, height: metrics.linkStripHeight)
                }

                Text(caption)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(driver), \(outcome)"))
        .accessibilityValue(Text(verbatim: "\(value) \(unit), \(caption)"))
    }
}

/// The high days and the low days of a link on one shared scale: a row of
/// faint dots each, high above low, and a solid mark on each row's mean. The
/// gap between the two marks is the effect the card states.
public struct SomaLinkStrip: View {
    private let high: [Double]
    private let low: [Double]
    private let tone: SomaLinkTone

    @Environment(\.somaTheme) private var theme

    public init(high: [Double], low: [Double], tone: SomaLinkTone) {
        self.high = high
        self.low = low
        self.tone = tone
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let highColor = tone.color(colors)
        let lowColor = colors.inkSecondary.color
        let track = colors.inkPrimary.color.opacity(metrics.hairlineOpacity)

        Canvas { context, size in
            let all = high + low
            guard let lowest = all.min(), let highest = all.max() else { return }
            let dot = metrics.linkStripDot
            let inset = max(dot, metrics.linkStripMeanWidth) / 2 + 1
            let width = size.width - inset * 2
            let span = max(highest - lowest, abs(highest) * 0.01, 0.0001)
            func x(_ value: Double) -> CGFloat {
                inset + width * CGFloat((value - lowest) / span)
            }

            let rowHeight = size.height / 2
            for (row, values, color) in [(0, high, highColor), (1, low, lowColor)] {
                let centre = rowHeight * (CGFloat(row) + 0.5)
                context.fill(Path(CGRect(x: 0, y: centre - 0.5, width: size.width, height: 1)), with: .color(track))
                for value in values {
                    let rect = CGRect(x: x(value) - dot / 2, y: centre - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(metrics.linkStripDotOpacity)))
                }
                if !values.isEmpty {
                    let mean = values.reduce(0, +) / Double(values.count)
                    let mark = CGRect(x: x(mean) - metrics.linkStripMeanWidth / 2, y: centre - rowHeight * 0.4,
                                      width: metrics.linkStripMeanWidth, height: rowHeight * 0.8)
                    context.fill(Path(roundedRect: mark, cornerRadius: metrics.linkStripMeanWidth / 2), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The links held back, in one row at the foot of the list: a title and
/// their names. A link without enough days is named here, never drawn.
///
/// With `select`, each name is its own row that opens what the link is
/// waiting on; without it the names run on as one caption.
public struct SomaLinkPendingRow: View {
    private let title: String
    private let names: [String]
    private let select: ((String) -> Void)?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - title: "Needs more days".
    ///   - names: each held link's title: "Steps → Sleep".
    ///   - select: when set, called with the name tapped.
    public init(title: String, names: [String], select: ((String) -> Void)? = nil) {
        self.title = title
        self.names = names
        self.select = select
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.linkCardSpacing * 0.5) {
                HStack(spacing: metrics.linkCardSpacing * 0.75) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(colors.inkSecondary.color)
                    Text(title)
                        .foregroundStyle(colors.inkPrimary.color)
                }
                .somaFont(type.cardTitle)
                .accessibilityElement(children: .combine)

                if let select {
                    VStack(spacing: 0) {
                        ForEach(names, id: \.self) { name in
                            Button { select(name) } label: {
                                HStack(spacing: metrics.linkCardSpacing) {
                                    Text(verbatim: name)
                                        .somaFont(type.callout)
                                        .foregroundStyle(colors.inkPrimary.color)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                                        .foregroundStyle(colors.inkSecondary.color)
                                }
                                .frame(minHeight: metrics.minimumTapTarget)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.somaGlassPressDim)
                            if name != names.last {
                                Rectangle()
                                    .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                } else {
                    Text(names.joined(separator: ", "))
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: select == nil ? .combine : .contain)
    }
}

#Preview("Link cards") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 12) {
            SomaLinkCard(driver: "Alcohol", outcome: "Sleep", value: "\u{2212}11", unit: "pts",
                         caption: "6 vs 40 nights", tone: .cost,
                         high: [62, 70, 58, 66, 71, 60], low: [78, 74, 81, 69, 77, 83, 72, 80, 75, 79])
            SomaLinkCard(driver: "Sleep", outcome: "HRV", value: "+8", unit: "ms",
                         caption: "20 long vs 20 short nights", tone: .good,
                         high: [58, 61, 55, 64, 60, 57], low: [49, 52, 47, 55, 50, 51])
            SomaLinkCard(driver: "Daylight", outcome: "Bedtime", value: "\u{2212}24", unit: "min",
                         caption: "15 bright vs 15 dim days", tone: .neutral,
                         high: [23.1, 23.4, 22.9, 23.2], low: [23.6, 23.9, 23.5, 24.1])
            SomaLinkPendingRow(title: "Needs more days", names: ["Steps \u{2192} Sleep", "Sauna \u{2192} HRV"])
        }
        .padding()
    }
}
