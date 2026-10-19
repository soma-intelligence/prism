//
//  PulseSignals.swift
//  Prism
//

import Foundation
import HealthExportCore

/// A stretch of the day when the heart ran well above resting while the body
/// was still: what the page calls a stress peak.
///
/// Health has no stress reading. A heart that climbs thirty beats above its
/// resting rate with no steps and no workout around it is the plainest sign of
/// one the store holds, and the page says what it saw, in beats, rather than
/// claiming more.
struct PulsePeak: Equatable, Sendable {
    var start: Date
    var end: Date
    /// The highest heart rate in the stretch, in beats per minute.
    var peak: Double
    /// How far the peak sat above resting.
    var above: Double
}

/// A workout, read for the page.
struct PulseWorkout: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Counted in steps: a walk, a run, a hike.
        case onFoot
        /// Counted in heart rate zones: the gym, a ride, a class.
        case other
    }

    var name: String
    var kind: Kind
    var start: Date
    var end: Date
    /// Steps taken during it, for one on foot.
    var steps: Double?
    /// Minutes at seventy percent of maximum heart rate or above: zone 3 of
    /// five, and higher.
    var zoneThreeMinutes: Double?
    /// Average heart rate during it, when the age for zones is unknown.
    var averageHeartRate: Double?

    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

enum PulseSignals {
    /// Beats above resting that count as raised.
    static let raisedBy: Double = 30
    /// Two raised readings closer than this are one stretch.
    static let peakJoin: TimeInterval = 15 * 60
    /// Steps around a reading that mean the body was moving.
    static let movingSteps: Double = 100
    /// How far around a reading the steps are counted.
    static let stepWindow: TimeInterval = 5 * 60
    /// The margin around a workout where a raised heart is still the workout.
    static let workoutMargin: TimeInterval = 10 * 60

    /// Stress peaks since waking, oldest first, at most four: the highest ones
    /// when there are more.
    ///
    /// Nothing is found without a resting rate to measure against, and nothing
    /// without any steps today, since then stillness cannot be told from a
    /// phone left on a desk.
    static func peaks(
        heartRate: [HealthReading],
        since start: Date,
        resting: Double?,
        steps: [HealthReading],
        stepsToday: Double?,
        workouts: [PulseWorkout]
    ) -> [PulsePeak] {
        guard let resting, let stepsToday, stepsToday > 0 else { return [] }
        let threshold = resting + raisedBy

        let raised = heartRate
            .filter { $0.start >= start && $0.value >= threshold }
            .filter { reading in
                !workouts.contains { workout in
                    reading.start >= workout.start.addingTimeInterval(-workoutMargin)
                        && reading.start <= workout.end.addingTimeInterval(workoutMargin)
                }
            }
            .filter { reading in
                let window = reading.start.addingTimeInterval(-stepWindow)..<reading.start.addingTimeInterval(stepWindow)
                let moved = steps
                    .filter { $0.end > window.lowerBound && $0.start < window.upperBound }
                    .reduce(0) { $0 + $1.value }
                return moved < movingSteps
            }
            .sorted { $0.start < $1.start }

        var stretches: [[HealthReading]] = []
        for reading in raised {
            if let last = stretches.last?.last, reading.start.timeIntervalSince(last.start) <= peakJoin {
                stretches[stretches.count - 1].append(reading)
            } else {
                stretches.append([reading])
            }
        }

        // One raised reading is a spike: a sneeze, a flight of stairs the
        // phone missed. A stretch needs two.
        let found = stretches.filter { $0.count >= 2 }.compactMap { stretch -> PulsePeak? in
            guard let first = stretch.first, let last = stretch.last,
                  let peak = stretch.map(\.value).max() else { return nil }
            return PulsePeak(start: first.start, end: last.end, peak: peak, above: peak - resting)
        }

        return Array(found.sorted { $0.above > $1.above }.prefix(4)).sorted { $0.start < $1.start }
    }

    /// The day's workouts, read for the page, oldest first.
    static func workouts(
        _ readings: [HealthReading],
        steps: [Date: Double],
        heartRate: [HealthReading],
        age: Int?
    ) -> [PulseWorkout] {
        readings.sorted { $0.start < $1.start }.map { reading in
            let (name, kind) = describe(activity: Int(reading.value))
            let during = heartRate
                .filter { $0.start >= reading.start && $0.start <= reading.end }
                .sorted { $0.start < $1.start }
            var workout = PulseWorkout(name: name, kind: kind, start: reading.start, end: reading.end)
            if kind == .onFoot {
                workout.steps = steps[reading.start]
            } else if let age, !during.isEmpty {
                workout.zoneThreeMinutes = zoneThreeMinutes(during, maximum: Double(220 - age), until: reading.end)
            } else if !during.isEmpty {
                workout.averageHeartRate = during.map(\.value).reduce(0, +) / Double(during.count)
            }
            return workout
        }
    }

    /// Minutes at or above seventy percent of `maximum`, each reading counting
    /// until the next one and never for more than a minute: a watch that
    /// lost contact for ten minutes did not see ten minutes of effort.
    static func zoneThreeMinutes(_ readings: [HealthReading], maximum: Double, until end: Date) -> Double {
        let threshold = 0.7 * maximum
        var seconds: TimeInterval = 0
        for (index, reading) in readings.enumerated() where reading.value >= threshold {
            let next = index + 1 < readings.count ? readings[index + 1].start : end
            seconds += min(max(next.timeIntervalSince(reading.start), 0), 60)
        }
        return seconds / 60
    }

    /// The name a workout reads under, from its `HKWorkoutActivityType` raw
    /// value, and how it is counted.
    static func describe(activity: Int) -> (String, PulseWorkout.Kind) {
        switch activity {
        case 52: ("Walk", .onFoot)
        case 37: ("Run", .onFoot)
        case 24: ("Hike", .onFoot)
        case 70, 71: ("Wheelchair", .other)
        case 13, 74: ("Ride", .other)
        case 50, 20, 59, 11: ("Gym", .other)
        case 63: ("Intervals", .other)
        case 57: ("Yoga", .other)
        case 66, 58: ("Pilates", .other)
        case 46: ("Swim", .other)
        case 35: ("Row", .other)
        case 16: ("Elliptical", .other)
        case 44, 68, 69: ("Stairs", .other)
        case 77, 78: ("Dance", .other)
        case 29, 62, 72, 80: ("Stretch", .other)
        case 8, 65, 28: ("Boxing", .other)
        case 48, 79: ("Racket", .other)
        default: ("Workout", .other)
        }
    }

    /// The middle value, or nil for none.
    nonisolated static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The value a share of the way through the sorted values.
    static func percentile(_ values: [Double], _ share: Double) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let position = share * Double(sorted.count - 1)
        let low = Int(position.rounded(.down))
        let high = Int(position.rounded(.up))
        let fraction = position - Double(low)
        return sorted[low] * (1 - fraction) + sorted[high] * fraction
    }

    /// One value per day, the days' own readings reduced by `reduce`.
    static func daily(
        _ readings: [HealthReading],
        calendar: Calendar,
        reduce: ([Double]) -> Double?
    ) -> [Date: Double] {
        Dictionary(grouping: readings) { calendar.startOfDay(for: $0.start) }
            .compactMapValues { reduce($0.map(\.value)) }
    }
}
