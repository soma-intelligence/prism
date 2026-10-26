//
//  SomaQuestionRow.swift
//  SomaUI
//
//  A question asked the way Apple's Health and Flighty set a list: a row
//  among others on one surface, a quiet glyph, the question in the body
//  size, a short cue under it when there is one, and the Journal's cross,
//  dash and check. Several of them make a check-in
//  that reads in one glance (redesigned with the owner, 2026-10-24).
//

import SwiftUI

// MARK: - Row

/// One question in a list of them: a quiet glyph, the question, an optional
/// cue in the secondary ink, and its answer.
///
/// A yes or no answer sits on the trailing edge in the Journal's
/// ``SomaTriStateControl``, cross, dash and check, so the row reads like a
/// Journal habit row. A scale or a count is wider than the
/// room a title leaves, so it lies under the words, across the row. The
/// glyph is in the secondary ink whatever the question's hue: a column of
/// colours read as decoration, not as information.
public struct SomaQuestionRow<Answer: View>: View {
    private let symbol: String
    private let question: String
    private let cue: String?
    private let hue: SomaHealthHue
    private let answerBelow: Bool
    private let yesNo: Binding<Bool?>?
    private let answer: Answer

    @Environment(\.somaTheme) private var theme

    /// A row whose answer lies under the question: a ``SomaCompactScale``, a
    /// ``SomaCompactCount``.
    ///
    /// - Parameters:
    ///   - cue: what the question was written from, "Slept 50 min less than
    ///     usual.", or nil.
    ///   - hue: the aspect the question is about.
    public init(
        symbol: String,
        question: String,
        cue: String? = nil,
        hue: SomaHealthHue,
        @ViewBuilder answer: () -> Answer
    ) {
        self.init(symbol: symbol, question: question, cue: cue, hue: hue,
                  answerBelow: true, yesNo: nil, answer: answer())
    }

    fileprivate init(
        symbol: String,
        question: String,
        cue: String?,
        hue: SomaHealthHue,
        answerBelow: Bool,
        yesNo: Binding<Bool?>?,
        answer: Answer
    ) {
        self.symbol = symbol
        self.question = question
        self.cue = cue
        self.hue = hue
        self.answerBelow = answerBelow
        self.yesNo = yesNo
        self.answer = answer
    }

    public var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.questionRowGap) {
            HStack(alignment: .firstTextBaseline, spacing: metrics.spaceS) {
                Image(systemName: symbol)
                    .somaFont(theme.typography.callout)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .frame(width: metrics.questionGlyphColumn, alignment: .leading)
                    .accessibilityHidden(true)
                words
                    .layoutPriority(1)
                Spacer(minLength: metrics.spaceS)
                if !answerBelow { answer }
            }
            if answerBelow { answer }
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .padding(.vertical, metrics.questionRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .modifier(SomaQuestionAccessibility(question: question, cue: cue, answer: yesNo, animation: theme.motion.selection))
    }

    private var words: some View {
        let colors = theme.colors
        return VStack(alignment: .leading, spacing: theme.metrics.scoreLabelSpacing) {
            Text(question)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            if let cue {
                Text(cue)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public extension SomaQuestionRow where Answer == SomaTriStateControl {
    /// A yes or no question: the Journal's cross, dash and check on the
    /// trailing edge, the dash meaning not answered yet, and the whole row
    /// one adjustable element for VoiceOver. Every check-in question takes
    /// it, as Whoop's journal does (owner, 2026-10-24).
    init(symbol: String, question: String, cue: String? = nil, hue: SomaHealthHue, answer: Binding<Bool?>) {
        self.init(symbol: symbol, question: question, cue: cue, hue: hue,
                  answerBelow: false, yesNo: answer,
                  answer: SomaTriStateControl(value: answer, hue: hue))
    }
}

/// How VoiceOver reads a question row. A yes or no row is one adjustable
/// element, as a Journal habit row is: the question for a label, the answer
/// for a value. Any other row keeps its control reachable on its own, after
/// the words.
private struct SomaQuestionAccessibility: ViewModifier {
    let question: String
    let cue: String?
    let answer: Binding<Bool?>?
    let animation: Animation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let answer {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(question))
                .accessibilityHint(cue.map { Text($0) } ?? Text(""))
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
            content.accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Compact scale

/// Five steps in one recessed track across the row, numbered, with the
/// ends named under it. The chosen step fills in the ink and slides from
/// one step to the next, the same mark as a chosen Yes or No (a colour per
/// step read as decoration, owner 2026-10-24); nothing is lifted
/// until a step is chosen. A second tap on the chosen step clears it, and
/// each change lands with a selection tick.
public struct SomaCompactScale: View {
    @Binding private var value: Int?
    private let low: String
    private let high: String
    private let tone: SomaScaleTone
    private let names: [String]

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var lift

    /// - Parameters:
    ///   - value: the step, 1...5, or nil until chosen.
    ///   - low: the word under the first step.
    ///   - high: the word under the last.
    ///   - tone: which way the scale runs, kept for callers; the chosen step
    ///     no longer takes a colour from it.
    ///   - names: what VoiceOver calls each step; its number when short.
    public init(value: Binding<Int?>, low: String, high: String, tone: SomaScaleTone = .rising, names: [String] = []) {
        self._value = value
        self.low = low
        self.high = high
        self.tone = tone
        self.names = names
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        VStack(spacing: metrics.spaceXS) {
            HStack(spacing: 0) {
                ForEach(1...SomaScaleOrbs.steps, id: \.self) { step in
                    Button {
                        choose(value == step ? nil : step)
                    } label: {
                        stop(step)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(step - 1 < names.count ? names[step - 1] : "\(step)"))
                    .accessibilityAddTraits(value == step ? .isSelected : [])
                }
            }
            .padding(metrics.journalChoiceInset)
            .background(Capsule().fill(colors.surfaceRecessed.color))

            HStack {
                Text(low)
                Spacer(minLength: metrics.cardSpacing)
                Text(high)
            }
            .somaFont(theme.typography.caption)
            .foregroundStyle(colors.inkSecondary.color)
            .lineLimit(1)
            .padding(.horizontal, metrics.spaceXS)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private func choose(_ step: Int?) {
        if reduceMotion { value = step } else { withAnimation(theme.motion.selection) { value = step } }
    }

    private func stop(_ step: Int) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let isChosen = value == step

        return Text("\(step)")
            .somaFont(theme.typography.rowValue)
            .foregroundStyle(isChosen ? colors.canvas.color : colors.inkSecondary.color)
            .frame(maxWidth: .infinity, minHeight: metrics.questionTrackHeight)
            .background {
                if isChosen {
                    Capsule()
                        .fill(colors.inkPrimary.color)
                        .matchedGeometryEffect(id: "lift", in: lift)
                }
            }
            .contentShape(.capsule)
    }
}

// MARK: - Compact count

/// A whole number on the trailing edge of a question row: a minus and a
/// plus in the Journal's graphite capsule with the number between them.
/// The number sits in the secondary ink until it is touched, so the start
/// value never reads as an answer nobody gave.
public struct SomaCompactCount: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let unit: String?
    private let isSet: Bool
    private let decrementLabel: String
    private let incrementLabel: String

    @Environment(\.somaTheme) private var theme

    /// - Parameters:
    ///   - isSet: whether the person has moved it yet.
    public init(
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        unit: String? = nil,
        isSet: Bool,
        decrementLabel: String,
        incrementLabel: String
    ) {
        self._value = value
        self.range = range
        self.unit = unit
        self.isSet = isSet
        self.decrementLabel = decrementLabel
        self.incrementLabel = incrementLabel
    }

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        HStack(spacing: 0) {
            segment("minus", label: decrementLabel, enabled: value > range.lowerBound) {
                value = max(value - 1, range.lowerBound)
            }
            Text(unit.map { "\(value) \($0)" } ?? "\(value)")
                .somaFont(theme.typography.rowValue)
                .foregroundStyle(isSet ? colors.inkPrimary.color : colors.inkSecondary.color)
                .contentTransition(.numericText(value: Double(value)))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, metrics.spaceXS)
                .accessibilityHidden(true)
            segment("plus", label: incrementLabel, enabled: value < range.upperBound) {
                value = min(value + 1, range.upperBound)
            }
        }
        .padding(metrics.journalChoiceInset)
        .background(Capsule().fill(colors.surfaceRecessed.color))
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(unit.map { "\(value) \($0)" } ?? "\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func segment(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let metrics = theme.metrics
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.journalChoiceGlyph, weight: .semibold))
                .foregroundStyle(theme.colors.inkPrimary.color.opacity(enabled ? 1 : metrics.journalChoiceIdleOpacity))
                .frame(width: metrics.journalChoiceWidth, height: metrics.journalChoiceHeight)
                // Taller to a thumb than to the eye, as the Journal's control.
                .padding(.vertical, metrics.journalChoiceReach)
                .contentShape(.rect)
                .padding(.vertical, -metrics.journalChoiceReach)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }
}

public extension SomaQuestionRow where Answer == SomaCompactCount {
    /// A count question: the number and its two buttons on the trailing
    /// edge, where a habit row keeps its amount.
    init(symbol: String, question: String, cue: String? = nil, hue: SomaHealthHue, count: SomaCompactCount) {
        self.init(symbol: symbol, question: question, cue: cue, hue: hue,
                  answerBelow: false, yesNo: nil, answer: count)
    }
}

// MARK: - Previews

#Preview("Question rows") {
    @Previewable @State var alcohol: Bool? = true
    @Previewable @State var tired: Bool?
    @Previewable @State var rested: Int? = 4
    @Previewable @State var glasses = 4

    let rows = ["tired", "alcohol", "rested", "glasses"]

    ZStack {
        SomaPreviewBackdrop()
        SomaBrowseGroup(rows.map(SomaPreviewRowID.init)) { row in
            switch row.id {
            case "tired":
                SomaQuestionRow(symbol: "bed.double.fill", question: "Feeling it?",
                                cue: "Slept 50 min less than usual.", hue: .sleep, answer: $tired)
            case "alcohol":
                SomaQuestionRow(symbol: "wineglass.fill", question: "Did you drink alcohol yesterday?",
                                hue: .heart, answer: $alcohol)
            case "rested":
                SomaQuestionRow(symbol: "moon.fill", question: "How rested do you feel?", hue: .sleep) {
                    SomaCompactScale(value: $rested, low: "Exhausted", high: "Fully rested")
                }
            default:
                SomaQuestionRow(symbol: "drop.fill", question: "Glasses of water so far?", hue: .nutrition,
                                count: SomaCompactCount(value: $glasses, in: 0...12, isSet: false,
                                                        decrementLabel: "Less", incrementLabel: "More"))
            }
        }
        .padding()
    }
}

private struct SomaPreviewRowID: Identifiable {
    let id: String
}
