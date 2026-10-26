//
//  PulseLinksInputs.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Trends page's links are read from: the score engine's daily series
/// (sleep, recovery, strain, energy, bedtime), ninety days of HRV and resting
/// heart rate, daily steps and daylight, and the Journal's tagged days.
///
/// The Health reads all name metrics already in the one permission sheet.
enum PulseLinksInputs {
    /// Days read back, matching the score engine's window.
    static let days = SomaScoresReader.days
    /// A day with fewer steps than this is a day the phone sat on a desk, not
    /// a quiet day: it is left out rather than counted low.
    static let wornSteps = 500.0

    enum Metric {
        static let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let daylight = "HKQuantityTypeIdentifierTimeInDaylight"
    }

    static let metrics = [Metric.hrv, Metric.restingHeartRate, Metric.steps, Metric.daylight]

    /// The readings from Health, as plain values.
    struct Health: Sendable, Equatable {
        var hrv: [HealthReading] = []
        var resting: [HealthReading] = []
        var steps: [Date: Double] = [:]
        var daylight: [Date: Double] = [:]
    }

    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> Health {
        let starts = SomaScoresReader.dayStarts(days: days, now: now, calendar: calendar)
        let first = starts.first ?? calendar.startOfDay(for: now)

        @Sendable func samples(_ identifier: String) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: first, to: now, limit: 0)) ?? []
        }

        async let hrv = samples(Metric.hrv)
        async let resting = samples(Metric.restingHeartRate)
        async let steps = HealthDailyTotals.read(Metric.steps, from: first, now: now, source: source, calendar: calendar)
        async let daylight = HealthDailyTotals.read(Metric.daylight, from: first, now: now, source: source, calendar: calendar)
        return Health(hrv: await hrv, resting: await resting, steps: await steps, daylight: await daylight)
    }

    /// Everything set into the links' series.
    ///
    /// - Parameters:
    ///   - scores: the score engine's result, whose detail series run ninety
    ///     days oldest first, ending on `now`'s day.
    ///   - journal: each logged day and what it holds.
    static func series(
        health: Health,
        scores: SomaScores?,
        journal: [Date: JournalDay],
        now: Date,
        calendar: Calendar
    ) -> LinkSeries {
        var series = LinkSeries()

        if let detail = scores?.detail {
            func keyed(_ values: [Double?]) -> [Date: Double] {
                let starts = SomaScoresReader.dayStarts(days: values.count, now: now, calendar: calendar)
                var out: [Date: Double] = [:]
                for (day, value) in zip(starts, values) {
                    if let value { out[day] = value }
                }
                return out
            }
            series.sleepHours = keyed(detail.sleepHours).filter { $0.value > 0 }
            series.sleepScore = keyed(detail.sleep)
            series.sleepOnset = keyed(detail.bedHour)
            series.recovery = keyed(detail.recovery)
            series.energy = keyed(detail.energyMorning)
            series.strain = keyed(detail.strain)
        }

        // The Journal's own rule for a morning's HRV, keyed there by the
        // evening before; moved onto the morning itself here.
        let body = TrackBody.make(from: TrackInputs(now: now, variability: health.hrv), calendar: calendar)
        series.morningHRV = LinkMath.shifted(body.nextMorningVariability, by: 1, calendar: calendar)

        let starts = SomaScoresReader.dayStarts(days: days, now: now, calendar: calendar)
        let resting = SomaScoresReader.dailyMeans(health.resting, dayStarts: starts, calendar: calendar)
        for (day, value) in zip(starts, resting) {
            if let value { series.restingHeart[day] = value }
        }

        series.steps = health.steps.filter { $0.value >= wornSteps }
        series.daylight = health.daylight

        var tagDays: [String: Set<Date>] = [:]
        for (day, entry) in journal {
            for tag in entry.tags { tagDays[tag, default: []].insert(calendar.startOfDay(for: day)) }
        }
        series.tagDays = tagDays
        series.firstJournalDay = journal.filter { !$0.value.tags.isEmpty || $0.value.feeling != nil }.keys.min()
        return series
    }
}
