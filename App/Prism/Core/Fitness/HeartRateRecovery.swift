//
//  HeartRateRecovery.swift
//  Prism
//

import Foundation
import HealthExportCore

/// Heart rate recovery: how far the heart falls in the minute after effort.
///
/// Apple Watch logs a one minute
/// recovery sample after most workouts, and that value is the drop itself.
/// The bands follow Cole et al. (1999): a drop of 12 beats or less carries the
/// worst prognosis and larger drops read as healthier autonomic recovery. The
/// trend is a least squares line through the readings, as a change a month.
nonisolated enum HeartRateRecovery {
    enum Band: String, Sendable {
        case poor = "Poor"
        case fair = "Fair"
        case good = "Good"
        case excellent = "Excellent"

        var title: String { rawValue }
    }

    /// The drop under which a doctor's look is worth it.
    static let concernThreshold = 12.0
    static let minimumTrendSamples = 5
    static let meaningfulMonthlySlope = 1.0

    static func band(_ drop: Double) -> Band {
        switch drop {
        case ..<12: .poor
        case ..<20: .fair
        case ..<30: .good
        default: .excellent
        }
    }

    /// Change in the drop per thirty days, from a least squares line through
    /// the readings. Nil under five readings or with all of them on one day.
    static func monthlySlope(_ readings: [HealthReading]) -> Double? {
        let sorted = readings.sorted { $0.start < $1.start }
        guard sorted.count >= minimumTrendSamples, let base = sorted.first?.start else { return nil }
        let xs = sorted.map { $0.start.timeIntervalSince(base) / 86_400 }
        let ys = sorted.map(\.value)
        let n = Double(sorted.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let spread = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard spread > 0 else { return nil }
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        return covariance / spread * 30
    }

    /// The reading nearest the end of `workout`, taken within `window` of it:
    /// the watch writes its recovery sample a little after the session stops.
    static func reading(after workout: FitnessWorkout, in readings: [HealthReading], window: TimeInterval = 15 * 60) -> HealthReading? {
        readings
            .filter { $0.start >= workout.start && $0.start <= workout.end.addingTimeInterval(window) }
            .min { abs($0.start.timeIntervalSince(workout.end)) < abs($1.start.timeIntervalSince(workout.end)) }
    }
}
