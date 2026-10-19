//
//  TrackRitualsView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// Track, Rituals: what the person does to settle, and what each thing does
/// for them, measured on their own days. The stats lead and each ritual is a
/// row with its effect; no headline and no explaining copy (owner, 2026-10-03).
///
/// Rituals are breathing sessions and walks from Apple Health, and the
/// Journal tags that behave like rituals (Meditation, Sauna, a tag of the
/// person's own that names one). Each is measured with ``EffectMath`` on the
/// same evening's HRV, or on the next night's deep sleep for one done at
/// bedtime.
///
/// It draws no navigation chrome: the Track page embeds it under its own top
/// bar. Needs `HealthDashboard` and `JournalStore` in the environment.
struct TrackRitualsView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme

    @State private var inputs: MindInputs?
    @State private var sheet: TrackRitualsSheet?

    var body: some View {
        let model = MindRituals.make(
            from: inputs ?? MindInputs(now: Date()),
            journal: MindJournal(journal),
            calendar: .current
        )

        TabPartScaffold(
            aspect: .mind,
            stats: [
                SomaStat("This week", value: model.thisWeek.map { "\($0)" }),
                SomaStat("Best effect", value: model.bestEffect),
                SomaStat("Streak", value: model.streak.map { "\($0)" }),
            ]
        ) {
            if !model.rituals.isEmpty {
                TrackRitualList(rituals: model.rituals)
            }

            SomaActionCard(
                eyebrow: "A ritual for tonight",
                title: model.tonight?.offer ?? "Breathe for 10 minutes",
                detail: model.tonightDetail,
                actionTitle: "Start",
                action: {
                    if let tonight = model.tonight, tonight.kind != .breathe {
                        sheet = .ritual(tonight.offer)
                    } else {
                        sheet = .breathe
                    }
                }
            ) {
                SomaOrb(aspect: model.tonight?.reading == .deepSleep ? .sleep : .mind, scale: .mini)
            }

            Button {
                sheet = .newRitual
            } label: {
                Text("Try a new ritual")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + 4)
                    .background(Capsule().fill(theme.colors.surface.color))
                    .overlay(
                        Capsule().strokeBorder(
                            theme.colors.inkPrimary.color.opacity(theme.metrics.hairlineOpacity),
                            lineWidth: 0.5
                        )
                    )
                    .contentShape(.capsule)
            }
            .buttonStyle(SomaGlassPressStyle())

            ToolsEntryTile()

            MindHealthStatus(status: health.status)
        }
        .refreshable { inputs = await MindLoad.inputs(health) }
        .task {
            guard inputs == nil else { return }
            inputs = await MindLoad.inputs(health)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .breathe:
                MindBreatheSheet()
            case .ritual(let name):
                NotWiredPage(
                    eyebrow: "Rituals",
                    title: "\(name)",
                    message: "Not built yet."
                )
            case .newRitual:
                NotWiredPage(
                    eyebrow: "Rituals",
                    title: "Try a new ritual",
                    message: "Not built yet."
                )
            }
        }
    }
}

/// What the Rituals part can open over itself.
enum TrackRitualsSheet: Identifiable {
    case breathe
    case ritual(String)
    case newRitual

    var id: String {
        switch self {
        case .breathe: "breathe"
        case .ritual(let name): "ritual-\(name)"
        case .newRitual: "new-ritual"
        }
    }
}

private struct TrackRitualList: View {
    let rituals: [MindRitual]

    @Environment(\.somaTheme) private var theme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let metrics = theme.metrics
        let hairline = theme.colors.inkPrimary.color.opacity(metrics.hairlineOpacity)
        let caption: LocalizedStringResource = rituals.allSatisfy { $0.reading == .deepSleep }
            ? "Effect the night after" : "Effect the same evening"

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.moveRowSpacing) {
                SomaCardHeader("Your rituals", caption: caption)
                ForEach(Array(rituals.enumerated()), id: \.element.id) { index, ritual in
                    if index > 0 {
                        Rectangle().fill(hairline).frame(height: 1 / displayScale)
                    }
                    TrackRitualRow(ritual: ritual)
                }
            }
        }
    }
}

private struct TrackRitualRow: View {
    let ritual: MindRitual

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let aspect: SomaAspect = ritual.reading == .deepSleep ? .sleep : .mind

        HStack(spacing: metrics.moveRowGap) {
            SomaOrb(aspect: aspect, scale: .mini)
            VStack(alignment: .leading, spacing: 2) {
                Text(ritual.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(ritual.detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text(ritual.value ?? "-")
                    .somaFont(type.rowValue)
                    .foregroundStyle(ritual.isCost ? colors.danger.color : colors.inkPrimary.color)
                SomaEffectBar(fraction: ritual.fraction, aspect: aspect, isCost: ritual.isCost)
                    .frame(width: metrics.miniOrbDiameter * 1.75)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Track, Rituals") {
    NavigationStack {
        TrackRitualsView()
    }
    .environment(HealthDashboard())
    .environment(JournalStore(url: nil))
}
