//
//  MindDaySheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Event category: one day's moments grouped by what they were, each with the
/// way it pulled. Moments come from the day told in words and from the
/// calendar; a calendar moment weighed when stress ran at medium or higher
/// during it. Moving a moment to another category is kept, for every moment
/// with that title, and is what the classifier learns from.
struct MindDaySheet: View {
    let day: Date
    var curve: MindStressDayCurve?
    var mind: Int?

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var events: [MindCalendarEvent] = []
    @State private var adding = ""
    @State private var revision = 0

    private struct Row: Identifiable {
        var id: String
        var title: String
        /// The title a correction is kept under, without the time.
        var key: String
        var category: MindEventCategory
        var pull: MindPull
    }

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let rows = self.rows
        let groups = MindEventCategory.allCases.compactMap { category -> (MindEventCategory, [Row])? in
            let found = rows.filter { $0.category == category }
            return found.isEmpty ? nil : (category, found)
        }

        MindSheetFrame(title: "", closeTitle: "Done") {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 4) {
                MindEyebrow(text: day.formatted(.dateTime.day().month(.wide)) + (mind.map { " · Mind \($0)" } ?? ""))
                Text(day.formatted(.dateTime.weekday(.wide)))
                    .somaFont(type.display)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                MindReasonText(text: summary(rows))
            }

            ForEach(groups, id: \.0) { category, items in
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 2) {
                    MindEyebrow(text: "\(category.title) · \(items.count) \(items.count == 1 ? "moment" : "moments")")
                    SomaCard {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { MindHairline() }
                                Menu {
                                    ForEach(MindEventCategory.selectable, id: \.self) { choice in
                                        Button(choice.title) {
                                            MindStore.shared.correct(row.key, to: choice)
                                            revision += 1
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(row.title)
                                            .somaFont(type.body)
                                            .foregroundStyle(colors.inkPrimary.color)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 8)
                                        Text(row.pull.title)
                                            .somaFont(type.callout)
                                            .foregroundStyle(pullColor(row.pull))
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(colors.inkSecondary.color)
                                            .accessibilityHidden(true)
                                    }
                                    .frame(minHeight: theme.metrics.minimumTapTarget + 8)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Moves it to another category")
                            }
                        }
                    }
                }
            }

            SomaCard {
                HStack {
                    TextField("Add a moment", text: $adding)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .onSubmit(add)
                    if !adding.isEmpty {
                        Button("Add", action: add)
                            .somaFont(type.body)
                            .foregroundStyle(colors.accent.color)
                    }
                }
            }

            Text("Tap a moment to move it to another category. Soma learns from the change.")
                .somaFont(type.caption)
                .foregroundStyle(colors.inkSecondary.color)
        } footer: {
            EmptyView()
        }
        .task {
            let start = Calendar.current.startOfDay(for: day)
            events = await MindCalendar.events(from: start, to: start.addingTimeInterval(24 * 60 * 60))
        }
    }

    private var rows: [Row] {
        _ = revision
        let store = MindStore.shared
        let moments = store.note(on: day)?.moments ?? []
        var rows = moments.map { Row(id: $0.id.uuidString, title: $0.title, key: $0.title, category: store.category(of: $0.title), pull: $0.pull) }
        for event in events where !rows.contains(where: { $0.title.caseInsensitiveCompare(event.title) == .orderedSame }) {
            let category = store.corrections[MindEventClassifier.fingerprint(event.title)]
                ?? MindEventClassifier.category(title: event.title, calendarTitle: event.calendarTitle)
            rows.append(Row(id: event.id, title: event.title + ", " + event.start.formatted(date: .omitted, time: .shortened), key: event.title, category: category, pull: pull(of: event, category: category)))
        }
        return rows
    }

    private func pull(of event: MindCalendarEvent, category: MindEventCategory) -> MindPull {
        guard let curve else { return .none }
        let values = curve.buckets(from: event.start, to: event.end).compactMap(curve.value)
        guard let peak = values.max() else { return .none }
        if peak >= MindStressRadar.elevated { return .weighed }
        return category.points > 0 ? .lifted : .none
    }

    private func pullColor(_ pull: MindPull) -> Color {
        switch pull {
        case .lifted: theme.aspects[.mind].identity.color
        case .weighed: theme.colors.danger.color
        case .none: theme.colors.inkSecondary.color
        }
    }

    private func summary(_ rows: [Row]) -> String {
        let weighed = rows.filter { $0.pull == .weighed }
        let lifted = rows.filter { $0.pull == .lifted }
        if rows.isEmpty {
            return "Nothing on this day yet. Tell your day, or let Mind read your calendar, and its moments land here."
        }
        var parts: [String] = []
        if let first = weighed.first { parts.append("\(first.title) weighed most.") }
        if let first = lifted.first { parts.append("\(first.title) brought you back.") }
        return parts.isEmpty ? "\(rows.count) moments, none with a clear pull." : parts.joined(separator: " ")
    }

    private func add() {
        let title = adding.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let store = MindStore.shared
        var note = store.note(on: day) ?? MindDayNote(day: day, text: "")
        note.moments.append(MindMoment(title: title, category: store.category(of: title), pull: .none))
        store.save(note)
        adding = ""
        revision += 1
    }
}
