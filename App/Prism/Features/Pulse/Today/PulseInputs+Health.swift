//
//  PulseInputs+Health.swift
//  Prism
//

import Foundation
import HealthExportCore

extension PulseInputs {
    /// The identifiers the Today page reads, all of them asked for at launch
    /// through `HealthDashboard.displayed`.
    enum Metric {
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
        static let heartRate = "HKQuantityTypeIdentifierHeartRate"
        static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
        static let heartRateVariability = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let exercise = "HKQuantityTypeIdentifierAppleExerciseTime"
        static let workout = "HKWorkoutTypeIdentifier"
        static let mindful = "HKCategoryTypeIdentifierMindfulSession"
        static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
    }

    /// Everything the Today page needs, read from `source` at once.
    ///
    /// A read that fails is left empty rather than failing the page: each
    /// value it would have fed renders as a dash, and the rest still read.
    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> PulseInputs {
        let today = calendar.startOfDay(for: now)
        let monthAgo = calendar.date(byAdding: .day, value: -31, to: today) ?? today
        // From six in the evening before, so last night's heart is in.
        let lastEvening = today.addingTimeInterval(-6 * 60 * 60)

        @Sendable func samples(_ identifier: String, from start: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        }

        @Sendable func total(_ identifier: String, from start: Date, to end: Date) async -> Double? {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
            return (try? await source.total(metric, from: start, to: end))?.value
        }

        async let sleep = samples(Metric.sleep, from: monthAgo)
        async let heartRate = samples(Metric.heartRate, from: lastEvening)
        async let resting = samples(Metric.restingHeartRate, from: monthAgo)
        async let variability = samples(Metric.heartRateVariability, from: monthAgo)
        async let steps = samples(Metric.steps, from: today)
        async let stepsToday = total(Metric.steps, from: today, to: now)
        async let exerciseToday = total(Metric.exercise, from: today, to: now)
        async let workouts = samples(Metric.workout, from: today)
        async let mindful = samples(Metric.mindful, from: today)

        // Exercise from midnight to this time of day, on each of the fourteen
        // days before: what "by now" usually looks like.
        let elapsed = now.timeIntervalSince(today)
        let exerciseBefore = await withTaskGroup(of: Double?.self) { group in
            for offset in 1...14 {
                guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                group.addTask { await total(Metric.exercise, from: start, to: start.addingTimeInterval(elapsed)) }
            }
            var found: [Double] = []
            for await value in group { if let value { found.append(value) } }
            return found
        }

        var age: Int?
        if let birth = HealthMetricCatalog.metric(for: Metric.dateOfBirth),
           let reading = try? await source.latest(birth) {
            age = Int(reading.value)
        }

        let readWorkouts = await workouts
        var workoutSteps: [Date: Double] = [:]
        for workout in readWorkouts where PulseSignals.describe(activity: Int(workout.value)).1 == .onFoot {
            workoutSteps[workout.start] = await total(Metric.steps, from: workout.start, to: workout.end)
        }

        return PulseInputs(
            now: now,
            sleep: await sleep,
            heartRate: await heartRate,
            restingHeartRate: await resting,
            heartRateVariability: await variability,
            steps: await steps,
            stepsToday: await stepsToday,
            exerciseToday: await exerciseToday,
            exerciseByNowBefore: exerciseBefore,
            workouts: readWorkouts,
            workoutSteps: workoutSteps,
            mindful: await mindful,
            age: age
        )
    }
}
