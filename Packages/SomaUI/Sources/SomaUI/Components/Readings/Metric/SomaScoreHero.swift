//
//  SomaScoreHero.swift
//  SomaUI
//

import SwiftUI

/// The head of a score page, set like a metric page's head so the two read as
/// one family: when the number is from, the number large and light with "of
/// 100" or its unit, one plain line led by a dot in its tone, and beside them
/// the score as a calm ring, the same ring Today draws under the orb, grown.
///
/// The ring fills to the score in the aspect's colour over a faint track of
/// the same colour; the person's usual sits on it as a slightly stronger arc,
/// so the fill reads against it at a glance. A reading with no 0 to 100 scale
/// (resting heart rate) draws ``Dial/marker`` instead: the usual arc and a dot
/// where today sits. The aspect's glyph rests in the middle.
///
/// The ring draws in once when the page opens and glides to a new value; the
/// number rolls. Under Reduce Motion both arrive in place.
public struct SomaScoreHero: View {
    /// What the ring shows, in shares of its turn (0 at the top, clockwise).
    public enum Dial: Equatable, Sendable {
        /// A score: the ring filled to `value`.
        case fill(Double?)
        /// A reading without a scale: a dot at `value` on the usual arc.
        case marker(Double?)
        /// No ring.
        case none
    }

    private let aspect: SomaAspect
    private let caption: String?
    private let value: String?
    private let unit: String?
    private let meaning: String?
    private let detail: String?
    private let tone: SomaCueTone
    private let dial: Dial
    private let usual: ClosedRange<Double>?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - caption: when the number is from: "Today", "Last night".
    ///   - unit: "of 100" for a score, the reading's unit otherwise.
    ///   - meaning: the score's word ("Restored"), led by the tone's dot.
    ///   - detail: what follows it in the secondary ink ("8 below last week").
    ///   - usual: the person's usual as shares of the ring's turn, 0 to 1.
    public init(
        aspect: SomaAspect,
        caption: String?,
        value: String?,
        unit: String?,
        meaning: String?,
        detail: String? = nil,
        tone: SomaCueTone = .neutral,
        dial: Dial,
        usual: ClosedRange<Double>? = nil
    ) {
        self.aspect = aspect
        self.caption = caption
        self.value = value
        self.unit = unit
        self.meaning = meaning
        self.detail = detail
        self.tone = tone
        self.dial = dial
        self.usual = usual
    }

    /// A reading's place on a ``Dial/marker`` ring and its usual, as shares
    /// of the turn: the usual takes the middle of the ring with as much room
    /// again either side, so a value well outside it still lands on it.
    public static func markerShares(_ value: Double?, usual: ClosedRange<Double>?) -> (value: Double?, usual: ClosedRange<Double>?) {
        SomaScoreDialMath.marker(value, usual: usual)
    }

    public var body: some View {
        let metrics = theme.metrics

        HStack(alignment: .center, spacing: metrics.cardSpacing) {
            SomaHeroText(caption: caption, value: value, unit: unit, meaning: meaning, detail: detail, tone: tone)

            if dial != .none {
                SomaScoreDial(aspect: aspect, dial: dial, usual: usual)
                    .frame(width: metrics.scoreHeroDial, height: metrics.scoreHeroDial)
            }
        }
        .padding(.top, metrics.scoreHeroTopPadding)
        .accessibilityElement(children: .combine)
    }
}

/// A head's words and number: when it is from, the number large and light
/// with its unit, and one line led by a dot in its tone. Shared by the score
/// head and the metric stage, so the two read as one family.
///
/// The number rolls digit by digit and keeps its room while it rolls, so a
/// number losing a digit never runs over its unit.
struct SomaHeroText: View {
    let caption: String?
    let value: String?
    let unit: String?
    let meaning: String?
    let detail: String?
    let tone: SomaCueTone

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let type = theme.typography

        VStack(alignment: .leading, spacing: metrics.metricHeroSpacing) {
            if let caption {
                Text(caption)
                    .somaFont(type.eyebrow)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: metrics.metricHeroSpacing * 1.5) {
                Text(value ?? "-")
                    .somaFont(type.metricHero)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .somaRollingNumber(value, holdsWidth: unit != nil)
                if let unit, value != nil {
                    Text(unit)
                        .somaFont(type.metricHeroUnit)
                        .foregroundStyle(colors.inkSecondary.color)
                        .lineLimit(1)
                }
            }
            if meaning != nil || detail != nil {
                HStack(alignment: .firstTextBaseline, spacing: metrics.metricHeroSpacing * 2) {
                    Circle()
                        .fill(tone.color(colors))
                        .frame(width: metrics.metricMeaningDot, height: metrics.metricMeaningDot)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    meaningText(colors: colors)
                        .somaFont(type.callout)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The word in the primary ink, what follows in the secondary.
    private func meaningText(colors: SomaColors) -> Text {
        let lead = Text(meaning ?? "").foregroundStyle(colors.inkPrimary.color)
        guard let detail, !detail.isEmpty else { return lead }
        let rest = Text((meaning == nil ? "" : "  ") + detail).foregroundStyle(colors.inkSecondary.color)
        return Text("\(lead)\(rest)")
    }
}

/// The ring beside a score page's number.
struct SomaScoreDial: View {
    let aspect: SomaAspect
    let dial: SomaScoreHero.Dial
    let usual: ClosedRange<Double>?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False until the ring first appears, so it draws in once.
    @State private var isDrawn = false

    var body: some View {
        let metrics = theme.metrics
        let hue = theme.aspects[aspect].identity.color
        let stroke = metrics.scoreHeroStroke
        let shown = isDrawn || reduceMotion

        ZStack {
            Circle()
                .stroke(hue.opacity(metrics.scoreHeroTrackOpacity), lineWidth: stroke)
            if let usual {
                let band = SomaScoreDialMath.clamp(usual)
                Circle()
                    .trim(from: band.lowerBound, to: shown ? band.upperBound : band.lowerBound)
                    .stroke(hue.opacity(metrics.scoreHeroUsualOpacity),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            switch dial {
            case .fill(let value):
                Circle()
                    .trim(from: 0, to: shown ? SomaScoreDialMath.share(value) : 0)
                    .stroke(hue, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            case .marker(let value):
                if let value {
                    GeometryReader { proxy in
                        let point = SomaScoreDialMath.point(share: value, in: proxy.size, inset: stroke / 2)
                        Circle()
                            .fill(hue)
                            .overlay(Circle().strokeBorder(theme.colors.canvas.color, lineWidth: stroke / 3))
                            .frame(width: stroke * 2.2, height: stroke * 2.2)
                            .position(point)
                            .opacity(shown ? 1 : 0)
                    }
                }
            case .none:
                EmptyView()
            }
            SomaAspectGlyph(aspect, style: .caption)
                .foregroundStyle(hue)
        }
        .padding(stroke / 2)
        .onAppear {
            guard !isDrawn else { return }
            if reduceMotion {
                isDrawn = true
            } else {
                withAnimation(theme.motion.chartDraw) { isDrawn = true }
            }
        }
        .animation(reduceMotion ? nil : theme.motion.chartMorph, value: dial)
        .animation(reduceMotion ? nil : theme.motion.chartMorph, value: usual)
        .accessibilityHidden(true)
    }
}

/// The ring's arithmetic, kept apart so it can be tested.
enum SomaScoreDialMath {
    /// A share of the turn, held in 0...1; nil is an empty ring.
    static func share(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    /// A band held inside the turn, never empty.
    static func clamp(_ band: ClosedRange<Double>) -> ClosedRange<Double> {
        let low = share(band.lowerBound)
        let high = max(low + 0.004, share(band.upperBound))
        return low...min(1, high)
    }

    /// Where a share of the turn lands on the ring, from the top, clockwise.
    static func point(share value: Double, in size: CGSize, inset: CGFloat) -> CGPoint {
        let radius = min(size.width, size.height) / 2 - inset
        let angle = (share(value) * 360 - 90) * .pi / 180
        return CGPoint(x: size.width / 2 + radius * cos(angle), y: size.height / 2 + radius * sin(angle))
    }

    /// A reading's place on a ring that spans its usual with room either
    /// side: the usual takes the middle half of the turn's lower three
    /// quarters, so a value well outside it still lands on the ring.
    static func marker(_ value: Double?, usual: ClosedRange<Double>?) -> (value: Double?, usual: ClosedRange<Double>?) {
        guard let usual, usual.upperBound > usual.lowerBound else { return (nil, nil) }
        let width = usual.upperBound - usual.lowerBound
        let low = usual.lowerBound - width
        let high = usual.upperBound + width
        func place(_ x: Double) -> Double { 0.125 + 0.75 * (x - low) / (high - low) }
        return (value.map { share(place($0)) }, place(usual.lowerBound)...place(usual.upperBound))
    }
}

#Preview("Score hero") {
    ScrollView {
        VStack(alignment: .leading, spacing: 40) {
            SomaScoreHero(aspect: .sleep, caption: "Last night", value: "87", unit: "of 100",
                          meaning: "Restored", detail: "8 below last week", tone: .good,
                          dial: .fill(0.87), usual: 0.78...0.9)
            SomaScoreHero(aspect: .mind, caption: "Today", value: "25", unit: "of 100",
                          meaning: "Run down", detail: "3 below yesterday", tone: .watch,
                          dial: .fill(0.25), usual: 0.45...0.62)
            SomaScoreHero(aspect: .heart, caption: "Resting today", value: "66", unit: "bpm",
                          meaning: "Above your usual", tone: .watch,
                          dial: .marker(0.7), usual: 0.31...0.56)
            SomaScoreHero(aspect: .activity, caption: "Today", value: nil, unit: "of 100",
                          meaning: "Waiting for a first reading", dial: .fill(nil))
        }
        .padding()
    }
    .background(SomaTheme.standard.colors.canvas.color)
}
