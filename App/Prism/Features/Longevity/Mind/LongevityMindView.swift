//
//  LongevityMindView.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Longevity, Mind, laid out like the Body lens: three numbers that open
/// their Health page; today's stress as a line coloured by zone, scrubbed
/// with a finger, and the day's share of each zone; fourteen days of mood as
/// orbs; the week of mindful minutes round today's goal ring; a breathing
/// session; sixty days of stress by weekday and hour; and every deeper page
/// as a glyph tile.
///
/// Almost no words (owner, 2026-10-03): values, short labels and status
/// words. Everything that reads as a value opens or reveals its detail.
///
/// It draws no stack and no top bar: the Longevity page hosts both.
struct LongevityMindView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(JournalStore.self) private var journal
    @Environment(AppRouter.self) private var router

    @State private var inputs: MindInputs?
    @State private var stress: [MindStressDay]?
    @State private var today: ScoreDetailInputs?
    @State private var moods: [MindMoodEntry] = []
    @State private var isBreathing = false
    @State private var sheet: MindEntryCards.Sheet?
    @State private var quickMood: SomaMood?

    /// What today's stress line is read from: Pulse's stress page reads the
    /// same parts, so the two share one cached read.
    private static let todayParts: Set<ScoreDetailInputs.Part> = [.heart, .today, .nights]

    var body: some View {
        let calendar = Calendar.current
        let base = inputs ?? MindInputs(now: Date())
        let inner = MindInnerSpace.make(from: base, scores: health.scores, calendar: calendar)
        let model = MindLensModel.make(
            inner: inner,
            stress: today.map { ScorePages.stress(health.scores, $0, calendar: calendar) },
            heatmap: MindHeatmap.make(stress ?? [], calendar: calendar),
            moods: moods,
            feelings: feelings(calendar: calendar),
            now: base.now,
            calendar: calendar
        )

        MindLensContent(
            model: model,
            status: health.status,
            latestMood: MindQuickMood.latestToday(moods, now: Date(), calendar: calendar),
            onStat: open,
            onBreathe: { isBreathing = true },
            onEntry: { sheet = $0 },
            onMood: { quickMood = $0 }
        )
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .sheet(isPresented: $isBreathing) { MindBreatheSession() }
        .sheet(item: $quickMood, onDismiss: { Task { await loadMoods() } }) { mood in
            MindEntryGate { MindMoodLogSheet(start: mood) }
                .presentationDetents([.large])
        }
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

    /// The Journal's evening feeling, by day.
    private func feelings(calendar: Calendar) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for entry in journal.loggedDays {
            if let feeling = entry.day.feeling { result[calendar.startOfDay(for: entry.date)] = feeling }
        }
        return result
    }

    private func load(force: Bool) async {
        if !force, inputs != nil { return }
        if today == nil { today = ScoreInputsCache.shared.value(for: Self.todayParts) }
        async let scoresRead: Void = health.loadScores(force: force)
        async let moodsRead: Void = loadMoods()
        let read = await MindLoad.inputs(health)
        inputs = read
        await loadToday(force: force)
        await scoresRead
        await moodsRead
        stress = await MindLoad.stress(health, inputs: read)
    }

    private func loadToday(force: Bool) async {
        let parts = Self.todayParts
        if !force, ScoreInputsCache.shared.isFresh(parts) { return }
        guard let source = await health.prepare(ScoreDetailInputs.metrics(for: parts)) else { return }
        let read = await ScoreDetailInputs.read(parts, from: source, now: Date(), calendar: .current)
        today = read
        ScoreInputsCache.shared.store(read, for: parts)
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
    var latestMood: MindMoodEntry?
    var onStat: (SomaStat) -> Void = { _ in }
    var onBreathe: () -> Void = {}
    var onEntry: (MindEntryCards.Sheet) -> Void = { _ in }
    var onMood: (SomaMood) -> Void = { _ in }

    @Environment(\.somaTheme) private var theme

    var body: some View {
        ScrollView {
            MindLensStack(model: model, status: status, latestMood: latestMood, onStat: onStat, onBreathe: onBreathe,
                          onEntry: onEntry, onMood: onMood)
        }
        .aspectWash(.mind)
    }
}

/// The lens's column, apart from its scroll view so a render draws it whole.
struct MindLensStack: View {
    let model: MindLensModel
    var status: HealthDashboard.Status = .ready
    var latestMood: MindMoodEntry?
    var onStat: (SomaStat) -> Void = { _ in }
    var onBreathe: () -> Void = {}
    var onEntry: (MindEntryCards.Sheet) -> Void = { _ in }
    var onMood: (SomaMood) -> Void = { _ in }

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            SomaStatRow([
                SomaStat("HRV", value: model.hrv.map(MindLensFormat.whole), unit: "ms", trend: model.hrvTrend),
                SomaStat("Resting HR", value: model.resting.map(MindLensFormat.whole), unit: "bpm", trend: model.restingTrend),
                SomaStat("Mindful", value: model.mindfulToday.map(MindLensFormat.whole), unit: "min"),
            ], onSelect: onStat)
            .padding(.top, metrics.heroTopPadding)

            MindSection("Stress", route: ScoreRoute.stress) {
                SomaCard {
                    MindStressDayChart(samples: model.stress, dayStart: model.dayStart)
                }
                NavigationLink(value: ScoreRoute.stress) {
                    MindStressZones(minutes: model.zoneMinutes)
                        .contentShape(.rect)
                }
                .buttonStyle(TilePressStyle())
            }

            MindSection("Mood", route: MindRoute.innerMap) {
                MindMoodCard(model: model, latest: latestMood, onEntry: onEntry, onMood: onMood)
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
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, metrics.pagePadding)
        .frame(maxWidth: metrics.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var mindfulRoute: VaultRoute? {
        HealthMetricCatalog.metric(for: MindInputs.Metric.mindful).map { VaultRoute.dataType(BodyDataType($0)) }
    }
}

/// The mood card: one question and five faces to answer it, a line that
/// says what you logged today, then fourteen days of mood under it. A face
/// opens the quick log already set to it; the other ways in (the full log,
/// a check in, telling the day) wait behind the card's menu.
struct MindMoodCard: View {
    let model: MindLensModel
    let latest: MindMoodEntry?
    var onEntry: (MindEntryCards.Sheet) -> Void = { _ in }
    var onMood: (SomaMood) -> Void = { _ in }

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let logged = latest.map { MindQuickMood.mood(valence: $0.valence) }

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                HStack(alignment: .center) {
                    Text(logged == nil ? "How do you feel?" : "How do you feel now?")
                        .somaFont(type.cardTitle)
                        .foregroundStyle(colors.inkPrimary.color)
                    Spacer(minLength: 0)
                    MindLogMenu(onEntry: onEntry)
                }

                SomaMoodFaces(selection: .constant(logged)) { mood in onMood(mood) }

                if let latest, let logged {
                    HStack(spacing: metrics.identityDotSpacing) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(logged.tone.color)
                        Text("Logged \(String(localized: logged.title)) at \(latest.date.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    .somaFont(type.caption)
                    .transition(.opacity)
                }

                Rectangle()
                    .fill(colors.inkPrimary.color.opacity(metrics.hairlineOpacity))
                    .frame(height: 0.5)

                Text("14 days")
                    .somaFont(type.captionValue)
                    .foregroundStyle(colors.inkSecondary.color)
                MindMoodStrip(days: model.moods)
            }
        }
        .animation(reduceMotion ? nil : theme.motion.selection, value: latest?.id)
    }
}

/// The menu on the mood card: the full log, a check in, telling the day,
/// today's moments, or what Mind keeps.
struct MindLogMenu: View {
    let onEntry: (MindEntryCards.Sheet) -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Menu {
            Button("Log in detail", systemImage: "face.smiling") { onEntry(.feeling) }
            Button("Check in", systemImage: "checkmark.circle") { onEntry(.checkIn) }
            Button("Tell your day", systemImage: "text.bubble") { onEntry(.tellDay) }
            Button("Today’s moments", systemImage: "clock") { onEntry(.day) }
            Divider()
            Button(MindStore.shared.consent.isGiven ? "Mind’s choices" : "Turn on Mind", systemImage: "hand.raised") {
                onEntry(.choices)
            }
        } label: {
            Image(systemName: "ellipsis")
                .somaFont(theme.typography.callout)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.inkPrimary.color)
                .frame(width: theme.metrics.minimumTapTarget, height: theme.metrics.minimumTapTarget)
                .background(theme.colors.surfaceRecessed.color, in: .circle)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More ways to log")
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
        case .unavailable, .failed: HealthStatusCard()
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
