//
//  TrackCustomizeView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Track, Customize: one list for everything Track lets a person arrange.
///
/// The quick add tiles on the Journal, in order, with the ones left off below
/// them; the steps of the morning and evening rituals; the questions the
/// Journal asks; and what Apple Health hands it without asking. Things on the
/// Journal or in a ritual carry a handle to drag and a minus to take them
/// off; things that can be added carry a plus. Every change is saved at once.
struct TrackCustomizeView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var isAddingTag = false
    @State private var newTag = ""
    @State private var addingStep: TrackRitualMoment?
    @State private var access = TrackHealthAccess()

    private let layout = TrackQuickAddLayout.shared
    private let rituals = TrackRitualStore.shared

    /// The daily "how did today feel" reminder is not here: Settings,
    /// Notifications owns it (the Journal row), so there is one switch.
    private enum Question: String, Identifiable, CaseIterable {
        case energy, stress
        var id: String { rawValue }
    }

    private struct HealthRow: Identifiable {
        var id: String { title }
        var title: String
        var status: TrackHealthAccess.Status
    }

    var body: some View {
        let colors = theme.colors

        List {
            Section {
                ForEach(layout.shown) { tile in
                    itemRow(tile.title, glyph: tile.glyph, tone: tile.tone, control: .remove) {
                        withAnimation(theme.motion.selection) { layout.hide(tile) }
                    }
                }
                .onMove { layout.move(from: $0, to: $1) }
            } header: {
                header("Quick add", detail: "On the Journal, in this order")
            }

            if !layout.hidden.isEmpty {
                Section {
                    ForEach(layout.hidden) { tile in
                        itemRow(tile.title, glyph: tile.glyph, tone: tile.tone, control: .add) {
                            withAnimation(theme.motion.selection) { layout.show(tile) }
                        }
                    }
                } header: {
                    header("More to add", detail: nil)
                }
            }

            ForEach(TrackRitualMoment.allCases) { moment in
                Section {
                    ForEach(rituals.ritual(moment).steps) { step in
                        itemRow(step.title, glyph: step.kind, tone: moment.tone, control: .remove) {
                            withAnimation(theme.motion.selection) { rituals.removeStep(step.id, from: moment) }
                        }
                    }
                    .onMove { rituals.moveSteps(in: moment, from: $0, to: $1) }
                    addRow("Add a step") { addingStep = moment }
                        .moveDisabled(true)
                } header: {
                    header("\(moment.title) ritual", detail: nil)
                }
            }

            Section {
                ForEach(journal.tags) { tag in
                    tagRow(tag)
                }
                addRow("Add a question") {
                    newTag = ""
                    isAddingTag = true
                }
            } header: {
                header("Journal questions", detail: "Done or not, each day")
            }

            Section {
                ForEach(Question.allCases) { question in
                    questionRow(question)
                }
            } header: {
                header("Asked each day", detail: nil)
            } footer: {
                Text("The daily reminder lives in Settings, under Notifications.")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }

            Section {
                ForEach(healthRows) { row in
                    HStack {
                        Text(row.title)
                            .somaFont(theme.typography.body)
                            .foregroundStyle(colors.inkPrimary.color)
                        Spacer()
                        Text(row.status.text)
                            .somaFont(theme.typography.rowValue)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .listRowBackground(colors.surface.color)
                }
            } header: {
                header("From Apple Health", detail: nil)
            }
        }
        .modifier(TrackCustomizeListStyle())
        .scrollContentBackground(.hidden)
        .background(colors.canvas.color.ignoresSafeArea())
        .alert("Add a question", isPresented: $isAddingTag) {
            TextField("Cold shower", text: $newTag)
            Button("Cancel", role: .cancel) { newTag = "" }
            Button("Add") {
                journal.addTag(newTag)
                newTag = ""
            }
        }
        .sheet(item: $addingStep) { moment in
            TrackRitualStepSheet(moment: moment) { title, glyph in
                rituals.addStep(title, glyph: glyph, to: moment)
            }
        }
        .task { await load() }
        .somaRefreshable { await load() }
    }

    private var healthRows: [HealthRow] {
        [
            HealthRow(title: "State of mind", status: access.stateOfMind),
            HealthRow(title: "Mindful minutes", status: access.mindful),
            HealthRow(title: "Medications", status: access.medications),
        ]
    }

    // MARK: Rows

    private enum Control { case add, remove }

    /// A section's heading: its name, and a few grey words on what it holds.
    private func header(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            TrackEyebrow(title)
            Spacer()
            if let detail {
                Text(detail)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .textCase(nil)
            }
        }
    }

    /// One tile or step: a plus or a minus, its glyph and its name.
    private func itemRow(_ title: String, glyph: SomaTrackGlyph.Kind, tone: SomaTrackTone,
                         control: Control, action: @escaping () -> Void) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return HStack(spacing: metrics.browseRowSpacing) {
            Button(action: action) {
                Image(systemName: control == .add ? "plus" : "minus")
                    .font(.system(size: metrics.trackAnswerGlyph, weight: .bold))
                    .foregroundStyle(colors.surface.color)
                    .frame(width: metrics.journalMarkDiameter * 0.8, height: metrics.journalMarkDiameter * 0.8)
                    .background(Circle().fill(control == .add ? SomaTrackTone.sage.color : SomaTrackTone.clay.color))
                    .frame(width: metrics.minimumTapTarget, height: metrics.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.somaGlassPress)
            .padding(.leading, -metrics.scoreLabelSpacing * 2)
            .accessibilityLabel(Text(control == .add ? "Add \(title)" : "Remove \(title)"))
            SomaTrackGlyph(glyph, tone: tone, style: .row)
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
                .lineLimit(1)
        }
        .listRowBackground(colors.surface.color)
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return Button(action: action) {
            HStack(spacing: metrics.browseRowSpacing) {
                SomaTrackGlyph(.less, tone: nil, style: .row)
                    .hidden()
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: metrics.browseGlyphSize * 0.8, weight: .medium))
                            .foregroundStyle(colors.inkPrimary.color)
                            .accessibilityHidden(true)
                    }
                Text(title)
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
        .listRowBackground(colors.surface.color)
    }

    private func tagRow(_ tag: JournalTag) -> some View {
        let style = TrackTagStyle.of(tag.id)
        return HStack(spacing: theme.metrics.browseRowSpacing) {
            SomaTrackGlyph(style.glyph, tone: style.tone, style: .row)
                .opacity(tag.isOffered ? 1 : 0.5)
            Toggle(tag.title, isOn: Binding(
                get: { tag.isOffered },
                set: { journal.setOffered($0, tag: tag.id) }
            ))
            .somaFont(theme.typography.body)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .toggleStyle(.soma)
        }
        .listRowBackground(theme.colors.surface.color)
    }

    private func questionRow(_ question: Question) -> some View {
        let questions = journal.questions
        let title: String
        let isOn: Bool
        switch question {
        case .energy: title = "Energy"; isOn = questions.asksEnergy
        case .stress: title = "Stress"; isOn = questions.asksStress
        }
        return Toggle(title, isOn: Binding(get: { isOn }, set: { set(question, $0) }))
            .somaFont(theme.typography.body)
            .foregroundStyle(theme.colors.inkPrimary.color)
            .toggleStyle(.soma)
            .listRowBackground(theme.colors.surface.color)
    }

    private func set(_ question: Question, _ isOn: Bool) {
        switch question {
        case .energy: journal.questions.asksEnergy = isOn
        case .stress: journal.questions.asksStress = isOn
        }
    }

    private func load() async {
        let source = health.readsEmptyStore ? nil : await health.prepare([])
        access = await TrackHealthAccess.read(from: source, now: .now, calendar: .current)
    }
}

/// The list's look on each platform: grouped cards with drag handles always
/// showing on a phone or a headset, the plain inset list on a Mac, where a
/// row is dragged by the pointer.
private struct TrackCustomizeListStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS) || os(visionOS)
        content
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
#else
        content.listStyle(.inset)
#endif
    }
}

// MARK: - Add a step

/// A new ritual step: a name and a glyph from the Track set, then Add.
struct TrackRitualStepSheet: View {
    let moment: TrackRitualMoment
    let add: (String, SomaTrackGlyph.Kind) -> Void

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var glyph: SomaTrackGlyph.Kind = .tag
    @FocusState private var focused: Bool

    var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let tone = moment.tone
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        NavigationStack {
            SomaPageScroll {
                VStack(alignment: .leading, spacing: metrics.leadSpacing * 0.75) {
                    HStack(spacing: metrics.browseRowSpacing) {
                        SomaTrackGlyph(glyph, tone: tone, style: .badge)
                        TextField("Stretch for five minutes", text: $title)
                            .somaFont(theme.typography.body)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { commit(trimmed) }
                    }
                    .padding(metrics.cardPadding)
                    .background(RoundedRectangle(cornerRadius: metrics.cardCornerRadius, style: .continuous).fill(colors.surface.color))

                    TrackEyebrow("Glyph")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: metrics.journalTileSpacing), count: 6),
                              spacing: metrics.journalTileSpacing) {
                        ForEach(TrackRitualStore.stepGlyphs) { kind in
                            Button {
                                glyph = kind
                            } label: {
                                SomaTrackGlyph(kind, tone: tone, style: .badge)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: metrics.aspectBadgeCornerRadius + 3, style: .continuous)
                                            .strokeBorder(colors.inkPrimary.color, lineWidth: 1.5)
                                            .padding(-3)
                                            .opacity(glyph == kind ? 1 : 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.somaGlassPress)
                            .accessibilityLabel(Text(kind.rawValue))
                            .accessibilityAddTraits(glyph == kind ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: glyph)
                }
                .padding(metrics.pagePadding)
            }
            .background(colors.canvas.color.ignoresSafeArea())
            .navigationTitle("\(moment.title) step")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commit(trimmed) }
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }

    private func commit(_ trimmed: String) {
        guard !trimmed.isEmpty else { return }
        add(trimmed, glyph)
        dismiss()
    }
}

#if DEBUG
#Preview("Customize") {
    NavigationStack {
        TrackCustomizeView()
    }
    .environment(HealthDashboard())
    .environment(JournalStore(url: nil))
}
#endif
