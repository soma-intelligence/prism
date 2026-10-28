//
//  LongevityMindView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Longevity, Mind, laid out like the Body lens and drawn like the reference design's
/// stress page: three numbers that open their Health page; today's stress as
/// a line coloured by zone, scrubbed with a finger, and the day's share of
/// each zone; fourteen days of mood as orbs; the week of mindful minutes
/// round today's goal ring; a breathing session; sixty days of stress by
/// weekday and hour; and every deeper page as a glyph tile.
///
/// Almost no words (owner, 2026-10-03): values, short labels and status
/// words. Everything that reads as a value opens or reveals its detail.
///
/// It draws no stack and no top bar: the Longevity page hosts both.
struct LongevityMindView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(AppRouter.self) private var router

    /// Moods read again after a log sheet closes; until then the lens draws
    /// the ones its read brought.
    @State private var moods: [MindMoodEntry]?
    @State private var isBreathing = false
    @State private var sheet: MindEntryCards.Sheet?

    /// The last read, this launch's or the last one's: the lens draws it at
    /// once and the next read replaces every card in one go.
    private var cache: LongevityCache { .shared }

    var body: some View {
        let calendar = Calendar.current
        let model: MindLensModel = if let parts = cache.mindParts {
            parts.model(scores: health.scores, moods: moods, journal: journal, calendar: calendar)
        } else if let cached = cache.mind {
            cached
        } else {
            LongevityMindParts.empty(now: Date()).model(scores: health.scores, journal: journal, calendar: calendar)
        }

        MindLensContent(
            model: model,
            status: health.status,
            onStat: open,
            onBreathe: { isBreathing = true },
            onEntry: { sheet = $0 }
        )
        .somaRefreshable { await cache.loadMind(health, journal: journal, force: true) }
        .task { await cache.loadMind(health, journal: journal) }
        .sheet(isPresented: $isBreathing) { MindBreatheSession() }
        .sheet(item: $sheet, onDismiss: { Task { await loadMoods() } }) { which in
            switch which {
            case .feeling: MindEntryGate { MindEmotionLogSheet() }
            case .checkIn: MindEntryGate { MindCheckInSheet() }
            case .tellDay: MindEntryGate { MindTellDaySheet() }
            case .day: MindDaySheet(day: Date())
            case .choices: MindChoicesSheet()
            }
        }
    }

    /// The three stats open their reading in the Vault.
    private func open(_ stat: SomaStat) {
        let identifier: String? = switch stat.id {
        case "HRV": MindInputs.Metric.heartRateVariability
        case "Resting HR": MindInputs.Metric.restingHeartRate
        case "Mindful": MindInputs.Metric.mindful
        default: nil
        }
        guard let identifier, let metric = HealthMetricCatalog.metric(for: identifier) else { return }
        router.longevityPath.append(VaultRoute.dataType(BodyDataType(metric)))
    }

    private func loadMoods() async {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -MindLensModel.moodDays, to: calendar.startOfDay(for: Date())) ?? Date()
        moods = await MindJourneyLoad.moods(since: start, store: .shared)
    }

    nonisolated static func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}

/// The lens itself, drawn from a ``MindLensModel``: no reads of its own, so
/// a fixture renders it as well as Health does.
struct MindLensContent: View {
    let model: MindLensModel
    var status: HealthDashboard.Status = .ready
    var onStat: (SomaStat) -> Void = { _ in }
    var onBreathe: () -> Void = {}
    var onEntry: (MindEntryCards.Sheet) -> Void = { _ in }

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaPageScroll {
            MindLensStack(model: model, status: status, onStat: onStat, onBreathe: onBreathe, onEntry: onEntry)
        }
        .softScrollEdges()
        .aspectWash(.mind)
    }
}

/// The lens's column, apart from its scroll view so a render draws it whole.
struct MindLensStack: View {
    let model: MindLensModel
    var status: HealthDashboard.Status = .ready
    var onStat: (SomaStat) -> Void = { _ in }
    var onBreathe: () -> Void = {}
    var onEntry: (MindEntryCards.Sheet) -> Void = { _ in }

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            SomaStatRow([
                SomaStat("HRV", value: model.hrv.map(MindLensFormat.whole), unit: "ms", trend: model.hrvTrend, better: .higher),
                SomaStat("Resting HR", value: model.resting.map(MindLensFormat.whole), unit: "bpm", trend: model.restingTrend, better: .lower),
                SomaStat("Mindful", value: model.mindfulToday.map(MindLensFormat.whole), unit: "min"),
            ], onSelect: onStat)
            .padding(.top, metrics.heroTopPadding)

            // The sections in one column on a phone and two where the width
            // holds them, each heading staying over its own cards.
            SomaCardColumns(gap: .sections) {
                MindSection("Stress", route: ScoreRoute.stress) {
                    SomaCard {
                        MindStressDayChart(samples: model.stress, dayStart: model.dayStart)
                    }
                    NavigationLink(value: ScoreRoute.stress) {
                        MindStressZones(minutes: model.zoneMinutes)
                            .contentShape(.rect)
                    }
                    .zoomSource(ScoreRoute.stress)
                    .buttonStyle(.somaGlassPress)
                }

                MindSection("Mood", route: MindRoute.innerMap) {
                    SomaCard {
                        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                            HStack {
                                Text("Last 14 days")
                                    .somaFont(theme.typography.captionValue)
                                    .foregroundStyle(theme.colors.inkSecondary.color)
                                Spacer(minLength: 0)
                                MindLogMenu(onEntry: onEntry)
                            }
                            MindMoodStrip(days: model.moods)
                        }
                    }
                }

                MindSection("Mindful minutes", route: mindfulRoute) {
                    MindMindfulCard(week: model.week, goal: MindLensModel.mindfulGoal)
                    MindBreatheCard(action: onBreathe)
                }

                MindSection("Stress by weekday and hour", route: MindRoute.insights) {
                    MindHeatmapCard(heatmap: model.heatmap)
                }

                MindSection("Go deeper") {
                    MindGlyphGrid()
                }

                MindHealthStatus(status: status)
            }
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, metrics.pagePadding)
        .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var mindfulRoute: VaultRoute? {
        HealthMetricCatalog.metric(for: MindInputs.Metric.mindful).map { VaultRoute.dataType(BodyDataType($0)) }
    }
}

/// The plus on the mood card: log a feeling, check in, tell the day, see
/// today's moments, or change what Mind keeps.
struct MindLogMenu: View {
    let onEntry: (MindEntryCards.Sheet) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Menu {
            Button("Log a feeling", systemImage: "face.smiling") { onEntry(.feeling) }
            Button("Check in", systemImage: "checkmark.circle") { onEntry(.checkIn) }
            Button("Tell your day", systemImage: "text.bubble") { onEntry(.tellDay) }
            Button("Today’s moments", systemImage: "clock") { onEntry(.day) }
            Divider()
            Button(MindStore.shared.consent.isGiven ? "Mind’s choices" : "Turn on Mind", systemImage: "hand.raised") {
                onEntry(.choices)
            }
        } label: {
            // A small pill rather than a big plus disc: logging is an action
            // on the card, not the card's subject.
            Label("Log", systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .somaFont(theme.typography.caption)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .padding(.horizontal, theme.metrics.spaceM)
                .padding(.vertical, theme.metrics.spaceXS + 2)
                .background(theme.colors.surfaceRecessed.color, in: .capsule)
                .frame(minHeight: theme.metrics.minimumTapTarget)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Log")
    }
}

/// A short status card: a title, and at most a few words under it.
struct MindTextCard: View {
    let title: LocalizedStringResource
    var text: String? = nil

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing + 6) {
                Text(title)
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                if let text {
                    MindReasonText(text: text)
                }
            }
        }
    }
}

/// The Health status card, only when there is something to explain: no store
/// on this device, or a read that failed.
struct MindHealthStatus: View {
    let status: HealthDashboard.Status

    var body: some View {
        switch status {
        case .unavailable, .failed: HealthStatusCard().somaColumnSpan(.full)
        default: EmptyView()
        }
    }
}

#if DEBUG
#Preview("Longevity, Mind") {
    NavigationStack {
        MindLensContent(model: .preview)
    }
    .somaTheme(.standard)
}
#endif
