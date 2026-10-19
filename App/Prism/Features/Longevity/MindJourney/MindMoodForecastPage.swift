//
//  MindMoodForecastPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// Mood forecast, today: a mood for the day from the signals already in hand,
/// what sets it, how the forecast has done against what was logged, and the
/// one lever worth pulling.
///
/// The forecast is `MindMoodForecast`. The first
/// forecast of a day is kept on the phone, so the page can check it against
/// the feelings logged that day.
struct MindMoodForecastPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme

    @State private var inputs: MindInputs?
    @State private var extras = MindJourneyExtras()
    @State private var moods: [MindMoodEntry] = []
    @State private var calls: [MindCalendarEvent] = []

    var body: some View {
        let calendar = Calendar.current
        let words = PulseWording(calendar: calendar, locale: .current)
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let base = inputs ?? MindInputs(now: now)
        let signals = MindSignals.make(
            heartRateVariability: base.heartRateVariability, restingHeartRate: base.restingHeartRate,
            respiratory: extras.respiratory, sleep: base.sleep, peaks: [],
            now: now, calendar: calendar, words: words
        )
        let forecastInputs = self.forecastInputs(signals: signals, calendar: calendar, today: today)
        let reading = inputs == nil ? nil : MindMoodForecast.forecast(forecastInputs)
        let felt = feltByDay(calendar: calendar)
        let kept = MindStore.shared.forecastsByDay(calendar: calendar)
        let track = MindMoodForecast.track(forecasts: kept, felt: felt)

        MindPage(
            navigationTitle: "Mood forecast",
            title: reading?.band.title ?? "Mood forecast",
            stats: [
                SomaStat("Mood", value: MindFormat.whole(reading?.index)),
                SomaStat("Signals", value: reading.map { "\($0.contributions.count) of 4" }),
                SomaStat("Confidence", value: reading?.confidence.title),
            ]
        ) {
            MindRowsCard(title: "What sets it", caption: "Against your usual", rows: rows(forecastInputs, signals: signals, words: words)) { MindSignalRowView(row: $0) }

            SomaChartCard(
                eyebrow: "How the forecast has done",
                value: track.of > 0 ? "\(track.within) of \(track.of)" : nil,
                unit: "days within 8 points",
                note: track.of == 0
                    ? "Log how you feel on a few days and each forecast is checked against it here."
                    : "Line is the forecast, dots are how you felt."
            ) {
                if track.of > 0 {
                    MindForecastTrackChart(days: (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }, forecasts: kept, felt: felt)
                }
            }

            if let reading {
                SomaActionCard(eyebrow: "Today", title: reading.lever.title, detail: reading.lever.detail) {
                    SomaOrb(aspect: reading.lever == .protectSleep ? .sleep : .mind, scale: .mini)
                }
            }
        }
        .task {
            async let more = MindJourneyLoad.extras(health)
            await health.loadScores()
            inputs = await MindLoad.inputs(health)
            extras = await more
            moods = await MindJourneyLoad.moods(since: calendar.date(byAdding: .day, value: -14, to: today) ?? today, store: .shared)
            calls = MindMeetingStress.meetings(in: MindCalendar.events(from: now, to: calendar.date(byAdding: .day, value: 1, to: today) ?? now))
            if let reading = MindMoodForecast.forecast(self.forecastInputs(signals: MindSignals.make(
                heartRateVariability: inputs?.heartRateVariability ?? [], restingHeartRate: inputs?.restingHeartRate ?? [],
                respiratory: extras.respiratory, sleep: inputs?.sleep ?? [], peaks: [], now: now, calendar: calendar, words: words
            ), calendar: calendar, today: today)) {
                MindStore.shared.keepForecast(reading.index, for: today)
            }
        }
    }

    private func forecastInputs(signals: MindSignals, calendar: Calendar, today: Date) -> MindMoodForecast.Inputs {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let daylight = extras.daylight.filter { calendar.isDate($0.start, inSameDayAs: yesterday) }.reduce(0) { $0 + $1.value }
        let restingUsual = signals.resting.usual.map { ($0.lowerBound + $0.upperBound) / 2 }
        return MindMoodForecast.Inputs(
            sleepScore: health.scores?.sleep,
            overnightHRV: signals.hrvLastNight,
            hrvBaseline: signals.hrvBaseline,
            restingHR: signals.resting.number,
            restingBaseline: restingUsual,
            daylightMinutes: extras.daylight.isEmpty ? nil : daylight,
            priorMood: moods.last.map { $0.mood / 100 }
        )
    }

    private func rows(_ inputs: MindMoodForecast.Inputs, signals: MindSignals, words: PulseWording) -> [MindSignalRow] {
        [
            MindSignalRow(kind: .sleep, title: "Sleep score", detail: "last night", value: inputs.sleepScore.map { "\($0)" }, isCost: (inputs.sleepScore ?? 100) < 65, number: nil, usual: nil),
            MindSignalRow(kind: .hrv, title: "HRV, overnight", detail: signals.hrv.detail, value: inputs.overnightHRV.map { "\(words.whole($0)) ms" }, isCost: MindUsual.place(inputs.overnightHRV, in: signals.hrvUsual) == .under, number: inputs.overnightHRV, usual: signals.hrvUsual),
            signals.resting,
            MindSignalRow(kind: .sleepDebt, title: "Daylight", detail: "yesterday", value: inputs.daylightMinutes.map { MindFormat.duration($0) }, isCost: (inputs.daylightMinutes ?? 60) < 30, number: nil, usual: nil),
            MindSignalRow(kind: .hardWeekday, title: "Last feeling logged", detail: moods.last.map { $0.date.formatted(.relative(presentation: .named)) }, value: moods.last.map { MindMoodEntry.title(stop: MindMoodEntry.stop(valence: $0.valence)) }, isCost: (moods.last?.valence ?? 0) < -0.3, number: nil, usual: nil),
        ]
    }

    private func feltByDay(calendar: Calendar) -> [Date: Double] {
        Dictionary(grouping: moods) { calendar.startOfDay(for: $0.date) }
            .compactMapValues { MindUsual.mean($0.map(\.mood)) }
    }
}

/// A week of forecasts as a dashed line, and how it felt as dots: filled in
/// the mind hue where the forecast held, in the out of range colour where it
/// missed by more than eight.
struct MindForecastTrackChart: View {
    let days: [Date]
    let forecasts: [Date: Double]
    let felt: [Date: Double]

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let hue = theme.aspects[.mind].identity.color
        let out = theme.colors.statusOut.color
        let days = days
        let forecasts = forecasts
        let felt = felt
        let values = days.flatMap { [forecasts[$0], felt[$0]].compactMap { $0 } }

        SomaPlot(scale: SomaPlotScale(values: values, desired: 3),
                 xLabels: days.map { $0.formatted(.dateTime.weekday(.narrow)) },
                 height: theme.metrics.chartCompactPlotHeight) { context, space, pen in
            let line = days.enumerated().map { index, day in
                forecasts[day].map { CGPoint(x: space.x(index, of: days.count), y: space.y($0)) }
            }
            pen.line(context, line, color: pen.inkSecondary, dashed: true, width: 1)
            for (index, day) in days.enumerated() {
                guard let value = felt[day] else { continue }
                let off = forecasts[day].map { abs($0 - value) > 8 } ?? false
                pen.dot(context, at: CGPoint(x: space.x(index, of: days.count), y: space.y(value)), color: off ? out : hue, filled: true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Forecast against how you felt, last 7 days")
    }
}
