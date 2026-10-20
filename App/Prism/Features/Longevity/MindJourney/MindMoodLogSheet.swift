//
//  MindMoodLogSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The quick mood log, opened from a face on the Mind lens's mood card: the
/// face you tapped, large, with its word; the five faces to change it; a few
/// words to name it and a note, both optional; one button to log it.
///
/// Kept on the phone in `MindStore` as a feeling right now, and written to
/// Apple Health as a State of Mind when the consent allowed it, as the full
/// log does. A heavy entry opens the safety sheet before the log closes.
struct MindMoodLogSheet: View {
    let start: SomaMood

    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mood: SomaMood?
    @State private var labels: [String] = []
    @State private var note = ""
    @State private var distress: MindDistress?
    @FocusState private var isWriting: Bool

    private var store: MindStore { MindStore.shared }

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let chosen = mood ?? start
        let valence = MindMoodEntry.valence(stop: MindQuickMood.stop(chosen))

        MindSheetFrame(title: "Mood") {
            VStack(spacing: metrics.cardSpacing) {
                SomaMoodFace(chosen, isFilled: true, side: metrics.moodLogFaceSide)
                    .id(chosen)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                Text(chosen.title)
                    .somaFont(type.headline)
                    .foregroundStyle(colors.inkPrimary.color)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, metrics.cardSpacing)
            .animation(reduceMotion ? nil : theme.motion.selection, value: chosen)
            .accessibilityElement(children: .combine)

            SomaMoodFaces(selection: $mood)

            VStack(alignment: .leading, spacing: metrics.moodLogPromptSpacing) {
                Text("A word for it, if you like")
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
                MindChipFlow().callAsFunction {
                    ForEach(MindFeeling.offered(for: valence)) { feeling in
                        MindChip(title: feeling.title, isSelected: labels.contains(feeling.id)) {
                            if let index = labels.firstIndex(of: feeling.id) { labels.remove(at: index) } else { labels.append(feeling.id) }
                        }
                    }
                }
            }

            TextField("Add a note", text: $note, axis: .vertical)
                .somaFont(type.body)
                .lineLimit(1...4)
                .focused($isWriting)
                .padding(.horizontal, metrics.noteFieldHorizontalInset)
                .padding(.vertical, metrics.noteFieldVerticalInset)
                .background(colors.surface.color, in: .rect(cornerRadius: metrics.cardCornerRadius, style: .continuous))
        } footer: {
            MindWideButton(title: "Log mood", isEnabled: !isLogged) { log(chosen) }
        }
        .onAppear { mood = start }
        .sensoryFeedback(.success, trigger: isLogged)
        .sheet(item: $distress, onDismiss: { dismiss() }) { level in
            MindCrisisSheet(distress: level)
        }
    }

    @State private var isLogged = false

    private func log(_ chosen: SomaMood) {
        // A fast second tap lands before the sheet closes: one log a sheet.
        guard !isLogged else { return }
        let stop = MindQuickMood.stop(chosen)
        let valence = MindMoodEntry.valence(stop: stop)
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = MindMoodEntry(date: Date(), kind: .momentary, valence: valence, labels: labels,
                                  note: text.isEmpty ? nil : text)
        store.add(entry)
        if store.consent.stateOfMind {
            Task {
                if await MindHealthBridge.save(entry) { store.markInHealth(entry.id) }
            }
        }
        isLogged = true
        let level = MindSafetyGuard.check(valence: valence, labels: labels, text: text)
        if level > .none { distress = level } else { dismiss() }
    }
}

#Preview("Mood log") {
    MindMoodLogSheet(start: .good)
        .somaTheme(.standard)
}
