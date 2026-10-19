//
//  FitnessWorkout.swift
//  Prism
//

import Foundation
import HealthExportCore

/// One recorded workout with the heart rate time it spent in each zone.
///
/// The shape every fitness engine reads, cut to what the engines use. Built from Health's workout readings and the heart rate taken
/// during each, by ``FitnessZones/workouts(_:heartRate:maxHeartRate:)``.
nonisolated struct FitnessWorkout: Sendable, Equatable, Identifiable {
    var start: Date
    var end: Date
    /// The raw `HKWorkoutActivityType`.
    var activity: Int
    /// Seconds in zones 1 to 5, index 0 is zone 1. All zero when the watch
    /// recorded no heart rate, or when there is no age to cut zones from.
    var zoneSeconds: [Double] = Array(repeating: 0, count: 5)
    /// Seconds under half the highest heart rate.
    var calmSeconds: Double = 0
    /// Metres walked or run, for the types a distance is read for.
    var distance: Double?
    /// Heart rate samples during the workout, in order.
    var heartRate: [Double] = []

    var id: Date { start }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var hasZones: Bool { zoneSeconds.contains { $0 > 0 } }
    var name: String { FitnessActivities.name(activity) }
}

/// Heart rate zones cut from the highest heart rate, the same five the Cardio
/// page draws (``BodyMath/Zone``): zone 1 starts at half the highest, each
/// next zone ten points on.
nonisolated enum FitnessZones {
    /// The bpm span of each zone, index 0 is zone 1. Nil without an age.
    static func ranges(maxHeartRate: Double?) -> [ClosedRange<Int>]? {
        guard let maxHeartRate, maxHeartRate > 0 else { return nil }
        return (1...5).map { zone in
            let low = Int((maxHeartRate * Double(40 + 10 * zone) / 100).rounded(.up))
            let high = zone == 5
                ? Int(maxHeartRate.rounded(.down))
                : Int((maxHeartRate * Double(50 + 10 * zone) / 100).rounded(.up)) - 1
            return low...max(low, high)
        }
    }

    /// The zone, 1 to 5, a heart rate falls in, or nil under half the highest.
    static func zone(for bpm: Double, maxHeartRate: Double) -> Int? {
        guard maxHeartRate > 0 else { return nil }
        let share = bpm / maxHeartRate
        return (1...5).last { share >= Double(40 + 10 * $0) / 100 }
    }

    /// Seconds in each zone and under them for the samples of one workout.
    ///
    /// Each sample holds until the next one, the end of the workout, or
    /// `longestGap`, whichever comes first, the same rule as
    /// ``BodyMath/zoneMinutes(heartRate:workouts:maxHeartRate:longestGap:)``.
    static func seconds(
        samples: [HealthReading],
        start: Date,
        end: Date,
        maxHeartRate: Double,
        longestGap: TimeInterval = 60
    ) -> (zones: [Double], calm: Double) {
        var zones = Array(repeating: 0.0, count: 5)
        var calm = 0.0
        let inside = samples.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
        for (index, sample) in inside.enumerated() {
            let next = index + 1 < inside.count ? inside[index + 1].start : end
            let held = min(next.timeIntervalSince(sample.start), longestGap)
            guard held > 0, maxHeartRate > 0 else { continue }
            if let zone = zone(for: sample.value, maxHeartRate: maxHeartRate) {
                zones[zone - 1] += held
            } else {
                calm += held
            }
        }
        return (zones, calm)
    }

    /// Workout readings turned into workouts with their zone time.
    static func workouts(
        _ readings: [HealthReading],
        heartRate: [HealthReading],
        maxHeartRate: Double?,
        distances: [Date: Double] = [:]
    ) -> [FitnessWorkout] {
        readings.map { reading in
            let samples = heartRate
                .filter { $0.start >= reading.start && $0.start < reading.end }
                .sorted { $0.start < $1.start }
            var workout = FitnessWorkout(
                start: reading.start,
                end: reading.end,
                activity: Int(reading.value),
                distance: distances[reading.start],
                heartRate: samples.map(\.value)
            )
            if let maxHeartRate {
                let split = seconds(samples: samples, start: reading.start, end: reading.end, maxHeartRate: maxHeartRate)
                workout.zoneSeconds = split.zones
                workout.calmSeconds = split.calm
            }
            return workout
        }
        .sorted { $0.start < $1.start }
    }
}
