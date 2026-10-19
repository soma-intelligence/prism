//
//  VitalityInputs.swift
//  HealthScoring (ported from the previous app, behaviour unchanged)
//
//  Substrate-agnostic inputs for the Vitality engine. Both the NewApp
//  (the host store / its snapshot) and legacy (HealthSnapshotProvider)
//  data worlds build this struct via thin adapters, so the stress and
//  body-battery math has ONE source of truth and stays pure + testable.
//

import Foundation

/// Confidence tier, driven by what the substrate could supply.
enum VitalityTier: String, Sendable, Hashable {
    case rich      // continuous intraday HR + periodic HRV (Watch/Oura/Whoop)
    case daily     // daily HRV + RHR + sleep + workouts, no intraday HR
    case minimal   // backbone only
}

/// One workout, reduced to what the drain + stress sections need.
struct VitalityWorkout: Sendable, Hashable {
    let start: Date
    let end: Date
    /// Edwards HR-zone TRIMP for this workout (0 when no HR was recorded).
    let trimp: Double
}

/// One engine output point. Timestamp + 0..100 value.
struct VitalitySample: Sendable, Hashable {
    let date: Date
    let value: Double
}

/// Everything the engine needs for a single day.
struct VitalityInputs: Sendable {
    // Instantaneous / today
    var hrv: Double?                  // representative RMSSD/SDNN today, ms
    var hrvBaseline: Double?          // personal 28d baseline, ms
    var restingHR: Double?            // bpm
    var restingHRBaseline: Double?    // personal 28d baseline, bpm
    var hrvSpread: Double?            // robust spread of LOG hrv over rolling window
    var rhrSpread: Double?            // robust spread of resting HR, bpm
    var maxHR: Double?                // bpm (Tanaka 208 - 0.7*age if unknown)
    var intradayHeartRate: [Double?]? // ascending buckets across today; nil gaps
    var intradayActiveEnergy: [Double?]? // ascending buckets across today, kcal; nil gaps
    var bucketMinutes: Int            // minutes per intraday bucket (e.g. 30)

    // Daily aggregates
    var sleepScore: Int?              // 0..100 last night
    var previousReserve: Double?      // yesterday's end-of-day battery (stock)
    var todayStrain: Int?             // 0..100 (ScoreCalculator strain)
    var vo2max: Double?               // fitness scaler for exercise drain

    // Timeline (all today unless noted)
    var wakeTime: Date?
    var bedTime: Date?               // typical/expected bedtime
    var sleepOnset: Date?            // last night's onset (for late-workout test)
    var now: Date

    var workouts: [VitalityWorkout]
    var tier: VitalityTier

    init(now: Date,
         bucketMinutes: Int = 30,
         workouts: [VitalityWorkout] = [],
         tier: VitalityTier = .daily) {
        self.now = now
        self.bucketMinutes = bucketMinutes
        self.workouts = workouts
        self.tier = tier
    }
}
