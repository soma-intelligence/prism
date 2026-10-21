//
//  PulseTodayView.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The Pulse tab's Today page: the orb with the next move on it, the three
/// scores under it, each against its usual, what moved most today, then the
/// moves, the energy bank and the day so far. The aspect cards that only
/// repeated a number shown above are hidden by default (Edit Today brings
/// them back).
///
/// Every number comes from `HealthDashboard.today`, which carries Soma's scores
/// from `HealthDashboard.scores`, and every missing one reads as a dash. On a phone it is one column; with room, the orb and the sentence
/// hold the leading column and the cards the trailing one.
///
/// The page is cut into small views on purpose, and each reads the theme into
/// locals once. A Debug build copies the whole theme for every
/// `theme.metrics.x` it evaluates, and a page built as one body nests all of
/// those copies in one stack: the phone's main thread has a megabyte, and a
/// single body for this page overflowed it at launch, where the Simulator's
/// eight megabytes hid it.
struct PulseTodayView: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
#endif
    @State private var insights = PulseInsights.empty

    var body: some View {
        let metrics = theme.metrics
        let canvas = theme.colors.canvas.color

        SomaPageScroll {
            Group {
                if isRoomy {
                    HStack(alignment: .top, spacing: metrics.leadSpacing) {
                        lead.frame(maxWidth: metrics.orbDiameter * 2)
                        PulseCards(today: health.today, status: health.status, scores: health.scores, insights: insights)
                    }
                } else {
                    VStack(alignment: .leading, spacing: metrics.browseSectionSpacing) {
                        lead
                        PulseCards(today: health.today, status: health.status, scores: health.scores, insights: insights)
                    }
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(canvas.ignoresSafeArea())
        .refreshable {
            await health.loadToday(force: true)
            await readInsights()
        }
        .task {
            await health.loadToday()
            await readInsights()
        }
    }

    private var lead: PulseLead {
        PulseLead(today: health.today, status: health.status, scores: health.scores, moved: insights.moved)
    }

    private func readInsights() async {
        guard let read = await PulseInsights.read(health: health, now: .now, calendar: .current) else { return }
        insights = read
    }

    private var isRoomy: Bool {
#if os(macOS)
        true
#else
        sizeClass == .regular
#endif
    }
}

// MARK: - The lead: orb, values, sentence

private struct PulseLead: View {
    let today: PulseToday?
    let status: HealthDashboard.Status
    let scores: SomaScores?
    /// What moved most today, ranked.
    let moved: [PulseInsightItem]

    @Environment(\.somaTheme) private var theme
    @Environment(\.zoomNamespace) private var zoom
    @Environment(AppRouter.self) private var router
    /// The quick add, lifted by a long press on the orb.
    @State private var quickAdd: HomeSheetRoute?
    /// The moves ticked off today: the orb moves past them.
    @AppStorage(PulseDoneMoves.key) private var doneMoves = ""

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: 0) {
            // One orb, one action: the move that matters now, never a carousel
            // to swipe through (owner, 2026-10-03). Tapping it opens that
            // move's page.
            let now = PulseNowAction.make(
                today: today, done: PulseDoneMoves(stored: doneMoves).aspects(on: Date()), at: NextMoveClock.now()
            )
            SomaOrb(aspect: now.aspect, label: now.label)
                .frame(maxWidth: .infinity)
                .padding(.top, metrics.heroTopPadding)
                .somaOrbTap { open(now.aspect) }
                .accessibilityElement()
                .accessibilityLabel(Text(now.label))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Open") { open(now.aspect) }
                // A long press lifts the quick add over Today.
                .onLongPressGesture { quickAdd = .quickAdd }
                .accessibilityAction(named: "Add to today") { quickAdd = .quickAdd }
                .homeSheets($quickAdd)

            // One tap on a score opens its page.
            // A ring zooms its page out of itself: its zoom id is the route
            // it pushes, the id the page's destination zooms to.
            SomaScoreRings(scoreRow, zoom: zoom, zoomID: { AnyHashable(TodayRoutes.ring($0)) }) { tapped in
                router.pulsePath.append(TodayRoutes.ring(tapped))
            }
                .padding(.top, metrics.heroSpacing * 2)

            PulseMovedSection(items: moved)
                .padding(.top, metrics.leadSpacing)

            // Words only when there is no data to show instead.
            if case .ready = status {} else if today == nil {
                PulseHeadline(status: status, today: today)
                    .padding(.top, metrics.leadSpacing)
            }

        }
    }

    /// The orb opens its aspect's own page, pushed plainly: the orb is no
    /// tile, and the ring that opens the same page keeps its own zoom.
    private func open(_ aspect: SomaAspect) {
        router.pulsePath.append(TodayRoutes.orb(aspect))
    }

    private var scoreRow: [SomaRingScore] {
        [
            ring(.sleep, scores?.sleep, today?.sleep.trend, PulseScoreInsights.sleep(scores)),
            ring(.mind, scores?.mind, today?.mind.trend, PulseScoreInsights.mind(scores)),
            ring(.activity, scores?.strain, today?.activity.trend, PulseScoreInsights.activity(scores)),
        ]
    }

    /// A score as a ring; its cue against its usual is read aloud, not printed.
    private func ring(_ aspect: SomaAspect, _ value: Int?, _ trend: SomaTrend?, _ insight: Insight) -> SomaRingScore {
        SomaRingScore(
            aspect: aspect,
            value: value,
            trend: trend,
            cue: insight.label.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }
}

/// The sentence the page leads with. Before the first read, and where there is
/// no Health store, it says so rather than inventing a day.
private struct PulseHeadline: View {
    let status: HealthDashboard.Status
    let today: PulseToday?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let words = self.words

        VStack(alignment: .leading, spacing: 8) {
            Text(words.title)
                .somaFont(type.headline)
                .foregroundStyle(colors.inkPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Text(words.reason)
                .somaFont(type.callout)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var words: (title: String, reason: String) {
        switch status {
        case .unavailable:
            return ("No Health store here.",
                    "This device has no Apple Health. The same page reads real values on iPhone and iPad.")
        case .failed(let message):
            return ("Could not read Health.", message)
        case .idle, .loading, .ready:
            guard let today else {
                return ("Reading Apple Health.", "Asking the Health store for last night, today and the month before.")
            }
            return (today.headline, today.reason)
        }
    }
}

// MARK: - The cards

private struct PulseCards: View {
    let today: PulseToday?
    let status: HealthDashboard.Status
    let scores: SomaScores?
    let insights: PulseInsights

    @Environment(\.somaTheme) private var theme
    /// Which cards show, in which order: chosen in Edit Today.
    @AppStorage(HomeTodayLayout.key) private var layout = HomeTodayLayout.standard.stored
    @State private var sheet: HomeSheetRoute?

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let shown = HomeTodayLayout(stored: layout).shown
        let firstAspect = shown.first(where: \.isAspect)

        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            OnboardingFirstWeekCard()

            ForEach(shown) { card in
                if card == firstAspect {
                    Text("Your aspects")
                        .somaFont(type.title)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, metrics.browseSectionSpacing - metrics.cardSpacing)
                }
                PulseTodayCardView(card: card, today: today, scores: scores, insights: insights) { sheet = $0 }
            }

            HomeTodayFoot { sheet = $0 }
                .padding(.top, metrics.browseSectionSpacing - metrics.cardSpacing)

            if status != .ready {
                HealthStatusCard()
            }
        }
        .homeSheets($sheet)
    }
}

private struct PulseMovesCard: View {
    let today: PulseToday?

    @Environment(\.somaTheme) private var theme
    @AppStorage(PulseDoneMoves.key) private var doneMoves = ""

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let done = PulseDoneMoves(stored: doneMoves).aspects(on: Date())

        // The whole card opens the next move and why; only the checks
        // inside it are their own buttons.
        NavigationLink(value: HomeRoute.nextMove) {
            SomaCard {
                VStack(alignment: .leading, spacing: metrics.cardHeaderSpacing) {
                    Text(today?.movesTitle ?? "Tonight")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .accessibilityAddTraits(.isHeader)
                    if let moves = today?.moves, !moves.isEmpty {
                        ForEach(moves) { move in
                            let words = move.words
                            SomaMoveRow(
                                aspect: move.aspect,
                                lead: words.lead,
                                title: words.hero,
                                reason: nil,
                                isDone: done.contains(move.aspect)
                            ) {
                                toggle(move)
                            }
                        }
                    } else {
                        Text("No moves yet")
                            .somaFont(type.callout)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityHint(Text("Opens the next move and why."))
    }

    private func toggle(_ move: PulseToday.Move) {
        var moves = PulseDoneMoves(stored: doneMoves)
        moves.toggle(move.aspect, on: Date())
        doneMoves = moves.stored
        // The engine hears it too, so the next read moves past it.
        if !move.moveID.isEmpty {
            NextMoveHistoryStore.shared.noteActed(
                move.moveID, moves.aspects(on: Date()).contains(move.aspect), at: NextMoveClock.now()
            )
        }
    }
}

/// The energy bank on Today: the charge cell with the level beside it and
/// the page's one line, then the day as a row of hours that filled or drew
/// down. It opens the energy page.
private struct PulseEnergyCard: View {
    let today: PulseToday?
    let scores: SomaScores?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let page = ScorePages.energy(scores)
        let day = EnergyDay(scores: scores, inputs: nil, page: page)
        let level = page.lead.value ?? today?.energyLevel.map { Int(($0 * 100).rounded()) }

        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                Text("Energy")
                    .somaFont(theme.typography.cardTitle)
                    .foregroundStyle(theme.colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                SomaEnergyGauge(level: level, line: page.lead.value == nil ? nil : page.lead.headline, size: .compact)
                if day.points.count > 1 {
                    SomaEnergyTimeline(points: day.points, now: day.now, ticks: [],
                                       charged: page.charged, drained: page.drained, size: .compact)
                }
            }
        }
    }
}

/// Last night on Today: the time asleep, one line, and the night in stages
/// as the hero. The score stays on the sleep page the card opens.
struct PulseSleepCard: View {
    let scores: SomaScores?

    var body: some View {
        let night = PulseSleepCard.night(scores)
        SomaNightCard(
            runs: night?.runs ?? [],
            asleep: night?.asleep,
            bed: night.map { ScoreMath.clock($0.bed) },
            wake: night.map { ScoreMath.clock($0.wake) },
            line: PulseSleepCard.line(scores),
            empty: "Stages draw here from a night your watch records."
        )
    }

    static func night(_ scores: SomaScores?) -> SleepNightSummary? {
        guard let detail = scores?.detail else { return nil }
        return SleepNightSummary.make(scoring: detail.lastNightStages, inBedStart: nil, parts: detail.sleepParts)
    }

    /// The sleep page's own headline, once there is a night to say it of.
    static func line(_ scores: SomaScores?) -> String? {
        let lead = ScorePages.sleep(scores, nil).lead
        return lead.value == nil ? nil : lead.headline
    }
}

private struct PulseDayCard: View {
    let today: PulseToday?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let spacing = theme.metrics.moveRowSpacing

        SomaCard {
            VStack(alignment: .leading, spacing: spacing) {
                SomaCardHeader("Today", caption: "So far")
                SomaTimeline(today?.events ?? [])
            }
        }
    }
}

/// One of Today's cards, as Edit Today orders them. The sleep card opens the
/// sleep page, the heart card its sheet, the day card the timeline.
private struct PulseTodayCardView: View {
    let card: HomeTodayCard
    let today: PulseToday?
    let scores: SomaScores?
    let insights: PulseInsights
    let open: (HomeSheetRoute) -> Void

    var body: some View {
        switch card {
        case .tonight:
            PulseMovesCard(today: today)
        case .energy:
            TileLink(value: ScoreRoute.energy) { PulseEnergyCard(today: today, scores: scores) }
        case .today:
            TileLink(value: HomeRoute.timeline) { PulseDayCard(today: today) }
        case .sleep:
            TileLink(value: TodayRoutes.nightCard) { PulseSleepCard(scores: scores) }
        case .heart:
            TileLink(value: TodayRoutes.aspectCard(.heart)) {
                SomaAspectCard(aspect: .heart, value: today?.heartCard.value, unit: "bpm resting",
                               summary: today?.heartCard.value == nil ? nil : insights[.restingHeartRate]?.insight.label) {
                    SomaBandLine(aspect: .heart, values: today?.restingDays ?? [], band: today?.restingBand)
                }
            }
        case .body:
            TileLink(value: TodayRoutes.aspectCard(.body)) {
                SomaAspectCard(aspect: .body, value: today?.bodyCard.value, unit: "fitness age",
                               summary: today?.bodyCard.summary) {
                    SomaRangeTrack(
                        aspect: .body,
                        range: 20...80,
                        estimate: nil,
                        reference: today?.age.map(Double.init),
                        referenceLabel: today?.age.map { "\($0)" }
                    )
                }
            }
        case .environment:
            TileLink(value: ScoreRoute.weather) { PulseAroundYouCard() }
        case .nutrition, .stand, .cycle:
            HomeTodayExtraCard(card: card, open: open)
        }
    }
}

/// The moves ticked off today, kept in one defaults string.
///
/// A tick belongs to its day: tomorrow's moves start unticked, however many
/// were ticked today.
struct PulseDoneMoves {
    static let key = "pulse.doneMoves"

    private(set) var day: String
    private(set) var aspects: Set<SomaAspect>

    init(stored: String) {
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        day = parts.first ?? ""
        aspects = Set((parts.count > 1 ? parts[1] : "").split(separator: ",").compactMap { SomaAspect(rawValue: String($0)) })
    }

    var stored: String {
        "\(day):" + aspects.map(\.rawValue).sorted().joined(separator: ",")
    }

    func aspects(on date: Date, calendar: Calendar = .current) -> Set<SomaAspect> {
        day == Self.stamp(date, calendar: calendar) ? aspects : []
    }

    mutating func toggle(_ aspect: SomaAspect, on date: Date, calendar: Calendar = .current) {
        let stamp = Self.stamp(date, calendar: calendar)
        if day != stamp {
            day = stamp
            aspects = []
        }
        if aspects.contains(aspect) { aspects.remove(aspect) } else { aspects.insert(aspect) }
    }

    static func stamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

/// Where each entry on Today opens: every aspect, wherever Today names it,
/// opens that aspect's own page (owner, 2026-10-20). The night card is the
/// one exception, by design: it opens last night, and the Sleep page
/// (the score's) links to it and back.
enum TodayRoutes {
    /// A score ring under the orb.
    static func ring(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// The orb, for the aspect it shows: the aspect's page, pushed plainly.
    static func orb(_ aspect: SomaAspect) -> PulseRoute { .orb(aspect) }
    /// An aspect card in Your aspects.
    static func aspectCard(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// A tile in Today's Categories grid.
    static func tile(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// A row of the six aspects in All categories.
    static func allCategories(_ aspect: SomaAspect) -> ScoreRoute { .aspect(aspect) }
    /// The last night card.
    static let nightCard = ScoreRoute.lastNight
}

/// The orb's one action, set for this moment of the person's day.
///
/// The engine's cue when the read found one, or the next move not ticked off
/// yet, or the calm default for this part of the day. Only before anything
/// was read does the clock decide: light and movement in the morning, a walk
/// at midday, a slower afternoon, winding down in the evening.
struct PulseNowAction: Equatable {
    var aspect: SomaAspect
    var label: LocalizedStringResource

    static func make(today: PulseToday?, done: Set<SomaAspect> = [], at date: Date, calendar: Calendar = .current) -> PulseNowAction {
        if let today, let cue = today.cue {
            let order = [cue] + today.moves + [today.steady].compactMap { $0 }
            let isSteady: (PulseToday.Move) -> Bool = { $0.moveID.hasPrefix("steady.") }
            if let move = order.first(where: { isSteady($0) || !done.contains($0.aspect) }) {
                return PulseNowAction(move)
            }
        }
        let aspect: SomaAspect = switch calendar.component(.hour, from: date) {
        case 5..<11: .body
        case 11..<15: .activity
        case 15..<19: .mind
        default: .sleep
        }
        return PulseNowAction(aspect: aspect, label: PulseWording.orbMove(aspect))
    }

    init(aspect: SomaAspect, label: LocalizedStringResource) {
        self.aspect = aspect
        self.label = label
    }

    init(_ move: PulseToday.Move) {
        aspect = move.aspect
        label = move.orb.isEmpty ? PulseWording.orbMove(move.aspect) : LocalizedStringResource(stringLiteral: move.orb)
    }
}

extension PulseToday.Move {
    /// A move with a time in it reads the time large: "In bed by 11:00 PM"
    /// is "In bed by" over "11:00 PM". Anything else is its own hero.
    var words: (lead: String?, hero: String) {
        guard let range = title.range(of: " by ", options: .backwards),
              title[range.upperBound...].contains(where: \.isNumber) else { return (nil, title) }
        return (String(title[..<range.lowerBound]) + " by", String(title[range.upperBound...]))
    }
}
