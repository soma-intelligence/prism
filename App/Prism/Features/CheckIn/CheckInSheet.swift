//
//  CheckInSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// "Soma asks": every question of the moment on one sheet sized to them.
/// A header with the moment, Later on its trailing edge and a thin progress
/// in segments under it; one grouped card of rows, each a quiet glyph, the
/// question, a short cue under it when the numbers wrote it, and the
/// Journal's cross, dash and check on the trailing edge. Every question is
/// a yes or no, as Whoop's journal asks (owner, 2026-10-24). Done at the
/// foot. Every tap lands with a light tick.
///
/// Nothing is written until Done, which hands the answers to the presenter
/// in the order it asked them and passes over the rest. Later keeps what was
/// answered and puts the remainder off. While an answer waits unsaved the
/// sheet does not swipe away, so a stray drag never loses it.
struct CheckInSheet: View {
    let session: CheckInSession
    let presenter: CheckInPresenter

    @Environment(\.somaTheme) private var theme
    /// What the person has said so far, by question id.
    @State private var answers: [String: CheckInAnswer] = [:]
    /// Bumped by Done: what the success tick listens to.
    @State private var finished = 0
    /// The height the questions need, measured: the sheet opens to it, so
    /// no empty page hangs under the card.
    @State private var fitted: CGFloat = 0

    var body: some View {
        let metrics = theme.metrics

        VStack(spacing: 0) {
            header
                .padding(.top, metrics.spaceL)
                .padding(.bottom, metrics.spaceM)

            SomaPageScroll {
                SomaBrowseGroup(session.questions) { question in
                    row(question)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)

            SomaActionButton(String(localized: "Done")) { done() }
                .padding(.top, metrics.spaceM)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, metrics.spaceM)
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .background(alignment: .top) { measure }
        .sensoryFeedback(.success, trigger: finished)
        .interactiveDismissDisabled(!answers.isEmpty)
        .presentationDetents(fitted > 0 ? [.height(fitted), .large] : [.large])
        .presentationBackground(theme.colors.canvas.color)
        .presentationDragIndicator(.visible)
        .modifier(CheckInSheetSize())
    }

    /// The whole sheet laid out at its natural height, unseen, to size the
    /// detent: the same parts as the body with the card unscrolled.
    private var measure: some View {
        let metrics = theme.metrics
        return VStack(spacing: 0) {
            header
                .padding(.top, metrics.spaceL)
                .padding(.bottom, metrics.spaceM)
            SomaBrowseGroup(session.questions) { question in
                row(question)
            }
            SomaActionButton(String(localized: "Done")) {}
                .padding(.top, metrics.spaceM)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, metrics.spaceM)
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            fitted = height
        }
    }

    // MARK: Header

    /// The moment with Later on its trailing edge, and under it one
    /// segment per question, filled as each gets an answer.
    private var header: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let total = session.questions.count
        let answered = session.questions.filter { answers[$0.id] != nil }.count

        return VStack(alignment: .leading, spacing: metrics.spaceM) {
            HStack(alignment: .firstTextBaseline, spacing: metrics.cardSpacing) {
                VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                    Text(String(localized: "Soma asks"))
                        .somaFont(type.eyebrow)
                        .foregroundStyle(colors.inkSecondary.color)
                    Text(Self.title(session.window))
                        .somaFont(type.title)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: metrics.cardSpacing)
                Button(String(localized: "Later")) { later() }
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkSecondary.color)
                    .buttonStyle(.plain)
            }

            HStack(spacing: metrics.spaceXS) {
                ForEach(session.questions.indices, id: \.self) { index in
                    Capsule()
                        .fill(session.questions[index].isAnswered(in: answers)
                              ? colors.inkPrimary.color
                              : colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                        .frame(height: metrics.questionProgressHeight)
                }
            }
            .animation(theme.motion.selection, value: answered)
            .accessibilityElement()
            .accessibilityLabel(Text(String(localized: "\(answered) of \(total) answered")))
        }
        .padding(.horizontal, metrics.scoreLabelSpacing)
    }

    private static func title(_ window: CheckInWindow) -> String {
        switch window {
        case .morning: String(localized: "This morning")
        case .evening: String(localized: "This evening")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ question: CheckInQuestion) -> some View {
        let style = CheckInRowStyle.of(question)
        let words = CheckInRowStyle.words(question)

        switch question.kind {
        case .yesNo:
            SomaQuestionRow(symbol: style.symbol, question: words.question, cue: words.cue, hue: style.hue,
                            answer: yesNo(question))
        case .scale(let low, let high, let tone):
            SomaQuestionRow(symbol: style.symbol, question: words.question, cue: words.cue, hue: style.hue) {
                SomaCompactScale(value: step(question), low: low, high: high, tone: tone)
            }
        case .number(let range, let start, let unit):
            SomaQuestionRow(
                symbol: style.symbol, question: words.question, cue: words.cue, hue: style.hue,
                count: SomaCompactCount(
                    value: count(question, start: start), in: range, unit: unit,
                    isSet: answers[question.id] != nil,
                    decrementLabel: String(localized: "Less"), incrementLabel: String(localized: "More")
                )
            )
        }
    }

    private func yesNo(_ question: CheckInQuestion) -> Binding<Bool?> {
        Binding(
            get: {
                switch answers[question.id] {
                case .yes?: true
                case .no?: false
                default: nil
                }
            },
            set: { answers[question.id] = $0.map { $0 ? .yes : .no } }
        )
    }

    private func step(_ question: CheckInQuestion) -> Binding<Int?> {
        Binding(
            get: {
                if case .scale(let step)? = answers[question.id] { return step }
                return nil
            },
            set: { answers[question.id] = $0.map(CheckInAnswer.scale) }
        )
    }

    private func count(_ question: CheckInQuestion, start: Int) -> Binding<Int> {
        Binding(
            get: {
                if case .number(let value)? = answers[question.id] { return value }
                return start
            },
            set: { answers[question.id] = .number($0) }
        )
    }

    // MARK: Saving

    /// Every answer, in the order the run asked them; what was left blank is
    /// passed over, as Skip passed it over. The window is then done.
    private func done() {
        commit(through: session.questions.count - 1)
        finished += 1
        presenter.close()
    }

    /// What was answered is kept, and anything left blank above the last
    /// answer is passed over with it; the questions after that come back
    /// once the snooze runs out. With nothing left to ask, Later is Done.
    private func later() {
        if let last = session.questions.lastIndex(where: { answers[$0.id] != nil }) {
            commit(through: last)
        }
        if session.isDone {
            finished += 1
            presenter.close()
        } else {
            presenter.later()
        }
    }

    /// Hands the answers to the presenter one by one up to `last`: the
    /// presenter answers the question in front of it and moves on, so the
    /// order is the run's own.
    private func commit(through last: Int) {
        for question in session.questions.prefix(last + 1) {
            guard session.current?.id == question.id else { continue }
            if let answer = answers[question.id] {
                presenter.answer(answer)
            } else {
                presenter.skip()
            }
        }
    }
}

private extension CheckInQuestion {
    func isAnswered(in answers: [String: CheckInAnswer]) -> Bool { answers[id] != nil }
}

/// How a question looks in its row: the Journal's own glyph and hue for a
/// question that sets a Journal tag, otherwise a glyph for where the answer
/// goes and the hue of the aspect it is about.
struct CheckInRowStyle: Equatable {
    var symbol: String
    var hue: SomaHealthHue

    static func of(_ question: CheckInQuestion) -> CheckInRowStyle {
        let hue = SomaHealthHue(question.aspect)
        switch question.destination {
        case .journalTag(let tag, _):
            let style = TrackTagStyle.of(tag)
            return CheckInRowStyle(symbol: style.symbol, hue: style.hue)
        case .journalFeeling: return CheckInRowStyle(symbol: "face.smiling", hue: hue)
        case .homeEnergy: return CheckInRowStyle(symbol: "bolt.fill", hue: hue)
        case .homeStress: return CheckInRowStyle(symbol: "waveform.path", hue: hue)
        case .homeBody: return CheckInRowStyle(symbol: "figure.cooldown", hue: hue)
        case .mindEnergy: return CheckInRowStyle(symbol: "battery.75percent", hue: hue)
        case .mindFocus: return CheckInRowStyle(symbol: "scope", hue: hue)
        case .wakeRating: return CheckInRowStyle(symbol: "sunrise.fill", hue: hue)
        case .bodyQuestion: return CheckInRowStyle(symbol: symbol(question.aspect), hue: hue)
        }
    }

    /// The glyph an aspect wears on a question the body asked.
    static func symbol(_ aspect: SomaAspect) -> String {
        switch aspect {
        case .sleep: "bed.double.fill"
        case .heart: "heart.fill"
        case .mind: "brain.head.profile"
        case .activity: "figure.walk"
        case .body: "figure.stand"
        case .gut: "fork.knife"
        }
    }

    /// The question and its cue. A question the numbers wrote says what it
    /// read before it asks, "Slept 50 min less than usual. Feeling it?": the
    /// reading becomes the cue under the row and the ask stays the title. The
    /// words saved with the answer are the question's own, whole.
    static func words(_ question: CheckInQuestion) -> (question: String, cue: String?) {
        words(question.text, isDataDriven: question.isDataDriven)
    }

    static func words(_ text: String, isDataDriven: Bool) -> (question: String, cue: String?) {
        guard isDataDriven, let stop = text.range(of: ". ", options: .backwards) else { return (text, nil) }
        let ask = text[stop.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !ask.isEmpty else { return (text, nil) }
        return (ask, String(text[..<stop.lowerBound]) + ".")
    }
}

/// A sheet on the phone sizes itself to the screen. On the Mac and the
/// headset it would shrink to its content, so it asks for a size.
private struct CheckInSheetSize: ViewModifier {
    @Environment(\.somaTheme) private var theme

    func body(content: Content) -> some View {
#if os(iOS)
        content
#else
        content.frame(width: theme.metrics.questionSheetWidth, height: theme.metrics.questionSheetHeight)
#endif
    }
}

/// Puts "Soma asks" on the shell: the sheet a notification or Track opens.
private struct CheckInPrompt: ViewModifier {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    private let presenter = CheckInPresenter.shared

    func body(content: Content) -> some View {
        @Bindable var presenter = presenter

        content
            .sheet(item: $presenter.session, onDismiss: { presenter.close() }) { session in
                CheckInSheet(session: session, presenter: presenter)
            }
            // It never opens on its own over what someone came to read (owner,
            // 2026-10-23): it opens from its notification or from Track.
            .task { presenter.attach(health: health, journal: journal) }
    }
}

#if DEBUG
extension CheckInPresenter {
    /// The defaults key behind `-checkin.preview morning` (or `evening`): a
    /// debug launch opens that window's run whatever the clock says, so the
    /// sheet can be looked at in the afternoon.
    static let reviewKey = "checkin.preview"

    /// Opens the run the launch argument names, picked as the engine would
    /// pick it a few hours into that window today. Answers are written as
    /// usual, to today.
    func presentForReview() {
        guard session == nil,
              let raw = UserDefaults.standard.string(forKey: Self.reviewKey),
              let window = CheckInWindow(rawValue: raw) else { return }
        let day = store.calendar.startOfDay(for: now())
        guard let at = store.calendar.date(byAdding: .hour, value: window.hours.lowerBound + 2, to: day) else { return }
        let run = questions(at: at)
        guard !run.isEmpty else { return }
        session = CheckInSession(window: window, questions: run)
    }
}
#endif

extension View {
    /// "Soma asks" on this view: the shell carries it once.
    func checkInPrompt() -> some View {
        modifier(CheckInPrompt())
    }
}
