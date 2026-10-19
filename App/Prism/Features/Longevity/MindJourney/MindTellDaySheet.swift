//
//  MindTellDaySheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Tell your day: the day in a person's own words, and what Soma picks out of
/// them on the phone (people, places, and moments that lifted or weighed).
///
/// Written only for now: voice waits on its own consent and is listed as not
/// there yet on the consent screen. The words are read for distress before
/// they are kept.
struct MindTellDaySheet: View {
    var day = Date()

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var picked: MindDayNote?
    @State private var distress: MindDistress?

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let note = picked ?? MindDayNote(day: day, text: text)

        MindSheetFrame(title: "Tell your day") {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 4) {
                MindEyebrow(text: day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                MindReasonText(text: "Write it down. Soma picks out the people, the places and the moments, on this phone, and tomorrow’s questions start from there.")
            }

            SomaCard {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("How did today go? Who did you see, and where?")
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkSecondary.color)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $text)
                        .somaFont(type.body)
                        .foregroundStyle(colors.inkPrimary.color)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: theme.metrics.minimumTapTarget * 3)
                        .accessibilityLabel("Your day")
                }
            }

            if !note.people.isEmpty || !note.places.isEmpty || !note.moments.isEmpty {
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 6) {
                    MindEyebrow(text: "Soma picked out")
                    group("People", note.people.map { ($0, MindPull.none) })
                    group("Places", note.places.map { ($0, MindPull.none) })
                    group("Moments", note.moments.map { ($0.title, $0.pull) })
                }
            }
        } footer: {
            MindWideButton(title: "Save to your day", isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { save() }
        }
        .onAppear {
            if let kept = MindStore.shared.note(on: day) {
                text = kept.text
                picked = kept
            }
        }
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            picked = MindDayReader.read(text, day: day, store: MindStore.shared)
        }
        .sheet(item: $distress, onDismiss: { dismiss() }) { MindCrisisSheet(distress: $0) }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [(String, MindPull)]) -> some View {
        if !items.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: theme.metrics.moveRowGap) {
                Text(title)
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .frame(width: theme.metrics.aspectChartWidth * 0.7, alignment: .leading)
                MindChipFlow().callAsFunction {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        MindPullChip(title: item.0, pull: item.1)
                    }
                }
            }
        }
    }

    private func save() {
        let note = MindDayReader.read(text, day: day, store: MindStore.shared)
        MindStore.shared.save(note)
        let level = MindSafetyGuard.check(valence: nil, labels: [], text: text)
        if level > .none { distress = level } else { dismiss() }
    }
}

/// A picked out word, with a dot for which way it pulled.
struct MindPullChip: View {
    let title: String
    let pull: MindPull

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        HStack(spacing: 6) {
            if pull != .none {
                Circle()
                    .fill(pull == .lifted ? theme.aspects[.mind].identity.color : colors.danger.color)
                    .frame(width: theme.metrics.identityDotDiameter, height: theme.metrics.identityDotDiameter)
            }
            Text(title)
                .somaFont(theme.typography.body)
                .foregroundStyle(colors.inkPrimary.color)
        }
        .padding(.horizontal, theme.metrics.cardPadding - 4)
        .frame(minHeight: theme.metrics.minimumTapTarget - 8)
        .background(Capsule().fill(colors.surface.color))
        .accessibilityElement(children: .combine)
        .accessibilityValue(pull == .none ? "" : pull.title)
    }
}
