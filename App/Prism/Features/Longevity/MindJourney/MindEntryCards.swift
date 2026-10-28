//
//  MindEntryCards.swift
//  Prism
//

import SwiftUI
import SomaUI

/// What the Mind lens adds under its own cards: the three ways to tell Mind
/// something (a feeling, a check-in, the day in words), today's moments, and
/// the way into every deeper page.
///
/// The first thing a person tells Mind opens the consent screen first
/// (`MindEntryGate`).
struct MindEntryCards: View {
    @Environment(\.somaTheme) private var theme

    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case feeling, checkIn, tellDay, day, choices
        var id: String { rawValue }
    }

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 8) {
                SomaCardHeader("How are you?")
                MindChipFlow().callAsFunction {
                    MindChip(title: "Log a feeling", isSelected: false) { sheet = .feeling }
                    MindChip(title: "Check in", isSelected: false) { sheet = .checkIn }
                    MindChip(title: "Tell your day", isSelected: false) { sheet = .tellDay }
                    MindChip(title: "Today’s moments", isSelected: false) { sheet = .day }
                }
            }
        }

        MindEyebrow(text: "Go deeper")
            .padding(.top, theme.metrics.leadSpacing - theme.metrics.cardSpacing)

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(.detail, "Mind score")
            tile(.hrv, "HRV")
            tile(.stressRadar, "Stress Radar")
            tile(.meetings, "Meetings")
            tile(.moodForecast, "Mood forecast")
            tile(.innerMap, "Inner map")
            tile(.insights, "Insights")
            tile(.habits(.recovery), "Habits")
        }

        NavigationLink {
            TrackRitualsView()
                .navigationTitle("Rituals")
        } label: {
            MindTile(title: "Rituals")
        }
        .buttonStyle(.somaGlassPress)

        Button {
            sheet = .choices
        } label: {
            Text(MindStore.shared.consent.isGiven ? "Mind’s choices" : "Turn on Mind")
                .somaFont(type.callout)
                .foregroundStyle(colors.inkSecondary.color)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .sheet(item: $sheet) { which in
            switch which {
            case .feeling: MindEntryGate { MindEmotionLogSheet() }
            case .checkIn: MindEntryGate { MindCheckInSheet() }
            case .tellDay: MindEntryGate { MindTellDaySheet() }
            case .day: MindDaySheet(day: Date())
            case .choices: MindChoicesSheet()
            }
        }
    }

    private func tile(_ route: MindRoute, _ title: String) -> some View {
        TileLink(value: route) {
            MindTile(title: title)
        }
    }
}

/// Shows the consent screen before the first entry, then the entry itself.
struct MindEntryGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var isGiven = MindStore.shared.consent.isGiven

    var body: some View {
        if isGiven {
            content()
        } else {
            MindConsentSheet { turnedOn in
                if turnedOn { isGiven = true } else { dismiss() }
            }
        }
    }
}

/// The consent screen opened again from the Mind page, to change or delete.
struct MindChoicesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MindConsentSheet { _ in dismiss() }
    }
}
