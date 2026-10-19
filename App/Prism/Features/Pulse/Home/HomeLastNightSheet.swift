//
//  HomeLastNightSheet.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// What the Last night sheet reads: the night in stages, and the overnight
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

/// Last night, in a sheet over Today: the hypnogram, the four stages, the
/// overnight signals against the usual, how you woke, and the doors to the
/// sleep pages.
struct HomeLastNightSheet: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var night = HomeLastNight.empty
    @State private var isRead = false

    private var track: TrackLogStore { .shared }
    private let calendar = Calendar.current

    var body: some View {
        let stages = night.stages

        HomeSheet(eyebrow: eyebrow, title: "Last night") {
            HomeReason(reason)

            SleepLastNightSection(
                night: stages.flatMap { SleepNightSummary.make(home: $0, parts: health.scores?.detail.sleepParts ?? []) },
                calendar: calendar
            )

            HomeRowsCard(caption: "Overnight, against your usual") {
                HomeMeasureRow(name: "Sleeping heart rate", unit: "bpm", latest: night.sleepingLow.latest, band: night.sleepingLow.band)
                HomeMeasureRow(name: "HRV", unit: "ms", latest: night.hrv.latest, band: night.hrv.band, higherIsWorse: false)
                HomeMeasureRow(name: "Breathing", unit: "/min", decimals: 1, latest: night.breathing.latest, band: night.breathing.band)
                HomeMeasureRow(name: "Wrist temperature", unit: "°C", decimals: 1, latest: night.wrist.latest, band: night.wrist.band)
            }

            wakeCard

            SomaBrowseGroup(rows) { row in
                if row.id == "detail" {
                    NavigationLink(value: PulseRoute.aspect(.sleep)) {
                        SomaBrowseRow(title: row.title, detail: row.detail)
                    }
                    .buttonStyle(.plain)
                } else {
                    SomaBrowseRow(title: row.title, detail: row.detail, opensSomething: false)
                }
            }
        }
        .task {
            guard !isRead, let source = await health.prepare([HomeMetric.respiratoryRate, HomeMetric.wristTemperature]) else { return }
            night = await HomeLastNight.read(from: source, now: Date(), calendar: calendar)
            isRead = true
            await health.loadScores()
        }
    }

    private var eyebrow: String {
        if let sleep = health.scores?.sleep { return "Sleep · \(sleep)" }
        return "Sleep"
    }

    private var reason: String {
        guard let stages = night.stages else {
            return isRead
                ? "No night recorded yet. Wear your watch to bed and last night fills in here in the morning."
                : "Reading last night from Apple Health."
        }
        let night = stages.night
        var parts = "Asleep at \(HomeFormat.clock(night.fellAsleep, calendar: calendar))"
        if let latency = stages.latency {
            parts += " within \(HomeFormat.span(latency))"
        }
        parts += ", up at \(HomeFormat.clock(night.woke, calendar: calendar))"
        switch stages.wakings.count {
        case 0: parts += ", and no wakings long enough to count."
        case 1: parts += ", awake once: at \(HomeFormat.clock(stages.wakings[0], calendar: calendar))."
        default:
            let times = stages.wakings.map { HomeFormat.clock($0, calendar: calendar) }
            parts += ", awake \(stages.wakings.count) times: at \(times.dropLast().joined(separator: ", ")) and \(times.last ?? "")."
        }
        let first = firstDeep.map { "The longest deep sleep came before \(HomeFormat.clock($0, calendar: calendar))." }
        return [HomeFormat.hoursMinutes(night.asleep) + " asleep.", parts, first].compactMap { $0 }.joined(separator: " ")
    }

    /// Where the longest stretch of deep sleep ended.
    private var firstDeep: Date? {
        night.stages?.segments
            .filter { $0.stage == .deep }
            .max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }?
            .end
    }

    private var wakeCard: some View {
        let feel = track.wakeFeel(on: Date())
        let words = ["Awful", "Tired", "Fine", "Good", "Great"]

        return SomaActionCard(
            eyebrow: "This morning",
            title: feel.map { "You woke \(words[$0 - 1].lowercased())" } ?? "How did you wake?",
            detail: "Your feeling sits beside the numbers, and Soma learns which nights you rate well."
        ) {
            PulseMiniOrb(aspect: .sleep, diameter: theme.metrics.miniOrbDiameter)
        }
        .overlay(alignment: .trailing) {
            Menu {
                ForEach(Array(words.enumerated()).reversed(), id: \.offset) { index, word in
                    Button(word) { track.setWakeFeel(index + 1, on: Date()) }
                }
            } label: {
                Text(feel == nil ? "Rate it" : "Change")
                    .somaFont(theme.typography.body)
                    .foregroundStyle(theme.colors.onAccent.color)
                    .padding(.horizontal, 16)
                    .frame(minHeight: theme.metrics.minimumTapTarget)
                    .background(Capsule().fill(theme.colors.accent.color))
            }
            .padding(theme.metrics.cardPadding)
        }
    }

    private struct Row: Identifiable {
        var id: String
        var title: String
        var detail: String?
    }

    private var rows: [Row] {
        let debt = health.scores?.sleepDebtHours.map { hours -> String in
            hours <= 0.1 ? "None, 7 nights" : "\(HomeFormat.span(hours * 3600)), 7 nights"
        }
        return [
            Row(id: "debt", title: "Sleep debt", detail: debt ?? "-"),
            Row(id: "detail", title: "Sleep in detail", detail: nil),
        ]
    }
}
