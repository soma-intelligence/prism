//
//  AskPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The destination behind the Soma mark at the trailing edge of the tab bar.
///
/// A tab and not a sheet: the mark sits where the tab bar keeps its prominent
/// destination, and a tab that opened a sheet instead of a page would break the
/// one promise a tab bar makes.
///
/// Answers come from ``AskAnswering``, a piece at a time. Until the model is
/// connected the default reports offline, and the page answers the three
/// questions it offers from today's own numbers, the ones the Pulse tab
/// already worked out, saying plainly that anything else waits for the model.
struct AskPage: View {
    /// What writes Soma's replies. Swap in the model client here.
    /// Nil means the model, through `ask-soma`; previews and tests pass the
    /// canned answers.
    var answering: (any AskAnswering)? = nil

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(HealthDashboard.self) private var health
    @Environment(AppRouter.self) private var router

    @State private var turns: [AskTurn] = []
    @State private var draft = ""
    @State private var sheet: AskSheet?
    @State private var path = NavigationPath()
    /// The conversation on screen, as ``AskHistoryStore`` and the account
    /// know it. Nil until the first question of a new one, which picks it.
    @State private var conversationID: UUID?
    @State private var isShowingHistory = false
    @State private var isShowingSettings = false
    @State private var history = AskHistoryStore.shared
    @State private var statuses = ActivityStatusStore.shared
    @State private var profile = SomaProfileStore.shared
    /// The reply being written, cancelled by the stop button.
    @State private var streaming: Task<Void, Never>?
    /// Ask's model settings, opened from a failure that is fixed there.
    @State private var isShowingModels = false
    @State private var providers = AskProviderSettings.shared
    @FocusState private var isFieldFocused: Bool

    private var isStreaming: Bool { streaming != nil }

    private var facts: AskFacts {
        AskFacts(today: health.today, variability: health.value(AskFacts.variabilityMetric), status: statuses.current)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            stack

            if isShowingHistory {
                theme.colors.canvas.color.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture { setHistory(false) }
                    .accessibilityLabel("Close history")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)

                AskHistoryDrawer(
                    current: conversationID,
                    open: { id in
                        restore(id)
                        setHistory(false)
                    },
                    startNew: {
                        startNew()
                        setHistory(false)
                    },
                    openRecords: {
                        setHistory(false)
                        path.append(GlobalRoute.healthRecords)
                    },
                    openSettings: {
                        setHistory(false)
                        isShowingSettings = true
                    }
                )
                .frame(maxWidth: theme.metrics.sidebarIdealWidth * 1.3)
                .transition(reduceMotion ? .opacity : .move(edge: .leading))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsSheet() }
        .sheet(isPresented: $isShowingModels) {
            NavigationStack { AskModelPage() }
                .presentationDetents([.large])
        }
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { reader in
                SomaPageScroll {
                    Group {
                        if turns.isEmpty {
                            AskReadyView(name: profile.profile.firstName, suggestions: Ask.suggestions(facts), send: send)
                        } else {
                            AskConversationView(turns: turns, send: send, retry: answer, start: { sheet = .move }, openModels: { isShowingModels = true })
                        }
                    }
                    .padding(.horizontal, theme.metrics.pagePadding * 1.25)
                    .padding(.bottom, theme.metrics.leadSpacing)
                    .somaReadableWidth()

                    Color.clear.frame(height: 1).id(AskPage.bottom)
                }
                .softScrollEdges()
#if !os(visionOS)
                // The headset's keyboard floats apart from the window.
                .scrollDismissesKeyboard(.interactively)
#endif
                .onChange(of: turns.count) {
                    withAnimation(reduceMotion ? nil : theme.motion.selection) { reader.scrollTo(AskPage.bottom, anchor: .bottom) }
                }
                // The reply grows a piece at a time; the page follows it.
                .onChange(of: turns.last?.answer.lead) {
                    reader.scrollTo(AskPage.bottom, anchor: .bottom)
                }
            }
            .background(theme.colors.canvas.color.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { composer }
            .journeyDestinations()
            .tabPageChrome(title: "Ask Soma")
            .toolbar {
                // The mark, small, in place of the bar's title: the title
                // still names the window on a Mac and the page to VoiceOver.
                ToolbarItem(placement: .principal) {
                    SomaMark(accessibilityLabel: "Ask Soma")
                        .scaleEffect(0.8)
                }
#if !os(visionOS)
                // Liquid Glass only: visionOS has no shared background to hide.
                .sharedBackgroundVisibility(.hidden)
#endif
                ToolbarItem(placement: .navigation) {
                    Button { setHistory(true) } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(theme.colors.inkPrimary.color)
                    }
                    .accessibilityLabel("Conversations")
                }
                if !turns.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: startNew) {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(theme.colors.inkPrimary.color)
                        }
                        .accessibilityLabel("New chat")
                    }
                }
            }
            .task { await health.loadToday() }
            .sheet(item: $sheet) { sheet in
                if sheet == .attach {
                    AskLogHub { choose($0) }
                } else {
                    sheet.page
                }
            }
        }
    }

    private static let bottom = "ask.bottom"

    private func setHistory(_ isShowing: Bool) {
        withAnimation(reduceMotion ? nil : theme.motion.selection) { isShowingHistory = isShowing }
    }

    private func send(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        let turn = AskTurn(question: trimmed, answer: .streamed("", followUps: []), phase: .waiting)
        if conversationID == nil { conversationID = UUID() }
        turns.append(turn)
        draft = ""
        answer(turn.id)
    }

    /// Writes Soma's side of the turn `id`: the stream's pieces as they land,
    /// the phone's own answer when the stream reports offline before its first
    /// piece, or an error under the question with a way to try again. The turn
    /// joins the history once it is answered.
    /// The model through `ask-soma`, fed the scores the dashboard holds; the
    /// canned answers when the page was given them.
    private var resolvedAnswering: any AskAnswering {
        if let answering { return answering }
        let scores = health.scores
        let profile = SomaProfileStore.shared.profile
        let context: @MainActor @Sendable () -> AskContext = { AskContextBuilder.make(scores: scores, insights: [], profile: profile) }
        let provider = providers.effective
        switch provider {
        case .appleIntelligence:
            return AppleIntelligenceAnswering(context: context)
        case .soma:
            return ModelAskAnswering(context: context)
        default:
            guard let key = providers.key(for: provider) else { return FailingAskAnswering(failure: .missingKey(provider)) }
            if let missing = providers.missing(for: provider) {
                return FailingAskAnswering(failure: AskFailure(kind: .missingKey, title: missing,
                                                               detail: "Finish \(provider.title) in Ask\u{2019}s settings.", opensSettings: true))
            }
            return RemoteAskAnswering(provider: provider, key: key, model: providers.model(for: provider),
                                      endpoint: providers.endpoint(for: provider), context: context)
        }
    }

    private func answer(_ id: UUID) {
        guard !isStreaming, let index = turns.firstIndex(where: { $0.id == id }) else { return }
        let question = turns[index].question
        let facts = self.facts
        let followUps = Ask.suggestions(facts).filter { Ask.normalized($0.question) != Ask.normalized(question) }
        let messages = turns[..<index].flatMap { turn in
            [AskMessage(role: .user, text: turn.question), AskMessage(role: .assistant, text: turn.answer.plainText)]
        } + [AskMessage(role: .user, text: question)]
        let conversation = conversationID ?? UUID()
        conversationID = conversation
        let stream = resolvedAnswering.stream(messages: messages, facts: facts, thread: AskThread(conversation: conversation, turn: id))

        update(id) { $0.phase = .waiting; $0.answer = .streamed("", followUps: []) }
        streaming = Task {
            var text = ""
            do {
                for try await piece in stream {
                    text += piece
                    update(id) { $0.phase = .streaming; $0.answer = .streamed(text, followUps: []) }
                }
                finish(id, text: text, followUps: followUps)
            } catch AskAnsweringError.offline where text.isEmpty {
                update(id) { $0.phase = .done; $0.answer = Ask.answer(to: question, facts: facts) }
                keep(id)
            } catch {
                if Task.isCancelled {
                    finish(id, text: text, followUps: followUps)
                } else {
                    let failure = error as? AskFailure
                    update(id) { $0.phase = .failed; $0.failure = failure }
                }
            }
            streaming = nil
        }
    }

    /// Settles a streamed reply, kept as far as it got when it was stopped.
    private func finish(_ id: UUID, text: String, followUps: [AskSuggestion]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            update(id) { $0.phase = .stopped }
            return
        }
        update(id) { $0.phase = .done; $0.answer = .streamed(trimmed, followUps: followUps) }
        keep(id)
    }

    private func update(_ id: UUID, _ change: (inout AskTurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    /// Adds an answered turn to the history. A turn cleared off the page while
    /// it was being answered is not kept.
    private func keep(_ id: UUID) {
        guard let turn = turns.first(where: { $0.id == id }) else { return }
        conversationID = history.append(turn.stored(at: Date()), to: conversationID)
    }

    private func stop() {
        streaming?.cancel()
    }

    private func startNew() {
        stop()
        streaming = nil
        turns.removeAll()
        conversationID = nil
        draft = ""
    }

    /// Puts a kept conversation back on screen, as it was answered then.
    private func restore(_ id: UUID) {
        guard let conversation = history.conversation(id) else { return }
        stop()
        streaming = nil
        turns = conversation.turns.map(AskTurn.init(stored:))
        conversationID = id
        draft = ""
    }

    /// Where a log hub tile goes: logging lives in Track, records open here.
    private func choose(_ shortcut: LogShortcut) {
        switch shortcut {
        case .record:
            path.append(GlobalRoute.healthRecords)
        default:
            router.selection = "track"
        }
    }

    /// One glass capsule over the page's foot: the plus that opens the log
    /// hub, the field, and a trailing button that is the microphone while the
    /// field is empty, send once there is something to send, and stop while
    /// Soma is answering.
    private var composer: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let hasDraft = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let disc = metrics.iconButtonDiameter * 0.75

        return HStack(spacing: metrics.spaceS) {
            Button { sheet = .attach } label: {
                Image(systemName: "plus")
                    .font(.system(size: metrics.browseGlyphSize, weight: .regular))
                    .foregroundStyle(colors.inkSecondary.color)
                    .frame(width: disc, height: disc)
                    .contentShape(.circle)
            }
            .buttonStyle(.somaGlassPress)
            .accessibilityLabel("Log something")

            TextField(turns.isEmpty ? "Ask Soma anything" : "Ask a follow-up", text: $draft)
                .textFieldStyle(.plain)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
                .focused($isFieldFocused)
                .submitLabel(.send)
                .onSubmit { if !isStreaming { send(draft) } }

            Group {
                if isStreaming {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: metrics.browseGlyphSize * 0.6, weight: .semibold))
                            .foregroundStyle(colors.onAccent.color)
                            .frame(width: disc, height: disc)
                            .background(Circle().fill(colors.accent.color))
                            .contentShape(.circle)
                    }
                    .accessibilityLabel("Stop answering")
                    .transition(.opacity)
                } else if hasDraft {
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: metrics.browseGlyphSize * 0.8, weight: .semibold))
                            .foregroundStyle(colors.onAccent.color)
                            .frame(width: disc, height: disc)
                            .background(Circle().fill(colors.accent.color))
                            .contentShape(.circle)
                    }
                    .accessibilityLabel("Send")
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else {
                    Button { sheet = .voice } label: {
                        Image(systemName: "mic")
                            .font(.system(size: metrics.browseGlyphSize * 0.9, weight: .regular))
                            .foregroundStyle(colors.inkSecondary.color)
                            .frame(width: disc, height: disc)
                            .contentShape(.circle)
                    }
                    .accessibilityLabel("Speak")
                    .transition(.opacity)
                }
            }
            .buttonStyle(.somaGlassPress)
        }
        .animation(reduceMotion ? nil : theme.motion.selection, value: hasDraft)
        .animation(reduceMotion ? nil : theme.motion.selection, value: isStreaming)
        .padding(.horizontal, metrics.spaceXS)
        .frame(minHeight: metrics.iconButtonDiameter + metrics.spaceS)
        .somaGlass(.regular, in: .capsule)
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, metrics.cardSpacing)
        // As wide as the conversation over it, not the window.
        .somaReadableWidth()
    }
}

/// One question and Soma's answer.
struct AskTurn: Identifiable, Equatable {
    /// Where Soma's side of the turn is.
    enum Phase: Equatable {
        /// Asked, nothing back yet.
        case waiting
        /// Pieces are landing.
        case streaming
        case done
        /// Stopped before the first piece.
        case stopped
        /// The answer failed; it can be asked again.
        case failed
    }

    /// The turn's id: the one the account stores its two messages under.
    let id: UUID
    var question: String
    var answer: AskAnswer
    var phase: Phase = .done
    /// Why the answer failed, worded for the person, when the phase is failed.
    var failure: AskFailure?

    init(id: UUID = UUID(), question: String, answer: AskAnswer, phase: Phase = .done) {
        self.id = id
        self.question = question
        self.answer = answer
        self.phase = phase
    }
}

extension AskTurn {
    /// The turn as the history keeps it.
    func stored(at date: Date) -> StoredAskTurn {
        StoredAskTurn(
            id: id, question: question, asked: date, lead: answer.lead, rest: answer.rest,
            signals: answer.signals, sources: answer.sources,
            moveTitle: answer.move?.title, moveReason: answer.move?.reason, moveAspect: answer.move?.aspect.rawValue,
            isModelMissing: answer.isModelMissing
        )
    }

    /// A kept turn, answered as it was on the day. It offers no follow-ups:
    /// they were built from that day's numbers.
    init(stored: StoredAskTurn) {
        let move: AskMove? = stored.moveTitle.map { title in
            AskMove(aspect: stored.moveAspect.flatMap(SomaAspect.init(rawValue:)) ?? .body,
                    title: title, reason: stored.moveReason ?? "")
        }
        self.init(id: stored.id, question: stored.question, answer: AskAnswer(
            lead: stored.lead, rest: stored.rest, signals: stored.signals, sources: stored.sources,
            move: move, followUps: [], isModelMissing: stored.isModelMissing
        ))
    }
}

/// What the page can open over itself. The plus opens the log hub; voice and
/// the guided session are not wired yet.
private enum AskSheet: String, Identifiable {
    case attach, voice, move

    var id: String { rawValue }

    @ViewBuilder
    var page: some View {
        switch self {
        case .attach:
            NotWiredPage(
                eyebrow: "Ask",
                title: "Add to your question",
                message: "Photos of a meal or a label will go with a question here. Nothing is connected yet."
            )
        case .voice:
            NotWiredPage(
                eyebrow: "Ask",
                title: "Talk to Soma",
                message: "Asking out loud comes with the conversation model. Until then, type or tap a question from today."
            )
        case .move:
            NotWiredPage(
                eyebrow: "Try this",
                title: "Guided sessions",
                message: "The guided session opens here once it is built. Today\u{2019}s move is still on the Pulse tab."
            )
        }
    }
}

// MARK: - Ready

/// The page before the first question: a greeting, one line, and at most
/// three questions built from today's numbers.
struct AskReadyView: View {
    let name: String?
    let suggestions: [AskSuggestion]
    let send: (String) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: metrics.leadSpacing * 1.5) {
            VStack(alignment: .leading, spacing: metrics.spaceXS) {
                Text(name.map { "Hi \($0)" } ?? String(localized: "Ask Soma"))
                    .somaFont(type.title)
                    .foregroundStyle(colors.inkPrimary.color)
                Text("Answers quote your Apple Health readings and say where each number comes from.")
                    .somaFont(type.callout)
                    .foregroundStyle(colors.inkSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: metrics.spaceS) {
                ForEach(suggestions.prefix(3)) { suggestion in
                    AskChip(title: suggestion.question) { send(suggestion.question) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, metrics.leadSpacing)
    }
}

/// A question to tap: ink on a hairline capsule, so the accent stays with
/// the send button.
private struct AskChip: View {
    let title: String
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        Button(action: action) {
            Text(title)
                .somaFont(theme.typography.callout)
                .foregroundStyle(colors.inkPrimary.color)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, metrics.cardPadding)
                .padding(.vertical, metrics.spaceS)
                .frame(minHeight: metrics.minimumTapTarget)
                .overlay(
                    Capsule().strokeBorder(
                        colors.inkPrimary.color.opacity(metrics.browseSeparatorOpacity),
                        lineWidth: 1
                    )
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.somaGlassPress)
    }
}

// MARK: - Answering

struct AskConversationView: View {
    let turns: [AskTurn]
    let send: (String) -> Void
    var retry: (UUID) -> Void = { _ in }
    let start: () -> Void
    var openModels: () -> Void = {}

    @Environment(\.somaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.leadSpacing * 1.5) {
            ForEach(turns) { turn in
                AskTurnView(turn: turn, isLast: turn.id == turns.last?.id, send: send, retry: { retry(turn.id) }, start: start,
                            openModels: openModels)
            }
        }
        .padding(.top, theme.metrics.leadSpacing)
    }
}

/// One turn: the question in a bubble on the trailing edge, the answer as
/// plain text on the ground, and under the last one the questions left.
private struct AskTurnView: View {
    let turn: AskTurn
    let isLast: Bool
    let send: (String) -> Void
    let retry: () -> Void
    let start: () -> Void
    var openModels: () -> Void = {}

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let answer = turn.answer
        let isSettled = turn.phase == .done

        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            HStack {
                Spacer(minLength: metrics.leadSpacing * 2)
                Text(turn.question)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .padding(.horizontal, metrics.cardPadding)
                    .padding(.vertical, metrics.spaceS)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.cardCornerRadius * 1.4, style: .continuous)
                            .fill(colors.surfaceRecessed.color)
                    )
            }

            switch turn.phase {
            case .waiting:
                AskTypingIndicator()
            case .stopped:
                Text("Stopped")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            case .failed:
                // What happened, then what to do, then the one action that
                // fixes it: never a code (owner, 2026-10-24).
                VStack(alignment: .leading, spacing: metrics.spaceXS) {
                    Text(turn.failure?.title ?? "Soma couldn\u{2019}t answer")
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkPrimary.color)
                    Text(turn.failure?.detail ?? "Try again in a moment.")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: metrics.cardSpacing) {
                        if turn.failure?.opensSettings == true {
                            Button("Choose a model", action: openModels)
                                .somaFont(type.caption)
                                .foregroundStyle(colors.inkPrimary.color)
                                .padding(.horizontal, metrics.spaceM)
                                .padding(.vertical, metrics.spaceS - 2)
                                .background(Capsule().fill(.fill.quaternary))
                                .buttonStyle(.somaGlassPress)
                                .frame(minHeight: metrics.minimumTapTarget)
                        }
                        Button("Try again", action: retry)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .buttonStyle(.somaGlassPress)
                            .frame(minHeight: metrics.minimumTapTarget)
                            .contentShape(.rect)
                    }
                }
                .padding(metrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
            case .streaming, .done:
                answerText(answer)
            }

            if isSettled && isLast && !answer.followUps.isEmpty {
                VStack(alignment: .leading, spacing: metrics.spaceS) {
                    ForEach(answer.followUps.prefix(3)) { suggestion in
                        AskChip(title: suggestion.question) { send(suggestion.question) }
                    }
                }
            }
        }
    }

    private func answerText(_ answer: AskAnswer) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        return VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                TrackLeadText(lead: answer.lead, rest: answer.rest)

                if let move = answer.move {
                    Button(action: start) {
                        HStack(spacing: metrics.spaceS) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: metrics.browseGlyphSize, weight: .regular))
                                .foregroundStyle(colors.accent.color)
                            Text(move.title)
                                .somaFont(type.callout)
                                .foregroundStyle(colors.inkPrimary.color)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(minHeight: metrics.minimumTapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.somaGlassPress)
                    .accessibilityLabel("Try this: \(move.title)")
                    .accessibilityHint(move.reason)
                }

                if let line = answer.sourceLine {
                    Text(line)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
    }
}

/// Three dots before the first piece of a reply lands. They breathe in turn;
/// with Reduce Motion they hold still at half ink.
private struct AskTypingIndicator: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = true

    var body: some View {
        let metrics = theme.metrics
        let dot = metrics.scoreLabelSpacing * 3.5
        let ink = theme.colors.inkSecondary.color

        // Thirty frames a second is plenty for an opacity that takes a whole
        // beat to swell; the display's full rate redrew the row for nothing.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isOnScreen)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: dot * 0.75) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(ink)
                        .frame(width: dot, height: dot)
                        .opacity(reduceMotion ? 0.5 : 0.3 + 0.7 * pulse(time, index))
                }
            }
        }
        .frame(minHeight: metrics.minimumTapTarget * 0.6, alignment: .leading)
        .somaOnScreen($isOnScreen)
        .accessibilityElement()
        .accessibilityLabel("Soma is answering")
    }

    /// 0 to 1 and back, each dot a third of a beat behind the one before. A
    /// beat is half a breath.
    private func pulse(_ time: TimeInterval, _ index: Int) -> Double {
        let beat = theme.motion.breathDuration / 2
        let phase = (time / beat - Double(index) / 3).truncatingRemainder(dividingBy: 1)
        return 0.5 - 0.5 * cos(phase * 2 * .pi)
    }
}

#Preview("Ask") {
    AskPage(answering: CannedAskAnswering())
        .environment(HealthDashboard())
        .environment(AppRouter())
        .environment(JournalStore(url: nil))
}
