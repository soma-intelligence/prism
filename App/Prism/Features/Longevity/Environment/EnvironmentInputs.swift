//
//  EnvironmentInputs.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What the Environment lens and the Around you card on Today are built from:
/// time in daylight and the sound around you and in your headphones, as the
/// watch recorded them into Apple Health.
///
/// UV comes from Apple Health when an app or sensor writes it there. Air
/// quality and the temperature need a weather source the app does not have
/// (no WeatherKit entitlement), so neither is here: the pages show a dash.
/// Sunrise and sunset are worked out on the device (``EnvironmentSun``).
struct EnvironmentInputs: Sendable, Equatable {
    var now: Date
    /// Time in daylight samples since midnight, each a stretch outside.
    var daylightToday: [HealthReading] = []
    /// Minutes of daylight per day, keyed by the day's midnight. The last 31
    /// days for the card; the whole year for the lens, which draws it.
    var daylightByDay: [Date: Double] = [:]
    /// Environmental sound level samples over the last 31 days, in dBA.
    var sound: [HealthReading] = []
    /// Headphone sound level samples over the last 31 days, in dBA. The
    /// report averages the last seven for the weekly limit.
    var headphones: [HealthReading] = []
    /// UV index samples over the last 31 days, from whatever app or sensor
    /// writes them to Apple Health.
    var uv: [HealthReading] = []

    enum Metric {
        static let daylight = "HKQuantityTypeIdentifierTimeInDaylight"
        static let sound = "HKQuantityTypeIdentifierEnvironmentalAudioExposure"
        static let headphones = "HKQuantityTypeIdentifierHeadphoneAudioExposure"
        static let uv = "HKQuantityTypeIdentifierUVExposure"
    }

    static let metrics = [Metric.daylight, Metric.sound, Metric.headphones, Metric.uv]

    var isEmpty: Bool {
        daylightToday.isEmpty && daylightByDay.isEmpty && sound.isEmpty && headphones.isEmpty && uv.isEmpty
    }

    /// Reads everything at once. `wholeYear` reads a daylight total for every
    /// day since the first of January, which the lens's grid needs and the
    /// Today card does not.
    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar, wholeYear: Bool) async -> EnvironmentInputs {
        let today = calendar.startOfDay(for: now)
        let monthAgo = calendar.date(byAdding: .day, value: -31, to: today) ?? today
        let january = calendar.dateInterval(of: .year, for: now)?.start ?? today
        let daylightFrom = wholeYear ? min(january, monthAgo) : monthAgo

        @Sendable func samples(_ identifier: String, from start: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        }

        async let daylightToday = samples(Metric.daylight, from: today)
        async let sound = samples(Metric.sound, from: monthAgo)
        async let headphones = samples(Metric.headphones, from: monthAgo)
        async let uv = samples(Metric.uv, from: monthAgo)
        async let byDay = dailyTotals(Metric.daylight, from: daylightFrom, now: now, source: source, calendar: calendar)

        return EnvironmentInputs(
            now: now,
            daylightToday: await daylightToday,
            daylightByDay: await byDay,
            sound: await sound,
            headphones: await headphones,
            uv: await uv
        )
    }

    /// One total per day from `start` to today, a handful in flight at a time.
    private static func dailyTotals(
        _ identifier: String,
        from start: Date,
        now: Date,
        source: any HealthSampleSource,
        calendar: Calendar
    ) async -> [Date: Double] {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [:] }
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day <= now {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return await withTaskGroup(of: (Date, Double?).self) { group in
            var result: [Date: Double] = [:]
            var pending = days.makeIterator()

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
