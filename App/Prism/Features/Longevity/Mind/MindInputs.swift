//
//  MindInputs.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Mind tab is built from: the readings as Apple Health returned
/// them, and the clock they were read at.
///
/// Plain values, so the three parts' arithmetic is tested without a Health
/// store. The sixty days of stress are read apart, in ``MindInputs/readStress(from:now:calendar:)``,
/// because only Insights needs them and they are the heaviest read on the tab.
struct MindInputs: Sendable, Equatable {
    var now: Date
    /// Heart rate variability (SDNN) over the last sixty days.
    var heartRateVariability: [HealthReading] = []
    /// Resting heart rate over the last sixty days.
    var restingHeartRate: [HealthReading] = []
    /// Mindful sessions over the last sixty days.
    var mindful: [HealthReading] = []
    /// Sleep analysis samples over the last sixty days, each with its stage.
    var sleep: [HealthReading] = []
    /// Workouts over the last sixty days, each carrying its activity type.
    var workouts: [HealthReading] = []
    /// Today's stress, read the way Insights reads each of its days.
    var today: MindStressDay?

    /// How far back the tab reads.
    static let days = 60

    var isEmpty: Bool {
        heartRateVariability.isEmpty && restingHeartRate.isEmpty && mindful.isEmpty
            && sleep.isEmpty && workouts.isEmpty && (today?.isReadable != true)
    }
}

extension MindInputs {
    enum Metric {
        static let heartRate = "HKQuantityTypeIdentifierHeartRate"
        static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
        static let heartRateVariability = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
        static let workout = "HKWorkoutTypeIdentifier"
        static let mindful = "HKCategoryTypeIdentifierMindfulSession"

        static let all = [heartRate, restingHeartRate, heartRateVariability, steps, sleep, workout, mindful]
    }

    /// Everything but the sixty days of stress, read at once. A read that
    /// fails is left empty: what it fed renders as a dash.
    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> MindInputs {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -days, to: today) ?? today

        async let variability = samples(source, Metric.heartRateVariability, from: start, to: now)
        async let resting = samples(source, Metric.restingHeartRate, from: start, to: now)
        async let mindful = samples(source, Metric.mindful, from: start, to: now)
        async let sleep = samples(source, Metric.sleep, from: start, to: now)
        async let workouts = samples(source, Metric.workout, from: start, to: now)

        var inputs = MindInputs(
            now: now,
            heartRateVariability: await variability,
            restingHeartRate: await resting,
            mindful: await mindful,
            sleep: await sleep,
            workouts: await workouts
        )
        inputs.today = await readDay(
            today, from: source, now: now, calendar: calendar,
            resting: inputs.restingHeartRate, workouts: inputs.workouts
        )
        return inputs
    }

    /// The last sixty days of stress, one day at a time.
    ///
    /// Sixty days of heart rate can be tens of thousands of samples, so each
    /// day is read on its own and reduced to its peaks at once: at most a few
    /// days' samples are held at a time, never the whole window.
    static func readStress(
        from source: any HealthSampleSource,
        now: Date,
        calendar: Calendar,
        resting: [HealthReading],
        workouts: [HealthReading]
    ) async -> [MindStressDay] {
        let today = calendar.startOfDay(for: now)
        let days = (1...Self.days).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let concurrent = 6

        return await withTaskGroup(of: MindStressDay?.self) { group in
            var pending = days.makeIterator()
            for _ in 0..<concurrent {
                guard let day = pending.next() else { break }
                group.addTask {
                    await readDay(day, from: source, now: now, calendar: calendar, resting: resting, workouts: workouts)
                }
            }
            var found: [MindStressDay] = []
            for await result in group {
                if let result { found.append(result) }
                if let day = pending.next() {
                    group.addTask {
                        await readDay(day, from: source, now: now, calendar: calendar, resting: resting, workouts: workouts)
                    }
                }
            }
            return found.sorted { $0.day < $1.day }
        }
    }

    /// One day's heart rate and steps, reduced to its stress peaks.
    static func readDay(
        _ day: Date,
        from source: any HealthSampleSource,
        now: Date,
        calendar: Calendar,
        resting: [HealthReading],
        workouts: [HealthReading]
    ) async -> MindStressDay? {
        let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? now, now)
        guard end > day else { return nil }
        async let heart = samples(source, Metric.heartRate, from: day, to: end)
        async let steps = samples(source, Metric.steps, from: day, to: end)
        return MindStress.day(
            day,
            heartRate: await heart,
            steps: await steps,
            resting: MindStress.resting(on: day, from: resting, calendar: calendar),
            workouts: workouts.filter { $0.end > day && $0.start < end },
            calendar: calendar
        )
    }

    private static func samples(_ source: any HealthSampleSource, _ identifier: String, from start: Date, to end: Date) async -> [HealthReading] {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
        return (try? await source.samples(metric, from: start, to: end, limit: 0)) ?? []
    }
}

/// How the Mind page and Track's Rituals read their inputs through the
/// dashboard: ask for the metrics, then read. With no Health store the
/// inputs come back empty, and every value they feed renders as a dash.
@MainActor
enum MindLoad {
    static func inputs(_ health: HealthDashboard) async -> MindInputs {
        guard let source = await health.prepare(MindInputs.Metric.all) else { return MindInputs(now: Date()) }
        return await MindInputs.read(from: source, now: Date(), calendar: .current)
    }

    static func stress(_ health: HealthDashboard, inputs: MindInputs) async -> [MindStressDay] {
        guard let source = await health.prepare(MindInputs.Metric.all) else { return [] }
        return await MindInputs.readStress(
            from: source, now: inputs.now, calendar: .current,
            resting: inputs.restingHeartRate, workouts: inputs.workouts
        )
    }
}
