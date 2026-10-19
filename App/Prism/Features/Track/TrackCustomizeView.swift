//
//  TrackCustomizeView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Track, Customize: which tags the Journal offers, which questions it asks
/// each day, and what Apple Health hands it without asking.
struct TrackCustomizeView: View {
    @Environment(\.somaTheme) private var theme
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal

    @State private var isAddingTag = false
    @State private var newTag = ""
    @State private var access = TrackHealthAccess()

    private enum TagRow: Identifiable, Hashable {
        case tag(String)
        case add
        var id: String {
            switch self {
            case .tag(let id): id
            case .add: "add"
            }
        }
    }

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
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        ScrollView {
            VStack(alignment: .leading, spacing: metrics.leadSpacing * 0.75) {
                Text("What the journal asks")
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)

                section("Tags") {
                    SomaBrowseGroup(journal.tags.map { TagRow.tag($0.id) } + [.add], hasGlyphs: false) { row in
                        switch row {
                        case .tag(let id): tagRow(id)
                        case .add: addRow
                        }
                    }
                }

                section("Asked each day") {
                    SomaBrowseGroup(Question.allCases, hasGlyphs: false) { question in
                        questionRow(question)
                    }
                    Text("The daily reminder lives in Settings, under Notifications.")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .padding(.horizontal, metrics.browseRowPadding)
                }

                section("From Apple Health") {
                    SomaBrowseGroup(healthRows, hasGlyphs: false) { row in
                        SomaBrowseRow(title: row.title, detail: row.status.text, opensSomething: false)
                    }
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, metrics.cardSpacing)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(colors.canvas.color.ignoresSafeArea())
        .alert("Add a tag", isPresented: $isAddingTag) {
            TextField("Cold shower", text: $newTag)
            Button("Cancel", role: .cancel) { newTag = "" }
            Button("Add") {
                journal.addTag(newTag)
                newTag = ""
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var healthRows: [HealthRow] {
        [
            HealthRow(title: "State of mind", status: access.stateOfMind),
            HealthRow(title: "Mindful minutes", status: access.mindful),
            HealthRow(title: "Medications", status: access.medications),
        ]
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardSpacing * 0.75) {
            TrackEyebrow(title)
                .padding(.leading, theme.metrics.scoreLabelSpacing)
            content()
        }
    }

    // MARK: Rows

    private func tagRow(_ id: String) -> some View {
        let tag = journal.tags.first { $0.id == id }
        return SomaBrowseRow(title: tag?.title ?? id, opensSomething: false) {
            Toggle(tag?.title ?? id, isOn: Binding(
                get: { tag?.isOffered ?? false },
                set: { journal.setOffered($0, tag: id) }
            ))
            .labelsHidden()
            .tint(theme.colors.accent.color)
        }
    }

    private var addRow: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        return Button {
            newTag = ""
            isAddingTag = true
        } label: {
            HStack {
                Text("Add a tag")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(colors.accent.color)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: metrics.browseGlyphSize, weight: .regular))
                    .foregroundStyle(colors.accent.color)
            }
            .padding(.horizontal, metrics.browseRowPadding)
            .padding(.vertical, metrics.browseRowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.browseRowMinHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPressDim)
    }

    private func questionRow(_ question: Question) -> some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let questions = journal.questions

        let title: String
        let isOn: Bool
        switch question {
        case .energy: title = "Energy"; isOn = questions.asksEnergy
        case .stress: title = "Stress"; isOn = questions.asksStress
        }

        return HStack(spacing: metrics.browseRowSpacing) {
            VStack(alignment: .leading, spacing: metrics.scoreLabelSpacing) {
                Text(title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(isOn ? "On" : "Off")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            Spacer(minLength: metrics.browseRowSpacing)
            Toggle(title, isOn: Binding(get: { isOn }, set: { set(question, $0) }))
                .labelsHidden()
                .tint(colors.accent.color)
        }
        .padding(.horizontal, metrics.browseRowPadding)
        .padding(.vertical, metrics.browseRowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.browseRowMinHeight, alignment: .leading)
    }

    private func set(_ question: Question, _ isOn: Bool) {
        switch question {
        case .energy: journal.questions.asksEnergy = isOn
        case .stress: journal.questions.asksStress = isOn
        }
    }

    private func load() async {
        let source = health.reader is EmptyHealthSource ? nil : await health.prepare([])
        access = await TrackHealthAccess.read(from: source, now: .now, calendar: .current)
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
