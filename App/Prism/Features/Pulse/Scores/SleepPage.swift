//
//  SleepPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthScoring

/// Sleep, the score's page: the score with its ring, a month of nights
/// against the usual, last night as a card that opens its own page, the
/// averages of the last week against the month, how regular the nights
/// were, what moved the score, and the readings behind it.
///
/// Everything about one night lives on ``LastNightPage``; this page reads
/// sleep over time (owner, 2026-10-20: two sleep pages). The score and the
/// night card each open one, and each links to the other.
struct SleepPage: View {
    @Environment(HealthDashboard.self) private var health
    @State private var inputs: ScoreDetailInputs?
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case debt, built
        var id: String { rawValue }
    }

    var body: some View {
        let scores = health.scores
        let page = ScorePages.sleep(scores, inputs)
        let detail = scores?.detail ?? SomaScores.Detail()

        ScorePageScaffold(aspect: .sleep, title: "Sleep") {
            ScoreStage(aspect: .sleep, lead: page.lead, series: scores?.sleepSeries ?? [], caption: "Last night")
            ScoreHead(page.lead)
            TileLink(value: ScoreRoute.lastNight) { PulseSleepCard(scores: scores) }
                .accessibilityHint(Text("Opens last night"))
            SleepAveragesCard(averages: SleepAverages.make(detail))
            SleepRhythmCard(nights: SleepAverages.windows(detail, nights: 14, calendar: .current),
                            note: SleepAverages.rhythmNote(detail))
            ScoreUsualCard(title: "What moved it", aspect: .sleep, lines: page.lines)
            ScoreLinks(links: [
                ScoreLink(title: "Sleep debt", detail: page.debt ?? "-") { sheet = .debt },
                ScoreLink(title: "How your score is built") { sheet = .built },
            ])
            if let move = page.move {
                ScoreMoveCard(move: move, aspect: .sleep)
            }
            AspectReadings(aspect: .sleep, identifiers: AspectReadingKind.sleepReadings, category: .aspect(.sleep))
        }
        .scoreInputs([.nights, .heart, .nightHeart, .breathing, .sound], into: $inputs)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .debt: SleepDebtSheet(scores: health.scores)
            case .built: SleepBuiltSheet(score: health.scores?.sleep, parts: page.parts)
            }
        }
    }
}

/// The nights in numbers: the last seven against the thirty, and the
/// windows they were slept in.
enum SleepAverages {
    struct Row: Identifiable, Equatable {
        var id: String { title }
        var title: String
        var week: String?
        var month: String?
    }

    /// Asleep, deep and REM as durations; bedtime and waking as clock times.
    static func make(_ detail: SomaScores.Detail) -> [Row] {
        func hours(_ values: [Double?]) -> (String?, String?) {
            (ScoreMath.mean(values.suffix(7)).map(ScoreMath.hoursMinutes),
             ScoreMath.mean(values.suffix(30)).map(ScoreMath.hoursMinutes))
        }
        func clock(_ values: [Double?]) -> (String?, String?) {
            (circularMean(values.suffix(7)).map(ScoreMath.clock), circularMean(values.suffix(30)).map(ScoreMath.clock))
        }
        let asleep = hours(detail.sleepHours)
        let deep = hours(detail.deepHours)
        let rem = hours(detail.remHours)
        let bed = clock(detail.bedHour)
        let wake = clock(detail.wakeHour)
        return [
            Row(title: "Asleep", week: asleep.0, month: asleep.1),
            Row(title: "Deep", week: deep.0, month: deep.1),
            Row(title: "REM", week: rem.0, month: rem.1),
            Row(title: "Bedtime", week: bed.0, month: bed.1),
            Row(title: "Woke up", week: wake.0, month: wake.1),
        ]
    }

    /// The last `nights` windows, oldest first, labelled by weekday letter.
    static func windows(_ detail: SomaScores.Detail, nights: Int, calendar: Calendar, now: Date = Date()) -> [SomaSleepWindow] {
        let beds = Array(detail.bedHour.suffix(nights))
        let wakes = Array(detail.wakeHour.suffix(nights))
        let count = min(beds.count, wakes.count)
        let today = calendar.startOfDay(for: now)
        var style = Date.FormatStyle.dateTime.weekday(.narrow)
        style.timeZone = calendar.timeZone
        return (0..<count).map { index in
            let day = calendar.date(byAdding: .day, value: index - count + 1, to: today) ?? today
            return SomaSleepWindow(id: index, label: day.formatted(style), bed: beds[index], wake: wakes[index])
        }
    }

    /// One plain line on how steady the bedtimes were over a fortnight:
    /// how far a usual night strays from the middle bedtime.
    static func rhythmNote(_ detail: SomaScores.Detail) -> String? {
        let beds = detail.bedHour.suffix(14).compactMap { $0 }.map(SomaSleepWindowClock.pastNoon)
        guard beds.count >= 5 else { return nil }
        let sorted = beds.sorted()
        let middle = sorted[sorted.count / 2]
        let strays = beds.map { abs($0 - middle) }.sorted()
        let typical = strays[strays.count / 2] * 60
        let minutes = max(5, Int((typical / 5).rounded()) * 5)
        return minutes <= 30
            ? "Bedtime within \(minutes) min on most nights"
            : "Bedtime moves about \(minutes) min from night to night"
    }

    /// The mean of clock hours across midnight: 23:30 and 00:30 average to
    /// midnight, not to noon.
    static func circularMean(_ hours: ArraySlice<Double?>) -> Double? {
        let known = hours.compactMap { $0 }
        guard !known.isEmpty else { return nil }
        let past = known.map(SomaSleepWindowClock.pastNoon)
        let mean = past.reduce(0, +) / Double(past.count)
        return (mean + 12).truncatingRemainder(dividingBy: 24)
    }
}

/// Clock hours as hours past noon, so a night reads in one run.
enum SomaSleepWindowClock {
    static func pastNoon(_ hour: Double) -> Double {
        let h = hour.truncatingRemainder(dividingBy: 24)
        let wrapped = h < 0 ? h + 24 : h
        return wrapped >= 12 ? wrapped - 12 : wrapped + 12
    }
}

/// The last week against the month: one row per average, the week's value
/// in the ink and the month's beside it in the secondary.
private struct SleepAveragesCard: View {
    let averages: [SleepAverages.Row]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors

        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SomaCardHeader("Averages", caption: "Last 7 nights")
                    Spacer()
                    Text("30 nights")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .frame(width: theme.metrics.bodyRowValueWidth, alignment: .trailing)
                }
                ScoreRows(averages) { row in
                    HStack {
                        Text(row.title)
                            .somaFont(type.body)
                            .foregroundStyle(colors.inkPrimary.color)
                        Spacer()
                        Text(row.week ?? "-")
                            .somaFont(type.rowValue)
                            .foregroundStyle(colors.inkPrimary.color)
                        Text(row.month ?? "-")
                            .somaFont(type.rowValue)
                            .foregroundStyle(colors.inkSecondary.color)
                            .frame(width: theme.metrics.bodyRowValueWidth, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// How regular the nights were: a fortnight of windows and one line.
private struct SleepRhythmCard: View {
    let nights: [SomaSleepWindow]
    let note: String?

    @Environment(\.somaTheme) private var theme

    var body: some View {
        SomaCard {
            VStack(alignment: .leading, spacing: theme.metrics.cardSpacing) {
                SomaCardHeader("Rhythm", caption: "Last 14 nights")
                if nights.contains(where: { $0.bed != nil }) {
                    SomaSleepWindows(nights)
                } else {
                    ScoreEmptyPlot(message: "Your nights line up here after a few of them.")
                }
                if let note {
                    Text(note)
                        .somaFont(theme.typography.callout)
                        .foregroundStyle(theme.colors.inkSecondary.color)
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
                        .somaFont(theme.typography.eyebrow).textCase(.uppercase)
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overnight signals")
                        .somaFont(theme.typography.eyebrow).textCase(.uppercase)
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
