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

/// One cause and its effect in plain words: a headline that says what
/// happens ("After a long night, your morning energy is higher"), one line
/// with the size and how many days it rests on, and the two averages set on
/// one track, the usual side small and grey, the side the card is about in
/// its colour, each named under its dot.
///
/// The track spans the outcome's own days, so the gap reads against how much
/// the days vary rather than against zero.
public struct SomaLinkCard: View {
    private let headline: String
    private let detail: String
    private let highLabel: String
    private let lowLabel: String
    private let tone: SomaLinkTone
    private let high: [Double]
    private let low: [Double]

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - headline: what happens, in a sentence.
    ///   - detail: the size and the days: "About 5 points, across 60 nights".
    ///   - highLabel: the side the card is about: "Long nights".
    ///   - lowLabel: the other side: "Short nights".
    ///   - tone: whether the move is in the outcome's favour.
    ///   - high: the outcome on each high (or tagged) day.
    ///   - low: the outcome on each low (or untagged) day.
    public init(
        headline: String,
        detail: String,
        highLabel: String,
        lowLabel: String,
        tone: SomaLinkTone,
        high: [Double],
        low: [Double]
    ) {
        self.headline = headline
        self.detail = detail
        self.highLabel = highLabel
        self.lowLabel = lowLabel
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
                Text(verbatim: headline)
                    .somaFont(type.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                SomaLinkTrack(high: high, low: low, highLabel: highLabel, lowLabel: lowLabel, tone: tone)
                    .padding(.top, metrics.linkCardSpacing / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: headline))
        .accessibilityValue(Text(verbatim: detail))
    }
}

/// Two averages on one track: the low side's mean as a small grey dot, the
/// high side's as a larger dot in the tone, a soft segment between, and the
/// two sides named under the track at the end each dot sits toward.
public struct SomaLinkTrack: View {
    private let high: [Double]
    private let low: [Double]
    private let highLabel: String
    private let lowLabel: String
    private let tone: SomaLinkTone

    @Environment(\.somaTheme) private var theme

    public init(high: [Double], low: [Double], highLabel: String, lowLabel: String, tone: SomaLinkTone) {
        self.high = high
        self.low = low
        self.highLabel = highLabel
        self.lowLabel = lowLabel
        self.tone = tone
    }

    /// Where each mean falls on the track, 0 at the lowest day and 1 at the
    /// highest, a tenth of the way in from each end. Nil when a side is empty.
    nonisolated public static func positions(high: [Double], low: [Double]) -> (high: Double, low: Double)? {
        guard !high.isEmpty, !low.isEmpty else { return nil }
        let all = high + low
        guard let lowest = all.min(), let highest = all.max() else { return nil }
        let span = highest - lowest
        func place(_ values: [Double]) -> Double {
            let mean = values.reduce(0, +) / Double(values.count)
            return span > 0 ? 0.1 + 0.8 * (mean - lowest) / span : 0.5
        }
        return (place(high), place(low))
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hue = tone.color(colors)
        let places = Self.positions(high: high, low: low)
        let highFirst = places.map { $0.high < $0.low } ?? false

        VStack(spacing: metrics.linkCardSpacing / 2) {
            Canvas { context, size in
                let mid = size.height / 2
                let bar = metrics.linkTrackHeight
                context.fill(Path(roundedRect: CGRect(x: 0, y: mid - bar / 2, width: size.width, height: bar),
                                  cornerRadius: bar / 2), with: .color(colors.surfaceRecessed.color))
                guard let places else { return }
                let a = size.width * min(places.high, places.low)
                let b = size.width * max(places.high, places.low)
                context.fill(Path(roundedRect: CGRect(x: a, y: mid - bar / 2, width: max(b - a, bar), height: bar),
                                  cornerRadius: bar / 2), with: .color(hue.opacity(metrics.linkSpanOpacity)))
                let small = metrics.linkDotSmall
                context.fill(Path(ellipseIn: CGRect(x: size.width * places.low - small / 2, y: mid - small / 2,
                                                    width: small, height: small)),
                             with: .color(colors.inkSecondary.color))
                let large = metrics.linkDotLarge
                let dot = CGRect(x: size.width * places.high - large / 2, y: mid - large / 2, width: large, height: large)
                context.fill(Path(ellipseIn: dot), with: .color(colors.surface.color))
                context.fill(Path(ellipseIn: dot.insetBy(dx: 2, dy: 2)), with: .color(hue))
            }
            .frame(height: metrics.linkTrackRow)

            HStack {
                side(highFirst ? highLabel : lowLabel, isHigh: highFirst)
                Spacer(minLength: metrics.linkCardSpacing)
                side(highFirst ? lowLabel : highLabel, isHigh: !highFirst)
            }
        }
        .accessibilityHidden(true)
    }

    /// A side's name, at the end of the track its dot sits toward, in its
    /// dot's colour.
    private func side(_ text: String, isHigh: Bool) -> some View {
        HStack(spacing: theme.metrics.identityDotSpacing) {
            Circle()
                .fill(isHigh ? tone.color(theme.colors) : theme.colors.inkSecondary.color)
                .frame(width: theme.metrics.identityDotDiameter, height: theme.metrics.identityDotDiameter)
            Text(verbatim: text)
                .somaFont(theme.typography.caption)
                .foregroundStyle(isHigh ? theme.colors.inkPrimary.color : theme.colors.inkSecondary.color)
                .lineLimit(1)
        }
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
                         high: [62, 70, 58, 66, 71, 60], low: [78, 74, 81, 69, 77, 83, 72, 80, 75, 79])
            SomaLinkCard(headline: "After a long night, your morning HRV is higher", detail: "About 8 ms, across 40 nights",
                         highLabel: "Long nights", lowLabel: "Short nights", tone: .good,
                         high: [58, 61, 55, 64, 60, 57], low: [49, 52, 47, 55, 50, 51])
            SomaLinkPendingRow(title: "Still learning", names: ["Active days and sleep", "Sauna and HRV"])
        }
        .padding()
    }
}
