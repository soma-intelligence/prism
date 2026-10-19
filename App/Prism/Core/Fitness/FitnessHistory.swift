//
//  FitnessHistory.swift
//  Prism
//

import Foundation
import HealthExportCore

/// Workouts with their heart rate zones, read out of Health once for the
/// fitness pages: cardio load, cardio focus, heart rate recovery, muscle work
/// and the activity summary all read this shape.
nonisolated struct FitnessHistory: Sendable, Equatable {
    var now: Date
    var workouts: [FitnessWorkout] = []
    /// Apple's one minute heart rate recovery readings over the window.
    var recovery: [HealthReading] = []
    var age: Int?

    var maxHeartRate: Double? {
        guard let age, age > 0, age < 120 else { return nil }
        return Double(220 - age)
    }

    enum Metric {
        static let workout = "HKWorkoutTypeIdentifier"
        static let heartRate = "HKQuantityTypeIdentifierHeartRate"
        static let recovery = "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
        static let distance = "HKQuantityTypeIdentifierDistanceWalkingRunning"
        static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
    }

    static let metrics = [Metric.workout, Metric.heartRate, Metric.recovery, Metric.distance, Metric.dateOfBirth]

    /// Workouts in flight at once while their heart rate is read.
    static let inFlight = 8

    /// Reads `days` days of workouts ending now, each with the heart rate
    /// taken during it and, on foot, its distance.
    ///
    /// Heart rate is read per workout rather than over the whole window,
    /// which would pull every sample the watch took at rest as well.
    static func read(from source: any HealthSampleSource, days: Int, now: Date, calendar: Calendar) async -> FitnessHistory {
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now

        @Sendable func samples(_ identifier: String, from: Date, to: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: from, to: to, limit: 0)) ?? []
        }

        async let readings = samples(Metric.workout, from: start, to: now)
        async let recovery = samples(Metric.recovery, from: start, to: now)
        async let age = age(in: source)

        let workouts = await readings
        let distanceMetric = HealthMetricCatalog.metric(for: Metric.distance)

        let perWorkout: [(Date, [HealthReading], Double?)] = await withTaskGroup(of: (Date, [HealthReading], Double?).self) { group in
            var results: [(Date, [HealthReading], Double?)] = []
            var pending = workouts.makeIterator()

            func add(_ workout: HealthReading) {
                group.addTask {
                    let heart = await samples(Metric.heartRate, from: workout.start, to: workout.end)
                    var distance: Double?
                    if FitnessActivities.onFoot.contains(Int(workout.value)), let distanceMetric {
                        distance = (try? await source.total(distanceMetric, from: workout.start, to: workout.end))?.value
                    }
                    return (workout.start, heart, distance)
                }
            }

            for _ in 0..<inFlight {
                guard let next = pending.next() else { break }
                add(next)
            }
            for await result in group {
                results.append(result)
                if let next = pending.next() { add(next) }
            }
            return results
        }

        let heartRate = perWorkout.flatMap(\.1)
        let distances = Dictionary(perWorkout.compactMap { item in item.2.map { (item.0, $0) } }, uniquingKeysWith: { first, _ in first })
        let knownAge = await age
        let maxHeartRate = knownAge.flatMap { $0 > 0 && $0 < 120 ? Double(220 - $0) : nil }

        return FitnessHistory(
            now: now,
            workouts: FitnessZones.workouts(workouts, heartRate: heartRate, maxHeartRate: maxHeartRate, distances: distances),
            recovery: await recovery,
            age: knownAge
        )
    }

    /// Age in whole years from the date of birth in Health.
    static func age(in source: any HealthSampleSource) async -> Int? {
        guard let birth = HealthMetricCatalog.metric(for: Metric.dateOfBirth),
              let reading = try? await source.latest(birth) else { return nil }
        return Int(reading.value)
    }

    /// One total per day for `days` days ending today, keyed by the day's
    /// midnight. A day the store has nothing for is absent, never zero.
    static func dailyTotals(
        _ identifier: String,
        days: Int,
        now: Date,
        source: any HealthSampleSource,
        calendar: Calendar
    ) async -> [Date: Double] {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [:] }
        let today = calendar.startOfDay(for: now)
        let starts = (0..<days).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }

        return await withTaskGroup(of: (Date, Double?).self) { group in
            var result: [Date: Double] = [:]
            var pending = starts.makeIterator()

            func add(_ day: Date) {
                let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? now, now)
                group.addTask { (day, (try? await source.total(metric, from: day, to: end))?.value) }
            }

            for _ in 0..<12 {
                guard let next = pending.next() else { break }
                add(next)
            }
            for await (day, value) in group {
                if let value { result[day] = value }
                if let next = pending.next() { add(next) }
            }
            return result
        }
    }
}
