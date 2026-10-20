//
//  MindNightStress.swift
//  Prism
//
//  Last night's stress, half hour by half hour, so the day reads whole:
//  the night, then the day.
//
//  The day's line leaves sleep out (a slow heart is not a calm one, and the
//  waking model reads heart rate against rest). The night is read with the
//  same acute model and the same scale, from what the watch measures while
//  you sleep: each half hour's heart rate against your resting rate, and the
//  HRV read nearest to it against your baseline, as the model's floor. The
//  model's own day uses one HRV for the whole day; the night has several
//  readings, so each half hour takes the nearest, then the night's own mean,
//  then the day's, in that order.
//
//  The grid is the day's: half hours from local midnight, counted back
//  before it for a night that began the evening before, so a night half hour
//  and a day half hour never overlap. A half hour belongs to the night when
//  its middle falls inside the night's window, the exact complement of the
//  rule that leaves it out of the day.
//

import Foundation
import HealthScoring

/// Last night on the stress line: its window and its half hours.
nonisolated struct MindStressNight: Equatable, Sendable, Codable {
    /// When sleep began, clamped to ``MindNightStress/earliestBefore`` before
    /// midnight.
    var start: Date
    /// When you woke.
    var end: Date
    /// The night's half hours, oldest first. Empty when nothing was read.
    var samples: [MindStressSample]
}

nonisolated enum MindNightStress {
    /// A night that began earlier than this before midnight is drawn from
    /// here: the chart has room for an evening, not a whole day.
    static let earliestBefore: TimeInterval = 6 * 60 * 60
    /// How far from a half hour's middle an HRV reading still speaks for it.
    static let hrvReach: TimeInterval = 60 * 60
    static let span = TimeInterval(ScoringIntradayStress.bucketMinutes * 60)

    /// Last night, when it ended today (after `dayStart`, before `now`).
    static func window(_ nights: [ScoringNightWindow?], dayStart: Date, now: Date) -> ScoringNightWindow? {
        let ended = nights.compactMap { $0 }.filter { $0.end > dayStart && $0.end <= now && $0.end > $0.start }
        guard let last = ended.max(by: { $0.end < $1.end }) else { return nil }
        let start = max(last.start, dayStart.addingTimeInterval(-earliestBefore))
        guard last.end > start else { return nil }
        return ScoringNightWindow(start: start, end: last.end)
    }

    /// The night's half hours on the day's grid.
    ///
    /// - Parameters:
    ///   - heartRate: heart rate readings across the night.
    ///   - hrv: HRV readings across the night.
    ///   - dayHRV: the day's HRV, the last fallback for a half hour with no
    ///     reading near it and a night with none at all.
    static func line(window: ScoringNightWindow,
                     dayStart: Date,
                     heartRate: [ScoringTimedValue],
                     hrv: [ScoringTimedValue],
                     dayHRV: Double?,
                     hrvBaseline: Double?,
                     restingHR: Double?,
                     maxHR: Double) -> [MindStressSample] {
        let first = Int((window.start.timeIntervalSince(dayStart) / span).rounded(.down))
        let last = Int((window.end.timeIntervalSince(dayStart) / span).rounded(.up))
        guard last > first else { return [] }
        let inside = hrv.filter { $0.start >= window.start && $0.start <= window.end && $0.value > 0 }
        let nightHRV = mean(inside.map(\.value))

        return (first..<last).compactMap { index in
            let start = dayStart.addingTimeInterval(Double(index) * span)
            let end = start.addingTimeInterval(span)
            let middle = start.addingTimeInterval(span / 2)
            guard middle >= window.start, middle <= window.end else { return nil }
            let beats = heartRate.filter { $0.start >= start && $0.start < end }
            guard !beats.isEmpty else { return nil }
            let near = inside.filter { abs($0.start.timeIntervalSince(middle)) <= hrvReach }.map(\.value)
            let local = mean(near) ?? nightHRV ?? dayHRV
            // One half hour at a time through the shared model, so the night
            // sits on exactly the scale the day does.
            let point = ScoringIntradayStress.line(
                heartRate: beats, dayStart: start, now: end.addingTimeInterval(-1), excluded: [],
                hrv: local, hrvBaseline: hrvBaseline, restingHR: restingHR, maxHR: maxHR
            ).first
            return point.map { MindStressSample(start: start, value: min(100, max(0, $0.value))) }
        }
    }

    /// Last night from the score inputs: the window, the beats and HRV read
    /// over it, and the same terms the day's line is read with. Nil without
    /// a night that ended today.
    static func read(_ inputs: ScoreDetailInputs, scores: SomaScores?, calendar: Calendar) -> MindStressNight? {
        let dayStart = calendar.startOfDay(for: inputs.now)
        guard let window = window(inputs.nights, dayStart: dayStart, now: inputs.now) else { return nil }
        let terms = scores?.recoveryTerms ?? []
        let hrvTerm = terms.first { $0.kind == .hrv }
        let rhrTerm = terms.first { $0.kind == .rhr }
        let samples = line(
            window: window, dayStart: dayStart,
            heartRate: inputs.lastNightBeats, hrv: inputs.lastNightHRV,
            dayHRV: hrvTerm?.value, hrvBaseline: hrvTerm?.baseline,
            restingHR: rhrTerm?.value ?? rhrTerm?.baseline,
            maxHR: SomaScoringEngine.maxHeartRate(ageYears: inputs.age)
        )
        return MindStressNight(start: window.start, end: window.end, samples: samples)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
