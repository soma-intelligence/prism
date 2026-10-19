//
//  MindEmotionLogSheet.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Emotion log · Right now: how it feels on seven stops, a word for it, and
/// what had a hand in it.
///
/// Kept on the phone in `MindStore`, and written to Apple Health as a State
/// of Mind when the consent allowed it (a momentary emotion for Right now, a
/// daily mood for Today, which also answers the Journal's feeling question).
/// A heavy entry opens the safety sheet before the log closes.
struct MindEmotionLogSheet: View {
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MindMoodEntry.Kind = .momentary
    @State private var stop: Double = 4
    @State private var labels: [String] = []
    @State private var associations: [String] = []
    @State private var showsAllFeelings = false
    @State private var showsAllThemes = false
    @State private var distress: MindDistress?

    private var store: MindStore { MindStore.shared }

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let valence = MindMoodEntry.valence(stop: Int(stop))
        let feelings = showsAllFeelings ? MindFeeling.all : MindFeeling.offered(for: valence)
        let themes = showsAllThemes ? MindAssociation.all : Array(MindAssociation.all.prefix(3))

        MindSheetFrame(title: "Mood") {
            SomaSegmentedControl(
                segments: [SomaSegment(id: MindMoodEntry.Kind.momentary, title: "Right now"), SomaSegment(id: .daily, title: "Today")],
                selection: $kind
            )
            .frame(maxWidth: .infinity)

            VStack(spacing: theme.metrics.cardHeaderSpacing + 6) {
                SomaOrb(aspect: .mind, scale: .hero)
                    .frame(maxHeight: theme.metrics.orbDiameter * 0.8)
                    .accessibilityHidden(true)
                Text(MindMoodEntry.title(stop: Int(stop)))
                    .somaFont(type.headline)
                    .foregroundStyle(colors.inkPrimary.color)
                Slider(value: $stop, in: 0...Double(MindMoodEntry.stops - 1), step: 1) {
                    Text("How it feels")
                } minimumValueLabel: {
                    Text("Very unpleasant").somaFont(type.caption)
                } maximumValueLabel: {
                    Text("Very pleasant").somaFont(type.caption)
                }
                .tint(theme.aspects[.mind].identity.color)
                .foregroundStyle(colors.inkSecondary.color)
                .accessibilityValue(MindMoodEntry.title(stop: Int(stop)))
            }
            .frame(maxWidth: .infinity)

            section("A word for it") {
                ForEach(feelings) { feeling in
                    MindChip(title: feeling.title, isSelected: labels.contains(feeling.id)) {
                        toggle(feeling.id, in: &labels)
                    }
                }
                if !showsAllFeelings {
                    MindChip(title: "More", isSelected: false) { showsAllFeelings = true }
                }
            }

            section("What had a hand in it") {
                ForEach(themes) { association in
                    MindChip(title: association.title, isSelected: associations.contains(association.id)) {
                        toggle(association.id, in: &associations)
                    }
                }
                if !showsAllThemes {
                    MindChip(title: "More", isSelected: false) { showsAllThemes = true }
                }
            }
        } footer: {
            MindWideButton(title: "Log it") { log(valence: valence) }
        }
        .sheet(item: $distress, onDismiss: { dismiss() }) { level in
            MindCrisisSheet(distress: level)
        }
    }

    private func section<Chips: View>(_ title: String, @ViewBuilder chips: () -> Chips) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 4) {
            Text(title)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkSecondary.color)
            MindChipFlow().callAsFunction { chips() }
        }
    }

    private func toggle(_ id: String, in list: inout [String]) {
        if let index = list.firstIndex(of: id) { list.remove(at: index) } else { list.append(id) }
    }

    private func log(valence: Double) {
        let entry = MindMoodEntry(date: Date(), kind: kind, valence: valence, labels: labels, associations: associations)
        store.add(entry)
        if kind == .daily { journal.setFeeling(Int(stop), on: Date()) }
        if store.consent.stateOfMind {
            Task {
                if await MindHealthBridge.save(entry) { store.markInHealth(entry.id) }
            }
        }
        let level = MindSafetyGuard.check(valence: valence, labels: labels, text: "")
        if level > .none { distress = level } else { dismiss() }
    }
}

extension MindDistress: Identifiable {
    var id: Int { rawValue }
}
