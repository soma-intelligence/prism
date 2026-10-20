//
//  SomaJournal.swift
//  SomaUI
//

import SwiftUI

// The journal's parts are coloured by what they are about, with the calm
// Track tones (``SomaTrackTone``): an evening dusk, water a tide, a meal sage.
// Those are data colours, muted on purpose. What a person chooses (a no, the
// stop they picked) stays in the ink, so the accent rule holds.

// MARK: - Quick add tile

/// One thing to add: its line glyph on a softly tinted square, the name under
/// it, on a plain card. Four sit in a row; the colour stays in the badge, so a
/// grid of them reads calm.
public struct SomaGlyphTile: View {
    private let title: String
    private let glyph: SomaTrackGlyph.Kind
    private let tone: SomaTrackTone?
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme

    /// - Parameter tone: nil draws the glyph in the ink on a recessed square,
    ///   for a tile that is a control (More, Less) rather than an entry.
    public init(_ title: String, glyph: SomaTrackGlyph.Kind, tone: SomaTrackTone?, action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let shape = RoundedRectangle(cornerRadius: metrics.journalTileCornerRadius, style: .continuous)

        Button(action: action) {
            VStack(spacing: metrics.journalTileLabelSpacing) {
                SomaTrackGlyph(glyph, tone: tone, style: .badge)
                Text(title)
                    .somaFont(theme.typography.tabLabel)
                    .foregroundStyle(colors.inkPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, metrics.scoreLabelSpacing)
            .frame(maxWidth: .infinity, minHeight: metrics.journalTileHeight + 10)
            .background(shape.fill(colors.surface.color))
            .overlay(shape.strokeBorder(colors.inkPrimary.color.opacity(metrics.hairlineOpacity), lineWidth: 0.5))
            .contentShape(shape)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Habit mark

/// The compact mark at the trailing edge of a row Health fills in.
public struct SomaHabitMark: View {
    public enum State: Equatable, Sendable {
        /// A switch that is off: an empty square.
        case off
        /// A switch the person turned on: the ink and a check. A choice, so
        /// it never takes a data colour.
        case on
        /// A goal Health measured as met: the row's tone and a check.
        case met
        /// A goal part of the way there, 0...1: an arc in the row's tone.
        case progress(Double)
        /// Nothing was measured: a dash, never an empty ring that reads as
        /// zero.
        case missing
    }

    private let state: State
    private let tone: SomaTrackTone

    @Environment(\.somaTheme) private var theme

    public init(_ state: State, tone: SomaTrackTone) {
        self.state = state
        self.tone = tone
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let diameter = metrics.journalMarkDiameter
        let square = RoundedRectangle(cornerRadius: metrics.ritualCheckCornerRadius, style: .continuous)

        Group {
            switch state {
            case .off:
                square.strokeBorder(colors.inkSecondary.color.opacity(metrics.journalMarkIdleOpacity), lineWidth: metrics.journalMarkLine * 0.75)
            case .on:
                check(fill: colors.inkPrimary.color, ink: colors.surface.color)
            case .met:
                check(fill: tone.color, ink: colors.surface.color)
            case .progress(let fraction):
                ZStack {
                    Circle()
                        .stroke(tone.color.opacity(metrics.trackBadgeTint * 1.4), lineWidth: metrics.journalMarkLine * 1.25)
                    Circle()
                        .trim(from: 0, to: min(max(fraction, 0), 1))
                        .stroke(tone.color, style: StrokeStyle(lineWidth: metrics.journalMarkLine * 1.25, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(metrics.journalMarkLine)
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
        let metrics = theme.metrics
        return RoundedRectangle(cornerRadius: metrics.ritualCheckCornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                SomaAnswerMarkShape(isYes: true)
                    .stroke(ink, style: StrokeStyle(lineWidth: metrics.trackAnswerGlyphStroke, lineCap: .round, lineJoin: .round))
                    .frame(width: metrics.journalMarkGlyph, height: metrics.journalMarkGlyph)
            }
    }
}

// MARK: - Answer switch

/// A done or not done answer on the trailing edge of a habit card: three
/// slots in one recessed track, a cross, a dash and a check, and a raised
/// knob that rests on one of them.
///
/// The knob always shows where the answer is: on the dash in the middle
/// while nothing is entered, on the cross for not done, on the check for
/// done, where it fills with the row's tone. A tap on a slot moves the knob
/// there; a tap on the chosen cross or check, or on the dash, clears the
/// answer back to the middle. The knob slides on a short spring and its
/// colour follows it; the marks never redraw, so nothing flickers mid move:
/// a mark takes the knob's ink exactly where the knob covers it. Under
/// Reduce Motion the knob simply lands. Every change lands with a selection
/// haptic.
public struct SomaAnswerSwitch: View {
    @Binding private var value: Bool?
    private let tone: SomaTrackTone

    @Environment(\.somaTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Binding<Bool?>, tone: SomaTrackTone) {
        self._value = value
        self.tone = tone
    }

    /// The answers in the order the slots sit and VoiceOver steps through
    /// them: no, none, yes.
    public static let order: [Bool?] = [false, nil, true]

    /// What VoiceOver says the answer is.
    public static func spokenValue(_ value: Bool?) -> String {
        switch value {
        case true?: "Done"
        case false?: "Not done"
        case nil: "Not answered"
        }
    }

    /// The answer one step along, `steps` toward yes when positive: what a
    /// swipe up or down does under VoiceOver. Held at the ends rather than
    /// wrapping, the way an adjustable control behaves.
    public static func step(_ value: Bool?, by steps: Int) -> Bool? {
        let index = order.firstIndex(of: value) ?? 1
        return order[min(max(index + steps, 0), order.count - 1)]
    }

    /// What a tap on one slot leaves: that answer, or none when it was
    /// already chosen. The dash always leaves none.
    public static func tapping(_ answer: Bool?, on value: Bool?) -> Bool? {
        value == answer ? nil : answer
    }

    /// Which slot the knob rests on, 0 to 2, left to right.
    public static func slot(_ value: Bool?) -> Int {
        order.firstIndex(of: value) ?? 1
    }

    public var body: some View {
        let metrics = theme.metrics
        let slot = metrics.trackAnswerSlotWidth
        let height = metrics.trackAnswerCellHeight
        let knob = RoundedRectangle(cornerRadius: metrics.trackAnswerCornerRadius - metrics.trackAnswerInset, style: .continuous)
        let offset = CGFloat(Self.slot(value)) * slot

        ZStack(alignment: .leading) {
            marks(chosen: false)
            knobFill(knob)
                .frame(width: slot, height: height)
                .offset(x: offset)
            marks(chosen: true)
                .mask(alignment: .leading) {
                    knob.frame(width: slot, height: height).offset(x: offset)
                }
            HStack(spacing: 0) {
                ForEach(Array(Self.order.enumerated()), id: \.offset) { _, answer in
                    Button {
                        choose(Self.tapping(answer, on: value))
                    } label: {
                        Color.clear
                            .frame(width: slot, height: height)
                            // Taller to a thumb than to the eye: the reach
                            // is added for the hit test and taken back for
                            // the layout.
                            .padding(.vertical, metrics.trackAnswerReach)
                            .contentShape(.rect)
                            .padding(.vertical, -metrics.trackAnswerReach)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(Self.spokenValue(answer)))
                }
            }
        }
        .frame(width: slot * CGFloat(Self.order.count), height: height)
        .padding(metrics.trackAnswerInset)
        .background(
            RoundedRectangle(cornerRadius: metrics.trackAnswerCornerRadius, style: .continuous)
                .fill(theme.colors.surfaceRecessed.color)
        )
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
        if reduceMotion { value = answer } else { withAnimation(theme.motion.trackAnswer) { value = answer } }
    }

    /// The three marks in a row: faint at rest, or in the ink each takes
    /// under the knob.
    private func marks(chosen: Bool) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let stroke = StrokeStyle(lineWidth: metrics.trackAnswerGlyphStroke, lineCap: .round, lineJoin: .round)

        return HStack(spacing: 0) {
            ForEach(Array(Self.order.enumerated()), id: \.offset) { _, answer in
                let ink: Color = if !chosen {
                    colors.inkSecondary.color.opacity(metrics.trackAnswerIdleOpacity)
                } else {
                    switch answer {
                    case true?: colors.surface.color
                    case false?: colors.inkPrimary.color
                    case nil: colors.inkSecondary.color
                    }
                }
                SomaAnswerMarkShape(answer: answer)
                    .stroke(ink, style: stroke)
                    .frame(width: metrics.trackAnswerGlyph, height: metrics.trackAnswerGlyph)
                    .frame(width: metrics.trackAnswerSlotWidth, height: metrics.trackAnswerCellHeight)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The knob: the row's tone on a yes, else a raised surface (an ink
    /// wash over the track in dark, where the surface is the card's own).
    /// One shape whose colour moves with it, never two crossfading.
    private func knobFill(_ knob: RoundedRectangle) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let isYes = value == true
        let isDark = scheme == .dark
        let base: Color = isYes ? tone.color : (isDark ? colors.surfaceRecessed.color : colors.surface.color)

        return knob.fill(base)
            .overlay(knob.fill(colors.inkPrimary.color.opacity(isDark && !isYes ? metrics.trackAnswerNoOpacity : 0)))
            .shadow(color: colors.inkPrimary.color.opacity(isDark ? 0 : metrics.journalChoiceShadowOpacity),
                    radius: metrics.journalChoiceShadowRadius, y: 0.5)
            .allowsHitTesting(false)
    }
}

/// A check, a cross or a dash as a line on a 24 unit grid, so it can draw
/// itself.
public struct SomaAnswerMarkShape: Shape {
    /// True for the check, false for the cross, nil for the dash.
    public let answer: Bool?

    public init(answer: Bool?) {
        self.answer = answer
    }

    public init(isYes: Bool) {
        self.answer = isYes
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let placement = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        var path = Path()
        switch answer {
        case true?:
            path.move(to: CGPoint(x: 4, y: 12.5))
            path.addLine(to: CGPoint(x: 9.5, y: 18))
            path.addLine(to: CGPoint(x: 20, y: 6.5))
        case false?:
            path.move(to: CGPoint(x: 6, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 18))
            path.move(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 6, y: 18))
        case nil:
            path.move(to: CGPoint(x: 7, y: 12))
            path.addLine(to: CGPoint(x: 17, y: 12))
        }
        return path.applying(placement)
    }
}

// MARK: - Quantity

/// The trailing edge of a habit card that counts rather than answers: the
/// day's amount and its unit, a dash before the unit while nothing is
/// logged, then an arrow in the same recessed square as
/// ``SomaAnswerSwitch``. The card itself is the button; the arrow says so.
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
                .font(.system(size: metrics.trackAnswerGlyph, weight: .semibold))
                .foregroundStyle(colors.inkPrimary.color)
                .frame(width: metrics.trackAnswerCellWidth + metrics.trackAnswerInset * 2,
                       height: metrics.trackAnswerCellHeight + metrics.trackAnswerInset * 2)
                .background(
                    RoundedRectangle(cornerRadius: metrics.trackAnswerCornerRadius, style: .continuous)
                        .fill(colors.surfaceRecessed.color)
                )
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Habit row

/// One habit: its line glyph on a tinted square, its name, an optional
/// value, and a compact control on the trailing edge. Sits on its own card in
/// a ``SomaHabitStack``, or in a ``SomaBrowseGroup``, which gives it the
/// surface and the hairlines; its glyph fills the group's glyph column so
/// the separators start under the title.
public struct SomaHabitRow<Trailing: View>: View {
    private let glyph: SomaTrackGlyph.Kind
    private let title: String
    private let detail: String?
    private let tone: SomaTrackTone
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
        glyph: SomaTrackGlyph.Kind,
        title: String,
        detail: String? = nil,
        tone: SomaTrackTone,
        isSelected: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(glyph: glyph, title: title, detail: detail, tone: tone,
                  isSelected: isSelected, action: action, answer: nil, trailing: trailing())
    }

    private init(
        glyph: SomaTrackGlyph.Kind,
        title: String,
        detail: String?,
        tone: SomaTrackTone,
        isSelected: Bool,
        action: (() -> Void)?,
        answer: Binding<Bool?>?,
        trailing: Trailing
    ) {
        self.glyph = glyph
        self.title = title
        self.detail = detail
        self.tone = tone
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
            SomaTrackGlyph(glyph, tone: tone, style: .row)
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
        .modifier(SomaHabitAccessibility(title: title, answer: answer, animation: theme.motion.trackAnswer))
    }
}

/// How VoiceOver reads a habit row. A row that answers is one adjustable
/// element, its name for a label and its answer for a value, so a swipe up
/// or down answers without hunting for two small buttons. Any other row
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
                .accessibilityValue(Text(SomaAnswerSwitch.spokenValue(answer.wrappedValue)))
                .accessibilityAdjustableAction { direction in
                    let steps: Int
                    switch direction {
                    case .increment: steps = 1
                    case .decrement: steps = -1
                    @unknown default: return
                    }
                    let next = SomaAnswerSwitch.step(answer.wrappedValue, by: steps)
                    if reduceMotion { answer.wrappedValue = next } else { withAnimation(animation) { answer.wrappedValue = next } }
                }
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

public extension SomaHabitRow where Trailing == SomaHabitMark {
    /// A row whose trailing control is a ``SomaHabitMark`` in the row's tone.
    init(
        glyph: SomaTrackGlyph.Kind,
        title: String,
        detail: String? = nil,
        tone: SomaTrackTone,
        mark: SomaHabitMark.State,
        action: (() -> Void)? = nil
    ) {
        self.init(glyph: glyph, title: title, detail: detail, tone: tone,
                  isSelected: mark == .on, action: action) {
            SomaHabitMark(mark, tone: tone)
        }
    }
}

public extension SomaHabitRow where Trailing == SomaAnswerSwitch {
    /// A row that asks a done or not done question: a ``SomaAnswerSwitch``
    /// on its trailing edge, and the whole row one adjustable element for
    /// VoiceOver.
    init(glyph: SomaTrackGlyph.Kind, title: String, tone: SomaTrackTone, answer: Binding<Bool?>) {
        self.init(glyph: glyph, title: title, detail: nil, tone: tone, isSelected: false,
                  action: nil, answer: answer,
                  trailing: SomaAnswerSwitch(value: answer, tone: tone))
    }
}

public extension SomaHabitRow where Trailing == SomaHabitQuantity {
    /// A row that counts: the day's amount, its unit and an arrow, the whole
    /// row opening where the amount is logged.
    init(glyph: SomaTrackGlyph.Kind, title: String, tone: SomaTrackTone, value: String?, unit: String, action: @escaping () -> Void) {
        self.init(glyph: glyph, title: title, tone: tone, action: action) {
            SomaHabitQuantity(value: value, unit: unit)
        }
    }
}

// MARK: - Habit stack

/// Habit rows each on a card of their own, a short gap between them: a list
/// of separate things to answer rather than one grouped table.
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
/// to its normal green: for the scales that need to warn.
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

/// A small ring filling clockwise along the calm ramp, clay at the start to
/// sage at full, with a view at its centre: how much of a day is logged.
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

        ZStack {
            Circle()
                .stroke(colors.surfaceRecessed.color, lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(SomaEnergyRamp.calm.value(at: fraction).color,
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
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

/// Seven stops from very unpleasant to very pleasant along the calm ramp,
/// clay through sand to sage. The value is the control: a tap sets the stop,
/// a second tap clears it. The chosen stop is drawn whole and marked with a
/// dot; the others fade.
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
        SomaEnergyRamp.calm.value(at: Double(min(max(stop, 0), 6)) / 6).color
    }

    public var body: some View {
        let metrics = theme.metrics

        HStack(spacing: metrics.journalFeelStopSpacing) {
            SomaTrackGlyph(.cloud, tone: nil, style: .caption)
                .opacity(0.6)
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
            SomaTrackGlyph(.daylight, tone: nil, style: .caption)
                .opacity(0.6)
        }
        .frame(minHeight: metrics.minimumTapTarget)
    }

    private func stopView(_ stop: Int) -> some View {
        let metrics = theme.metrics
        let hue = Self.color(stop, theme: theme)
        let isChosen = value == stop
        let idle = value == nil ? metrics.journalFeelRestOpacity : metrics.journalFeelIdleOpacity

        return RoundedRectangle(cornerRadius: metrics.journalFeelStopHeight / 3.5, style: .continuous)
            .fill(hue.opacity(isChosen ? 1 : idle))
            .overlay {
                if isChosen {
                    Circle()
                        .fill(theme.colors.surface.color)
                        .frame(width: metrics.aspectDotSize * 1.4, height: metrics.aspectDotSize * 1.4)
                }
            }
            .frame(height: isChosen ? metrics.journalFeelStopHeight : metrics.journalFeelStopHeight * 0.72)
            .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
            .contentShape(.rect)
    }
}
