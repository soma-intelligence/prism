//
//  PulseTrendsInputs.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Trends page is built from: a year of sleep, two months of HRV, and
/// daily totals of steps and exercise, as Apple Health returned them.
///
/// Plain values, so the page's arithmetic is tested without a Health store.
struct PulseTrendsInputs: Sendable, Equatable {
    var now: Date
    /// Sleep analysis samples over the last year, each carrying its coded stage.
    var sleep: [HealthReading] = []
    /// Heart rate variability (SDNN) over the last sixty days.
    var heartRateVariability: [HealthReading] = []
    /// Steps per day, keyed by the day's midnight, from the first of last month
    /// to today. A day Health holds nothing for is absent, not zero.
    var stepsByDay: [Date: Double] = [:]
    /// Exercise minutes per day, keyed by the day's midnight, from the first of
    /// January (or sixty days back, whichever is earlier) to today.
    var exerciseByDay: [Date: Double] = [:]

    var isEmpty: Bool {
        sleep.isEmpty && heartRateVariability.isEmpty && stepsByDay.isEmpty && exerciseByDay.isEmpty
    }
}

extension PulseTrendsInputs {
    /// The identifiers the Trends page reads. All four are in the launch set.
    static let metrics = [
        PulseInputs.Metric.sleep,
        PulseInputs.Metric.heartRateVariability,
        PulseInputs.Metric.steps,
        PulseInputs.Metric.exercise,
    ]

    /// Everything the page needs, read from `source` at once.
    ///
    /// Sleep and HRV are read as samples once and bucketed here. Steps and
    /// exercise are read as one total per day, so a watch and a phone that
    /// both counted the same walk count it once; those totals run a bounded
    /// number at a time, since a year of days is a few hundred queries.
    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> PulseTrendsInputs {
        let today = calendar.startOfDay(for: now)
        let yearAgo = calendar.date(byAdding: .day, value: -366, to: today) ?? today
        let sixtyAgo = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? today
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let january = calendar.dateInterval(of: .year, for: now)?.start ?? today
        let exerciseFrom = min(january, sixtyAgo)

        @Sendable func samples(_ identifier: String, from start: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        }

        async let sleep = samples(PulseInputs.Metric.sleep, from: yearAgo)
        async let variability = samples(PulseInputs.Metric.heartRateVariability, from: sixtyAgo)
        async let steps = HealthDailyTotals.read(PulseInputs.Metric.steps, from: lastMonth, now: now, source: source, calendar: calendar)
        async let exercise = HealthDailyTotals.read(PulseInputs.Metric.exercise, from: exerciseFrom, now: now, source: source, calendar: calendar)

        return PulseTrendsInputs(
            now: now,
            sleep: await sleep,
            heartRateVariability: await variability,
            stepsByDay: await steps,
            exerciseByDay: await exercise
        )
    }
}
