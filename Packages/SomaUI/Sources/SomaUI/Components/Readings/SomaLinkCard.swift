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

/// One cause and its effect in plain words and one small picture: the cause's
/// glyph leading to the effect's, a headline that says what happens ("After
/// a long night, your morning energy is higher"), one line with the size and
/// how many days it rests on, then the two sides as a pair of columns, before
/// and after: every day a faint dot at its value, each side's average a short
/// bar with its number over it, and a line joining the two averages, so the
/// rise or the fall reads before a word does.
///
/// The usual side stands first in grey, the side the card is about second in
/// its tone. The columns share one scale, the outcome's own days, so the gap
/// reads against how much the days vary rather than against zero.
public struct SomaLinkCard: View {
    private let headline: String
    private let detail: String
    private let highLabel: String
    private let lowLabel: String
    private let tone: SomaLinkTone
    private let high: [Double]
    private let low: [Double]
    private let cause: SomaAspect?
    private let effect: SomaAspect?
    private let highText: String?
    private let lowText: String?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - headline: what happens, in a sentence.
    ///   - detail: the size and the days: "About 5 points, across 60 nights".
    ///   - highLabel: the side the card is about: "Long nights".
    ///   - lowLabel: the other side: "Short nights".
    ///   - tone: whether the move is in the outcome's favour.
    ///   - high: the outcome on each high (or tagged) day.
    ///   - low: the outcome on each low (or untagged) day.
    ///   - cause: the aspect the cause belongs to, whose glyph leads the card.
    ///   - effect: the aspect the outcome belongs to.
    ///   - highText: the high side's average as the column says it; nil
    ///     writes the number.
    ///   - lowText: the low side's average.
    public init(
        headline: String,
        detail: String,
        highLabel: String,
        lowLabel: String,
        tone: SomaLinkTone,
        high: [Double],
        low: [Double],
        cause: SomaAspect? = nil,
        effect: SomaAspect? = nil,
        highText: String? = nil,
        lowText: String? = nil
    ) {
        self.headline = headline
        self.detail = detail
        self.highLabel = highLabel
        self.lowLabel = lowLabel
        self.tone = tone
        self.high = high
        self.low = low
        self.cause = cause
        self.effect = effect
        self.highText = highText
        self.lowText = lowText
    }

    public var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.linkCardSpacing) {
                if let cause, let effect {
                    HStack(spacing: metrics.linkCardSpacing) {
                        SomaAspectGlyph(cause, style: .inline)
                            .foregroundStyle(theme.aspects[cause].identity.color)
                        Image(systemName: "arrow.right")
                            .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                            .foregroundStyle(colors.inkSecondary.color)
                        SomaAspectGlyph(effect, style: .inline)
                            .foregroundStyle(theme.aspects[effect].identity.color)
                    }
                    .accessibilityHidden(true)
                }
                Text(verbatim: headline)
                    .somaFont(type.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                SomaLinkPair(high: high, low: low, highLabel: highLabel, lowLabel: lowLabel, tone: tone,
                             highText: highText, lowText: lowText)
                    .padding(.top, metrics.linkCardSpacing / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: headline))
        .accessibilityValue(Text(verbatim: detail))
    }
}

/// The two sides of a link as a pair of columns, before and after: the
/// usual side first in grey, the card's side second in its tone. Each day is
/// a faint dot at its value, each side's average a short bar with its number
/// over it, and a line joins the two averages.
///
/// The averages part from their shared middle once when the card arrives,
/// so the gap opens in front of the reader; under Reduce Motion they are
/// drawn in place.
public struct SomaLinkPair: View {
    private let high: [Double]
    private let low: [Double]
    private let highLabel: String
    private let lowLabel: String
    private let tone: SomaLinkTone
    private let highText: String?
    private let lowText: String?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    public init(high: [Double], low: [Double], highLabel: String, lowLabel: String, tone: SomaLinkTone,
                highText: String? = nil, lowText: String? = nil) {
        self.high = high
        self.low = low
        self.highLabel = highLabel
        self.lowLabel = lowLabel
        self.tone = tone
        self.highText = highText
        self.lowText = lowText
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = tone.color(colors)
        let grey = colors.inkSecondary.color
        let layout = SomaLinkPairLayout(high: high, low: low)
        let shown = isDrawn || reduceMotion

        VStack(spacing: metrics.linkCardSpacing / 2) {
            GeometryReader { proxy in
                let size = proxy.size
                let plotTop = metrics.linkPairLabelRoom
                let plot = max(1, size.height - plotTop)
                let lanes = [(x: size.width * 0.3, mean: layout.lowMean, days: layout.lowDays, color: grey, text: lowText),
                             (x: size.width * 0.7, mean: layout.highMean, days: layout.highDays, color: hue, text: highText)]
                let middle = layout.middle
                let y: (Double) -> CGFloat = { plotTop + plot * (1 - $0) }

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for lane in lanes {
                            for (index, share) in lane.days.enumerated() {
                                let jitter = SomaLinkPairLayout.jitter(index) * metrics.linkPairLaneWidth / 2
                                let dot = metrics.linkPairDayDot
                                context.fill(Path(ellipseIn: CGRect(x: lane.x + jitter - dot / 2, y: y(share) - dot / 2,
                                                                    width: dot, height: dot)),
                                             with: .color(lane.color.opacity(metrics.linkPairDayOpacity)))
                            }
                        }
                    }
                    if let lowMean = lanes[0].mean, let highMean = lanes[1].mean {
                        let a = CGPoint(x: lanes[0].x, y: y(shown ? lowMean : middle))
                        let b = CGPoint(x: lanes[1].x, y: y(shown ? highMean : middle))
                        Path { path in
                            path.move(to: a)
                            path.addLine(to: b)
                        }
                        .stroke(hue.opacity(metrics.linkSpanOpacity),
                                style: StrokeStyle(lineWidth: metrics.linkTrackHeight / 2, lineCap: .round, dash: [3, 4]))
                        ForEach(0..<2, id: \.self) { index in
                            let lane = lanes[index]
                            let point = index == 0 ? a : b
                            Capsule()
                                .fill(lane.color)
                                .frame(width: metrics.linkPairLaneWidth, height: metrics.linkTrackHeight)
                                .position(point)
                            SomaNumber(lane.text ?? SomaLinkPairLayout.number(index == 0 ? layout.lowAverage : layout.highAverage),
                                       theme.typography.rowValue)
                                .foregroundStyle(index == 0 ? colors.inkSecondary.color : colors.inkPrimary.color)
                                .fixedSize()
                                .position(x: point.x, y: point.y - metrics.linkPairLabelRoom / 2 - metrics.linkTrackHeight)
                        }
                    }
                }
            }
            .frame(height: metrics.linkPairHeight)

            HStack(spacing: 0) {
                Text(verbatim: lowLabel)
                    .foregroundStyle(colors.inkSecondary.color)
                    .frame(maxWidth: .infinity)
                Text(verbatim: highLabel)
                    .foregroundStyle(colors.inkPrimary.color)
                    .frame(maxWidth: .infinity)
            }
            .somaFont(theme.typography.caption)
            .lineLimit(1)
            .padding(.horizontal, metrics.linkCardSpacing * 2)
        }
        .onAppear {
            guard !isDrawn else { return }
            if reduceMotion { isDrawn = true } else { withAnimation(theme.motion.chartMorph.delay(0.15)) { isDrawn = true } }
        }
        .accessibilityHidden(true)
    }
}

/// Where a link's days and averages sit in its pair of columns, as shares of
/// the plot's height over both sides' days together, kept apart so it is
/// tested.
struct SomaLinkPairLayout: Equatable {
    var lowDays: [Double]
    var highDays: [Double]
    var lowMean: Double?
    var highMean: Double?
    var lowAverage: Double?
    var highAverage: Double?

    /// Where both averages start before they part.
    var middle: Double {
        guard let lowMean, let highMean else { return 0.5 }
        return (lowMean + highMean) / 2
    }

    init(high: [Double], low: [Double]) {
        let all = high + low
        let lowest = all.min() ?? 0
        let highest = all.max() ?? 1
        let span = highest - lowest
        func place(_ value: Double) -> Double { span > 0 ? 0.08 + 0.84 * (value - lowest) / span : 0.5 }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        lowDays = low.map(place)
        highDays = high.map(place)
        lowAverage = mean(low)
        highAverage = mean(high)
        lowMean = lowAverage.map(place)
        highMean = highAverage.map(place)
    }

    /// A day's sideways nudge in its lane, -1 to 1, the same every time it
    /// is drawn so the dots never shuffle.
    static func jitter(_ index: Int) -> Double {
        let golden = 0.618_033_988_75
        let x = (Double(index) * golden).truncatingRemainder(dividingBy: 1)
        return x * 2 - 1
    }

    /// An average as the column writes it: whole past ten, one decimal under.
    static func number(_ value: Double?) -> String? {
        guard let value else { return nil }
        return abs(value) >= 10 ? String(Int(value.rounded())) : String(format: "%.1f", value)
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
    ///   - names: each held link's plain name: "Active days and sleep".
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
            SomaLinkCard(headline: "After drinking, your sleep score is lower", detail: "About 11 points, across 46 nights",
                         highLabel: "Alcohol", lowLabel: "Without", tone: .cost,
                         high: [62, 70, 58, 66, 71, 60], low: [78, 74, 81, 69, 77, 83, 72, 80, 75, 79],
                         cause: .gut, effect: .sleep)
            SomaLinkCard(headline: "After a long night, your morning HRV is higher", detail: "About 8 ms, across 40 nights",
                         highLabel: "Long nights", lowLabel: "Short nights", tone: .good,
                         high: [58, 61, 55, 64, 60, 57], low: [49, 52, 47, 55, 50, 51])
            SomaLinkPendingRow(title: "Still learning", names: ["Active days and sleep", "Sauna and HRV"])
        }
        .padding()
    }
}
