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
/// hold the leading column and the cards the trailing one. The room is the
/// page's own width, never the device.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The last read, so a return from a pushed page draws at once.
    @State private var insights = PulseInsightsCache.shared.value
    /// Whether the page is wide enough to set the orb beside the cards: read
    /// off the page's own width, so an iPhone on its side, an unfolded
    /// foldable and a resized window each answer for the room they have.
    @State private var widthClass = SomaWidthClass.compact

    var body: some View {
        let metrics = theme.metrics
        let canvas = theme.colors.canvas.color

        SomaPageScroll {
            // One layout that changes shape rather than two branches, so the
            // orb and the cards keep their state when the width crosses the
            // line (a foldable opening, a window resized).
            let roomy = widthClass == .regular
            let layout = roomy
                ? AnyLayout(HStackLayout(alignment: .top, spacing: metrics.leadSpacing))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.browseSectionSpacing))
            layout {
                lead.frame(maxWidth: roomy ? metrics.orbDiameter * 2 : .infinity)
                    // The last launch's numbers are on screen while the first
                    // read of this one runs: a quiet pill in the space above
                    // the orb says so, and leaves when they land.
                    .overlay(alignment: .top) {
                        if health.isShowingCache {
                            SomaUpdatingPill(since: health.cachedAt)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .animation(reduceMotion ? theme.motion.fade : theme.motion.quick, value: health.isShowingCache)
                PulseCards(today: health.today, status: health.status, scores: health.scores, insights: insights)
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.pagePadding)
            .frame(maxWidth: metrics.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
        .somaWidthClass($widthClass)
        .background(canvas.ignoresSafeArea())
        .somaRefreshable {
            await health.loadToday(force: true)
            await readInsights(force: true)
        }
        .task {
            await health.loadToday()
            await readInsights(force: false)
        }
    }

    private var lead: PulseLead {
        PulseLead(today: health.today, status: health.status, scores: health.scores, moved: insights.moved)
    }

    /// Reads what moved, unless the last read is fresh.
    ///
    /// `.task` runs again each time the page comes back into view, and that
    /// is the end of every zoom back out of a tile: the read is ninety days
    /// of every Body reading, worked out on the main actor, and it landed on
    /// the last frames of the zoom. A pull to refresh reads again.
    private func readInsights(force: Bool) async {
        let cache = PulseInsightsCache.shared
        if !force, cache.isFresh() {
            if cache.value != insights { insights = cache.value }
            return
        }
        guard let read = await PulseInsights.read(health: health, now: .now, calendar: .current) else { return }
        cache.store(read)
        if read != insights { insights = read }
    }

}

/// The last read of what moved, kept for the life of the app under the
/// score pages' rule (``ScoreInputsCache``): drawn at once, read again only
/// once it is older than ``freshFor`` or on a pull to refresh.
@MainActor
final class PulseInsightsCache {
    static let shared = PulseInsightsCache()

    static let freshFor: TimeInterval = ScoreInputsCache.freshFor

    private(set) var value = PulseInsights.empty
    private var readAt: Date?

    func isFresh(now: Date = Date()) -> Bool {
        guard let readAt else { return false }
        return now.timeIntervalSince(readAt) < Self.freshFor
    }

    func store(_ insights: PulseInsights, now: Date = Date()) {
        value = insights
        readAt = now
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
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(AppRouter.self) private var router
    /// The quick add, lifted by a long press on the orb.
    @State private var quickAdd: HomeSheetRoute?

    var body: some View {
        let metrics = theme.metrics

        VStack(alignment: .leading, spacing: 0) {
            // One orb, one action: the move that matters now, never a carousel
            // to swipe through (owner, 2026-10-03). It presses on touch down
            // and opens that move's page as the finger lifts, zooming out of
            // the orb; a long press lifts the quick add over Today instead.
            let now = PulseNowAction.make(moves: today?.moves ?? [], at: Date())
            SomaOrb(aspect: now.aspect, label: now.label)
                .frame(maxWidth: .infinity)
                .padding(.top, metrics.heroTopPadding)
                .somaOrbTap(aspect: now.aspect, longPress: { quickAdd = .quickAdd }) {
                    open(ScoreRoute.aspect(now.aspect))
                }
                .zoomSource(ScoreRoute.aspect(now.aspect))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(now.label))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open(ScoreRoute.aspect(now.aspect)) }
                .accessibilityAction(named: "Add to today") { quickAdd = .quickAdd }
                .homeSheets($quickAdd)

            // One tap on a score opens its page, zooming out of its dial.
            SomaScoreZones(scoreRow, zoom: zoomNamespace, zoomID: { AnyHashable(ScoreRoute.aspect($0)) }) { tapped in
                open(ScoreRoute.aspect(tapped))
            }
                .padding(.top, metrics.heroSpacing * 2)

            // A meeting coming up that tends to run tense, a day ahead.
            PulseMeetingHeadsUp()
                .padding(.top, metrics.leadSpacing)

            PulseMovedSection(items: moved)
                .padding(.top, metrics.leadSpacing)

            // Words only when there is no data to show instead.
            if case .ready = status {} else if today == nil {
                PulseHeadline(status: status, today: today)
                    .padding(.top, metrics.leadSpacing)
            }

        }
    }

    /// Pushes a score page onto Pulse's own stack. A destination presented
    /// from a binding sat over the stack instead, so a link inside it (Last
    /// night, from Sleep) pushed under it and Sleep came back on top: a loop
    /// (owner, 2026-10-24).
    private func open(_ route: ScoreRoute?) {
        guard let route else { return }
        router.pulsePath.append(route)
    }

    private var scoreRow: [SomaRingScore] {
        [
            ring(.sleep, scores?.sleep, today?.sleep.trend, PulseScoreInsights.sleep(scores)),
            ring(.mind, scores?.mind, today?.mind.trend, PulseScoreInsights.mind(scores)),
            ring(.activity, scores?.strain, today?.activity.trend, PulseScoreInsights.activity(scores),
                 // Activity's range is the strain today's recovery supports,
                 // and the person's usual until there is one.
                 range: scores?.strainTarget.map { Double($0.lowerBound)...Double($0.upperBound) }),
        ]
    }

    /// A score as a dial; its cue against its usual is read aloud, not printed.
    /// The dial's range arc spans the usual band unless a range is given.
    private func ring(
        _ aspect: SomaAspect, _ value: Int?, _ trend: SomaTrend?, _ insight: Insight,
        range: ClosedRange<Double>? = nil
    ) -> SomaRingScore {
        SomaRingScore(
            aspect: aspect,
            value: value,
            trend: trend,
            cue: insight.label.map { LocalizedStringResource(stringLiteral: $0) },
            range: range ?? insight.band
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

        // One column beside the orb or on a phone, two where the cards have
        // the width to themselves (the inner screen of a foldable).
        SomaCardColumns {
            OnboardingFirstWeekCard()

            ForEach(shown) { card in
                if card == firstAspect {
                    Text("Your aspects")
                        .somaFont(type.title)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, metrics.browseSectionSpacing - metrics.cardSpacing)
                        .somaColumnSpan(.full)
                }
                PulseTodayCardView(card: card, today: today, scores: scores, insights: insights) { sheet = $0 }
            }

            HomeTodayFoot { sheet = $0 }
                .padding(.top, metrics.browseSectionSpacing - metrics.cardSpacing)
                .somaColumnSpan(.full)

            if status != .ready {
                HealthStatusCard()
                    .somaColumnSpan(.full)
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
                                toggle(move.aspect)
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
        .zoomSource(HomeRoute.nextMove)
        .buttonStyle(.somaGlassPress)
        .accessibilityHint(Text("Opens the next move and why."))
    }

    private func toggle(_ aspect: SomaAspect) {
        var moves = PulseDoneMoves(stored: doneMoves)
        moves.toggle(aspect, on: Date())
        doneMoves = moves.stored
    }
}

/// The energy bank, set like the other cards: the number with "of 100", one
/// slim track filled to the level in one colour, and today's line.
private struct PulseEnergyCard: View {
    let today: PulseToday?
    let scores: SomaScores?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let metrics = theme.metrics
        let level = today?.energyLevel
        let curve = (scores?.energyCurve ?? []).sorted { $0.date < $1.date }.map { Optional($0.level) }
        // One colour for where the level sits, worn by the line and the
        // track alike.
        let tint: Color = switch level ?? 1 {
        case ..<0.34: colors.statusAlert.color
        case ..<0.67: colors.statusOut.color
        default: colors.statusNormal.color
        }

        SomaCard {
            VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                Text("Energy")
                    .somaFont(type.cardTitle)
                    .foregroundStyle(colors.inkPrimary.color)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .bottom, spacing: metrics.cardSpacing) {
                    SomaNumber(level.map { "\(Int(($0 * 100).rounded()))" }, type.metric,
                               unit: String(localized: "of 100"), unitSpec: type.callout)
                        .foregroundStyle(colors.inkPrimary.color)
                        .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    if curve.count > 1 {
                        SomaSparkline(curve, tint: tint, filled: false)
                            .frame(width: metrics.chartSparkHeight * 3, height: metrics.chartSparkHeight)
                    }
                }

                // The track: a slim capsule filled to the level in one flat
                // colour, the level's own.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.surfaceRecessed.color)
                        if let level {
                            Capsule()
                                .fill(tint)
                                .frame(width: max(metrics.sleepGradeBarHeight * 1.5, proxy.size.width * min(1, max(0, level))))
                        }
                    }
                }
                .frame(height: metrics.sleepGradeBarHeight * 1.5)
                .accessibilityHidden(true)
            }
        }
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

/// One of Today's cards, as Edit Today orders them. The sleep and heart cards
/// open their sheets; the day card opens the timeline.
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
            Button { open(.lastNight) } label: {
                SomaAspectCard(aspect: .sleep, value: today?.sleepCard.value, unit: "asleep",
                               summary: today?.sleepCard.value == nil ? nil : insights[.sleepDuration]?.insight.label) {
                    SomaNightBars(aspect: .sleep, values: today?.nights ?? Array(repeating: nil, count: 7))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.somaGlassPress)
        case .heart:
            Button { open(.marker(.restingHeartRate)) } label: {
                SomaAspectCard(aspect: .heart, value: today?.heartCard.value, unit: "bpm resting",
                               summary: today?.heartCard.value == nil ? nil : insights[.restingHeartRate]?.insight.label) {
                    SomaBandLine(aspect: .heart, values: today?.restingDays ?? [], band: today?.restingBand)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.somaGlassPress)
        case .body:
            TileLink(value: PulseRoute.aspect(.body)) {
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

/// The orb's one action, set for this moment of the day.
///
/// The day's first move when the read found one (they arrive already ranked
/// by what matters most now). Without one, the hour decides: light and
/// movement in the morning, a walk at midday, a slower afternoon, winding
/// down in the evening.
struct PulseNowAction: Equatable {
    var aspect: SomaAspect
    var label: LocalizedStringResource

    static func make(moves: [PulseToday.Move], at date: Date, calendar: Calendar = .current) -> PulseNowAction {
        if let first = moves.first {
            return PulseNowAction(aspect: first.aspect, label: PulseWording.orbMove(first.aspect))
        }
        let aspect: SomaAspect = switch calendar.component(.hour, from: date) {
        case 5..<11: .body
        case 11..<15: .activity
        case 15..<19: .mind
        default: .sleep
        }
        return PulseNowAction(aspect: aspect, label: PulseWording.orbMove(aspect))
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
