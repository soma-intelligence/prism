//
//  BodyMath.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// The arithmetic the three parts of the Body tab share: a reading against the
/// one eight weeks before it, heart rate zones, and sessions counted by week.
///
/// Pure functions over plain readings, so every number the tab shows is tested
/// without a Health store.
enum BodyMath {
    /// How far back a trend looks.
    static let trendWeeks = 8

    // MARK: - Change against eight weeks ago

    /// The latest value and the one it is compared with.
    struct Change: Equatable, Sendable {
        var latest: Double
        /// The newest reading at or before the start of the window, or nil when
        /// nothing that old is on record.
        var earlier: Double?

        var delta: Double? { earlier.map { latest - $0 } }
    }

    /// The newest reading, by when it ended.
    static func latest(_ readings: [HealthReading]) -> HealthReading? {
        readings.max { $0.end < $1.end }
    }

    /// The latest reading against the newest one taken at least `weeks` weeks
    /// before `now`. Nil when there is no reading at all.
    static func change(
        _ readings: [HealthReading],
        now: Date,
        weeks: Int = trendWeeks,
        calendar: Calendar
    ) -> Change? {
        guard let newest = latest(readings) else { return nil }
        let cutoff = calendar.date(byAdding: .day, value: -7 * weeks, to: now) ?? now
        let earlier = readings
            .filter { $0.end <= cutoff }
            .max { $0.end < $1.end }
        return Change(latest: newest.value, earlier: earlier?.value)
    }

    /// Which way a change went, or nil when it moved less than `tolerance`
    /// either way or there is nothing to compare with.
    static func trend(_ delta: Double?, tolerance: Double) -> SomaTrend? {
        guard let delta, abs(delta) >= tolerance else { return nil }
        return delta > 0 ? .up : .down
    }

    // MARK: - Heart rate zones

    /// The five zones as shares of the highest heart rate.
    enum Zone: Int, CaseIterable, Identifiable, Sendable {
        case one = 1, two, three, four, five

        var id: Int { rawValue }

        var title: String { "Zone \(rawValue)" }

        var name: String {
            switch self {
            case .one: "Easy"
            case .two: "Aerobic"
            case .three: "Tempo"
            case .four: "Threshold"
            case .five: "Max"
            }
        }

        /// The share of the highest heart rate the zone starts at.
        var lowerShare: Double { 0.4 + 0.1 * Double(rawValue) }
    }

    /// The highest heart rate the zones are cut from: 220 less the age. Nil
    /// without an age, since a guess would move every zone.
    static func maxHeartRate(age: Int?) -> Double? {
        guard let age, age > 0, age < 120 else { return nil }
        return Double(220 - age)
    }

    /// The zone a heart rate falls in, or nil below half the highest.
    static func zone(for bpm: Double, maxHeartRate: Double) -> Zone? {
        guard maxHeartRate > 0 else { return nil }
        let share = bpm / maxHeartRate
        return Zone.allCases.last { share >= $0.lowerShare }
    }

    /// Minutes spent in each zone during the workouts.
    ///
    /// Each heart rate sample holds until the next one, the end of its
    /// workout, or `longestGap`, whichever comes first: a watch that lost
    /// contact for ten minutes does not credit the last reading with all ten.
    static func zoneMinutes(
        heartRate: [HealthReading],
        workouts: [HealthReading],
        maxHeartRate: Double,
        longestGap: TimeInterval = 60
    ) -> [Zone: Double] {
        var minutes: [Zone: Double] = [:]
        for workout in workouts {
            let inside = heartRate
                .filter { $0.start >= workout.start && $0.start < workout.end }
                .sorted { $0.start < $1.start }
            for (index, sample) in inside.enumerated() {
                let next = index + 1 < inside.count ? inside[index + 1].start : workout.end
                let held = min(next.timeIntervalSince(sample.start), longestGap)
                guard held > 0, let zone = zone(for: sample.value, maxHeartRate: maxHeartRate) else { continue }
                minutes[zone, default: 0] += held / 60
            }
        }
        return minutes
    }

    /// The span zone 2 usually covers in a week: the least and the most over
    /// the `weeks` rolling weeks before the last seven days, counting only
    /// weeks that held a workout. Nil with fewer than two such weeks.
    static func usualZoneTwo(
        heartRate: [HealthReading],
        workouts: [HealthReading],
        maxHeartRate: Double,
        now: Date,
        weeks: Int = 4
    ) -> ClosedRange<Double>? {
        let week: TimeInterval = 7 * 24 * 60 * 60
        var totals: [Double] = []
        for offset in 1...weeks {
            let end = now.addingTimeInterval(-week * Double(offset))
            let start = end.addingTimeInterval(-week)
            let held = workouts.filter { $0.start >= start && $0.start < end }
            guard !held.isEmpty else { continue }
            let zones = zoneMinutes(heartRate: heartRate, workouts: held, maxHeartRate: maxHeartRate)
            totals.append(zones[.two] ?? 0)
        }
        guard totals.count >= 2, let low = totals.min(), let high = totals.max() else { return nil }
        return low...high
    }

    // MARK: - Sessions by week

    /// Sessions of the given activity types in each of the last `weeks`
    /// calendar weeks, oldest first; the last is the week in progress.
    static func weeklyCounts(
        _ workouts: [HealthReading],
        types: Set<Int>,
        weeks: Int = trendWeeks,
        now: Date,
        calendar: Calendar
    ) -> [Int] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<weeks).reversed().map { back in
            let start = calendar.date(byAdding: .day, value: -7 * back, to: thisWeek.start) ?? thisWeek.start
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return workouts.filter {
                types.contains($0.code) && $0.start >= start && $0.start < end
            }.count
        }
    }

    /// The mean over the complete weeks, which leaves out the week in progress
    /// so a Monday does not read as a lapse. Nil with no complete week.
    static func averagePerWeek(_ counts: [Int]) -> Double? {
        let complete = counts.dropLast()
        guard !complete.isEmpty else { return nil }
        return Double(complete.reduce(0, +)) / Double(complete.count)
    }

    // MARK: - Words for numbers

    /// A number with a fixed count of decimals, or nil for nil.
    static func format(_ value: Double?, decimals: Int, locale: Locale) -> String? {
        value.map { $0.formatted(.number.precision(.fractionLength(decimals)).locale(locale)) }
    }

    /// A count that is a whole number when it is close to one, else one
    /// decimal: 2, not 2.0, and 1.4 as it is.
    static func formatCount(_ value: Double?, locale: Locale) -> String? {
        guard let value else { return nil }
        let rounded = value.rounded()
        return abs(value - rounded) < 0.05
            ? format(rounded, decimals: 0, locale: locale)
            : format(value, decimals: 1, locale: locale)
    }

    /// A span of time as a clock reads it: 52:40, or 1:05:12 past the hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
