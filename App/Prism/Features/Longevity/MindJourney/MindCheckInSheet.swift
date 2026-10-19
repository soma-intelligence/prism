//
//  MindCheckInSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Check-in: energy, mood and focus on five steps each, and one question when
/// the body raised one (breathing over its usual range three nights running).
/// Kept on the phone in `MindStore`; the mood is also written to Apple Health
/// as a State of Mind when the consent allowed it.
struct MindCheckInSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var energy: Int?
    @State private var mood: Int?
    @State private var focus: Int?
    @State private var question: String?
    @State private var answer: MindCheckIn.Answer?

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        MindSheetFrame(title: "Check-in") {
            VStack(spacing: theme.metrics.leadSpacing) {
                MindStepRow(title: "Energy", word: MindCheckIn.word(energy: energy), value: $energy)
                MindStepRow(title: "Mood", word: MindCheckIn.word(mood: mood), value: $mood)
                MindStepRow(title: "Focus", word: MindCheckIn.word(focus: focus), value: $focus)
            }
            .padding(.top, theme.metrics.cardSpacing)

            if let question {
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 4) {
                    Text(question)
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                    MindChipFlow().callAsFunction {
                        ForEach(MindCheckIn.Answer.allCases, id: \.self) { option in
                            MindChip(title: option.title, isSelected: answer == option) {
                                answer = answer == option ? nil : option
                            }
                        }
                    }
                }
            }
        } footer: {
            MindWideButton(title: "Save", isEnabled: energy != nil || mood != nil || focus != nil) { save() }
        }
        .task {
            let extras = await MindJourneyLoad.extras(health)
            let nights = MindSignals.fastBreathingNights(extras.respiratory, now: Date(), calendar: .current)
            if nights >= 3 {
                question = "Your breathing has run fast for \(nights) nights. Coming down with something?"
            }
        }
    }

    private func save() {
        let store = MindStore.shared
        store.add(MindCheckIn(date: Date(), energy: energy, mood: mood, focus: focus, question: question, answer: answer))
        if let mood {
            // Five mood steps onto Apple's -1 to 1.
            let entry = MindMoodEntry(date: Date(), kind: .momentary, valence: Double(mood) / 2 - 1)
            store.add(entry)
            if store.consent.stateOfMind {
                Task { if await MindHealthBridge.save(entry) { store.markInHealth(entry.id) } }
            }
        }
        dismiss()
    }
}

/// One dimension: its name and word, and five bars that rise left to right.
struct MindStepRow: View {
    let title: String
    let word: String
    @Binding var value: Int?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let hue = theme.aspects[.mind].identity.color
        let tallest = theme.metrics.minimumTapTarget

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(word)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<MindCheckIn.steps, id: \.self) { step in
                    Button {
                        value = value == step ? nil : step
                    } label: {
                        RoundedRectangle(cornerRadius: theme.metrics.chartBarCornerRadius + 2, style: .continuous)
                            .fill(step <= (value ?? -1) ? hue : colors.surfaceRecessed.color)
                            .frame(width: tallest * 0.55, height: tallest * (0.35 + 0.65 * Double(step) / Double(MindCheckIn.steps - 1)))
                            .frame(height: tallest, alignment: .bottom)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), step \(step + 1) of \(MindCheckIn.steps)")
                    .accessibilityAddTraits(value == step ? .isSelected : [])
                }
            }
        }
    }
}
