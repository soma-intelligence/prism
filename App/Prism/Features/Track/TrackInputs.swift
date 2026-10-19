//
//  TrackInputs.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Journal reads from Apple Health: sixty days of sleep and heart
/// rate variability, and the heart's average over each night.
///
/// Plain values, so the Journal's arithmetic is tested without a Health store.
struct TrackInputs: Sendable, Equatable {
    var now: Date
    /// Sleep analysis samples, each carrying its coded stage.
    var sleep: [HealthReading] = []
    /// Heart rate variability (SDNN) samples.
    var variability: [HealthReading] = []
    /// The average heart rate across each night asleep, keyed by the night's
    /// day: the morning it ended on.
    var overnightHeart: [Date: Double] = [:]

    /// How far back the Journal reads: the effects card's sixty days, and the
    /// night after the first of them.
    static let windowDays = 61

    enum Metric {
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
        static let variability = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let heartRate = "HKQuantityTypeIdentifierHeartRate"
        static let mindful = "HKCategoryTypeIdentifierMindfulSession"
    }

    /// Everything the Journal needs, read from `source`. A read that fails is
    /// left empty, and whatever it would have fed renders its empty state.
    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> TrackInputs {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -windowDays, to: today) ?? today

        @Sendable func samples(_ identifier: String) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        }

        async let sleep = samples(Metric.sleep)
        async let variability = samples(Metric.variability)
        let readSleep = await sleep

        // One average per night, over the span actually asleep: a handful of
        // statistics queries rather than every heart beat of two months.
        var overnight: [Date: Double] = [:]
        if let heart = HealthMetricCatalog.metric(for: Metric.heartRate) {
            for night in PulseNights.nights(from: readSleep, calendar: calendar) {
                if let reading = try? await source.average(heart, from: night.fellAsleep, to: night.woke) {
                    overnight[night.day] = reading.value
                }
            }
        }

        return TrackInputs(now: now, sleep: readSleep, variability: await variability, overnightHeart: overnight)
    }
}

/// The daily series the Journal sets against its tags, each keyed by the start
/// of the day a tag would be logged on.
///
/// A night's readings belong to the evening before it: a coffee at four is
/// logged on Tuesday and shows in the sleep that ends on Wednesday morning.
struct TrackBody: Equatable, Sendable {
    /// Deep sleep in minutes on the night after the day.
    var deepSleep: [Date: Double] = [:]
    /// The median heart rate variability measured on the day, in ms.
    var dayVariability: [Date: Double] = [:]
    /// The median heart rate variability on the morning after the day, in ms.
    var nextMorningVariability: [Date: Double] = [:]
    /// The average heart rate across the night after the day, in bpm.
    var overnightHeart: [Date: Double] = [:]
    /// Hours asleep on the night that ended on the morning of the day: the
    /// sleep a person wakes into, which is the one a day's journal shows.
    var nightAsleep: [Date: Double] = [:]

    /// The usual day's variability: the median over the whole window.
    var usualVariability: Double? { EffectMath.median(Array(dayVariability.values)) }

    static func make(from inputs: TrackInputs, calendar: Calendar) -> TrackBody {
        var body = TrackBody()

        func dayBefore(_ date: Date) -> Date? {
            calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))
        }

        for night in PulseNights.nights(from: inputs.sleep, calendar: calendar) {
            if let deep = night.deep, let key = dayBefore(night.day) {
                body.deepSleep[key] = deep / 60
            }
            if night.asleep > 0 {
                body.nightAsleep[calendar.startOfDay(for: night.day)] = night.asleep / 3600
            }
        }
        for (day, value) in inputs.overnightHeart {
            if let key = dayBefore(day) { body.overnightHeart[key] = value }
        }

        var byDay: [Date: [Double]] = [:]
        var byMorning: [Date: [Double]] = [:]
        for reading in inputs.variability {
            let day = calendar.startOfDay(for: reading.start)
            byDay[day, default: []].append(reading.value)
            if calendar.component(.hour, from: reading.start) < 12, let key = dayBefore(day) {
                byMorning[key, default: []].append(reading.value)
            }
        }
        body.dayVariability = byDay.compactMapValues { EffectMath.median($0) }
        body.nextMorningVariability = byMorning.compactMapValues { EffectMath.median($0) }
        return body
    }
}

/// One day's totals from Apple Health, for the Journal's automatic rows:
/// steps, time in daylight and exercise minutes. Each is nil when Health
/// holds nothing for the day, which the row shows as a dash.
///
/// Every type here is already in ``HealthAccess``'s one request.
struct TrackDayTotals: Sendable, Equatable {
    var steps: Double?
    var daylightMinutes: Double?
    var exerciseMinutes: Double?

    enum Metric {
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let daylight = "HKQuantityTypeIdentifierTimeInDaylight"
        static let exercise = "HKQuantityTypeIdentifierAppleExerciseTime"
    }

    /// The goals the rows are met at.
    enum Goal {
        static let steps = 8_000.0
        static let daylightMinutes = 30.0
        static let exerciseMinutes = 30.0
        static let sleepHours = 7.0
    }

    static func read(from source: any HealthSampleSource, day: Date, now: Date, calendar: Calendar) async -> TrackDayTotals {
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let end = min(next, max(now, start))

        @Sendable func total(_ identifier: String) async -> Double? {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
            return (try? await source.total(metric, from: start, to: end))?.value
        }

        async let steps = total(Metric.steps)
        async let daylight = total(Metric.daylight)
        async let exercise = total(Metric.exercise)
        return TrackDayTotals(steps: await steps, daylightMinutes: await daylight, exerciseMinutes: await exercise)
    }
}
