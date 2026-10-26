//
//  FixtureCycle.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthExportCore

/// A made up year of periods, a month of symptoms and wrist temperatures,
/// for looking at the cycle page and its log on a simulator. Debug only,
/// chosen with the launch argument `-health.cycle YES`, and never written
/// anywhere: neither Health nor the cycle store sees it.
///
/// Eleven cycles whose lengths wander by a week or more three times, the
/// last period started seventeen days ago, hot flashes on six days and night
/// sweats on four nights of the last thirty, the wrist warmer on three of
/// them: the page then shows signs consistent with the early transition.
enum FixtureCycle {
    /// The defaults key behind `-health.cycle YES`.
    nonisolated static let launchKey = "health.cycle"

    nonisolated static var isOn: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    /// The person's age in the fixture, so the stage is read.
    static let age = 47

    private static let lengths = [28, 27, 36, 28, 26, 35, 29, 27, 38, 28, 27]

    static func flowDays(now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var starts = [-17]
        for length in lengths.reversed() { starts.insert(starts[0] - length, at: 0) }
        return starts.flatMap { start in
            (0..<5).compactMap { calendar.date(byAdding: .day, value: start + $0, to: today) }
        }
    }

    static func symptoms(now: Date = .now, calendar: Calendar = .current) -> [CycleSymptom: [Date]] {
        let today = calendar.startOfDay(for: now)
        func days(_ offsets: [Int]) -> [Date] { offsets.compactMap { calendar.date(byAdding: .day, value: -$0, to: today) } }
        return [
            .cramps: days([17, 16, 45]),
            .bloating: days([18, 15]),
            .headache: days([4]),
            .hotFlashes: days([1, 3, 6, 9, 13, 20]),
            .nightSweats: days([2, 6, 11, 22]),
            .sleepChanges: days([2, 11]),
        ]
    }

    static func wristTemperature(now: Date = .now, calendar: Calendar = .current) -> [HealthReading] {
        let today = calendar.startOfDay(for: now)
        let warm: Set<Int> = [2, 6, 11]
        return (0..<30).compactMap { back -> HealthReading? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let value = warm.contains(back) ? 36.8 : 36.3 + Double(back % 3) * 0.05
            return HealthReading(metric: HomeMetric.wristTemperature, value: value, unit: .degreeCelsius,
                                 start: day.addingTimeInterval(-4 * 3600), end: day.addingTimeInterval(6 * 3600),
                                 source: "Apple Watch")
        }
    }
}
#endif
