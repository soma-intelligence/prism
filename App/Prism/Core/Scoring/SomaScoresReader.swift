//
//  SomaScoresReader.swift
//  Prism
//

import Foundation
import HealthExportCore
import HealthScoring

/// Reads what the score engine needs out of a `HealthSampleSource`.
///
/// Ninety days, oldest first, ending today. Totals and means come from the
/// store's own statistics, one query a day, so a watch and a phone that both
/// counted a walk count it once and a day of heart rate is never pulled
/// sample by sample. Resting heart rate and HRV are sparse (a few readings a
/// day), so they are read as samples once and averaged here. The only raw
/// heart rate read is today's, for the zones of today's load.
///
/// Everything here reads metrics already in `HealthDashboard.displayed`, so
/// the scores ask for nothing new.
nonisolated enum SomaScoresReader {
    /// Days in every series. Ninety covers the strain normalizer's window and
    /// leaves the 60 day baselines a month of history before the 30 days the
    /// pages show.
    static let days = 90
    /// Statistics queries in flight at once.
    static let inFlight = 12

    enum Metric {
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
        static let exercise = "HKQuantityTypeIdentifierAppleExerciseTime"
        static let heartRate = "HKQuantityTypeIdentifierHeartRate"
        static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
        static let heartRateVariability = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
        static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
    }

    /// The first moment of each day in the window, oldest first.
    static func dayStarts(days: Int, now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0 - (days - 1), to: today) }
    }

    /// Readings averaged per day, onto `dayStarts`. A reading belongs to the
    /// day it started on; a day with none is nil, never zero.
    static func dailyMeans(_ readings: [HealthReading], dayStarts: [Date], calendar: Calendar) -> [Double?] {
        var sums: [Date: (total: Double, count: Int)] = [:]
        for reading in readings {
            let day = calendar.startOfDay(for: reading.start)
            let current = sums[day] ?? (0, 0)
            sums[day] = (current.total + reading.value, current.count + 1)
        }
        return dayStarts.map { day in
            sums[day].map { $0.total / Double($0.count) }
        }
    }

    /// The mean of the readings that started inside `window`, or nil.
    static func mean(_ readings: [HealthReading], in window: ScoringNightWindow) -> Double? {
        let inside = readings.filter { $0.start >= window.start && $0.start <= window.end }.map(\.value)
        return inside.isEmpty ? nil : inside.reduce(0, +) / Double(inside.count)
    }

    /// Everything the engine needs, read from `source`.
    ///
    /// A read that fails is left empty rather than failing the scores: the
    /// value it would have fed is missing, and the engine treats it so.
    @concurrent
    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> ScoringInputs {
        // Whatever store this is handed, read it through the border that drops
        // values no arithmetic can use.
        let source: any HealthSampleSource = source is SanitizedHealthSource ? source : SanitizedHealthSource(base: source)
        let starts = dayStarts(days: days, now: now, calendar: calendar)
        guard let first = starts.first else { return ScoringInputs(now: now, calendar: calendar) }
        // Sleep reaches back to the evening before the first day, so the
        // night that ended on it is whole.
        let sleepFrom = calendar.date(byAdding: .hour, value: -18, to: first) ?? first

        @Sendable func samples(_ identifier: String, from start: Date, to end: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: end, limit: 0)) ?? []
        }

        async let sleep = samples(Metric.sleep, from: sleepFrom, to: now)
        async let resting = samples(Metric.restingHeartRate, from: first, to: now)
        async let variability = samples(Metric.heartRateVariability, from: first, to: now)
        async let daily = dailyStatistics(source: source, dayStarts: starts, now: now, calendar: calendar)
        async let latestResting = latest(Metric.restingHeartRate, from: source)
        async let birth = latest(Metric.dateOfBirth, from: source)

        let sleepSamples = await sleep.compactMap {
            ScoringSleepSample(code: $0.code, start: $0.start, end: $0.end, source: $0.source)
        }
        let restingReadings = await resting
        let variabilityReadings = await variability

        // Today's heart rate and active energy from last night's bedtime, or
        // from midnight when there was no night.
        let today = calendar.startOfDay(for: now)
        let night = SomaScoringEngine.lastNight(from: sleepSamples, now: now, calendar: calendar)
        let intradayFrom = night.map { min($0.start, today) } ?? today
        async let heartRate = samples(Metric.heartRate, from: intradayFrom, to: now)
        async let energy = samples(Metric.activeEnergy, from: intradayFrom, to: now)
        async let nightHeartRate = nightAverage(night, source: source)

        let statistics = await daily
        return ScoringInputs(
            now: now,
            calendar: calendar,
            restingHeartRate: dailyMeans(restingReadings, dayStarts: starts, calendar: calendar),
            heartRateVariability: dailyMeans(variabilityReadings, dayStarts: starts, calendar: calendar),
            dayHeartRate: statistics.heartRate,
            steps: statistics.steps,
            activeEnergy: statistics.activeEnergy,
            exerciseMinutes: statistics.exercise,
            sleepSamples: sleepSamples,
            intradayHeartRate: await heartRate.map { ScoringTimedValue(start: $0.start, end: $0.end, value: $0.value) },
            intradayActiveEnergy: await energy.map { ScoringTimedValue(start: $0.start, end: $0.end, value: $0.value) },
            lastNightHeartRate: await nightHeartRate,
            lastNightVariability: night.flatMap { mean(variabilityReadings, in: $0) },
            latestRestingHeartRate: await latestResting,
            ageYears: await birth
        )
    }

    // MARK: - Pieces

    private static func latest(_ identifier: String, from source: any HealthSampleSource) async -> Double? {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
        return (try? await source.latest(metric))?.value
    }

    private static func nightAverage(_ night: ScoringNightWindow?, source: any HealthSampleSource) async -> Double? {
        guard let night, let metric = HealthMetricCatalog.metric(for: Metric.heartRate) else { return nil }
        return (try? await source.average(metric, from: night.start, to: night.end))?.value
    }

    struct Daily: Sendable {
        var steps: [Double?]
        var activeEnergy: [Double?]
        var exercise: [Double?]
        var heartRate: [Double?]
    }

    /// One statistic per metric per day, a bounded number in flight.
    private static func dailyStatistics(
        source: any HealthSampleSource,
        dayStarts: [Date],
        now: Date,
        calendar: Calendar
    ) async -> Daily {
        enum Kind: Int, CaseIterable { case steps, activeEnergy, exercise, heartRate }
        let identifiers: [Kind: String] = [
            .steps: Metric.steps, .activeEnergy: Metric.activeEnergy,
            .exercise: Metric.exercise, .heartRate: Metric.heartRate,
        ]
        let metrics = identifiers.compactMapValues(HealthMetricCatalog.metric(for:))
        var jobs: [(kind: Kind, day: Int)] = []
        for kind in Kind.allCases where metrics[kind] != nil {
            for day in dayStarts.indices { jobs.append((kind, day)) }
        }

        let empty = [Double?](repeating: nil, count: dayStarts.count)
        var result: [Kind: [Double?]] = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, empty) })
        await withTaskGroup(of: (Kind, Int, Double?).self) { group in
            var pending = jobs.makeIterator()
            func add(_ job: (kind: Kind, day: Int)) {
                guard let metric = metrics[job.kind] else { return }
                let start = dayStarts[job.day]
                let end = min(calendar.date(byAdding: .day, value: 1, to: start) ?? now, now)
                group.addTask {
                    let reading = job.kind == .heartRate
                        ? try? await source.average(metric, from: start, to: end)
                        : try? await source.total(metric, from: start, to: end)
                    return (job.kind, job.day, reading?.value)
                }
            }
            for _ in 0..<inFlight {
                guard let next = pending.next() else { break }
                add(next)
            }
            for await (kind, day, value) in group {
                result[kind]?[day] = value
                if let next = pending.next() { add(next) }
            }
        }
        return Daily(
            steps: result[.steps] ?? empty,
            activeEnergy: result[.activeEnergy] ?? empty,
            exercise: result[.exercise] ?? empty,
            heartRate: result[.heartRate] ?? empty
        )
    }
}
