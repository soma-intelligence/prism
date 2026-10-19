//
//  VaultPreviewSource.swift
//  Prism
//

#if DEBUG
import Foundation
import HealthExportCore

/// A Health store for the Vault's previews: a few days of heart rate from a
/// watch, a chest strap and a hand, so the rows show every grade.
///
/// Debug only, and never handed to a shipping dashboard: it exists so a page
/// can be looked at without a device.
struct VaultPreviewSource: HealthSampleSource {
    var isAvailable: Bool { true }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        Self.readings.first
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        let inside = Self.readings.filter { $0.start >= from && $0.start < to }
        guard !inside.isEmpty else { return nil }
        return HealthReading(metric: metric.identifier, value: inside.map(\.value).reduce(0, +),
                             unit: metric.unit, start: from, end: to)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        let inside = Self.readings.filter { $0.start >= from && $0.start < to }
        guard !inside.isEmpty else { return nil }
        return HealthReading(metric: metric.identifier, value: inside.map(\.value).reduce(0, +) / Double(inside.count),
                             unit: metric.unit, start: from, end: to)
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        let inside = Self.readings.filter { $0.end <= to && $0.end > from }
        return limit == 0 ? inside : Array(inside.prefix(limit))
    }

    /// Newest first, one every forty minutes for a week.
    static let readings: [HealthReading] = (0..<252).map { sample(minutesAgo: $0 * 40) }

    static func sample(minutesAgo: Int) -> HealthReading {
        let at = Date.now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
        let value = 62 + Double((minutesAgo / 40) % 17)
        switch (minutesAgo / 40) % 5 {
        case 0:
            return HealthReading(metric: "HKQuantityTypeIdentifierHeartRate", value: value, unit: .countPerMinute,
                                 start: at, end: at, source: "Polar Flow", device: "Polar H10", deviceModel: "H10 Polar")
        case 1:
            return HealthReading(metric: "HKQuantityTypeIdentifierHeartRate", value: value, unit: .countPerMinute,
                                 start: at, end: at, source: "Health", wasUserEntered: true)
        default:
            return HealthReading(metric: "HKQuantityTypeIdentifierHeartRate", value: value, unit: .countPerMinute,
                                 start: at, end: at, source: "Apple Watch", device: "Apple Watch", deviceModel: "Watch Apple Inc.")
        }
    }
}
#endif
