//
//  TrackMoodView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Daily mood: right now, or the day as a whole.
///
/// Three steps on one sheet, the way Apple's State of Mind asks. First the
/// feeling: the orb is the mood itself, its palette and size following the
/// slider from cool and small to warm and full. Once a feeling is chosen, the
/// words for it (the ones that fit its side of the scale first) and what had a
/// hand in it, each a glyph. Both of those are optional.
///
/// "Today" sets the Journal's feeling for the day, the same seven stops the
/// Journal's card shows. Both are saved to Apple Health as a state of mind
/// (a daily mood or a momentary emotion) and kept in ``TrackLogStore``.
struct TrackMoodView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case now, today
        var id: String { rawValue }
        var title: String { self == .now ? "Right now" : "Today" }
        var question: String { self == .now ? "How are you feeling right now?" : "How has today felt overall?" }
    }

    @Environment(JournalStore.self) private var journal
    @Environment(\.dismiss) private var dismiss

    @State private var scope: Scope
    @State private var valence: Int?
    @State private var words: Set<String>
    @State private var contexts: Set<String>

    private let log = TrackLogStore.shared

    /// The words Apple Health knows, split by the side of the scale they sit
    /// on. The side the feeling is on comes first; the rest wait behind More.
    static let pleasantWords = ["Happy", "Calm", "Content", "Grateful", "Hopeful", "Peaceful", "Excited", "Confident", "Proud"]
    static let unpleasantWords = ["Tired", "Stressed", "Anxious", "Irritated", "Overwhelmed", "Sad", "Lonely"]
    static let neutralWords = ["Calm", "Content", "Tired", "Peaceful", "Stressed", "Hopeful", "Anxious"]

    /// What had a hand in it, with the glyph each one wears.
    static let contextGlyphs: [(title: String, symbol: String)] = [
        ("Work", "briefcase"), ("Family", "house"), ("Fitness", "figure.run"),
        ("Health", "stethoscope"), ("Partner", "heart"), ("Friends", "person.2"),
        ("Money", "creditcard"), ("Weather", "cloud.sun"), ("Self care", "leaf"),
        ("Travel", "airplane"), ("Education", "book"),
    ]
    static let firstContextCount = 6

    init(scope: Scope = .today, valence: Int? = nil, words: Set<String> = [], contexts: Set<String> = []) {
        _scope = State(initialValue: scope)
        _valence = State(initialValue: valence)
        _words = State(initialValue: words)
        _contexts = State(initialValue: contexts)
    }

    /// The words that fit a feeling's side of the scale.
    static func firstWords(for valence: Int?) -> [String] {
        let middle = TrackJournal.feelingLabels.count / 2
        guard let valence else { return neutralWords }
        if valence > middle { return pleasantWords }
        if valence < middle { return unpleasantWords }
        return neutralWords
    }

    var body: some View {
        TrackEntryPage(title: "Mood") {
            TrackMoodForm(scope: scope, valence: $valence, words: $words, contexts: $contexts)
        } footer: {
            SomaActionButton("Log it") { save() }
                .disabled(valence == nil)
        } principal: {
            SomaSegmentedControl(
                segments: Scope.allCases.map { SomaSegment(id: $0, title: LocalizedStringResource(stringLiteral: $0.title)) },
                selection: $scope
            )
        }
        .onAppear {
            if scope == .today, valence == nil { valence = journal.day(.now).feeling }
        }
    }

    private func save() {
        guard let valence else { return }
        let now = Date.now
        let entry = TrackMoodEntry(valence: valence, isDaily: scope == .today, words: words.sorted(), contexts: contexts.sorted(), date: now)
        log.addMood(entry)
        if scope == .today { journal.setFeeling(valence, on: now) }
        let mood = TrackHealthWriter.Mood(valence: Double(valence - 3) / 3, isDaily: entry.isDaily, words: entry.words, contexts: entry.contexts)
        Task { await TrackHealthWriter.saveMood(mood, at: now) }
        dismiss()
    }
}

/// The three steps of the mood sheet, laid out for ``TrackEntryPage``: the
/// feeling, then once one is chosen, the words and what had a hand in it.
struct TrackMoodForm: View {
    let scope: TrackMoodView.Scope
    @Binding var valence: Int?
    @Binding var words: Set<String>
    @Binding var contexts: Set<String>

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var moreWords = false
    @State private var moreContexts = false

    private typealias Lists = TrackMoodView

    var body: some View {
        VStack(spacing: theme.metrics.leadSpacing * 0.75) {
            feeling

            if valence != nil {
                Group {
                    wordStep
                    contextStep
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: theme.metrics.cardSpacing)))
            }
        }
        .animation(reduceMotion ? nil : theme.motion.selection, value: valence == nil)
    }

    // MARK: Step one: the feeling

    private var feeling: some View {
        let metrics = theme.metrics
        let colors = theme.colors

        return VStack(spacing: 0) {
            Text(scope.question)
                .somaFont(theme.typography.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(reduceMotion ? nil : theme.motion.selection, value: scope)

            SomaMoodOrb(value: valence, stops: TrackJournal.feelingLabels.count)
                .padding(.vertical, metrics.cardSpacing)

            SomaValenceSlider(
                value: $valence,
                stops: TrackJournal.feelingLabels.count,
                low: "Very unpleasant",
                high: "Very pleasant",
                names: TrackJournal.feelingLabels,
                prompt: "Slide to choose"
            )
        }
        .padding(.top, metrics.cardSpacing)
        .frame(maxWidth: .infinity)
    }

    // MARK: Step two: the words

    private var wordStep: some View {
        let first = Lists.firstWords(for: valence)
        let rest = (Lists.pleasantWords + Lists.unpleasantWords).filter { !first.contains($0) }
        // A word already chosen stays in view when the feeling crosses sides.
        let shown = moreWords ? first + rest : first + rest.filter(words.contains)
        let tint = SomaMoodScale.aspect(for: valence, stops: TrackJournal.feelingLabels.count)

        return step("Describe it", note: "Pick any that fit.") {
            ForEach(shown, id: \.self) { word in
                SomaChoiceChip(word, isOn: words.contains(word), style: .tinted(tint)) { toggle(word, in: $words) }
            }
            if !moreWords {
                SomaChoiceChip("More", symbol: "ellipsis", style: .tinted(tint)) { moreWords = true }
            }
        }
    }

    // MARK: Step three: what had a hand in it

    private var contextStep: some View {
        let all = Lists.contextGlyphs
        let shown = moreContexts ? all : Array(all.prefix(Lists.firstContextCount)) + all.dropFirst(Lists.firstContextCount).filter { contexts.contains($0.title) }
        let tint = SomaMoodScale.aspect(for: valence, stops: TrackJournal.feelingLabels.count)

        return step("What had a hand in it", note: nil) {
            ForEach(shown, id: \.title) { context in
                SomaChoiceChip(context.title, symbol: context.symbol, isOn: contexts.contains(context.title), style: .tinted(tint)) {
                    toggle(context.title, in: $contexts)
                }
            }
            if !moreContexts {
                SomaChoiceChip("More", symbol: "ellipsis", style: .tinted(tint)) { moreContexts = true }
            }
        }
    }

    // MARK: Parts

    private func step(_ title: String, note: String?, @ViewBuilder chips: () -> some View) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors

        return VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                Spacer(minLength: metrics.cardSpacing)
                if let note {
                    Text(note)
                        .somaFont(theme.typography.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                }
            }
            TrackFlowLayout(spacing: metrics.cardSpacing * 0.75) {
                chips()
            }
        }
        .padding(.top, metrics.cardSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ item: String, in set: Binding<Set<String>>) {
        if set.wrappedValue.contains(item) { set.wrappedValue.remove(item) } else { set.wrappedValue.insert(item) }
    }
}

#if DEBUG
#Preview("Mood") {
    NavigationStack { TrackMoodView() }
        .environment(JournalStore(url: nil))
}

#Preview("Mood, chosen") {
    NavigationStack { TrackMoodView(scope: .now, valence: 5, words: ["Calm", "Grateful"], contexts: ["Family"]) }
        .environment(JournalStore(url: nil))
}
#endif
