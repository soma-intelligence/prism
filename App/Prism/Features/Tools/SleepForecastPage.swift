//
//  SleepForecastPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Sleep Forecast: tonight's sleep score before the night starts, what can
/// still move it, and last night checked against its forecast.
///
/// The sleep forecast engine: tonight's duration and stages projected from
/// the recent nights, then pulled by the levers still in play (caffeine on
/// board at bedtime, timing irregularity, a low HRV, carried debt), each
/// capped so no single lever can claim more than its share.
struct SleepForecastPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    private var model: ToolsModel { .shared }
    private var store: ToolsStore { .shared }

    var body: some View {
        let day = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
        let forecast = SleepForecastReading.make(day: day, scores: health.scores)
        let last = day.inputs.lastNight(calendar: day.calendar)

        ToolPage(ToolKind.sleepForecast.title) {
            ToolGauge(aspect: .sleep, fraction: forecast.map { Double($0.score) / 100 }, display: forecast.map { "\($0.score)" },
                      state: forecast == nil ? "\(day.nightCount) of 7 nights" : "Tonight’s forecast",
                      delta: forecast.flatMap { f in f.lastNightScore.map { deltaLine(f.score - $0) } },
                      deltaIsWorse: forecast.flatMap { f in f.lastNightScore.map { f.score < $0 } } ?? false)

            if let forecast {
                ToolHero(headline: headline(forecast),
                         lead: forecast.leadLine,
                         rest: forecast.leverTotal > 0 ? "Together what still moves is worth about \(forecast.leverTotal) points." : nil)
                ToolStats([
                    SomaStat("Asleep", value: forecast.hours.map { ToolFormat.hoursMinutes($0) }),
                    SomaStat("Deep", value: forecast.deep.map { ToolFormat.hoursMinutes($0) }),
                    SomaStat("REM", value: forecast.rem.map { ToolFormat.hoursMinutes($0) }),
                ])
                ToolRowsCard(title: "What still moves tonight", eyebrow: "Against your usual", aspect: .sleep, rows: forecast.rows)
            } else {
                ToolHero(headline: "The forecast needs a week of nights.",
                         lead: "It learns your usual from seven recorded nights before it predicts one.",
                         rest: "\(day.nightCount) recorded so far.")
            }

            let week = Array(day.inputs.nights.suffix(7))
            SomaChartCard(eyebrow: "Last seven nights", value: last.map { ToolFormat.hoursMinutes($0.asleep) }, unit: "last night",
                          note: last.map { "Deep \(Int(($0.deep * 60).rounded())) min, REM \(Int(($0.rem * 60).rounded())) min." }
                            ?? "No night recorded since yesterday.") {
                ToolStackedBars(aspect: .sleep, bars: week.map { night in
                    ToolStackedBars.Bar(label: night.wakeDay.formatted(.dateTime.weekday(.abbreviated)),
                                        parts: [night.deep, night.core, night.rem, night.awake])
                }, top: 10, target: 7...8)
            }

            if let check = forecast?.check {
                ToolNoteCard(title: "Last night, checked", lead: check.lead, rest: check.rest)
            }
            ToolFootnote("An estimate, not medical advice.")
            ToolLinkRow(title: "About Sleep Forecast", detail: nil, value: ToolRoute.intro(.sleepForecast))
        }
        .task {
            store.markOpened(.sleepForecast)
            await model.load(health)
            let now = ToolDay(inputs: model.current, cups: TrackLogStore.shared.caffeineCups, sleepNeedHours: health.scores?.sleepNeedHours)
            if let score = SleepForecastReading.make(day: now, scores: health.scores)?.score,
               let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now.inputs.now) {
                store.update { $0.forecasts[ToolsStore.stamp(tomorrow)] = score }
            }
        }
    }

    private func deltaLine(_ delta: Int) -> String {
        delta == 0 ? "Level with last night" : "\(abs(delta)) \(delta < 0 ? "below" : "above") last night"
    }

    private func headline(_ forecast: SleepForecastReading) -> String {
        guard let last = forecast.lastNightScore else { return "Tonight’s forecast is \(forecast.score)." }
        let delta = forecast.score - last
        if abs(delta) <= 2 { return "A night much like the last." }
        return delta < 0 ? "A slightly lighter night than last." : "A slightly better night than last."
    }
}

/// Tonight's forecast, worked out from the day and the scores.
struct SleepForecastReading {
    var score: Int
    var hours: Double?
    var deep: Double?
    var rem: Double?
    var leverTotal: Int
    var leadLine: String
    var rows: [ToolRow]
    var lastNightScore: Int?
    var check: (lead: String, rest: String)?

    static func make(day: ToolDay, scores: SomaScores?) -> SleepForecastReading? {
        guard day.hasEnoughNights else { return nil }
        let calendar = day.calendar
        let nights = day.inputs.nights
        let recent = Array(nights.suffix(14))
        let need = scores?.sleepNeedHours ?? day.sleepNeedHours
        let baseline = scores.map { series in
            SomaTools.SleepForecastEngine.recentMean(series.sleepSeries.compactMap { $0 }.suffix(14).map { $0 })
        } ?? 0
        let caffeine = day.caffeine?.atBedtimeMg ?? 0
        let last = day.inputs.lastNight(calendar: calendar)
        let debt = max(0, need - (last?.asleep ?? need))
        let hrv = scores?.recoveryTerms.first { $0.kind == .hrv }
        let hrvRatio = hrv.flatMap { term in term.value.flatMap { v in term.baseline.map { v / max($0, 1) } } } ?? 1
        let recentSeries = day.inputs.series(days: 28, calendar: calendar)
        let jetlag = SomaTools.SocialJetlag.compare(bedHours: recentSeries.bed, wakeHours: recentSeries.wake, today: day.inputs.now)?.gapHours ?? 0

        var inputs = SomaTools.SleepForecastEngine.Inputs(
            sleepNeedHours: need, baselineScore: baseline > 0 ? baseline : 50, caffeineMg: caffeine,
            priorNightDebtHours: debt, hrvRatio: hrvRatio, socialJetlagHours: jetlag)
        inputs.recentSleepHours = recent.map(\.asleep)
        inputs.recentDeepFractions = recent.map { $0.asleep > 0 ? $0.deep / $0.asleep : 0 }
        inputs.recentRemFractions = recent.map { $0.asleep > 0 ? $0.rem / $0.asleep : 0 }
        let forecast = SomaTools.SleepForecastEngine.forecast(inputs)

        let hours = forecast.predictedHoursEstimate
        let lastScore = scores?.sleepSeries.last.flatMap { $0 }.map { Int($0.rounded()) }
        let stamp = ToolsStore.stamp(day.inputs.now, calendar: calendar)

        var lead = "About \(Int(caffeine.rounded())) mg of caffeine will still be active at bedtime"
        if caffeine < 5 { lead = "Little caffeine will be left at bedtime" }
        lead += debt > 0.25 ? ", and you carry \(ToolFormat.span(hours: debt)) from last night." : "."

        let breathing = day.inputs.respiratoryRate
        let breathingLast = last.flatMap { night in
            let inside = breathing.filter { $0.start >= night.bed && $0.start <= night.wake }.map(\.value)
            return inside.isEmpty ? nil : inside.reduce(0, +) / Double(inside.count)
        }
        let breathingUsual = breathing.isEmpty ? nil : breathing.map(\.value).reduce(0, +) / Double(breathing.count)

        var rows: [ToolRow] = [
            ToolRow(title: "Caffeine at bedtime", detail: "aim under 25 mg", value: "\(Int(caffeine.rounded())) mg",
                    tone: caffeine > 25 ? .danger : .plain,
                    band: ToolBand(range: 0...75, usual: 0...25, value: caffeine)),
            ToolRow(title: "Sleep debt", detail: "against a \(ToolFormat.hoursMinutes(need)) need",
                    value: ToolFormat.span(hours: debt), tone: debt > 1.5 ? .danger : .plain,
                    band: ToolBand(range: 0...3, usual: 0...1, value: debt)),
        ]
        if let breathingLast {
            let usual = breathingUsual.map { ($0 - 1)...($0 + 1) }
            rows.append(ToolRow(title: "Breathing", detail: usual.map { "usual \(ToolFormat.number($0.lowerBound, decimals: 1)) to \(ToolFormat.number($0.upperBound, decimals: 1))" },
                                value: "\(ToolFormat.number(breathingLast, decimals: 1)) /min",
                                tone: usual.map { !$0.contains(breathingLast) } == true ? .danger : .plain,
                                band: ToolBand(range: 10...22, usual: usual, value: breathingLast)))
        }
        for lever in forecast.levers {
            rows.append(ToolRow(title: leverTitle(lever.kind), detail: "worth about \(lever.pointsAtStake) points tonight", value: "+\(lever.pointsAtStake)"))
        }

        var check: (String, String)?
        if let predicted = ToolsStore.shared.record.forecasts[stamp], let actual = lastScore {
            let gap = actual - predicted
            check = ("Forecast \(predicted), actual \(actual).",
                     gap == 0 ? "Right on." : "It was \(abs(gap)) points \(gap > 0 ? "cautious" : "hopeful"), and it learns from every morning.")
        }

        return SleepForecastReading(
            score: forecast.predictedScore,
            hours: hours,
            deep: hours.flatMap { h in forecast.deepFractionEstimate.map { h * $0 } },
            rem: hours.flatMap { h in forecast.remFractionEstimate.map { h * $0 } },
            leverTotal: forecast.leverTotal,
            leadLine: lead,
            rows: rows,
            lastNightScore: lastScore,
            check: check)
    }

    static func leverTitle(_ kind: SomaTools.SleepForecastEngine.LeverKind) -> String {
        switch kind {
        case .caffeine: "Less caffeine"
        case .consistency: "A steadier bedtime"
        case .recovery: "An easier evening"
        case .sleepDebt: "An earlier night"
        }
    }
}
