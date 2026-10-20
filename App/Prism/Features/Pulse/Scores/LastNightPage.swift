//
//  LastNightPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore
import HealthScoring

/// Last night, everything about it: the time asleep against the need with
/// its ring, the sleep period and the stages, the heart through the night,
/// the overnight signals against the usual (heart rate variability,
/// breathing, wrist temperature, the sleeping low), the disturbances, and
/// the doors to the night's details and back to the Sleep page.
///
/// The night card on Today and on the Sleep page opens it; the Sleep score
/// opens ``SleepPage`` (owner, 2026-10-20: two sleep pages).
struct LastNightPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var inputs: ScoreDetailInputs?
    @State private var night = HomeLastNight.empty
    @State private var isRead = false
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case dip, breathing, environment
        var id: String { rawValue }
    }

    private let calendar = Calendar.current

    var body: some View {
        let scores = health.scores
        let page = ScorePages.sleep(scores, inputs)
        let stages = night.stages
        let summary = stages.flatMap { SleepNightSummary.make(home: $0, parts: scores?.detail.sleepParts ?? []) }
            ?? SleepNightSummary.make(scoring: page.stages, inBedStart: inputs?.inBedStart, parts: page.parts)
        let hero = LastNightHero.make(asleep: summary?.asleep, need: scores?.sleepNeedHours,
                                      nights: scores?.detail.sleepHours ?? [])

        ScorePageScaffold(aspect: .sleep, title: "Last night") {
            SomaScoreHero(
                aspect: .sleep,
                caption: "Last night",
                value: hero.value,
                unit: hero.value == nil ? nil : "asleep",
                meaning: hero.meaning,
                detail: hero.detail,
                tone: hero.tone,
                dial: .fill(hero.share),
                usual: hero.usual
            )
            SleepLastNightSection(night: summary, calendar: calendar)
            LastNightHeartCard(beats: inputs?.lastNightBeats ?? [], night: inputs?.nights.last ?? nil)
            HomeRowsCard("Overnight", caption: "Against your usual") {
                HomeMeasureRow(name: "Heart rate variability", unit: "ms", latest: night.hrv.latest, band: night.hrv.band, higherIsWorse: false)
                HomeMeasureRow(name: "Sleeping heart rate", unit: "bpm", latest: night.sleepingLow.latest, band: night.sleepingLow.band)
                HomeMeasureRow(name: "Breathing", unit: "/min", decimals: 1, latest: night.breathing.latest, band: night.breathing.band)
                HomeMeasureRow(name: "Wrist temperature", unit: "°C", decimals: 1, latest: night.wrist.latest, band: night.wrist.band)
            }
            LastNightDisturbances(stages: stages, isRead: isRead, calendar: calendar)
            ScoreLinks(links: [
                ScoreLink(title: "Night dip", detail: page.dip ?? "-") { sheet = .dip },
                ScoreLink(title: "Breathing", detail: page.breathing ?? "-") { sheet = .breathing },
                ScoreLink(title: "Sleep environment", detail: page.sound ?? "-") { sheet = .environment },
            ])
            ScorePageLinks(routes: [(.sleep, "Sleep over time", scores?.sleep.map(String.init))])
        }
        .scoreInputs([.nights, .heart, .nightHeart, .breathing, .sound], into: $inputs)
        .task {
            guard !isRead else { return }
            guard let source = await health.prepare([HomeMetric.respiratoryRate, HomeMetric.wristTemperature]) else {
                isRead = true
                return
            }
            night = await HomeLastNight.read(from: source, now: Date(), calendar: calendar)
            isRead = true
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .dip: NightDipSheet(scores: health.scores, inputs: inputs)
            case .breathing: BreathingSheet(inputs: inputs)
            case .environment: SleepEnvironmentSheet(scores: health.scores, inputs: inputs)
            }
        }
    }
}

/// What the head of Last night says: the time asleep, the ring filled to
/// the night's share of the need, and the usual nights marked on it.
struct LastNightHero: Equatable {
    var value: String?
    var meaning: String?
    var detail: String?
    var tone: SomaCueTone
    var share: Double?
    var usual: ClosedRange<Double>?

    /// Hours as "7h 54m", the way the sleep totals write them.
    static func span(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static func make(asleep: TimeInterval?, need: Double?, nights: [Double?]) -> LastNightHero {
        let usualHours = AspectPageMath.usual(nights)
        guard let asleep, asleep > 0 else {
            return LastNightHero(value: nil, meaning: "Waiting for a night your watch records", detail: nil,
                                 tone: .neutral, share: nil, usual: nil)
        }
        let hours = asleep / 3600
        let need = max(need ?? 8, 1)
        let meaning = MetricPageWords.meaning(value: hours, band: usualHours, isReference: false,
                                              known: nights.compactMap { $0 }.count, todayOpen: false,
                                              risingIsGood: true, format: ScoreMath.hoursMinutes, unit: nil)
        return LastNightHero(
            value: span(hours),
            meaning: meaning?.text,
            detail: "Need \(span(need))",
            tone: meaning?.tone ?? .neutral,
            share: min(1, hours / need),
            usual: usualHours.map { min(1, $0.lowerBound / need)...min(1, $0.upperBound / need) }
        )
    }
}

/// The heart through the night, its lowest marked.
private struct LastNightHeartCard: View {
    let beats: [ScoringTimedValue]
    let night: ScoringNightWindow?

    var body: some View {
        let lowest = beats.min { $0.value < $1.value }
        SomaChartCard(eyebrow: "Heart rate asleep", value: lowest.map { ScoreMath.number($0.value) }, unit: "bpm lowest",
                      note: lowest.map { "Reached at \(ScoreMath.clock($0.start))." } ?? "Your watch's heart readings through the night draw here.") {
            if let night, beats.count >= 2 {
                let values = beats.map(\.value)
                let low = (values.min() ?? 40) - 3, high = (values.max() ?? 80) + 3
                let span = max(1, night.end.timeIntervalSince(night.start))
                ScoreDayLine(points: beats.map { ($0.start.timeIntervalSince(night.start) / span, $0.value) },
                             aspect: .heart, range: low...high,
                             labels: [ScoreMath.clock(night.start), ScoreMath.clock(night.end)],
                             marker: lowest.map { ($0.start.timeIntervalSince(night.start) / span, $0.value) })
            } else {
                ScoreEmptyPlot(message: "No heart readings last night.")
            }
        }
    }
}

/// How long it took to fall asleep and when the night was broken.
struct LastNightDisturbances: View {
    let stages: HomeNightStages?
    let isRead: Bool
    let calendar: Calendar

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let type = theme.typography
        let colors = theme.colors
        let rows = LastNightDisturbances.rows(stages, calendar: calendar)

        SomaCard {
            VStack(alignment: .leading, spacing: 0) {
                SomaCardHeader("Disturbances", caption: "Last night")
                if rows.isEmpty {
                    Text(isRead ? "No night recorded yet" : "Reading last night")
                        .somaFont(type.caption)
                        .foregroundStyle(colors.inkSecondary.color)
                        .padding(.top, theme.metrics.cardHeaderSpacing)
                } else {
                    ScoreRows(rows) { row in
                        HStack {
                            Text(row.title)
                                .somaFont(type.body)
                                .foregroundStyle(colors.inkPrimary.color)
                            Spacer()
                            Text(row.value)
                                .somaFont(type.rowValue)
                                .foregroundStyle(colors.inkPrimary.color)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    struct Row: Identifiable, Equatable {
        var id: String { title }
        var title: String
        var value: String
    }

    /// Fell asleep within, times awake, and each waking's clock time.
    static func rows(_ stages: HomeNightStages?, calendar: Calendar) -> [Row] {
        guard let stages else { return [] }
        var rows: [Row] = []
        if let latency = stages.latency {
            rows.append(Row(title: "Fell asleep within", value: ScoreMath.duration(hours: latency / 3600)))
        }
        rows.append(Row(title: "Times awake", value: stages.wakings.isEmpty ? "None" : "\(stages.wakings.count)"))
        if !stages.wakings.isEmpty {
            let times = stages.wakings.prefix(4).map { ScoreMath.clock($0, calendar: calendar) }
            rows.append(Row(title: stages.wakings.count == 1 ? "Woke at" : "Woke around", value: times.joined(separator: ", ")))
        }
        return rows
    }
}

/// What the Last night page reads: the night in stages, and the overnight
/// signals against the fortnight before.
struct HomeLastNight: Sendable {
    var stages: HomeNightStages?
    var sleepingLow: HomeMarkerSeries
    var hrv: HomeMarkerSeries
    var breathing: HomeMarkerSeries
    var wrist: HomeMarkerSeries

    static let empty = HomeLastNight(
        stages: nil,
        sleepingLow: HomeMarkerSeries(days: [], latest: nil, usual: nil, band: nil, changes: []),
        hrv: HomeMarkerSeries(days: [], latest: nil, usual: nil, band: nil, changes: []),
        breathing: HomeMarkerSeries(days: [], latest: nil, usual: nil, band: nil, changes: []),
        wrist: HomeMarkerSeries(days: [], latest: nil, usual: nil, band: nil, changes: [])
    )

    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> HomeLastNight {
        async let sleep = source.home(PulseInputs.Metric.sleep, days: 31, now: now, calendar: calendar)
        async let heart = source.home(PulseInputs.Metric.heartRate, days: 15, now: now, calendar: calendar)
        async let variability = source.home(PulseInputs.Metric.heartRateVariability, days: 31, now: now, calendar: calendar)
        async let breathing = source.home(HomeMetric.respiratoryRate, days: 31, now: now, calendar: calendar)
        async let wrist = source.home(HomeMetric.wristTemperature, days: 31, now: now, calendar: calendar)

        let sleepSamples = await sleep
        let heartSamples = await heart
        let nights = PulseNights.nights(from: sleepSamples, calendar: calendar)
        // Each night's lowest heart rate asleep, dated by the morning it ended.
        let lows: [HealthReading] = nights.compactMap { night in
            let asleep = heartSamples.filter { $0.start >= night.fellAsleep && $0.start <= night.woke }
            guard let low = asleep.min(by: { $0.value < $1.value }) else { return nil }
            return HealthReading(metric: low.metric, value: low.value, unit: low.unit, start: night.day, end: night.day)
        }
        let mean: ([Double]) -> Double? = { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) }
        return HomeLastNight(
            stages: HomeNightStages.make(sleepSamples, now: now, calendar: calendar),
            sleepingLow: HomeMarkerSeries.make(lows, days: 14, today: now, calendar: calendar, aggregate: { $0.min() }),
            hrv: HomeMarkerSeries.make(await variability, days: 14, today: now, calendar: calendar, aggregate: mean),
            breathing: HomeMarkerSeries.make(await breathing, days: 14, today: now, calendar: calendar, aggregate: mean),
            wrist: HomeMarkerSeries.make(await wrist, days: 14, today: now, calendar: calendar, aggregate: mean)
        )
    }
}
