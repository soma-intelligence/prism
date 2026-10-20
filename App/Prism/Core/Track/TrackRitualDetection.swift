//
//  TrackRitualDetection.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// What Apple Health recorded that a ritual step can be read from: wake
/// times, time in daylight, steps, workouts, mindful sessions and water.
///
/// Plain readings, so the rules are tested without a Health store. Every
/// type here is already in ``HealthAccess``'s one request.
struct TrackRitualSignals: Sendable, Equatable {
    /// Sleep analysis samples, for when each morning began.
    var sleep: [HealthReading] = []
    /// Time in daylight, in minutes per sample.
    var daylight: [HealthReading] = []
    /// Step counts. Read for the strip's days only: a watch writes hundreds
    /// of samples a day.
    var steps: [HealthReading] = []
    /// Workouts, each carrying its `HKWorkoutActivityType` raw value.
    var workouts: [HealthReading] = []
    /// Mindful sessions.
    var mindful: [HealthReading] = []
    /// Water drunk, in millilitres, from Health and from the Journal's own
    /// drinks.
    var water: [HealthReading] = []

    enum Metric {
        static let daylight = "HKQuantityTypeIdentifierTimeInDaylight"
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let water = "HKQuantityTypeIdentifierDietaryWater"

        static let all = [daylight, steps, water] + MindInputs.Metric.all
    }

    /// The readings `inputs` does not already hold, read from `source`, laid
    /// beside the ones it does. A read that fails is left empty, and the
    /// steps it fed are simply not ticked.
    static func read(from source: any HealthSampleSource, inputs: MindInputs, stepDays: Int,
                     now: Date, calendar: Calendar) async -> TrackRitualSignals {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -MindInputs.days, to: today) ?? today
        let stepStart = calendar.date(byAdding: .day, value: -stepDays, to: today) ?? today

        @Sendable func samples(_ identifier: String, from: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: from, to: now, limit: 0)) ?? []
        }

        async let daylight = samples(Metric.daylight, from: start)
        async let steps = samples(Metric.steps, from: stepStart)
        async let water = samples(Metric.water, from: start)
        return TrackRitualSignals(
            sleep: inputs.sleep,
            daylight: await daylight,
            steps: await steps,
            workouts: inputs.workouts,
            mindful: inputs.mindful,
            water: await water
        )
    }
}

/// Which ritual steps tick themselves from Apple Health, and when.
///
/// A step is read by its glyph, so a step the person adds with the same
/// glyph is read the same way. Each rule looks inside the ritual's window:
/// from waking to noon for the morning, from 17:00 to midnight for the
/// evening. A step whose glyph has no rule (screens away, reading, a
/// supplement) stays the person's to tick: nothing on the phone records it.
///
/// - Daylight: time in daylight inside the window reaches the minutes the
///   step names, or 10.
/// - Walk: a walk or hike workout inside the window, or a run of minutes at
///   walking pace (80 steps a minute or more) as long as the step names, or
///   10.
/// - Stretch: a yoga, flexibility, pilates, tai chi, mind and body,
///   cool down or recovery workout inside the window.
/// - Breathe and meditate: mindful minutes inside the window reach the
///   minutes the step names, or 1.
/// - Water: any water logged inside the window.
/// - Exercise and training: any workout of 10 minutes or more inside the
///   window.
enum TrackRitualDetection {
    enum Rule: Equatable, Sendable {
        case daylight(minutes: Double)
        case walk(minutes: Double)
        case stretch
        case mindful(minutes: Double)
        case water
        case workout
    }

    /// `HKWorkoutActivityType`: walking and hiking.
    static let walkActivities: Set<Int> = [52, 24]
    /// `HKWorkoutActivityType`: mind and body, yoga, flexibility, pilates,
    /// tai chi, preparation and recovery, cool down.
    static let stretchActivities: Set<Int> = [29, 57, 62, 66, 72, 73, 80]
    /// Steps in five minutes that count as walking pace: 80 a minute.
    static let walkingPaceSteps = 400.0
    /// The bins a walk is found in, in seconds.
    static let walkBin: TimeInterval = 5 * 60
    /// The shortest workout the exercise rule counts.
    static let workoutMinimum: TimeInterval = 10 * 60

    /// How a step is read, or nil when Health cannot tell.
    static func rule(for step: TrackRitualStep) -> Rule? {
        let named = minutes(in: step.title)
        switch step.kind {
        case .daylight: return .daylight(minutes: named ?? 10)
        case .walk, .steps: return .walk(minutes: named ?? 10)
        case .stretch: return .stretch
        case .breathe, .meditation: return .mindful(minutes: named ?? 1)
        case .drink: return .water
        case .exercise, .training: return .workout
        default: return nil
        }
    }

    /// The minutes a step's name gives it: "Daylight, 10 minutes" is 10.
    static func minutes(in title: String) -> Double? {
        let pattern = /(\d+)\s*(?:min|minute|minutes)\b/
        guard let match = title.lowercased().firstMatch(of: pattern) else { return nil }
        return Double(match.1)
    }

    /// When on `day` a ritual is looked for, cut at `now`, or nil when the
    /// window has not begun.
    static func window(_ moment: TrackRitualMoment, on day: Date, wake: Date?,
                       now: Date, calendar: Calendar) -> DateInterval? {
        let start = calendar.startOfDay(for: day)
        func at(_ hour: Int) -> Date { calendar.date(byAdding: .hour, value: hour, to: start) ?? start }
        let from: Date
        var to: Date
        switch moment {
        case .morning:
            // From waking, or 04:00 with no night recorded, to noon; a late
            // riser still gets four hours.
            from = wake.flatMap { calendar.isDate($0, inSameDayAs: start) ? $0 : nil } ?? at(4)
            to = max(at(12), from.addingTimeInterval(4 * 3600))
        case .evening:
            from = at(17)
            to = at(24)
        }
        to = min(to, now)
        return to > from ? DateInterval(start: from, end: to) : nil
    }

    /// Whether `rule` happened inside `window`.
    static func holds(_ rule: Rule, in window: DateInterval, signals: TrackRitualSignals) -> Bool {
        switch rule {
        case .daylight(let minutes):
            return inside(signals.daylight, window).reduce(0) { $0 + $1.value } >= minutes
        case .walk(let minutes):
            let walked = signals.workouts.contains {
                walkActivities.contains(Int($0.value)) && overlap($0, window) > 0
            }
            return walked || longestWalk(signals.steps, in: window) >= minutes * 60
        case .stretch:
            return signals.workouts.contains {
                stretchActivities.contains(Int($0.value)) && overlap($0, window) > 0
            }
        case .mindful(let minutes):
            return signals.mindful.reduce(0) { $0 + overlap($1, window) } / 60 >= minutes
        case .water:
            return inside(signals.water, window).contains { $0.value > 0 }
        case .workout:
            return signals.workouts.contains { overlap($0, window) >= workoutMinimum }
        }
    }

    /// The step ids Health ticked on each day, for every ritual.
    static func detected(_ rituals: [TrackRitual], days: [Date], signals: TrackRitualSignals,
                         now: Date, calendar: Calendar) -> [Date: Set<String>] {
        var wakes: [Date: Date] = [:]
        for night in PulseNights.nights(from: signals.sleep, calendar: calendar) {
            wakes[calendar.startOfDay(for: night.woke)] = night.woke
        }
        var found: [Date: Set<String>] = [:]
        for day in days.map(calendar.startOfDay(for:)) {
            for ritual in rituals {
                guard let window = window(ritual.moment, on: day, wake: wakes[day], now: now, calendar: calendar) else { continue }
                for step in ritual.steps {
                    guard let rule = rule(for: step), holds(rule, in: window, signals: signals) else { continue }
                    found[day, default: []].insert(step.id)
                }
            }
        }
        return found
    }

    // MARK: Arithmetic

    /// Readings whose time falls in the window, each scaled to the share of
    /// it inside: a daylight sample half in the window counts half.
    private static func inside(_ readings: [HealthReading], _ window: DateInterval) -> [HealthReading] {
        readings.compactMap { reading in
            let length = reading.end.timeIntervalSince(reading.start)
            if length <= 0 {
                return window.contains(reading.start) ? reading : nil
            }
            let share = overlap(reading, window) / length
            guard share > 0 else { return nil }
            return HealthReading(metric: reading.metric, value: reading.value * share, unit: reading.unit,
                                 start: reading.start, end: reading.end)
        }
    }

    /// Seconds of the reading inside the window.
    private static func overlap(_ reading: HealthReading, _ window: DateInterval) -> TimeInterval {
        max(0, min(reading.end, window.end).timeIntervalSince(max(reading.start, window.start)))
    }

    /// The longest run of five minute bins at walking pace inside the
    /// window, in seconds. Each sample's steps are spread evenly over its
    /// span, so a long sample from a quiet hour never reads as a walk.
    static func longestWalk(_ steps: [HealthReading], in window: DateInterval) -> TimeInterval {
        let count = Int((window.duration / walkBin).rounded(.up))
        guard count > 0 else { return 0 }
        var bins = [Double](repeating: 0, count: count)
        for sample in steps {
            let length = max(sample.end.timeIntervalSince(sample.start), 1)
            let from = max(sample.start, window.start), to = min(max(sample.end, sample.start.addingTimeInterval(1)), window.end)
            guard to > from else { continue }
            var cursor = from
            while cursor < to {
                let index = min(Int(cursor.timeIntervalSince(window.start) / walkBin), count - 1)
                let binEnd = window.start.addingTimeInterval(Double(index + 1) * walkBin)
                let piece = min(binEnd, to).timeIntervalSince(cursor)
                bins[index] += sample.value * piece / length
                cursor = cursor.addingTimeInterval(max(piece, 1))
            }
        }
        var longest = 0, run = 0
        for value in bins {
            run = value >= walkingPaceSteps ? run + 1 : 0
            longest = max(longest, run)
        }
        return Double(longest) * walkBin
    }
}
