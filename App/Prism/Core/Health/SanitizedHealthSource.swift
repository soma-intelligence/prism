//
//  SanitizedHealthSource.swift
//  Prism
//

import Foundation
import HealthExportCore

/// Apple Health as the app reads it, with what no page can draw taken out.
///
/// Any app on the phone can write to Health, so the store can hold a NaN, an
/// infinite value or a sample that ends before it starts. The arithmetic
/// above assumes finite numbers in forward time, and a single bad value
/// turned into an `Int` or a range traps. This wrapper is the one border
/// every read crosses: non-finite readings are dropped, and a backwards
/// interval is turned the right way round. Everything else passes untouched.
nonisolated struct SanitizedHealthSource: HealthSampleSource {
    let base: any HealthSampleSource

    var isAvailable: Bool { base.isAvailable }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {
        try await base.requestAuthorization(for: metrics)
    }

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        try await base.latest(metric).flatMap(Self.clean)
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        try await base.total(metric, from: from, to: to).flatMap(Self.clean)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        try await base.average(metric, from: from, to: to).flatMap(Self.clean)
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        try await base.samples(metric, from: from, to: to, limit: limit).compactMap(Self.clean)
    }

    /// The reading, or nil when its value is not a finite number; a reading
    /// that ends before it starts is turned round.
    static func clean(_ reading: HealthReading) -> HealthReading? {
        guard reading.value.isFinite else { return nil }
        guard reading.end < reading.start else { return reading }
        return HealthReading(metric: reading.metric, value: reading.value, unit: reading.unit,
                             start: reading.end, end: reading.start, source: reading.source,
                             sourceBundle: reading.sourceBundle, device: reading.device,
                             deviceModel: reading.deviceModel, wasUserEntered: reading.wasUserEntered)
    }
}

extension HealthReading {
    /// The value as a whole number, for a coded value (a sleep stage, a
    /// workout type, a stand hour) or a count of years: -1 when it is not a
    /// finite number, so a bad sample reads as an unknown code instead of
    /// trapping.
    nonisolated var code: Int {
        guard value.isFinite else { return -1 }
        return Int(max(min(value, Double(Int32.max)), Double(Int32.min)))
    }
}
