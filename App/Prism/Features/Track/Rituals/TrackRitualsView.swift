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
            TrackTonightCard(
                title: model.tonight?.offer ?? "Breathe for 10 minutes",
                detail: model.tonightDetail,
                aspect: model.tonight?.reading == .deepSleep ? .sleep : .mind
            ) {
                if let tonight = model.tonight, tonight.kind != .breathe {
                    sheet = .ritual(tonight.offer)
                } else {
                    sheet = .breathe
                }
            }

            TrackRitualList(rituals: model.rituals) { sheet = .newRitual }

            ToolsEntryTile()

            MindHealthStatus(status: health.status)
        }
        .somaRefreshable { inputs = await MindLoad.inputs(health) }
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
    let tryNew: () -> Void

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
                if !rituals.isEmpty {
                    Rectangle().fill(hairline).frame(height: 1 / displayScale)
                }
                Button(action: tryNew) {
                    HStack(spacing: metrics.moveRowGap) {
                        Image(systemName: "plus")
                            .font(.system(size: metrics.journalTileGlyph * 0.8, weight: .light))
                            .frame(width: metrics.miniOrbDiameter)
                        Text("Try a new ritual")
                            .somaFont(theme.typography.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.colors.inkSecondary.color)
                    .frame(minHeight: metrics.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.somaGlassPressDim)
            }
        }
    }
}

fileprivate struct TrackRitualRow: View {
    let ritual: MindRitual

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let aspect: SomaAspect = ritual.reading == .deepSleep ? .sleep : .mind

        HStack(spacing: metrics.moveRowGap) {
            Image(systemName: symbol)
                .font(.system(size: metrics.journalTileGlyph * 0.9, weight: .light))
                .foregroundStyle(colors.inkPrimary.color)
                .frame(width: metrics.miniOrbDiameter, height: metrics.miniOrbDiameter)
            VStack(alignment: .leading, spacing: 2) {
                Text(ritual.title)
                    .somaFont(type.body)
                    .foregroundStyle(colors.inkPrimary.color)
                Text(ritual.detail)
                    .somaFont(type.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: theme.metrics.spaceS) {
                SomaNumber(ritual.signedDelta, type.rowValue, unit: ritual.unit)
                    .foregroundStyle(ritual.isCost ? colors.danger.color : colors.inkPrimary.color)
                SomaEffectBar(fraction: ritual.fraction, aspect: aspect, isCost: ritual.isCost)
                    .frame(width: metrics.miniOrbDiameter * 1.75)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension TrackRitualRow {
    /// An ink glyph for the kind of ritual, in place of a repeated orb.
    fileprivate var symbol: String {
        switch ritual.kind {
        case .breathe: "wind"
        case .walk: "figure.walk"
        case .tag(let tag):
            switch tag.lowercased() {
            case let name where name.contains("sauna"): "flame"
            case let name where name.contains("cold") || name.contains("plunge"): "snowflake"
            case let name where name.contains("medit"): "sparkles"
            case let name where name.contains("read"): "book"
            case let name where name.contains("stretch") || name.contains("yoga"): "figure.mind.and.body"
            default: "circle.dotted"
            }
        }
    }
}

/// Tonight's ritual as the page's lead: the breath ring, what it is and why
/// tonight, and one Start that fills the card's width.
private struct TrackTonightCard: View {
    let title: String
    let detail: String
    let aspect: SomaAspect
    let start: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .top, spacing: metrics.cardSpacing) {
                    VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                        Text("Tonight")
                            .somaFont(type.eyebrow)
                            .foregroundStyle(colors.inkSecondary.color)
                        Text(title)
                            .somaFont(type.headline)
                            .foregroundStyle(colors.inkPrimary.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail)
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    MindBreathRing(aspect: aspect)
                        .frame(width: metrics.miniOrbDiameter * 2, height: metrics.miniOrbDiameter * 2)
                }
                Button(action: start) {
                    Text("Start")
                        .somaFont(type.callout)
                        .foregroundStyle(colors.onAccent.color)
                        .frame(maxWidth: .infinity, minHeight: metrics.minimumTapTarget)
                        .background(colors.accent.color, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.somaGlassPress)
            }
        }
    }
}

#Preview("Track, Rituals") {
    NavigationStack {
        TrackRitualsView()
    }
    .environment(HealthDashboard())
    .environment(JournalStore(url: nil))
}
