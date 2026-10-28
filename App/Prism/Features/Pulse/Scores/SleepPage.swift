//
//  SleepPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// Last night set the way the earlier app's sleep sheet set it (owner,
/// 2026-10-27): the night full bleed at the head, then its title, its span,
/// the score's ring and the two totals; then the night read in a sentence,
/// its parts graded, its stages split, the time asleep against the need, and
/// the heart and the context through the night. What moved the score and
/// the move close the page. The long run is ``SleepTrendsPage``.
struct SleepPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var inputs: ScoreDetailInputs?
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case debt, dip, breathing, environment, built, history
        var id: String { rawValue }
    }

    var body: some View {
        let page = ScorePages.sleep(health.scores, inputs)
        let night = SleepNightSummary.make(scoring: page.stages, inBedStart: inputs?.inBedStart, parts: page.parts)
        let scale = Double(max(page.lead.scale, 1))

        ScorePageScaffold(aspect: .sleep, title: "Last night") {
            // The night's shape leads (owner, 2026-10-27), full bleed.
            SleepNightHypnogram(night: night)
                .padding(.top, theme.metrics.heroTopPadding)
                .somaColumnSpan(.full)

            SomaSleepHeadline(bed: night.map { ScoreMath.clock($0.bed) }, wake: night.map { ScoreMath.clock($0.wake) },
                              asleep: night?.asleep, inBed: night?.inBed,
                              score: page.lead.value.map { Double($0) / scale },
                              usual: page.lead.range.map { ($0.lowerBound / scale)...($0.upperBound / scale) })
                .somaColumnSpan(.full)

            SleepNightRead(lead: page.lead)

            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                    SomaCardHeader("Sleep quality")
                    SomaSleepGradeGrid(night?.grades ?? SleepNightSummary.grades([]))
                }
            }

            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.cardPadding) {
                    SomaCardHeader("Sleep stages")
                    SomaStageBreakdown(night?.stages ?? [:])
                }
            }

            SleepNeedCard(asleep: night?.asleep, needHours: health.scores?.sleepNeedHours)

            SleepNightFacts(night: night, dip: ScorePages.nightDip(health.scores, inputs), inputs: inputs,
                            parts: [.heart, .context])

            ScoreUsualCard(title: "What moved it", aspect: .sleep, lines: page.lines)
            if let move = page.move {
                ScoreMoveCard(move: move, aspect: .sleep)
            }
        }
        .scoreInputs([.nights, .heart, .nightHeart, .breathing, .sound], into: $inputs)
    }
}

/// What the night was, in a sentence, under the head: the earlier app's
/// night read, from the score's own headline and reason.
private struct SleepNightRead: View {
    let lead: ScorePages.Lead

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                Text("The night")
                    .somaFont(theme.typography.eyebrow)
                    .foregroundStyle(theme.colors.inkSecondary.color)
                ScoreParagraph(lead: lead.headline,
                               rest: [lead.reason, lead.aside ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The time asleep against the need, side by side, as the earlier app closed
/// its night: what you slept, and what you need.
private struct SleepNeedCard: View {
    let asleep: TimeInterval?
    let needHours: Double?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
                SomaCardHeader("Against your need")
                SomaStatRow([
                    SomaStat("Slept", value: SomaFormat.duration(asleep)),
                    SomaStat("Needed", value: SomaFormat.duration(needHours.map { $0 * 3600 })),
                ])
            }
        }
    }
}

/// Last night's time asleep, large, and one sentence against your need.
private struct SleepLead: View {
    let asleepHours: Double?
    let needHours: Double?
    let night: SleepNightSummary?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        VStack(alignment: .leading, spacing: theme.metrics.cardHeaderSpacing) {
            Text("Last night")
                .somaFont(type.callout)
                .foregroundStyle(colors.inkSecondary.color)
            SomaNumber(asleepHours.map { TodayFormat.duration(seconds: $0 * 3600) }, type.metric)
                .foregroundStyle(colors.inkPrimary.color)
            Text(sentence)
                .somaFont(type.body)
                .foregroundStyle(colors.inkSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, theme.metrics.cardSpacing)
        .accessibilityElement(children: .combine)
    }

    private var sentence: String {
        guard let asleepHours else {
            return "No sleep was recorded last night. Wear your Apple Watch to bed with at least 30% battery."
        }
        var words = ""
        if let night {
            words = "Asleep from \(ScoreMath.clock(night.bed)) to \(ScoreMath.clock(night.wake)). "
        }
        guard let needHours else { return words }
        let gap = (needHours - asleepHours) * 3600
        let need = TodayFormat.duration(seconds: needHours * 3600)
        if abs(gap) < 5 * 60 { return words + "That meets the \(need) you need." }
        return words + "That is \(TodayFormat.span(seconds: abs(gap))) \(gap > 0 ? "under" : "over") the \(need) you need."
    }
}

/// When to be in bed tonight, from your usual waking time and your need, and
/// the one reminder this page can set. Notifications are asked for here, the
/// first time someone taps it, never before.
private struct SleepTonightCard: View {
    let day: ScoringPeakDay
    let needHours: Double?

    @Environment(\.somaTheme) private var theme
    @State private var reminded: Bool?

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let today = Calendar.current.startOfDay(for: .now)
        let bed = today.addingTimeInterval((day.bedHour < 12 ? day.bedHour + 24 : day.bedHour) * 3600)
        let windDown = today.addingTimeInterval((day.windDownHour < 12 ? day.windDownHour + 24 : day.windDownHour) * 3600)
        let wake = TodayFormat.clock(hour: day.wakeHour, on: .now, calendar: .current)

        ScoreSection(title: "Tonight") {
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                    Text(needHours.map { "Be in bed by \(bed.formatted(date: .omitted, time: .shortened)) to get your \(TodayFormat.duration(seconds: $0 * 3600))." }
                         ?? "Be in bed by \(bed.formatted(date: .omitted, time: .shortened)).")
                        .somaFont(type.title)
                        .foregroundStyle(colors.inkPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You usually wake at \(wake). A reminder at \(windDown.formatted(date: .omitted, time: .shortened)) leaves time to wind down.")
                        .somaFont(type.callout)
                        .foregroundStyle(colors.inkSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            reminded = await ToolNotifier.remind(
                                id: "sleep.windDown",
                                title: String(localized: "Time to wind down"),
                                body: String(localized: "In bed by \(bed.formatted(date: .omitted, time: .shortened)) gets you the sleep you need."),
                                at: windDown
                            )
                        }
                    } label: {
                        Text(reminded == true ? "Reminder set for \(windDown.formatted(date: .omitted, time: .shortened))"
                             : "Remind me at \(windDown.formatted(date: .omitted, time: .shortened))")
                            .somaFont(type.headerTitle)
                            .foregroundStyle(colors.onAccent.color)
                            .frame(maxWidth: .infinity, minHeight: theme.metrics.minimumTapTarget + theme.metrics.cardHeaderSpacing)
                            .background(Capsule().fill(colors.accent.color))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.somaGlassPress)
                    .disabled(reminded == true)
                    .sensoryFeedback(.success, trigger: reminded == true)
                    if reminded == false {
                        Text("Notifications are off for Soma, or the time has passed. You can turn them on in Settings.")
                            .somaFont(type.caption)
                            .foregroundStyle(colors.inkSecondary.color)
                    }
                }
            }
        }
    }
}

// MARK: - Sleep debt

struct SleepDebtSheet: View {
    let scores: SomaScores?

    @State private var nights = 7
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let debt = ScorePages.debt(scores)
        let detail = scores?.detail ?? SomaScores.Detail()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let count = min(nights, detail.sleepHours.count)
        let columns: [ScoreStageColumns.Night] = (0..<count).map { offset in
            let index = detail.sleepHours.count - count + offset
            let asleep = detail.sleepHours[index]
            let deep = detail.deepHours.indices.contains(index) ? detail.deepHours[index] : nil
            let rem = detail.remHours.indices.contains(index) ? detail.remHours[index] : nil
            let core = asleep.map { max(0, $0 - (deep ?? 0) - (rem ?? 0)) }
            let day = calendar.date(byAdding: .day, value: offset - count + 1, to: today) ?? today
            return .init(id: offset, label: day.formatted(.dateTime.weekday(.abbreviated)), deep: deep, core: core, rem: rem)
        }
        let average = ScoreMath.mean(detail.sleepHours.suffix(nights))

        ScoreSheet(eyebrow: "Sleep · Debt", title: "Sleep debt") {
            ScoreFigure(value: debt.value, unit: "over 14 nights")
            ScoreParagraph(lead: debt.headline, rest: debt.reason)
            SomaSegmentedControl(segments: [SomaSegment(id: 7, title: "7 nights"), SomaSegment(id: 30, title: "30 nights"),
                                            SomaSegment(id: 90, title: "90 nights")], selection: $nights)
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Asleep against your need")
                        .somaFont(theme.typography.eyebrow)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    ScoreFigure(value: average.map(ScoreMath.hoursMinutes), unit: "a night, on average")
                    ScoreStageColumns(nights: columns, need: scores?.sleepNeedHours ?? 8, aspect: .sleep)
                }
            }
            ScoreTrendCard(caption: "Last night included", rows: debt.rows,
                           note: "Each row compares the week’s debt now with the week’s debt then.")
            ScoreAbout(lead: "What 14 nights fell short of your need.",
                       rest: "Your need, \(debt.need), is your own nights pulled toward eight hours. A long night pays some back.",
                       symbol: "hourglass", hue: .sleep)
        }
    }
}

// MARK: - Night dip

struct NightDipSheet: View {
    let scores: SomaScores?
    let inputs: ScoreDetailInputs?

    @Environment(JournalStore.self) private var journal
    @Environment(\.somaTheme) private var theme

    var body: some View {
        let dip = ScorePages.nightDip(scores, inputs)
        let today = dip?.today
        let beats = inputs?.lastNightBeats ?? []
        let night = inputs?.nights.last ?? nil
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let logged = journal.day(yesterday).tags

        ScoreSheet(eyebrow: "Sleep · Heart", title: "Night dip") {
            ScoreFigure(value: today.map { "\(Int($0.percent.rounded()))%" },
                        unit: today.map { $0.band.rawValue } ?? "no reading")
            ScoreParagraph(lead: dip?.headline ?? "Night dip needs your watch at night.",
                           rest: dip?.reason ?? "It sets your sleeping heart rate against your resting baseline.")
            ScoreStats(stats: [
                SomaStat("Asleep bpm", value: today.map { ScoreMath.number($0.meanSleepingHR) }),
                SomaStat("Resting bpm", value: dip?.restingHR.map { ScoreMath.number($0) }),
                SomaStat("Usual dip", value: dip?.usualPercent.map { "\(Int($0.rounded()))%" }),
            ])
            SomaChartCard(eyebrow: "Sleeping heart rate", value: today.map { ScoreMath.number($0.lowest) }, unit: "bpm lowest",
                          note: today.map { "Reached at \(ScoreMath.clock($0.lowestAt))." } ?? "Your watch’s heart readings through the night draw here.") {
                if let night, beats.count >= 2 {
                    let values = beats.map(\.value)
                    let low = (values.min() ?? 40) - 3, high = (values.max() ?? 80) + 3
                    let span = max(1, night.end.timeIntervalSince(night.start))
                    ScoreDayLine(points: beats.map { ($0.start.timeIntervalSince(night.start) / span, $0.value) },
                                 aspect: .heart, range: low...high,
                                 labels: [ScoreMath.clock(night.start), ScoreMath.clock(night.end)],
                                 marker: today.map { ($0.lowestAt.timeIntervalSince(night.start) / span, $0.lowest) })
                } else {
                    ScoreEmptyPlot(message: "No heart readings last night.")
                }
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(today.map { "Where \(Int($0.percent.rounded()))% sits" } ?? "The bands")
                        .somaFont(theme.typography.cardTitle).foregroundStyle(theme.colors.inkPrimary.color)
                    ScoreBandBar(bands: [.init(title: "Flat", detail: "under 5%"), .init(title: "Shallow", detail: "5 to 10%"),
                                         .init(title: "Healthy", detail: "10 to 20%"), .init(title: "Deep", detail: "over 20%")],
                                 aspect: .heart, position: today.map { min(1, max(0, $0.percent / 25)) },
                                 label: today.map { "Last night, \(Int($0.percent.rounded()))%" },
                                 usual: dip?.usualPercent.map { min(1, max(0, $0 / 25)) })
                    if let usual = dip?.usualPercent {
                        ScoreFootnote(text: "The ring marks your usual, \(Int(usual.rounded()))%.")
                    }
                }
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 8) {
                    SomaCardHeader("Last 14 nights", caption: "Dip each night")
                    if let nights = dip?.nights, nights.contains(where: { $0 != nil }) {
                        ScoreDayBars(values: nights.map { $0.map { max(0, $0) } }, aspect: .heart, band: 10...20,
                                     ceiling: 25, labels: ["14 nights ago", "Last night"])
                    } else {
                        ScoreEmptyPlot(message: "Nights draw here once your watch records heart rate while you sleep.")
                    }
                }
            }
            SomaCard {
                VStack(alignment: .leading, spacing: 0) {
                    SomaCardHeader("The usual causes, checked", caption: "Last night")
                    ScoreRows((dip?.causes ?? []) + [
                        journalLine("Late meal", logged.contains("late-meal")),
                        journalLine("Alcohol", logged.contains("alcohol")),
                    ]) { line in
                        ScoreUsualRow(line: line, aspect: .heart)
                    }
                }
            }
            ScoreAbout(lead: "Sleeping heart rate against resting.",
                       rest: "10 to 20 percent lower is healthy. Alcohol, a late meal, heat, illness or hard training flatten it.",
                       symbol: "heart.fill", hue: .heart)
        }
    }

    private func journalLine(_ title: String, _ logged: Bool) -> ScoreMath.UsualLine {
        ScoreMath.UsualLine(title: title, detail: logged ? "logged in your Journal" : "nothing logged in your Journal",
                            value: logged ? "Yes" : nil, position: nil, band: nil, isOff: logged)
    }
}

// MARK: - Breathing

struct BreathingSheet: View {
    let inputs: ScoreDetailInputs?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let page = ScorePages.breathing(inputs)

        ScoreSheet(eyebrow: "Sleep · Breathing", title: "Breathing rate") {
            ScoreFigure(value: page.value.map { ScoreMath.number($0, decimals: 1) }, unit: "breaths a minute, asleep")
            ScoreParagraph(lead: page.headline,
                           rest: page.usual.map { "Your usual is \(ScoreMath.number($0.low, decimals: 1)) to \(ScoreMath.number($0.high, decimals: 1)). " + page.reason } ?? page.reason)
            SomaCard {
                VStack(alignment: .leading, spacing: theme.metrics.spaceM) {
                    Text("Overnight signals")
                        .somaFont(theme.typography.eyebrow)
                        .foregroundStyle(theme.colors.inkSecondary.color)
                    ScoreFigure(value: "\(page.inRange) of \(page.signals.count)", unit: "in range")
                    ForEach(page.signals) { signal in
                        ScoreSparkRow(title: signal.title, values: signal.values, usual: signal.usual,
                                      latest: signal.latest, aspect: signal.title == "Breathing" ? .sleep : .mind,
                                      isOff: signal.inRange == false)
                    }
                }
            }
            ScoreTrendCard(caption: "Last night included", rows: page.rows,
                           note: "Breaths a minute. Each row compares 7 night averages.")
            ScoreAbout(lead: "Counted asleep, from your heartbeat’s rhythm.",
                       rest: "It holds steady, so one breath a minute is a real shift.",
                       symbol: "lungs.fill", hue: .respiratory)
        }
    }
}
