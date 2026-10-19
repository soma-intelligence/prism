//
//  MindMoodForecast.swift
//  Prism
//
//  A mood for the day ahead, from the signals already in hand: last night's
//  sleep score, overnight HRV and
//  resting heart rate against their baselines, yesterday's daylight, and the
//  last feeling logged. A transparent heuristic, not a trained model, so the
//  page says how confident it is and checks itself against what was logged.
//

import Foundation

nonisolated enum MindMoodForecast {
    enum Signal: String, CaseIterable, Sendable {
        case sleep, autonomic, daylight, priorMood
    }

    enum Band: String, Sendable {
        case low, steady, bright

        static let steadyFrom: Double = 42
        static let brightFrom: Double = 62

        init(_ index: Double) {
            switch index {
            case ..<Self.steadyFrom: self = .low
            case ..<Self.brightFrom: self = .steady
            default: self = .bright
            }
        }

        var title: String {
            switch self {
            case .low: "A heavier day"
            case .steady: "A steady day"
            case .bright: "A bright day"
            }
        }
    }

    enum Confidence: String, Sendable {
        case low, fair, good

        init(signals: Int) {
            switch signals {
            case ...1: self = .low
            case 2: self = .fair
            default: self = .good
            }
        }

        var title: String {
            switch self {
            case .low: "Low"
            case .fair: "Fair"
            case .good: "Good"
            }
        }
    }

    /// The one thing still worth doing: the most negative signal, when it is
    /// meaningfully off.
    enum Lever: String, Sendable {
        case protectSleep, morningLight, easeToday, planJoy, keepRhythm

        var title: String {
            switch self {
            case .protectSleep: "In bed on time tonight"
            case .morningLight: "Ten minutes of morning light"
            case .easeToday: "Keep today light"
            case .planJoy: "Plan one thing you enjoy"
            case .keepRhythm: "Keep your rhythm"
            }
        }

        var detail: String {
            switch self {
            case .protectSleep: "Sleep pulls the forecast down the most. A full night lifts the next one."
            case .morningLight: "Daylight ran short. Light early in the day lifts mood by the afternoon."
            case .easeToday: "Your heart is under strain. A lighter day and slow breathing help it settle."
            case .planJoy: "The last feeling you logged was low. Something small to look forward to helps."
            case .keepRhythm: "Nothing is pulling the forecast down. The same bedtime keeps it there."
            }
        }
    }

    struct Inputs: Equatable, Sendable {
        var sleepScore: Int?
        var overnightHRV: Double?
        var hrvBaseline: Double?
        var restingHR: Double?
        var restingBaseline: Double?
        var daylightMinutes: Double?
        /// The last feeling logged, 0 (very unpleasant) to 1 (very pleasant).
        var priorMood: Double?
    }

    struct Reading: Equatable, Sendable {
        /// 0 (heavy) to 100 (bright); 50 is a neutral day.
        var index: Double
        var band: Band
        var confidence: Confidence
        var lever: Lever
        /// Each signal's push on the index, in points.
        var contributions: [Signal: Double]
    }

    static let neutral: Double = 50

    /// Nil when no signal is in hand: no honest forecast, rather than a 50.
    static func forecast(_ inputs: Inputs) -> Reading? {
        var parts: [Signal: Double] = [:]
        if let score = inputs.sleepScore, score > 0 {
            parts[.sleep] = clamp((Double(score) - 65) / 35 * 18, -18, 18)
        }
        var autonomic = 0.0
        var hasAutonomic = false
        if let hrv = inputs.overnightHRV, let base = inputs.hrvBaseline, hrv > 0, base > 0 {
            autonomic += (clamp(hrv / base, 0.7, 1.3) - 1) / 0.3 * 12
            hasAutonomic = true
        }
        if let resting = inputs.restingHR, let base = inputs.restingBaseline, resting > 0, base > 0 {
            autonomic += -(clamp(resting / base, 0.85, 1.15) - 1) / 0.15 * 8
            hasAutonomic = true
        }
        if hasAutonomic { parts[.autonomic] = autonomic }
        if let daylight = inputs.daylightMinutes {
            parts[.daylight] = (clamp(daylight, 0, 120) / 120 - 0.5) * 2 * 8
        }
        if let mood = inputs.priorMood {
            parts[.priorMood] = (clamp(mood, 0, 1) - 0.5) * 2 * 10
        }
        guard !parts.isEmpty else { return nil }

        let index = clamp(neutral + parts.values.reduce(0, +), 0, 100)
        let lever: Lever
        if let worst = parts.min(by: { $0.value < $1.value }), worst.value < -2 {
            lever = switch worst.key {
            case .sleep: .protectSleep
            case .daylight: .morningLight
            case .autonomic: .easeToday
            case .priorMood: .planJoy
            }
        } else {
            lever = .keepRhythm
        }
        return Reading(index: index, band: Band(index), confidence: Confidence(signals: parts.count), lever: lever, contributions: parts)
    }

    /// Days whose logged mood landed within `margin` of the forecast, of the
    /// days with both.
    static func track(forecasts: [Date: Double], felt: [Date: Double], margin: Double = 8) -> (within: Int, of: Int) {
        let days = forecasts.keys.filter { felt[$0] != nil }
        let within = days.filter { abs((felt[$0] ?? 0) - (forecasts[$0] ?? 0)) <= margin }.count
        return (within, days.count)
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
