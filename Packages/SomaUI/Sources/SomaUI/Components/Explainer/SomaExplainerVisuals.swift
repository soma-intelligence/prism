//
//  SomaExplainerVisuals.swift
//  SomaUI
//

import SwiftUI

// MARK: - Data

/// One part of a score, with the weight the formula gives it.
public struct SomaExplainerPart: Identifiable, Sendable, Equatable {
    public var id: String { title }
    public var title: String
    public var symbol: String
    public var hue: SomaHealthHue
    /// Its share of the whole, in percent. The donut normalises, so any unit
    /// that adds up works.
    public var weight: Double
    /// One short line on what it is.
    public var line: String?

    public init(title: String, symbol: String, hue: SomaHealthHue, weight: Double, line: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.hue = hue
        self.weight = weight
        self.line = line
    }
}

/// What moved the number today: one signal and how far it pushed.
public struct SomaExplainerMove: Identifiable, Sendable, Equatable {
    /// How the bar is drawn.
    public enum Shape: Sendable, Equatable {
        /// From a centre tick, -1...1 of the half width: right adds, left takes.
        case signed(Double)
        /// From the left, 0...1: how much of its share the part earned.
        case filled(Double)
    }

    public var id: String { title }
    public var title: String
    /// The number at the trailing edge: "+12", "34 of 42".
    public var value: String
    /// One short line under the name, or nil.
    public var detail: String?
    public var hue: SomaHealthHue
    public var shape: Shape

    public init(title: String, value: String, detail: String? = nil, hue: SomaHealthHue, shape: Shape) {
        self.title = title
        self.value = value
        self.detail = detail
        self.hue = hue
        self.shape = shape
    }

    /// Whether the move costs: a signed move to the left.
    var isCost: Bool {
        if case .signed(let fraction) = shape { return fraction < 0 }
        return false
    }
}

/// One band of a score's scale: its name, where it starts and ends, and how
/// it reads.
public struct SomaExplainerBand: Identifiable, Sendable, Equatable {
    /// The band's colour. The status tones say good or bad, in the data hues
    /// that read apart in both appearances (green, orange, red); the steps
    /// say only more or less, in the aspect's own colour.
    public enum Tone: Sendable, Equatable {
        case good, fair, poor
        case light, middle, strong
    }

    public var id: String { title }
    public var title: String
    public var range: ClosedRange<Double>
    public var tone: Tone
    /// The threshold under the name. Nil reads it off the range in whole
    /// numbers: "under 34", "34 to 66", "67 and over".
    public var detail: String?

    public init(_ title: String, _ range: ClosedRange<Double>, tone: Tone, detail: String? = nil) {
        self.title = title
        self.range = range
        self.tone = tone
        self.detail = detail
    }
}

// MARK: - The ring

/// The score as a ring heading an explainer: a thick arc in the
/// aspect's colours over a quiet track, around a raised disc that holds the
/// number. The arc grows from nothing on first appearance, or sits at its
/// value at once under Reduce Motion.
public struct SomaExplainerRing: View {
    private let value: String?
    private let caption: String?
    private let fraction: Double
    private let aspect: SomaAspect

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    /// - Parameters:
    ///   - fraction: how much of the ring is filled, 0...1.
    ///   - value: the number in the middle, or nil for none.
    ///   - caption: the word under it, or nil.
    ///   - aspect: whose colours the arc wears.
    public init(fraction: Double, value: String? = nil, caption: String? = nil, aspect: SomaAspect) {
        self.fraction = min(1, max(0, fraction))
        self.value = value
        self.caption = caption
        self.aspect = aspect
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let look = theme.aspects[aspect]
        let stroke = metrics.explainerHeroStroke
        let shown = (hasAppeared || reduceMotion) ? fraction : 0

        ZStack {
            Circle()
                .stroke(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 1.2), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [look.identity.color.opacity(0.55), look.identity.color],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            SomaExplainerCore(value: value, caption: caption)
                .padding(stroke * 1.4)
        }
        .frame(width: metrics.explainerHeroDiameter, height: metrics.explainerHeroDiameter)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(theme.motion.explainerDraw) { hasAppeared = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([value, caption].compactMap { $0 }.joined(separator: ", ")))
    }
}

// MARK: - The donut

/// A score's parts as a donut: one arc per part, sized by its weight and
/// coloured by its hue, the score in the middle. It reads as "what this
/// number is made of" before a word is read. The parts draw in turn on first
/// appearance, or all at once under Reduce Motion.
public struct SomaExplainerDonut: View {
    private let parts: [SomaExplainerPart]
    private let value: String?
    private let caption: String?

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    public init(parts: [SomaExplainerPart], value: String? = nil, caption: String? = nil) {
        self.parts = parts
        self.value = value
        self.caption = caption
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let stroke = metrics.explainerHeroStroke
        let total = max(0.0001, parts.reduce(0) { $0 + max(0, $1.weight) })
        let gap = parts.count > 1 ? metrics.explainerDonutGap : 0
        let progress = (hasAppeared || reduceMotion) ? 1.0 : 0.0
        let spans = parts.reduce(into: [(part: SomaExplainerPart, start: Double, end: Double)]()) { spans, part in
            let start = spans.last?.end ?? 0
            spans.append((part, start, start + max(0, part.weight) / total))
        }

        ZStack {
            Circle()
                .stroke(colors.inkPrimary.color.opacity(metrics.hairlineOpacity * 1.2), lineWidth: stroke)
            ForEach(spans, id: \.part.id) { span in
                Circle()
                    .trim(from: span.start * progress + gap / 2,
                          to: max(span.start * progress + gap / 2, span.end * progress - gap / 2))
                    .stroke(span.part.hue.color, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            SomaExplainerCore(value: value, caption: caption)
                .padding(stroke * 1.4)
        }
        .frame(width: metrics.explainerHeroDiameter, height: metrics.explainerHeroDiameter)
        .onAppear {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(theme.motion.explainerDraw) { hasAppeared = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(parts.map { "\($0.title) \(Int(($0.weight / total * 100).rounded())) percent" }
            .joined(separator: ", ")))
        .accessibilityValue(Text([value, caption].compactMap { $0 }.joined(separator: " ")))
    }
}

/// The raised disc in the middle of the ring and the donut.
private struct SomaExplainerCore: View {
    let value: String?
    let caption: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        ZStack {
            Circle()
                .fill(colors.surface.color)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            VStack(spacing: 2) {
                if let value {
                    Text(value)
                        .somaFont(theme.typography.explainerHeroValue)
                        .foregroundStyle(colors.inkPrimary.color)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                if let caption {
                    Text(caption)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(theme.metrics.explainerRowGap / 2)
        }
    }
}

// MARK: - What moves it

/// What moved the number today, one bar per signal: from a centre tick for a
/// signed push (right adds, left takes, a cost in the danger ink), or from
/// the left for how much of its share a part earned.
public struct SomaExplainerMoves: View {
    private let title: String
    private let moves: [SomaExplainerMove]

    @Environment(\.somaTheme) private var theme

    public init(_ title: String, moves: [SomaExplainerMove]) {
        self.title = title
        self.moves = moves
    }

    public var body: some View {
        SomaExplainerSection(title) {
            ForEach(moves) { move in
                SomaExplainerMoveRow(move: move)
            }
        }
    }
}

private struct SomaExplainerMoveRow: View {
    let move: SomaExplainerMove

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let fill = move.isCost ? colors.danger.color : move.hue.color

        VStack(alignment: .leading, spacing: metrics.explainerBarGap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: metrics.explainerLineSpacing) {
                    Text(move.title)
                        .somaFont(type.explainerTerm)
                        .foregroundStyle(colors.inkPrimary.color)
                    if let detail = move.detail {
                        Text(detail)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: metrics.explainerRowGap)
                Text(move.value)
                    .somaFont(type.rowValue)
                    .foregroundStyle(move.isCost ? colors.danger.color : colors.inkPrimary.color)
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = metrics.explainerBarHeight
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.surfaceRecessed.color)
                    switch move.shape {
                    case .filled(let fraction):
                        Capsule().fill(fill)
                            .frame(width: max(height, width * min(1, max(0, fraction))))
                            .opacity(fraction > 0 ? 1 : 0)
                    case .signed(let fraction):
                        let clamped = min(1, max(-1, fraction))
                        let length = width / 2 * abs(clamped)
                        if length > 0 {
                            Capsule().fill(fill)
                                .frame(width: max(height, length))
                                .offset(x: clamped > 0 ? width / 2 : width / 2 - max(height, length))
                        }
                        Rectangle()
                            .fill(colors.inkPrimary.color.opacity(0.5))
                            .frame(width: max(1, 2 / displayScale), height: height * 2.4)
                            .offset(x: width / 2 - 1 / displayScale)
                    }
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
            }
            .frame(height: metrics.explainerBarHeight * 2.4)
            .accessibilityHidden(true)
        }
        .padding(metrics.explainerRowPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ranges

/// The scale as coloured bands with their thresholds, today marked on it:
/// what a paragraph of "under 34 means" would say, drawn.
public struct SomaExplainerRanges: View {
    private let title: String
    private let bands: [SomaExplainerBand]
    private let aspect: SomaAspect
    private let marker: Double?
    private let markerLabel: String?

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - bands: in order, low to high, meeting end to end: each band's
    ///     upper bound is where the next one starts (0...34, 34...67, 67...100).
    ///   - aspect: the colour of the step tones.
    ///   - marker: today's value on the same scale, or nil.
    ///   - markerLabel: the word over the marker: "Today, 72".
    public init(_ title: String, bands: [SomaExplainerBand], aspect: SomaAspect,
                marker: Double? = nil, markerLabel: String? = nil) {
        self.title = title
        self.bands = bands
        self.aspect = aspect
        self.marker = marker
        self.markerLabel = markerLabel
    }

    public var body: some View {
        SomaExplainerSection(title) {
            strip
                .padding(theme.metrics.explainerRowPadding)
        }
    }

    private var strip: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let low = bands.first?.range.lowerBound ?? 0
        let high = bands.last?.range.upperBound ?? 1
        let span = max(0.0001, high - low)
        let gap = metrics.explainerRangeGap
        let position = marker.map { min(1, max(0, ($0 - low) / span)) }

        return VStack(alignment: .leading, spacing: metrics.explainerBarGap) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let usable = width - gap * CGFloat(max(0, bands.count - 1))
                ZStack(alignment: .topLeading) {
                    HStack(spacing: gap) {
                        ForEach(bands) { band in
                            Capsule()
                                .fill(color(band.tone))
                                .frame(width: usable * (band.range.upperBound - band.range.lowerBound) / span)
                        }
                    }
                    .frame(height: metrics.explainerRangeHeight)
                    .offset(y: metrics.explainerRangeLabelRoom + (metrics.explainerRangeMarker - metrics.explainerRangeHeight) / 2)

                    if let position {
                        let x = width * position
                        Circle()
                            .fill(colors.inkPrimary.color)
                            .overlay(Circle().strokeBorder(colors.surface.color, lineWidth: 3))
                            .frame(width: metrics.explainerRangeMarker, height: metrics.explainerRangeMarker)
                            .offset(x: x - metrics.explainerRangeMarker / 2, y: metrics.explainerRangeLabelRoom)
                        if let markerLabel {
                            Text(markerLabel)
                                .somaFont(type.captionValue)
                                .foregroundStyle(colors.inkPrimary.color)
                                .fixedSize()
                                .frame(width: width, alignment: position < 0.2 ? .leading : position > 0.8 ? .trailing : .center)
                                .offset(x: position < 0.2 || position > 0.8 ? 0 : x - width / 2)
                        }
                    }
                }
            }
            .frame(height: metrics.explainerRangeLabelRoom + metrics.explainerRangeMarker)

            GeometryReader { proxy in
                let usable = proxy.size.width - gap * CGFloat(max(0, bands.count - 1))
                HStack(alignment: .top, spacing: gap) {
                    ForEach(bands) { band in
                        VStack(alignment: .leading, spacing: metrics.explainerLineSpacing) {
                            Text(band.title)
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkPrimary.color)
                            Text(threshold(band))
                                .somaFont(type.captionValue)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: usable * (band.range.upperBound - band.range.lowerBound) / span, alignment: .leading)
                    }
                }
            }
            .frame(height: metrics.explainerGlyphDiameter + metrics.explainerLineSpacing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(bands.map { "\($0.title), \(threshold($0))" }.joined(separator: "; ")))
        .accessibilityValue(Text(markerLabel ?? ""))
    }

    /// "Under 34", "34 to 66", "67 and over": each band's upper bound is
    /// where the next one starts.
    private func threshold(_ band: SomaExplainerBand) -> String {
        if let detail = band.detail { return detail }
        let lower = Int(band.range.lowerBound.rounded())
        let upper = Int(band.range.upperBound.rounded())
        if band.id == bands.first?.id { return String(localized: "under \(upper)") }
        if band.id == bands.last?.id { return String(localized: "\(lower) and over") }
        return String(localized: "\(lower) to \(upper - 1)")
    }

    private func color(_ tone: SomaExplainerBand.Tone) -> Color {
        let hue = theme.aspects[aspect].identity.color
        switch tone {
        case .good: return SomaHealthHue.nutrition.color
        case .fair: return SomaHealthHue.mobility.color
        case .poor: return SomaHealthHue.vitals.color
        case .light: return hue.opacity(0.3)
        case .middle: return hue.opacity(0.6)
        case .strong: return hue
        }
    }
}

#Preview("Explainer parts") {
    ScrollView {
        VStack(spacing: 16) {
            HStack {
                SomaExplainerRing(fraction: 0.72, value: "72", caption: "Recovered", aspect: .heart)
                SomaExplainerDonut(parts: [
                    SomaExplainerPart(title: "One", symbol: "clock", hue: .sleep, weight: 60),
                    SomaExplainerPart(title: "Two", symbol: "heart", hue: .heart, weight: 40),
                ], value: "35", caption: "Low")
            }
            .scaleEffect(0.8)
            SomaExplainerSection("Rows") {
                SomaExplainerRow(symbol: "waveform.path.ecg", hue: .heart, term: "Term", line: "One short line.")
                SomaExplainerRow(symbol: "moon.fill", hue: .sleep, term: "Term", line: "One short line.", trailing: "40%")
            }
            SomaExplainerMoves("What moves it", moves: [
                SomaExplainerMove(title: "Adds", value: "+12", hue: .heart, shape: .signed(0.45)),
                SomaExplainerMove(title: "Takes", value: "-6", hue: .vitals, shape: .signed(-0.3)),
                SomaExplainerMove(title: "Earned", value: "30 of 42", hue: .sleep, shape: .filled(0.71)),
            ])
            SomaExplainerRanges("Ranges", bands: [
                SomaExplainerBand("Low", 0...34, tone: .poor),
                SomaExplainerBand("Middle", 34...67, tone: .fair),
                SomaExplainerBand("High", 67...100, tone: .good),
            ], aspect: .heart, marker: 72, markerLabel: "Today, 72")
        }
        .padding()
    }
    .background(SomaPreviewBackdrop())
}
