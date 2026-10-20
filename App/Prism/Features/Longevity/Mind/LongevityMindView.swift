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
    /// What's on this phone, so today's logged mood shows from the first
    /// frame; Apple Health's State of Mind joins it once read.
    @State private var moods: [MindMoodEntry] = MindStore.shared.moods
    /// What the lens drew the last time, kept on the device, so it opens on
    /// its numbers rather than on dashes (``LongevitySnapshotStore``).
    @State private var kept = LongevitySnapshotStore.shared.mind
    /// True once every read of this opening has landed: the lens then
    /// draws them, the numbers rolling from the kept ones.
    @State private var landed = false
    @State private var isBreathing = false
    @State private var sheet: MindEntryCards.Sheet?
    @State private var quickMood: SomaMood?
    /// The calendar against stress, worked out on the phone after the rest
    /// has landed, and kept in memory only.
    @State private var calendarState = MindCalendarState(access: MindCalendar.access)

    /// What today's stress line is read from: Pulse's stress page reads the
    /// same parts, so the two share one cached read.
    private static let todayParts: Set<ScoreDetailInputs.Part> = [.heart, .today, .nights]

    var body: some View {
        let calendar = Calendar.current
        let live = liveModel(calendar: calendar)
        // Before the reads land, the kept lens; with none kept (a first
        // launch), the reads as they come.
        let shown = LongevityShown(kept: kept, fresh: landed || kept == nil ? live : nil)

        MindLensContent(
            model: shown.value ?? live,
            updated: shown.updated(now: Date()),
            status: health.status,
            latestMood: MindQuickMood.latestToday(moods, now: Date(), calendar: calendar),
            onStat: open,
            onBreathe: { isBreathing = true },
            onEntry: { sheet = $0 },
            onMood: { quickMood = $0 },
            calendar: calendarState,
            onCalendar: connectCalendar
        )
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .onChange(of: live) { _, model in
            // A mood logged, or the scores read again: kept for next time.
            if landed { LongevitySnapshotStore.shared.save(mind: model) }
        }
        .sheet(isPresented: $isBreathing) { MindBreatheSession() }
        .sheet(item: $quickMood, onDismiss: { Task { await loadMoods() } }) { mood in
            MindEntryGate { MindMoodLogSheet(start: mood) }
                .presentationDetents([.large])
        }
        .sheet(item: $sheet, onDismiss: { Task { await loadMoods(); await loadCalendar(asking: false) } }) { which in
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

    /// The lens as the reads on hand draw it.
    private func liveModel(calendar: Calendar) -> MindLensModel {
        let base = inputs ?? MindInputs(now: Date())
        let inner = MindInnerSpace.make(from: base, scores: health.scores, calendar: calendar)
        return MindLensModel.make(
            inner: inner,
            stress: today.map { ScorePages.stress(health.scores, $0, calendar: calendar) },
            heatmap: MindHeatmap.make(stress ?? [], calendar: calendar),
            night: today.flatMap { MindNightStress.read($0, scores: health.scores, calendar: calendar) },
            moods: moods,
            feelings: feelings(calendar: calendar),
            now: base.now,
            calendar: calendar
        )
    }

    /// Reads everything, then shows it at once, the numbers rolling from
    /// the kept ones, and keeps it for the next opening. With nothing kept,
    /// each read shows as it lands.
    private func load(force: Bool) async {
        if !force, inputs != nil { return }
        let progressive = kept == nil && !landed
        if today == nil { today = ScoreInputsCache.shared.value(for: Self.todayParts) }
        async let scoresRead: Void = health.loadScores(force: force)
        async let moodsRead: Void = loadMoods()
        let read = await MindLoad.inputs(health)
        if progressive { inputs = read }
        let todayRead = await readToday(force: force)
        if progressive, let todayRead { today = todayRead }
        await scoresRead
        await moodsRead
        let stressRead = await MindLoad.stress(health, inputs: read)
        withAnimation(reduceMotion ? nil : theme.motion.numberRoll) {
            inputs = read
            if let todayRead { today = todayRead }
            stress = stressRead
            landed = true
        }
        LongevitySnapshotStore.shared.save(mind: liveModel(calendar: .current))
        await loadCalendar(asking: false)
    }

    /// The card's button: asks for the calendar, or opens Mind's choices
    /// when the calendar is off there.
    private func connectCalendar() {
        if calendarState.access == .off {
            sheet = .choices
        } else {
            Task { await loadCalendar(asking: true) }
        }
    }

    /// Thirty days of the calendar against thirty days of stress and the
    /// next mornings' HRV, reduced to a few lines on the phone. Nothing is
    /// kept: the events and the lines live in memory for this opening.
    private func loadCalendar(asking: Bool) async {
        let access = asking ? await MindCalendar.requestAccess() : MindCalendar.access
        guard access == .granted else {
            calendarState = MindCalendarState(access: access)
            return
        }
        if calendarState.access != .granted { calendarState = MindCalendarState(access: access) }
        let calendar = Calendar.current
        let now = Date()
        // The lines compare whole days, so one read a day is enough: a month
        // of heart rate and of events is read again only the next day.
        let insights: [MindCalendarInsights.Insight]
        if let kept = MindCalendarDayCache.insights(on: now, calendar: calendar) {
            insights = kept
        } else {
            let start = calendar.date(byAdding: .day, value: -MindMeetingsPage.historyDays, to: calendar.startOfDay(for: now)) ?? now
            let events = await MindCalendar.events(from: start, to: now)
            let base: MindInputs
            if let inputs { base = inputs } else { base = await MindLoad.inputs(health) }
            let curves = await MindJourneyLoad.curves(health, inputs: base, days: MindMeetingsPage.historyDays)
            let hrv = base.heartRateVariability
            insights = await Task.detached(priority: .utility) {
                MindCalendarInsights.lines(curves: curves, events: events, hrv: hrv, now: now, calendar: calendar)
            }.value
            MindCalendarDayCache.store(insights, on: now, calendar: calendar)
        }
        withAnimation(reduceMotion ? nil : theme.motion.selection) {
            calendarState = MindCalendarState(access: access, insights: insights)
        }
    }

    /// Today's heart, sleep and steps for the stress line: the shared read
    /// while it is fresh, else a new one. Nil when nothing new was read.
    private func readToday(force: Bool) async -> ScoreDetailInputs? {
        let parts = Self.todayParts
        if !force, ScoreInputsCache.shared.isFresh(parts) { return nil }
        guard let source = await health.prepare(ScoreDetailInputs.metrics(for: parts)) else { return nil }
        let read = await ScoreDetailInputs.read(parts, from: source, now: Date(), calendar: .current)
        ScoreInputsCache.shared.store(read, for: parts)
        return read
    }

    private func loadMoods() async {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -MindLensModel.moodDays, to: calendar.startOfDay(for: Date())) ?? Date()
        moods = await MindJourneyLoad.moods(since: start, store: .shared)
    }

    @Environment(\.somaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}

/// The lens itself, drawn from a ``MindLensModel``: no reads of its own, so
/// a fixture renders it as well as Health does.
struct MindLensContent: View {
    let model: MindLensModel
    /// When the kept numbers on screen were read, while they are old.
    var updated: Date?
    var status: HealthDashboard.Status = .ready
    var latestMood: MindMoodEntry?
    var onStat: (SomaStat) -> Void = { _ in }
    var onBreathe: () -> Void = {}
    var onEntry: (MindEntryCards.Sheet) -> Void = { _ in }
    var onMood: (SomaMood) -> Void = { _ in }
    /// Nil leaves the calendar out (a fixture render).
    var calendar: MindCalendarState?
    var onCalendar: () -> Void = {}

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaPageScroll {
            MindLensStack(model: model, updated: updated, status: status, latestMood: latestMood, onStat: onStat,
                          onBreathe: onBreathe, onEntry: onEntry, onMood: onMood,
                          calendar: calendar, onCalendar: onCalendar)
        }
        .aspectWash(.mind)
    }
}

/// The lens's column, apart from its scroll view so a render draws it whole.
struct MindLensStack: View {
    let model: MindLensModel
    var updated: Date?
    var status: HealthDashboard.Status = .ready
    var latestMood: MindMoodEntry?
    var onStat: (SomaStat) -> Void = { _ in }
    var onBreathe: () -> Void = {}
    var onEntry: (MindEntryCards.Sheet) -> Void = { _ in }
    var onMood: (SomaMood) -> Void = { _ in }
    var calendar: MindCalendarState?
    var onCalendar: () -> Void = {}

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            SomaUpdatedHeader(updated) {
                SomaStatRow([
                    SomaStat("HRV", value: model.hrv.map(MindLensFormat.whole), unit: "ms", trend: model.hrvTrend),
                    SomaStat("Resting HR", value: model.resting.map(MindLensFormat.whole), unit: "bpm", trend: model.restingTrend),
                    SomaStat("Mindful", value: model.mindfulToday.map(MindLensFormat.whole), unit: "min"),
                ], onSelect: onStat)
                .padding(.top, metrics.heroTopPadding)
            }

            MindSection("Stress", route: ScoreRoute.stress) {
                SomaCard {
                    MindStressDayChart(samples: model.stress, dayStart: model.dayStart, night: model.night)
                }
                NavigationLink(value: ScoreRoute.stress) {
                    MindStressZones(minutes: model.zoneMinutes)
                        .contentShape(.rect)
                }
                .buttonStyle(TilePressStyle())
            }

            if let calendar {
                MindSection("Calendar", route: MindRoute.meetings) {
                    MindCalendarCard(state: calendar, onConnect: onCalendar)
                }
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

/// The calendar's lines for the day they were worked out on, for the life
/// of the app.
@MainActor
enum MindCalendarDayCache {
    private static var day: Date?
    private static var kept: [MindCalendarInsights.Insight]?

    static func insights(on date: Date, calendar: Calendar) -> [MindCalendarInsights.Insight]? {
        guard let day, calendar.isDate(day, inSameDayAs: date) else { return nil }
        return kept
    }

    static func store(_ insights: [MindCalendarInsights.Insight], on date: Date, calendar: Calendar) {
        day = calendar.startOfDay(for: date)
        kept = insights
    }

    /// Forgets the lines, for "Delete my data".
    static func clear() {
        day = nil
        kept = nil
    }
}
