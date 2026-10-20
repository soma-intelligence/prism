//
//  PulseInputs.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Today page is built from: the readings as Apple Health returned
/// them, and the clock they were read at.
///
/// Plain values, so the page's arithmetic is tested without a Health store: a
/// test writes one of these and reads the page it makes. `HealthDashboard`
/// fills one from the store in `loadToday()`.
struct PulseInputs: Sendable, Equatable {
    var now: Date
    /// Sleep analysis samples over the last month, each carrying its coded
    /// stage: in bed, asleep, awake, core, deep, REM.
    var sleep: [HealthReading] = []
    /// Heart rate samples since the evening before last, so last night is in.
    var heartRate: [HealthReading] = []
    /// Resting heart rate over the last month. Health writes about one a day.
    var restingHeartRate: [HealthReading] = []
    /// Heart rate variability (SDNN) over the last month.
    var heartRateVariability: [HealthReading] = []
    /// Step samples since midnight, to tell a heart raised at rest from one
    /// raised on the move.
    var steps: [HealthReading] = []
    /// Steps since midnight, as Health totals them with each device counted
    /// once.
    var stepsToday: Double?
    /// Exercise minutes since midnight.
    var exerciseToday: Double?
    /// Exercise minutes from midnight to this time of day, on each of the
    /// previous fourteen days that holds any.
    var exerciseByNowBefore: [Double] = []
    /// Workouts since midnight, each carrying its coded activity type.
    var workouts: [HealthReading] = []
    /// Steps taken during each of those workouts, keyed by its start.
    var workoutSteps: [Date: Double] = [:]
    /// Mindful sessions since midnight.
    var mindful: [HealthReading] = []
    /// Age in whole years, from the date of birth in Health.
    var age: Int?
    /// The latest VO2 max from the watch in the last sixteen weeks, which
    /// fitness age is read off.
    var vo2Max: Double?
    /// The sex fitness age is read with.
    var sex: BodyFitnessAge.Sex = .unknown

    /// Whether Health returned anything at all for the page to read.
    var isEmpty: Bool {
        sleep.isEmpty && heartRate.isEmpty && restingHeartRate.isEmpty
            && heartRateVariability.isEmpty && steps.isEmpty && stepsToday == nil
            && exerciseToday == nil && workouts.isEmpty && mindful.isEmpty
    }
}
