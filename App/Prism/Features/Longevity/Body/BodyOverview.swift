//
//  BodyOverview.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// The identifiers the Body tab reads, beyond the ones Pulse already names.
enum BodyMetric {
    static let leanBodyMass = "HKQuantityTypeIdentifierLeanBodyMass"
    static let vo2Max = "HKQuantityTypeIdentifierVO2Max"
    static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
    static let heartRateRecovery = "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
    static let heartRate = "HKQuantityTypeIdentifierHeartRate"
    static let distanceWalkingRunning = "HKQuantityTypeIdentifierDistanceWalkingRunning"
    static let workout = "HKWorkoutTypeIdentifier"
    static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"

    /// How far back a trend reading is fetched: past the eight week mark, so
    /// the reading it compares with is in.
    static let trendLookbackDays = 16 * 7

    /// Samples of one metric from `start` to `now`, empty when the read fails
    /// or the catalog does not carry the identifier.
    static func samples(
        _ identifier: String,
        from start: Date,
        to end: Date,
        in source: any HealthSampleSource
    ) async -> [HealthReading] {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
        return (try? await source.samples(metric, from: start, to: end, limit: 0)) ?? []
    }

    /// Age in whole years from the date of birth in Health.
    static func age(in source: any HealthSampleSource) async -> Int? {
        guard let birth = HealthMetricCatalog.metric(for: dateOfBirth),
              let reading = try? await source.latest(birth) else { return nil }
        return Int(reading.value)
    }
}

/// What the Overview is built from.
struct BodyOverviewInputs: Sendable, Equatable {
    var now: Date
    /// Lean body mass over the last sixteen weeks, in kilograms.
    var leanMass: [HealthReading] = []
    /// VO2 max over the last sixteen weeks.
    var vo2Max: [HealthReading] = []
    /// Age in whole years, from the date of birth in Health.
    var age: Int?

    static let metrics = [BodyMetric.leanBodyMass, BodyMetric.vo2Max, BodyMetric.dateOfBirth]

    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> BodyOverviewInputs {
        let start = calendar.date(byAdding: .day, value: -BodyMetric.trendLookbackDays, to: now) ?? now
        async let lean = BodyMetric.samples(BodyMetric.leanBodyMass, from: start, to: now, in: source)
        async let vo2 = BodyMetric.samples(BodyMetric.vo2Max, from: start, to: now, in: source)
        async let age = BodyMetric.age(in: source)
        return BodyOverviewInputs(now: now, leanMass: await lean, vo2Max: await vo2, age: await age)
    }
}

/// The Overview's words and numbers.
struct BodyOverview: Equatable {
    var eyebrow: String?
    var headline: String
    var reason: String

    var leanMass: String?
    var leanTrend: SomaTrend?
    var vo2Max: String?
    var vo2Trend: SomaTrend?
    /// Your age, the line a fitness age is read against. Health knows it
    /// before a Soma visit does.
    var age: Int?

    static func make(from inputs: BodyOverviewInputs, calendar: Calendar = .current, locale: Locale = .current) -> BodyOverview {
        let lean = BodyMath.change(inputs.leanMass, now: inputs.now, calendar: calendar)
        let vo2 = BodyMath.change(inputs.vo2Max, now: inputs.now, calendar: calendar)

        var page = BodyOverview(
            eyebrow: "Body",
            headline: "Your body composition.",
            reason: "Nothing measured yet. Lean mass comes from Apple Health, and a Soma visit adds fitness age, lean mass by region and grip. This page fills from there.",
            leanMass: BodyMath.format(lean?.latest, decimals: 1, locale: locale),
            leanTrend: BodyMath.trend(lean?.delta, tolerance: 0.1),
            vo2Max: BodyMath.format(vo2?.latest, decimals: 0, locale: locale),
            vo2Trend: BodyMath.trend(vo2?.delta, tolerance: 0.5),
            age: inputs.age
        )

        if let lean, let delta = lean.delta {
            let amount = BodyMath.format(abs(delta), decimals: 1, locale: locale) ?? ""
            let now = page.leanMass ?? ""
            page.eyebrow = "Lean mass · eight weeks"
            switch BodyMath.trend(delta, tolerance: 0.1) {
            case .up:
                page.headline = "You’ve built lean mass."
                page.reason = "Lean mass rose \(amount) kg in eight weeks, to \(now) kg. A Soma visit can show where it went."
            case .down:
                page.headline = "Lean mass slipped a little."
                page.reason = "Lean mass fell \(amount) kg in eight weeks, to \(now) kg. Strength work twice a week is what holds it."
            case nil:
                page.headline = "Lean mass is holding."
                page.reason = "Lean mass has stayed near \(now) kg for eight weeks. A Soma visit can show how it sits by region."
            }
        } else if let now = page.leanMass {
            page.eyebrow = "Lean mass"
            page.headline = "Your body composition."
            page.reason = "Lean mass reads \(now) kg. In eight weeks there is a trend to show, and a Soma visit can show where it sits."
        }

        return page
    }
}

#if DEBUG
extension BodyOverview {
    static var preview: BodyOverview {
        let now = Date()
        func reading(_ id: String, _ value: Double, daysAgo: Int) -> HealthReading {
            let date = now.addingTimeInterval(-Double(daysAgo) * 86_400)
            return HealthReading(metric: id, value: value, unit: .kilogram, start: date, end: date)
        }
        return make(from: BodyOverviewInputs(
            now: now,
            leanMass: [reading(BodyMetric.leanBodyMass, 52.1, daysAgo: 70), reading(BodyMetric.leanBodyMass, 53.6, daysAgo: 2)],
            vo2Max: [reading(BodyMetric.vo2Max, 41, daysAgo: 60), reading(BodyMetric.vo2Max, 44, daysAgo: 3)],
            age: 46
        ))
    }
}
#endif
