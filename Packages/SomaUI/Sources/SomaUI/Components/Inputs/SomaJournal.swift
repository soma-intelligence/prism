//
//  SomaJournal.swift
//  SomaUI
//

import SwiftUI

// The journal's parts are coloured by what they are about, with the Health
// category hues (``SomaHealthHue``): water cyan, a meal green, an evening
// indigo. Those are data colours. What a person chooses (a tag switched on,
// the stop they picked) stays in the ink, so the accent rule holds.

// MARK: - Glyph disc

/// A symbol on a disc tinted with a Health hue: the picture that leads a
/// habit row.
public struct SomaGlyphDisc: View {
    private let symbol: String
    private let hue: SomaHealthHue

    @Environment(\.somaTheme) private var theme

    public init(symbol: String, hue: SomaHealthHue) {
        self.symbol = symbol
        self.hue = hue
    }

    public var body: some View {
        let metrics = theme.metrics
        let diameter = metrics.journalRowDisc

        Image(systemName: symbol)
            .font(.system(size: metrics.journalRowGlyph, weight: .semibold))
            .foregroundStyle(hue.color)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [hue.start.color, hue.end.color],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .opacity(metrics.journalDiscOpacity)
                )
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Quick add tile

/// One thing to add: its glyph in its hue on a tile washed with the same
/// hue, the name under it. Four sit in a row, the way the + menu of a journal
/// lays its actions out.
public struct SomaGlyphTile: View {
    private let title: String
    private let symbol: String
    private let hue: SomaHealthHue
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme

    public init(_ title: String, symbol: String, hue: SomaHealthHue, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.hue = hue
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.journalTileCornerRadius, style: .continuous)

        Button(action: action) {
            VStack(spacing: metrics.journalTileLabelSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: metrics.journalTileGlyph, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [hue.start.color, hue.end.color], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: metrics.journalTileGlyph * 1.3)
                Text(title)
                    .somaFont(theme.typography.tabLabel)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, metrics.scoreLabelSpacing)
            .frame(maxWidth: .infinity, minHeight: metrics.journalTileHeight)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [hue.start.color, hue.end.color],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .opacity(metrics.journalTileWashOpacity)
                )
            )
            .overlay(shape.strokeBorder(hue.color.opacity(metrics.journalTileRimOpacity), lineWidth: 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Habit mark

/// The compact control at the trailing edge of a habit row.
public struct SomaHabitMark: View {
    public enum State: Equatable, Sendable {
        /// A switch that is off: an empty ring.
        case off
        /// A switch the person turned on: a disc in the ink and a check. A
        /// choice, so it never takes a data colour.
        case on
        /// A goal Health measured as met: a disc in the row's hue and a
        /// check.
        case met
        /// A goal part of the way there, 0...1: an arc in the row's hue.
        case progress(Double)
        /// Nothing was measured: a dash, never an empty ring that reads as
        /// zero.
        case missing
    }

    private let state: State
    private let hue: SomaHealthHue

    @Environment(\.somaTheme) private var theme

    public init(_ state: State, hue: SomaHealthHue) {
        self.state = state
        self.hue = hue
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let diameter = metrics.journalMarkDiameter

        Group {
            switch state {
            case .off:
                Circle()
                    .strokeBorder(colors.inkSecondary.color.opacity(metrics.journalMarkIdleOpacity), lineWidth: metrics.journalMarkLine)
            case .on:
                check(fill: colors.inkPrimary.color, ink: colors.canvas.color)
            case .met:
                check(fill: hue.color, ink: SomaHealthHue.ink.color)
            case .progress(let fraction):
                ZStack {
                    Circle()
                        .stroke(hue.color.opacity(metrics.journalDiscOpacity), lineWidth: metrics.journalMarkLine * 1.5)
                    Circle()
                        .trim(from: 0, to: min(max(fraction, 0), 1))
                        .stroke(hue.color, style: StrokeStyle(lineWidth: metrics.journalMarkLine * 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(metrics.journalMarkLine * 0.75)
            case .missing:
                Text("-")
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(colors.inkSecondary.color)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func check(fill: Color, ink: Color) -> some View {
        Circle()
            .fill(fill)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: theme.metrics.journalMarkGlyph, weight: .bold))
                    .foregroundStyle(ink)
            }
    }
}

// MARK: - Answer

/// A yes or no answer on the trailing edge of a habit card: three glyphs in one graphite capsule, a cross, a dash
/// and a check. The chosen one sits in a raised pill a step lighter than the
/// track, and the pill slides between them.
///
/// The dash is the resting place: an unanswered day sits on it, and choosing
/// it clears the answer. A check takes the row's hue, because a yes is what
/// the row is about; a cross takes the alert colour held low, a real answer
/// that does not shout. Every change lands with a selection haptic.
public struct SomaTriStateControl: View {
    @Binding private var value: Bool?
    private let hue: SomaHealthHue

    @Namespace private var pill
    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Binding<Bool?>, hue: SomaHealthHue) {
        self._value = value
        self.hue = hue
    }

    /// The three answers in the order they are drawn: no, none, yes.
    public static let order: [Bool?] = [false, nil, true]

    /// What VoiceOver says the answer is.
    public static func spokenValue(_ value: Bool?) -> String {
        switch value {
        case true?: "Yes"
        case false?: "No"
        case nil: "Not answered"
        }
    }

    /// The answer one step along the control, `steps` to the right when
    /// positive: what a swipe up or down does under VoiceOver. Held at the
    /// ends rather than wrapping, the way an adjustable control behaves.
    public static func step(_ value: Bool?, by steps: Int) -> Bool? {
        let index = order.firstIndex(of: value) ?? 1
        return order[min(max(index + steps, 0), order.count - 1)]
    }

    public var body: some View {
        let metrics = theme.metrics

        HStack(spacing: 0) {
            ForEach(Self.order.indices, id: \.self) { index in
                segment(Self.order[index])
            }
        }
        .padding(metrics.journalChoiceInset)
        .background(Capsule().fill(theme.colors.surfaceRecessed.color))
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Answer"))
        .accessibilityValue(Text(Self.spokenValue(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: choose(Self.step(value, by: 1))
            case .decrement: choose(Self.step(value, by: -1))
            @unknown default: break
            }
        }
    }

    private func choose(_ answer: Bool?) {
        guard answer != value else { return }
        if reduceMotion { value = answer } else { withAnimation(theme.motion.selection) { value = answer } }
    }

    private func segment(_ answer: Bool?) -> some View {
        let metrics = theme.metrics
        let isChosen = value == answer

        return Button {
            choose(answer)
        } label: {
            Image(systemName: Self.symbol(answer))
                .font(.system(size: metrics.journalChoiceGlyph, weight: .semibold))
                .foregroundStyle(glyphColor(answer, isChosen: isChosen))
                .frame(width: metrics.journalChoiceWidth, height: metrics.journalChoiceHeight)
                .background {
                    if isChosen {
                        raisedPill.matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                // Taller to a thumb than to the eye: the reach is added for
                // the hit test and taken back for the layout.
                .padding(.vertical, metrics.journalChoiceReach)
                .contentShape(.rect)
                .padding(.vertical, -metrics.journalChoiceReach)
        }
        .buttonStyle(.plain)
    }

    /// The chosen segment's pill: a wash of ink over the track on the dark
    /// ground, the card's own surface with a soft shadow on the light one.
    @ViewBuilder
    private var raisedPill: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        if scheme == .dark {
            Capsule()
                .fill(colors.inkPrimary.color.opacity(metrics.journalChoiceLiftOpacity))
                .overlay(Capsule().strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
        } else {
            Capsule()
                .fill(colors.surface.color)
                .shadow(color: colors.inkPrimary.color.opacity(metrics.journalChoiceShadowOpacity),
                        radius: metrics.journalChoiceShadowRadius, y: 0.5)
        }
    }

    private static func symbol(_ answer: Bool?) -> String {
        switch answer {
        case true?: "checkmark"
        case false?: "xmark"
        case nil: "minus"
        }
    }

    private func glyphColor(_ answer: Bool?, isChosen: Bool) -> Color {
        let metrics = theme.metrics
        let colors = theme.colors
        guard isChosen else { return colors.inkSecondary.color.opacity(metrics.journalChoiceIdleOpacity) }
        switch answer {
        case true?: return hue.color
        case false?: return colors.statusAlert.color.opacity(metrics.journalChoiceNoOpacity)
        case nil: return colors.inkPrimary.color
        }
    }
}

// MARK: - Quantity

/// The trailing edge of a habit card that counts rather than answers: the
/// day's amount and its unit, a dash before the unit while nothing is
/// logged, then an arrow in the same graphite capsule as
/// ``SomaTriStateControl``. The card itself is the button; the arrow says so.
public struct SomaHabitQuantity: View {
    private let value: String?
    private let unit: String

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - value: the amount already formatted, or nil for nothing logged.
    ///   - unit: what it is counted in: "ml", "mg".
    public init(value: String?, unit: String) {
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: metrics.cardSpacing) {
            Text("\(value ?? "-") \(unit)")
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(colors.inkSecondary.color)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "arrow.right")
                .font(.system(size: metrics.journalChoiceGlyph, weight: .semibold))
                .foregroundStyle(colors.inkPrimary.color)
                .frame(width: metrics.journalChoiceWidth + metrics.journalChoiceInset * 2,
                       height: metrics.journalChoiceHeight + metrics.journalChoiceInset * 2)
                .background(Capsule().fill(colors.surfaceRecessed.color))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Habit row

/// One habit: a tinted glyph, its name, an optional value, and a compact
/// control on the trailing edge. Sits on its own card in a
/// ``SomaHabitStack``, or in a ``SomaBrowseGroup``, which gives it the
/// surface and the hairlines; its glyph fills the group's glyph column so
/// the separators start under the title.
public struct SomaHabitRow<Trailing: View>: View {
    private let symbol: String
    private let title: String
    private let detail: String?
    private let hue: SomaHealthHue
    private let isSelected: Bool
    private let action: (() -> Void)?
    private let answer: Binding<Bool?>?
    private let trailing: Trailing

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - detail: a value set before the control, in the secondary ink.
    ///   - isSelected: whether a switch row is on, for VoiceOver.
    ///   - action: what a tap anywhere on the row does. Nil for a row that
    ///     only reports.
    public init(
        symbol: String,
        title: String,
        detail: String? = nil,
        hue: SomaHealthHue,
        isSelected: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(symbol: symbol, title: title, detail: detail, hue: hue,
                  isSelected: isSelected, action: action, answer: nil, trailing: trailing())
    }

    private init(
        symbol: String,
        title: String,
        detail: String?,
        hue: SomaHealthHue,
        isSelected: Bool,
        action: (() -> Void)?,
        answer: Binding<Bool?>?,
        trailing: Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.hue = hue
        self.isSelected = isSelected
        self.action = action
        self.answer = answer
        self.trailing = trailing
    }

    public var body: some View {
        if let action {
            Button(action: action) { line }
                .buttonStyle(SomaBrowseRowStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            line
        }
    }

    private var line: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        return HStack(spacing: metrics.browseRowSpacing) {
            SomaGlyphDisc(symbol: symbol, hue: hue)
                .frame(width: metrics.browseGlyphColumn)
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: metrics.browseRowSpacing)
            if let detail {
                Text(detail)
                    .somaFont(theme.typography.rowValue)
                    .foregroundStyle(colors.inkSecondary.color)
                    .lineLimit(1)
                    .fixedSize()
            }
            trailing
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: metrics.journalRowMinHeight)
        .contentShape(.rect)
        .modifier(SomaHabitAccessibility(title: title, answer: answer, animation: theme.motion.selection))
    }
}

/// How VoiceOver reads a habit row. A row that answers is one adjustable
/// element, its name for a label and its answer for a value, so a swipe up
/// or down answers without hunting for three small buttons. Any other row
/// reads its parts together.
private struct SomaHabitAccessibility: ViewModifier {
    let title: String
    let answer: Binding<Bool?>?
    let animation: Animation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let answer {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(SomaTriStateControl.spokenValue(answer.wrappedValue)))
                .accessibilityAdjustableAction { direction in
                    let steps: Int
                    switch direction {
                    case .increment: steps = 1
                    case .decrement: steps = -1
                    @unknown default: return
                    }
                    let next = SomaTriStateControl.step(answer.wrappedValue, by: steps)
                    if reduceMotion { answer.wrappedValue = next } else { withAnimation(animation) { answer.wrappedValue = next } }
                }
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

public extension SomaHabitRow where Trailing == SomaHabitMark {
    /// A row whose trailing control is a ``SomaHabitMark`` in the row's hue.
    init(
        symbol: String,
        title: String,
        detail: String? = nil,
        hue: SomaHealthHue,
        mark: SomaHabitMark.State,
        action: (() -> Void)? = nil
    ) {
        self.init(
            symbol: symbol,
            title: title,
            detail: detail,
            hue: hue,
            isSelected: mark == .on,
            action: action
        ) {
            SomaHabitMark(mark, hue: hue)
        }
    }
}

public extension SomaHabitRow where Trailing == SomaTriStateControl {
    /// A row that asks a yes or no question: a ``SomaTriStateControl`` on
    /// its trailing edge, and the whole row one adjustable element for
    /// VoiceOver.
    init(symbol: String, title: String, hue: SomaHealthHue, answer: Binding<Bool?>) {
        self.init(symbol: symbol, title: title, detail: nil, hue: hue, isSelected: false,
                  action: nil, answer: answer,
                  trailing: SomaTriStateControl(value: answer, hue: hue))
    }
}

public extension SomaHabitRow where Trailing == SomaHabitQuantity {
    /// A row that counts: the day's amount, its unit and an arrow, the whole
    /// row opening where the amount is logged.
    init(symbol: String, title: String, hue: SomaHealthHue, value: String?, unit: String, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, hue: hue, action: action) {
            SomaHabitQuantity(value: value, unit: unit)
        }
    }
}

// MARK: - Habit stack

/// Habit rows each on a card of their own, a short gap between them: a list
/// of separate things to answer rather than
/// one grouped table.
public struct SomaHabitStack<Data: RandomAccessCollection, Row: View>: View
where Data.Element: Identifiable {
    private let data: Data
    private let row: (Data.Element) -> Row

    @Environment(\.somaTheme) private var theme

    public init(_ data: Data, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.row = row
    }

    public var body: some View {
        let metrics = theme.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.journalCardCornerRadius, style: .continuous)

        VStack(spacing: metrics.journalCardSpacing) {
            ForEach(data) { element in
                row(element)
                    .background(shape.fill(theme.colors.surface.color))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Status gradient

/// The theme's status colours as one scale, from its alert red through amber
/// to its normal green: a feeling, a share of a day logged.
public enum SomaStatusScale {
    /// The colour at `position` in 0...1.
    public static func color(at position: Double, theme: SomaTheme) -> Color {
        let colors = theme.colors
        let alert = colors.statusAlert.color
        let out = colors.statusOut.color
        let normal = colors.statusNormal.color
        let t = min(max(position, 0), 1)
        return t < 0.5 ? alert.mix(with: out, by: t * 2) : out.mix(with: normal, by: (t - 0.5) * 2)
    }

    /// The three stops, for a gradient.
    public static func stops(_ theme: SomaTheme) -> [Color] {
        [theme.colors.statusAlert.color, theme.colors.statusOut.color, theme.colors.statusNormal.color]
    }
}

// MARK: - Progress ring

/// A small ring filling clockwise along the status scale, red at the start
/// to green at full, with a view at its centre: how much of a day is logged.
public struct SomaProgressRing<Center: View>: View {
    private let fraction: Double
    private let center: Center

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double, @ViewBuilder center: () -> Center) {
        self.fraction = min(max(fraction, 0), 1)
        self.center = center()
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let line = metrics.journalRingLine
        let gradient = AngularGradient(
            colors: SomaStatusScale.stops(theme),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * max(fraction, 0.01))
        )

        ZStack {
            Circle()
                .stroke(colors.surfaceRecessed.color, lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(gradient, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : theme.motion.selection, value: fraction)
            center
        }
        .padding(line / 2)
        .frame(width: metrics.journalRingDiameter, height: metrics.journalRingDiameter)
    }
}

public extension SomaProgressRing where Center == EmptyView {
    init(fraction: Double) {
        self.init(fraction: fraction) { EmptyView() }
    }
}

// MARK: - Feeling scale

/// Seven stops from very unpleasant to very pleasant along the status scale,
/// red through amber to green. The value is the control: a tap sets the
/// stop, a second tap clears it. The chosen stop is drawn whole and marked
/// with an ink dot; the others fade.
public struct SomaFeelingScale: View {
    @Binding private var value: Int?
    private let names: [String]

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: 0...6, or nil until chosen.
    ///   - names: what each stop is called, for VoiceOver.
    public init(value: Binding<Int?>, names: [String]) {
        self._value = value
        self.names = names
    }

    /// The colour of one stop, 0...6.
    public static func color(_ stop: Int, theme: SomaTheme) -> Color {
        SomaStatusScale.color(at: Double(min(max(stop, 0), 6)) / 6, theme: theme)
    }

    public var body: some View {
        let metrics = theme.metrics

        HStack(spacing: metrics.journalFeelStopSpacing) {
            Image(systemName: "cloud.rain.fill")
                .font(.system(size: metrics.journalRowGlyph, weight: .semibold))
                .foregroundStyle(Self.color(0, theme: theme))
                .accessibilityHidden(true)
            ForEach(0..<7, id: \.self) { stop in
                Button {
                    let next = value == stop ? nil : stop
                    if reduceMotion { value = next } else { withAnimation(theme.motion.selection) { value = next } }
                } label: {
                    stopView(stop)
                }
                .buttonStyle(.somaGlassPressDim)
                .accessibilityLabel(Text(stop < names.count ? names[stop] : "\(stop + 1)"))
                .accessibilityAddTraits(value == stop ? .isSelected : [])
            }
            Image(systemName: "sun.max.fill")
                .font(.system(size: metrics.journalRowGlyph, weight: .semibold))
                .foregroundStyle(Self.color(6, theme: theme))
                .accessibilityHidden(true)
        }
        .frame(minHeight: metrics.minimumTapTarget)
    }

    private func stopView(_ stop: Int) -> some View {
        let metrics = theme.metrics
        let hue = Self.color(stop, theme: theme)
        let isChosen = value == stop
        let idle = value == nil ? metrics.journalFeelRestOpacity : metrics.journalFeelIdleOpacity

        return RoundedRectangle(cornerRadius: metrics.journalFeelStopHeight / 3, style: .continuous)
            .fill(hue.opacity(isChosen ? 1 : idle))
            .overlay {
                if isChosen {
                    Circle()
                        .fill(SomaHealthHue.ink.color)
                        .frame(width: metrics.aspectDotSize * 1.4, height: metrics.aspectDotSize * 1.4)
                }
            }
            .frame(height: isChosen ? metrics.journalFeelStopHeight : metrics.journalFeelStopHeight * 0.72)
            .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
            .contentShape(.rect)
    }
}
