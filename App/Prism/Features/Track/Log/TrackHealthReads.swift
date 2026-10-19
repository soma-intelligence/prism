//
//  TrackHealthReads.swift
//  Prism
//

import Foundation
import HealthExportCore

/// The few things Track's entries read back from Apple Health: the last
/// weight and height to start the scale and the ruler from, and the usual
/// night to set a fast against. Each asks for its own metric when the sheet
/// that needs it opens, never before.
@MainActor
enum TrackHealthReads {
    enum Metric {
        static let bodyMass = "HKQuantityTypeIdentifierBodyMass"
        static let height = "HKQuantityTypeIdentifierHeight"
        static let waist = "HKQuantityTypeIdentifierWaistCircumference"
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
    }

    /// The latest sample of a metric, converted to the unit asked for.
    static func latest(_ identifier: String, from health: HealthDashboard) async -> HealthReading? {
        guard !(health.reader is EmptyHealthSource),
              let metric = HealthMetricCatalog.metric(for: identifier),
              let source = await health.prepare([identifier]) else { return nil }
        return try? await source.latest(metric)
    }

    /// The median night of the last two weeks, as clock hours from falling
    /// asleep to waking. Nil under three nights.
    static func sleepWindow(from health: HealthDashboard, now: Date = .now, calendar: Calendar = .current) async -> (from: Double, to: Double)? {
        guard !(health.reader is EmptyHealthSource),
              let metric = HealthMetricCatalog.metric(for: Metric.sleep),
              let source = await health.prepare([Metric.sleep]) else { return nil }
        let start = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let samples = (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        let nights = PulseNights.nights(from: samples, calendar: calendar)
        return TrackFasting.usualWindow(asleep: nights.map(\.fellAsleep), woke: nights.map(\.woke), calendar: calendar)
    }
}
