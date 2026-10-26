//
//  SleepTrendsPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring
import SomaWidgetKit

/// Sleep, the page the Sleep score opens, set after Apple Health's sleep
/// score and the reference design's sleep page: the night's score and its verdict, last
/// night as a tile that opens the night's own page, what tonight needs, the
/// night dip, then every sleep reading as a trend row against its usual
/// band. A row opens its sheet.
///
/// Last night keeps its own page (``SleepPage``): the owner asked for the
/// night and the trend apart, the night reached from here (2026-10-24).
struct SleepTrendsPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var inputs: ScoreDetailInputs?
    @State private var sheet: SleepPage.Sheet?
    @State private var windingDown = SomaLiveActivities.shared.isRunning(.windDown)

    var body: some View {
        let scores = health.scores
        let page = ScorePages.sleep(scores, inputs)
        let night = SleepNightSummary.make(scoring: page.stages, inBedStart: inputs?.inBedStart, parts: page.parts)
        let dip = ScorePages.nightDip(scores, inputs)

        ScorePageScaffold(aspect: .sleep, title: "Sleep") {
            ScoreGauge(aspect: .sleep, lead: page.lead)
            ScoreHead(page.lead)

            SleepLastNightTile(score: scores?.sleep, word: page.lead.word, night: night)

            ScoreLinks(links: [
                ScoreLink(title: "Tonight’s sleep needed",
                          detail: scores.map { SleepTrends.hm($0.sleepNeedHours) } ?? "-") { sheet = .debt },
            ])

            if let move = page.move {
                if SomaLiveActivities.shared.isAvailable {
                    ScoreMoveCard(move: move, aspect: .sleep,
                                  actionTitle: windingDown ? "Stop" : "Wind down") {
                        toggleWindDown(move, scores: scores)
                    }
                } else {
                    ScoreMoveCard(move: move, aspect: .sleep)
                }
            }

            if let dip, dip.today != nil {
                SleepDipCard(dip: dip) { sheet = .dip }
            }

            SleepTrendList(rows: SleepTrends.rows(scores: scores, inputs: inputs, dip: dip)) { target in
                switch target {
                case .history: sheet = .history
                case .debt: sheet = .debt
                case .dip: sheet = .dip
                case .breathing: sheet = .breathing
                case .night: break
                }
            }

            ScoreLinks(links: [
                ScoreLink(title: "Sleep environment", detail: page.sound ?? "-") { sheet = .environment },
                ScoreLink(title: "How your score is built") { sheet = .built },
            ])
        }
        .scoreInputs([.nights, .heart, .nightHeart, .breathing, .sound], into: $inputs)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .debt: SleepDebtSheet(scores: scores)
            case .dip: NightDipSheet(scores: scores, inputs: inputs)
            case .breathing: BreathingSheet(inputs: inputs)
            case .environment: SleepEnvironmentSheet(scores: scores, inputs: inputs)
            case .built: SleepBuiltSheet(score: scores?.sleep, parts: page.parts)
            case .history: ScoreHistorySheet(kind: .sleep, scores: scores)
            }
        }
    }
}

extension SleepTrendsPage {
    /// Puts the countdown to lights out on the lock screen and in the
    /// Dynamic Island, or takes it off. Lights out is the move's own time,
    /// half an hour after its reminder; the wake is the usual one.
    func toggleWindDown(_ move: ScorePages.Move, scores: SomaScores?, now: Date = Date()) {
        if windingDown {
            SomaLiveActivities.shared.end(.windDown)
            windingDown = false
            return
        }
        guard let remind = move.remindAt else { return }
        let detail = scores?.detail ?? SomaScores.Detail()
        let lightsOut = SleepTrends.next(hour: remind + 0.5, after: now)
        let wake = ScoreMath.median(detail.wakeHour.suffix(14)).map { SleepTrends.next(hour: $0, after: lightsOut) }
        SomaLiveActivities.shared.start(.windDown, SomaActivityCopy.windDown(now: now, lightsOut: lightsOut, wake: wake,
                                                                             need: scores?.sleepNeedHours))
        windingDown = true
    }
}

/// The night dip as the earlier app sets it: the percent and its band on the title
/// line, sleeping and resting heart rate under it, and one line on what it
/// means. Opens the dip sheet.
private struct SleepDipCard: View {
    let dip: ScorePages.NightDip
    let open: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let today = dip.today
        let colors = theme.colors

        Button(action: open) {
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                            Text("Night dip")
                                .somaFont(theme.typography.cardTitle)
                                .foregroundStyle(colors.inkPrimary.color)
                            Text(verbatim: today.map { $0.band.rawValue.capitalized } ?? "No reading")
                                .somaFont(theme.typography.caption)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: today.map { "\(Int($0.percent.rounded()))%" } ?? "-")
                            .somaFont(theme.typography.metric)
                            .foregroundStyle(today.map { $0.band == .healthy ? colors.statusNormal.color : colors.statusOut.color }
                                             ?? colors.inkSecondary.color)
                    }
                    SomaStatRow([
                        SomaStat("Sleeping HR", value: today.map { ScoreMath.number($0.meanSleepingHR) }, unit: "bpm"),
                        SomaStat("Resting HR", value: dip.restingHR.map { ScoreMath.number($0) }, unit: "bpm"),
                        SomaStat("Usual dip", value: dip.usualPercent.map { "\(Int($0.rounded()))%" }),
                    ])
                    Text(dip.headline)
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.somaGlassPress)
    }
}

/// Last night as a tile on the trends page, the way Apple's sleep card sets
/// it: the night's span, time in bed and asleep, and its stages small,
/// opening the night's own page.
private struct SleepLastNightTile: View {
    let score: Int?
    let word: String?
    let night: SleepNightSummary?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let metrics = theme.metrics
        let type = theme.typography
        let colors = theme.colors
        let calendar = Calendar.current

        TileLink(value: ScoreRoute.sleep) {
            SomaCard {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Last night")
                            .somaFont(type.cardTitle)
                            .foregroundStyle(colors.inkPrimary.color)
                        Spacer(minLength: 0)
                        if let night {
                            Text(verbatim: "\(ScoreMath.clock(night.bed, calendar: calendar)) to \(ScoreMath.clock(night.wake, calendar: calendar))")
                                .somaFont(type.captionValue)
                                .foregroundStyle(colors.inkSecondary.color)
                        }
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                    SomaSleepTotals(inBed: night?.inBed, asleep: night?.asleep)
                    if let night, !night.runs.isEmpty {
                        SomaHypnogram(runs: night.runs, laneHeight: 12, laneTitles: false)
                    }
                }
            }
        }
        .accessibilityLabel(Text("Last night"))
        .accessibilityValue(Text(score.map { "Score \($0)" } ?? "No score"))
    }
}
