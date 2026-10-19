//
//  SomaQuestionPrompt.swift
//  SomaUI
//
//  The pieces of a question asked on its own: a row of dots for how far
//  along the run is, the question set large in the middle, and an answer a
//  single tap gives. Nothing sits in a card: the question lies on the
//  sheet's own ground.
//

import SwiftUI

// MARK: - Progress

/// How far through a short run of questions a person is, as small dots: the
/// ones behind in ink, the current one stretched into a short capsule, the
/// ones to come faint. Past the last index every dot is ink.
public struct SomaStepProgress: View {
    private let count: Int
    private let current: Int
    private let label: String

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - count: how many questions the run holds.
    ///   - current: the index being asked, 0 based; `count` once all are done.
    ///   - label: what VoiceOver reads, "2 of 5".
    public init(count: Int, current: Int, label: String) {
        self.count = max(count, 1)
        self.current = current
        self.label = label
    }

    public var body: some View {
        let metrics = theme.metrics
        HStack(spacing: metrics.questionProgressSpacing) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(fill(index))
                    .frame(
                        width: index == current ? metrics.questionProgressDot * 3 : metrics.questionProgressDot,
                        height: metrics.questionProgressDot
                    )
            }
        }
        .animation(reduceMotion ? nil : theme.motion.selection, value: current)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
    }

    private func fill(_ index: Int) -> Color {
        let colors = theme.colors
        if index <= current { return colors.inkPrimary.color }
        return colors.inkSecondary.color.opacity(theme.metrics.questionIdleOpacity)
    }
}

// MARK: - Prompt

/// One question, centred and set large, with its answer under it. No card,
/// no caption: whatever has to be said lives in the question.
public struct SomaQuestionPrompt<Answer: View>: View {
    private let question: String
    private let answer: Answer

    @Environment(\.somaTheme) private var theme

    public init(_ question: String, @ViewBuilder answer: () -> Answer) {
        self.question = question
        self.answer = answer()
    }

    public var body: some View {
        VStack(spacing: theme.metrics.questionAnswerGap) {
            Text(question)
                .somaFont(theme.typography.question)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            answer
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Stack

/// What carries one question to the next: a new `index` slides the prompt
/// out to the leading edge and the next one in from the trailing edge on a
/// short spring. Under Reduce Motion the two crossfade in place.
public struct SomaQuestionStack<Content: View>: View {
    private let index: Int
    private let content: Content

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }

    public var body: some View {
        ZStack {
            content
                .id(index)
                .transition(transition)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? theme.motion.cardAdvanceReduced : theme.motion.cardAdvance, value: index)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Yes or no

/// Yes and no as two wide pills: no drawn as an outline, yes filled with the
/// question's aspect hue. The chosen one swells for the beat before the next
/// question comes.
public struct SomaYesNoPills: View {
    private let yes: String
    private let no: String
    private let aspect: SomaAspect
    private let chosen: Bool?
    private let onAnswer: (Bool) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(yes: String, no: String, aspect: SomaAspect, chosen: Bool? = nil, onAnswer: @escaping (Bool) -> Void) {
        self.yes = yes
        self.no = no
        self.aspect = aspect
        self.chosen = chosen
        self.onAnswer = onAnswer
    }

    public var body: some View {
        HStack(spacing: theme.metrics.answerSpacing) {
            pill(no, value: false)
            pill(yes, value: true)
        }
        .animation(reduceMotion ? nil : theme.motion.cardAdvance, value: chosen)
    }

    private func pill(_ title: String, value: Bool) -> some View {
        let colors = theme.colors
        let metrics = theme.metrics
        let hue = theme.aspects[aspect].identity.color
        let isChosen = chosen == value
        let isPassed = chosen != nil && !isChosen

        return Button { onAnswer(value) } label: {
            Text(title)
                .somaFont(theme.typography.field)
                .foregroundStyle(value ? colors.onOrb.color : colors.inkPrimary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: metrics.answerPillHeight)
                .background {
                    if value {
                        Capsule().fill(hue)
                    } else {
                        Capsule().strokeBorder(colors.inkPrimary.color.opacity(metrics.questionOutlineOpacity), lineWidth: 1.5)
                    }
                }
                .scaleEffect(isChosen ? metrics.answerChosenScale : 1)
                .opacity(isPassed ? metrics.questionIdleOpacity : 1)
                .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

// MARK: - Scale

/// Which way a five step scale's colours run.
public enum SomaScaleTone: Sendable, Equatable {
    /// Low is bad, high is good: red through amber to green.
    case rising
    /// Low is good, high is bad: green through amber to red. Stress.
    case falling
    /// Neither end is better: one aspect's hue, deepening along the row.
    case neutral(SomaAspect)
}

/// Five orbs in a row, one tap to answer. Before a choice each carries a
/// faint wash of its colour so the row reads as a scale; the chosen one grows
/// and fills, the others step back. The words under the ends name them.
public struct SomaScaleOrbs: View {
    private let chosen: Int?
    private let low: String
    private let high: String
    private let tone: SomaScaleTone
    private let names: [String]
    private let onSelect: (Int) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The number of steps, which is what a five step scale is.
    public static var steps: Int { 5 }

    /// - Parameters:
    ///   - chosen: the step picked, 1...5, or nil.
    ///   - low: the word under the first orb.
    ///   - high: the word under the last.
    ///   - tone: which way the colours run.
    ///   - names: what VoiceOver calls each step; the step's number when short.
    public init(chosen: Int? = nil, low: String, high: String, tone: SomaScaleTone = .rising, names: [String] = [], onSelect: @escaping (Int) -> Void) {
        self.chosen = chosen
        self.low = low
        self.high = high
        self.tone = tone
        self.names = names
        self.onSelect = onSelect
    }

    /// The colour of one step, 1...5.
    public static func color(_ step: Int, tone: SomaScaleTone, theme: SomaTheme) -> Color {
        let position = Double(min(max(step, 1), steps) - 1) / Double(steps - 1)
        switch tone {
        case .rising: return SomaStatusScale.color(at: position, theme: theme)
        case .falling: return SomaStatusScale.color(at: 1 - position, theme: theme)
        case .neutral(let aspect):
            return theme.aspects[aspect].identity.color.opacity(0.45 + 0.55 * position)
        }
    }

    public var body: some View {
        let metrics = theme.metrics
        VStack(spacing: metrics.answerSpacing) {
            HStack(spacing: 0) {
                ForEach(1...Self.steps, id: \.self) { step in
                    orb(step)
                }
            }
            .frame(height: metrics.scaleOrbChosen)
            HStack {
                Text(low)
                Spacer(minLength: metrics.answerSpacing)
                Text(high)
            }
            .somaFont(theme.typography.caption)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : theme.motion.cardAdvance, value: chosen)
    }

    private func orb(_ step: Int) -> some View {
        let metrics = theme.metrics
        let hue = Self.color(step, tone: tone, theme: theme)
        let isChosen = chosen == step
        let diameter = isChosen ? metrics.scaleOrbChosen : metrics.scaleOrbIdle
        let wash = chosen == nil ? metrics.scaleOrbWash : metrics.scaleOrbWash * 0.6
        let name = step - 1 < names.count ? names[step - 1] : "\(step)"

        return Button { onSelect(step) } label: {
            Circle()
                .fill(
                    isChosen
                        ? AnyShapeStyle(RadialGradient(
                            colors: [hue.opacity(0.75), hue],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0, endRadius: diameter * 0.7
                        ))
                        : AnyShapeStyle(hue.opacity(wash))
                )
                .overlay(Circle().strokeBorder(hue.opacity(isChosen ? 0 : wash * 1.6), lineWidth: 1))
                .shadow(color: hue.opacity(isChosen ? 0.45 : 0), radius: metrics.scaleOrbChosen * 0.25)
                .frame(width: diameter, height: diameter)
                .frame(maxWidth: .infinity, minHeight: metrics.scaleOrbChosen)
                .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

// MARK: - Count

/// A whole number set with a minus and a plus either side of it, read large
/// in the middle with its unit.
public struct SomaCountStepper: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let unit: String?
    private let decrementLabel: String
    private let incrementLabel: String

    @Environment(\.somaTheme) private var theme

    public init(
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int = 1,
        unit: String? = nil,
        decrementLabel: String,
        incrementLabel: String
    ) {
        self._value = value
        self.range = range
        self.step = max(step, 1)
        self.unit = unit
        self.decrementLabel = decrementLabel
        self.incrementLabel = incrementLabel
    }

    public var body: some View {
        let metrics = theme.metrics
        HStack(spacing: metrics.answerSpacing) {
            disc("minus", label: decrementLabel, enabled: value > range.lowerBound) {
                value = max(value - step, range.lowerBound)
            }
            HStack(alignment: .firstTextBaseline, spacing: metrics.readoutUnitGap) {
                Text("\(value)")
                    .somaFont(theme.typography.metric)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .contentTransition(.numericText(value: Double(value)))
                if let unit {
                    Text(unit)
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(value + step, range.upperBound)
                case .decrement: value = max(value - step, range.lowerBound)
                @unknown default: break
                }
            }
            disc("plus", label: incrementLabel, enabled: value < range.upperBound) {
                value = min(value + step, range.upperBound)
            }
        }
    }

    private func disc(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let metrics = theme.metrics
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.countGlyphSize, weight: .semibold))
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(width: metrics.countButtonDiameter, height: metrics.countButtonDiameter)
                .background(Circle().fill(theme.colors.surfaceRecessed.color))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(.circle)
        }
        .buttonStyle(.somaGlassPress)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Quiet buttons

/// A quiet way out of a question: small text alone in the secondary ink, at
/// a full tap target. "Skip", "Later".
public struct SomaQuietButton: View {
    private let title: String
    private let action: () -> Void

    @Environment(\.somaTheme) private var theme

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
                .padding(.horizontal, theme.metrics.answerSpacing)
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
    }
}

// MARK: - Previews

#Preview("Yes or no") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 28) {
            SomaStepProgress(count: 5, current: 1, label: "2 of 5")
            SomaQuestionStack(index: 1) {
                SomaQuestionPrompt("Did you drink alcohol yesterday?") {
                    SomaYesNoPills(yes: "Yes", no: "No", aspect: .heart) { _ in }
                }
            }
            HStack(spacing: 4) {
                SomaQuietButton("Skip") {}
                SomaQuietButton("Later") {}
            }
        }
        .padding()
    }
}

#Preview("Scale") {
    ZStack {
        SomaPreviewBackdrop()
        VStack(spacing: 40) {
            SomaQuestionPrompt("How rested do you feel?") {
                SomaScaleOrbs(chosen: 4, low: "Exhausted", high: "Fully rested") { _ in }
            }
            SomaQuestionPrompt("How stressed was today?") {
                SomaScaleOrbs(low: "Calm", high: "Very", tone: .falling) { _ in }
            }
        }
        .padding()
    }
}
