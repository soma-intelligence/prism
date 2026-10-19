//
//  FixtureHealthSource.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import HealthExportCore

/// A year of made up readings for every metric Soma interprets, for looking
/// at the pages on a simulator with no Health data. Debug only, chosen with
/// the launch argument `-health.fixture YES`, and never written anywhere.
///
/// The values wobble round a steady usual, and the last few days move on
/// purpose (resting heart rate up, HRV down, wrist temperature up), so "What
/// moved" and the cues have something to say.
struct FixtureHealthSource: HealthSampleSource {
    var isAvailable: Bool { true }

    /// The defaults key behind `-health.fixture YES`.
    static let launchKey = "health.fixture"

    private let readings: [String: [HealthReading]]

    init(now: Date = .now, calendar: Calendar = .current) {
        readings = Self.build(now: now, calendar: calendar)
    }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        readings[metric.identifier]?.max { $0.end < $1.end }
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        let inside = (readings[metric.identifier] ?? []).filter { $0.start >= from && $0.start < to }
        guard !inside.isEmpty else { return nil }
        return HealthReading(metric: metric.identifier, value: inside.map(\.value).reduce(0, +), unit: metric.unit, start: from, end: to)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        let inside = (readings[metric.identifier] ?? []).filter { $0.start >= from && $0.start < to }
        guard !inside.isEmpty else { return nil }
        return HealthReading(metric: metric.identifier, value: inside.map(\.value).reduce(0, +) / Double(inside.count),
                             unit: metric.unit, start: from, end: to)
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        let inside = (readings[metric.identifier] ?? [])
            .filter { $0.end > from && $0.start <= to }
            .sorted { $0.end > $1.end }
        return limit == 0 ? inside : Array(inside.prefix(limit))
    }

    // MARK: - The year

    /// A value for `day` days ago: a usual, a slow wave, a little noise, and
    /// a move over the last days.
    private static func value(_ usual: Double, wave: Double, noise: Double, day: Int, seed: Int, recent: Double = 0, recentDays: Int = 0) -> Double {
        let wobble = sin(Double(day + seed) / 9) * wave
        let jitter = (Double((day * 7919 + seed * 104_729) % 1000) / 1000 - 0.5) * 2 * noise
        let move = day < recentDays ? recent * Double(recentDays - day) / Double(recentDays) : 0
        return usual + wobble + jitter + move
    }

    private static func build(now: Date, calendar: Calendar) -> [String: [HealthReading]] {
        let today = calendar.startOfDay(for: now)
        var out: [String: [HealthReading]] = [:]

        func add(_ identifier: String, day: Int, hour: Double, value: Double, every: Int = 1, length: TimeInterval = 0, source: String = "Apple Watch") {
            guard day % every == 0, let metric = HealthMetricCatalog.metric(for: identifier),
                  let date = calendar.date(byAdding: .day, value: -day, to: today) else { return }
            let start = date.addingTimeInterval(hour * 3600)
            guard start <= now else { return }
            out[identifier, default: []].append(HealthReading(
                metric: identifier, value: value, unit: metric.unit, start: start, end: start.addingTimeInterval(length),
                source: source, device: source == "Apple Watch" ? "Apple Watch" : nil,
                deviceModel: source == "Apple Watch" ? "Watch Apple Inc." : nil
            ))
        }

        let q = "HKQuantityTypeIdentifier"
        for day in 0..<365 {
            add(q + "RestingHeartRate", day: day, hour: 7, value: value(56, wave: 1.5, noise: 1.2, day: day, seed: 1, recent: 9, recentDays: 4))
            add(q + "HeartRateVariabilitySDNN", day: day, hour: 6, value: value(52, wave: 4, noise: 4, day: day, seed: 2, recent: -16, recentDays: 5))
            add(q + "RespiratoryRate", day: day, hour: 4, value: value(14.5, wave: 0.3, noise: 0.3, day: day, seed: 3))
            add(q + "OxygenSaturation", day: day, hour: 4, value: value(0.97, wave: 0.004, noise: 0.004, day: day, seed: 4))
            add(q + "AppleSleepingWristTemperature", day: day, hour: 5, value: value(35.9, wave: 0.1, noise: 0.08, day: day, seed: 5, recent: 0.6, recentDays: 3))
            add(q + "VO2Max", day: day, hour: 18, value: value(41, wave: 0.6, noise: 0.3, day: day, seed: 6) + Double(365 - day) * 0.006, every: 4)
            add(q + "HeartRateRecoveryOneMinute", day: day, hour: 18, value: value(28, wave: 2, noise: 2, day: day, seed: 7), every: 3)
            add(q + "WalkingSpeed", day: day, hour: 12, value: value(1.38, wave: 0.03, noise: 0.03, day: day, seed: 8))
            add(q + "BodyMass", day: day, hour: 7.2, value: 78.5 - Double(120 - min(day, 120)) * 0.02 + value(0, wave: 0.2, noise: 0.25, day: day, seed: 9), every: 3, source: "Withings")
            add(q + "BodyFatPercentage", day: day, hour: 7.2, value: 0.215 - Double(120 - min(day, 120)) * 0.00008 + value(0, wave: 0.002, noise: 0.002, day: day, seed: 10), every: 7, source: "Withings")
            add(q + "LeanBodyMass", day: day, hour: 7.2, value: 61 + Double(120 - min(day, 120)) * 0.006 + value(0, wave: 0.2, noise: 0.2, day: day, seed: 11), every: 7, source: "Withings")
            add(q + "BodyMassIndex", day: day, hour: 7.2, value: 24.2 + value(0, wave: 0.1, noise: 0.08, day: day, seed: 12), every: 3, source: "Withings")
            add(q + "BloodPressureSystolic", day: day, hour: 8, value: value(121, wave: 3, noise: 3, day: day, seed: 13), every: 2, source: "Omron")
            add(q + "BloodPressureDiastolic", day: day, hour: 8, value: value(79, wave: 2, noise: 2, day: day, seed: 14), every: 2, source: "Omron")
            add(q + "BloodGlucose", day: day, hour: 7.5, value: value(92, wave: 4, noise: 4, day: day, seed: 15), every: 2, source: "Dexcom")
            for hour in stride(from: 8.0, to: 21, by: 1) {
                add(q + "StepCount", day: day, hour: hour, value: max(0, value(640, wave: 120, noise: 180, day: day * 13 + Int(hour), seed: 16)), length: 3000, source: "iPhone")
                add(q + "HeartRate", day: day, hour: hour, value: value(74, wave: 6, noise: 8, day: day * 13 + Int(hour), seed: 17))
                add(q + "ActiveEnergyBurned", day: day, hour: hour, value: max(0, value(32, wave: 6, noise: 8, day: day * 13 + Int(hour), seed: 18)), length: 3000)
            }
            // A night: core, deep and REM, ending on the morning of `day`.
            let asleep = value(7.2, wave: 0.4, noise: 0.5, day: day, seed: 19)
            let bed = -1.0 + value(23, wave: 0.3, noise: 0.3, day: day, seed: 20) - 24
            add("HKCategoryTypeIdentifierSleepAnalysis", day: day, hour: bed, value: 4, length: 1.2 * 3600)
            add("HKCategoryTypeIdentifierSleepAnalysis", day: day, hour: bed + 1.2, value: 3, length: (asleep - 2.8) * 3600)
            add("HKCategoryTypeIdentifierSleepAnalysis", day: day, hour: bed + asleep - 1.6, value: 5, length: 1.6 * 3600)
        }
        return out
    }
}
#endif
