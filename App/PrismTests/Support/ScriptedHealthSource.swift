//
//  ScriptedHealthSource.swift
//  PrismTests
//

import Foundation
import HealthExportCore

/// A Health store that holds exactly the readings a test gives it.
///
/// Reads answer the way HealthKit does over the same samples: a range holds a
/// reading that starts inside it, an average is the mean of those, a total
/// their sum, and the latest is the one that started last. Set `fails` and
/// every read throws, which is what a denied or broken store looks like to
/// the code above it.
struct ScriptedHealthSource: HealthSampleSource {
    struct Failure: Error {}

    var readings: [HealthReading] = []
    var fails = false
    var isAvailable = true

    init(_ readings: [HealthReading] = [], fails: Bool = false) {
        self.readings = readings
        self.fails = fails
    }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func inside(_ metric: HealthMetric, from: Date, to: Date) throws -> [HealthReading] {
        if fails { throw Failure() }
        return readings.filter { $0.metric == metric.identifier && $0.start >= from && $0.start <= to }
    }

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        if fails { throw Failure() }
        return readings.filter { $0.metric == metric.identifier }.max { $0.start < $1.start }
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        let found = try inside(metric, from: from, to: to)
        guard !found.isEmpty else { return nil }
        return HealthReading(metric: metric.identifier, value: found.map(\.value).reduce(0, +),
                             unit: metric.unit, start: from, end: to)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        let found = try inside(metric, from: from, to: to)
        guard !found.isEmpty else { return nil }
        return HealthReading(metric: metric.identifier, value: found.map(\.value).reduce(0, +) / Double(found.count),
                             unit: metric.unit, start: from, end: to)
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        let found = try inside(metric, from: from, to: to).sorted { $0.start > $1.start }
        return limit > 0 ? Array(found.prefix(limit)) : found
    }
}

extension HealthReading {
    /// A reading for a test: `metric` is the HealthKit identifier, the unit is
    /// left to the code that reads it.
    static func test(_ metric: String, _ value: Double, at start: Date, minutes: Double = 1) -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .count, start: start, end: start.addingTimeInterval(minutes * 60))
    }

    /// A reading over an explicit span.
    static func test(_ metric: String, _ value: Double, from start: Date, to end: Date) -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .count, start: start, end: end)
    }
}
