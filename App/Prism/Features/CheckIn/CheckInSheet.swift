//
//  CheckInSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// "Soma asks": one question at a time on a half height sheet, set large in
/// the middle of the app's own ground, with no card inside the sheet.
///
/// A tap answers: the orb grows or the pill swells, a light tick, and after
/// a short beat the question slides away and the next one springs in. Under
/// Reduce Motion they crossfade. Skip and Later sit together under it as
/// small quiet text. After the last question the sheet says the day is done
/// and closes itself.
struct CheckInSheet: View {
    let session: CheckInSession
    let presenter: CheckInPresenter

    @Environment(\.somaTheme) private var theme
    @State private var chosen: CheckInAnswer?
    @State private var count: Int
    /// Bumped on each answer: what the selection tick listens to.
    @State private var ticks = 0
    @State private var isHolding = false

    /// How long "Done for today" stays before the sheet goes by itself.
    static let doneHold: Duration = .seconds(1.4)

    init(session: CheckInSession, presenter: CheckInPresenter) {
        self.session = session
        self.presenter = presenter
        _count = State(initialValue: Self.start(of: session.current))
    }

    var body: some View {
        let metrics = theme.metrics

        VStack(spacing: 0) {
            SomaStepProgress(
                count: session.questions.count,
                current: session.index,
                label: String(localized: "\(min(session.index + 1, session.questions.count)) of \(session.questions.count)")
            )
            .padding(.top, metrics.cardSpacing * 1.5)

            Spacer(minLength: metrics.cardSpacing)

            SomaQuestionStack(index: session.index) {
                if let question = session.current {
                    prompt(question)
                } else {
                    SomaQuestionPrompt(String(localized: "Done for today")) {
                        Image(systemName: "checkmark")
                            .font(.system(size: metrics.countGlyphSize, weight: .semibold))
                            .foregroundStyle(theme.colors.onOrb.color)
                            .frame(width: metrics.scaleOrbChosen, height: metrics.scaleOrbChosen)
                            .background(Circle().fill(theme.colors.statusNormal.color))
                            .accessibilityHidden(true)
                    }
                }
            }

            Spacer(minLength: metrics.cardSpacing)

            HStack(spacing: 0) {
                SomaQuietButton(String(localized: "Skip")) { presenter.skip() }
                SomaQuietButton(String(localized: "Later")) { presenter.later() }
            }
            .opacity(session.isDone ? 0 : 1)
            .disabled(session.isDone || isHolding)
            .accessibilityHidden(session.isDone)
        }
        .padding(.horizontal, metrics.questionSheetInset)
        .padding(.bottom, metrics.cardSpacing * 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: ticks)
        .sensoryFeedback(.success, trigger: session.isDone, condition: { _, done in done })
        .onChange(of: session.index) {
            chosen = nil
            count = Self.start(of: session.current)
        }
        .task(id: session.isDone) {
            guard session.isDone else { return }
            try? await Task.sleep(for: Self.doneHold)
            guard !Task.isCancelled else { return }
            presenter.close()
        }
        .presentationDetents([.medium])
        .presentationBackground(theme.colors.canvas.color)
        .presentationDragIndicator(.visible)
        .modifier(CheckInSheetSize())
    }

    @ViewBuilder
    private func prompt(_ question: CheckInQuestion) -> some View {
        switch question.kind {
        case .yesNo:
            SomaQuestionPrompt(question.text) {
                SomaYesNoPills(
                    yes: String(localized: "Yes"), no: String(localized: "No"),
                    aspect: question.aspect, chosen: chosen.map { $0 == .yes }
                ) { pick($0 ? .yes : .no) }
            }
        case .scale(let low, let high, let tone):
            SomaQuestionPrompt(question.text) {
                SomaScaleOrbs(chosen: chosenStep, low: low, high: high, tone: tone) { pick(.scale($0)) }
            }
        case .number(let range, _, let unit):
            SomaQuestionPrompt(question.text) {
                VStack(spacing: theme.metrics.cardSpacing) {
                    SomaCountStepper(
                        value: $count, in: range, unit: unit,
                        decrementLabel: String(localized: "Less"), incrementLabel: String(localized: "More")
                    )
                    SomaActionButton(String(localized: "Next")) { pick(.number(count)) }
                }
            }
        }
    }

    private var chosenStep: Int? {
        if case .scale(let step) = chosen { return step }
        return nil
    }

    /// Shows the answer, ticks, holds for a beat, then hands it on: no
    /// Continue to press.
    private func pick(_ answer: CheckInAnswer) {
        guard !isHolding else { return }
        isHolding = true
        chosen = answer
        ticks += 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(theme.motion.answerHold))
            presenter.answer(answer)
            isHolding = false
        }
    }

    private static func start(of question: CheckInQuestion?) -> Int {
        if case .number(_, let start, _)? = question?.kind { return start }
        return 0
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

/// Puts "Soma asks" on the shell: the sheet, and the automatic opening once
/// per window when the app becomes active.
///
/// The wait before it asks lets a notification that launched the app say so
/// first, and lets the Today page's read of Health land, which is what the
/// questions the body asks are written from.
private struct CheckInPrompt: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    private let presenter = CheckInPresenter.shared

    /// How long after becoming active the app waits before it asks.
    static let settle: Duration = .seconds(1.5)

    func body(content: Content) -> some View {
        @Bindable var presenter = presenter

        content
            .sheet(item: $presenter.session, onDismiss: { presenter.close() }) { session in
                CheckInSheet(session: session, presenter: presenter)
            }
            .task { presenter.attach(health: health, journal: journal) }
            .task(id: phase) {
                guard phase == .active else { return }
                try? await Task.sleep(for: Self.settle)
                guard !Task.isCancelled, phase == .active else { return }
                presenter.presentAutomatically()
            }
    }
}

extension View {
    /// "Soma asks" on this view: the shell carries it once.
    func checkInPrompt() -> some View {
        modifier(CheckInPrompt())
    }
}
