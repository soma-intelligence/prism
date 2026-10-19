//
//  SoundExposure.swift
//  Prism
//

import Foundation
import HealthExportCore

/// The arithmetic behind the two sound pages: the level around you and the
/// level in your headphones, as the watch and the phone write them to Health.
///
/// Each sample is a level held over a stretch of time, so a day's level is
/// weighted by how long each sample lasted. The safe week follows the WHO
/// standard Apple's Health app uses: 80 dB for 40 hours a week, and every
/// 3 dB louder halves the time.
nonisolated enum SoundExposure {
    /// The level Apple warns about when it is held for long.
    static let limit = 80.0
    /// Hours at the limit a week allows.
    static let safeWeekHours = 40.0
    /// Decibels that halve the allowed time.
    static let exchangeRate = 3.0

    /// A sample's weight: how long it lasted, at least a second.
    static func seconds(_ reading: HealthReading) -> Double {
        max(1, reading.end.timeIntervalSince(reading.start))
    }

    /// The time weighted mean level of the readings, nil for none.
    static func mean(_ readings: [HealthReading]) -> Double? {
        guard !readings.isEmpty else { return nil }
        let weight = readings.reduce(0) { $0 + seconds($1) }
        return readings.reduce(0) { $0 + $1.value * seconds($1) } / weight
    }

    /// One level per day for the `days` days ending today, oldest first; nil
    /// for a day with no reading.
    static func daily(_ readings: [HealthReading], days: Int, now: Date, calendar: Calendar) -> [Double?] {
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.start) }
        return (0..<days).map { index in
            guard let day = calendar.date(byAdding: .day, value: index - (days - 1), to: today) else { return nil }
            return grouped[day].flatMap(mean)
        }
    }

    /// Seconds spent at or above `level`.
    static func timeAbove(_ level: Double, in readings: [HealthReading]) -> TimeInterval {
        readings.filter { $0.value >= level }.reduce(0) { $0 + seconds($1) }
    }

    /// Seconds of listening: the sum of every headphone sample's span.
    static func listening(_ readings: [HealthReading]) -> TimeInterval {
        readings.reduce(0) { $0 + seconds($1) }
    }

    /// The share of a safe week the readings used, 0 upward (1 is the whole
    /// week).
    static func weeklyDose(_ readings: [HealthReading]) -> Double {
        let allowed = safeWeekHours * 3600
        return readings.reduce(0) { total, reading in
            total + seconds(reading) * pow(2, (reading.value - limit) / exchangeRate) / allowed
        }
    }

    /// The mean over the last `days` days against the `days` before them, in
    /// decibels. Nil when either side holds nothing.
    static func change(_ readings: [HealthReading], days: Int, now: Date) -> Double? {
        let span = TimeInterval(days) * 86_400
        let recent = readings.filter { $0.start > now.addingTimeInterval(-span) }
        let before = readings.filter { $0.start <= now.addingTimeInterval(-span) && $0.start > now.addingTimeInterval(-2 * span) }
        guard let now = mean(recent), let then = mean(before) else { return nil }
        return now - then
    }

    /// A change in decibels as the page writes it: +1 dB, -1 dB, or Level
    /// under half a decibel. A dash when there is nothing to compare.
    static func changeText(_ delta: Double?) -> String {
        guard let delta else { return "-" }
        let rounded = Int(delta.rounded())
        if rounded == 0 { return "Level" }
        return rounded > 0 ? "+\(rounded) dB" : "\u{2212}\(-rounded) dB"
    }

    /// Minutes as hours and minutes: 11 h 20, or 14 min under an hour.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", rest))"
    }
}
