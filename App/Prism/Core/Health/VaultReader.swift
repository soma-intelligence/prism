//
//  VaultReader.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// What the Vault's pages read: one metric's chart over a period, its headline
/// value, and its raw records a page at a time.
///
/// A sum or a mean is asked of the store bucket by bucket, so a year of heart
/// rate is twelve statistics and not half a million samples. Only the types
/// the store keeps no statistic for (categories, and quantities with no
/// aggregation) are read as samples and folded here.
struct VaultReader: Sendable {
    let source: any HealthSampleSource
    var calendar: Calendar = .current

    /// How many records one page of All Data holds.
    static let pageSize = 200

    /// The most samples a chart folds by hand before it stops reading.
    static let foldLimit = 20_000

    func series(_ metric: HealthMetric, period: VaultPeriod, now: Date) async -> [VaultPoint] {
        let buckets = period.buckets(endingAt: now, calendar: calendar)
        guard let first = buckets.first, let last = buckets.last else { return [] }

        if metric.kind == .quantity, metric.aggregation != .none {
            return await withTaskGroup(of: (Int, Double?).self) { group in
                for (index, bucket) in buckets.enumerated() {
                    group.addTask { [source] in
                        guard bucket.start <= now else { return (index, nil) }
                        let reading = try? await source.summary(metric, from: bucket.start, to: min(bucket.end, now))
                        return (index, reading?.value)
                    }
                }
                var values = [Double?](repeating: nil, count: buckets.count)
                for await (index, value) in group { values[index] = value }
                return zip(buckets, values).map { VaultPoint(interval: $0, value: $1) }
            }
        }

        let readings = (try? await source.samples(
            metric, from: first.start, to: min(last.end, now), limit: Self.foldLimit
        )) ?? []
        return VaultBucketing.fold(readings, into: buckets, counting: metric.kind == .category)
    }

    /// The number at the top of the page: today's total for a sum, and the
    /// most recent record for anything else.
    func headline(_ metric: HealthMetric, now: Date) async -> HealthReading? {
        if metric.kind == .quantity, metric.aggregation == .cumulative {
            return try? await source.total(metric, from: calendar.startOfDay(for: now), to: now)
        }
        return try? await source.latest(metric)
    }

    /// The most recent record, whatever the kind: where a "past seven days"
    /// view ends.
    func latestRecord(_ metric: HealthMetric) async -> HealthReading? {
        try? await source.latest(metric)
    }

    /// The next page of records, newest first, older than every record in
    /// `seen`.
    ///
    /// The store is asked for records ending at or before the oldest one held,
    /// and the ones already held are dropped: ends can tie, and a cursor that
    /// stepped past a tie would lose records.
    func page(_ metric: HealthMetric, before cursor: Date, seen: Set<HealthReading>) async throws -> [HealthReading] {
        let found = try await source.samples(metric, from: .distantPast, to: cursor, limit: Self.pageSize)
        return found.filter { !seen.contains($0) }
    }
}

/// How the Vault writes a value.
enum VaultFormat {
    /// A number at the precision it deserves: whole numbers as they are,
    /// two decimals under one, one under a hundred, none above.
    static func number(_ value: Double) -> String {
        let decimals: Int
        if value.rounded() == value || abs(value) >= 100 {
            decimals = 0
        } else if abs(value) < 1 {
            decimals = 2
        } else {
            decimals = 1
        }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// The value as a person reads it. Health keeps a percentage as a
    /// fraction (0.97), and a person reads 97.
    static func scaled(_ value: Double, unit: HealthUnit) -> Double {
        unit == .percent ? value * 100 : value
    }

    /// A record's value and unit. A category record has no value worth
    /// reading (its code is a case, not a measurement), so it reads as how
    /// long it lasted, or as an event when it had no length.
    static func value(of reading: HealthReading, metric: HealthMetric) -> (value: String, unit: String?) {
        if metric.kind == .category {
            let seconds = reading.end.timeIntervalSince(reading.start)
            guard seconds >= 60 else { return ("Event", nil) }
            return (duration(seconds), nil)
        }
        return (number(scaled(reading.value, unit: reading.unit)), reading.unit.shortLabel)
    }

    /// How long a record ran, the way every duration in the app is written
    /// ("7h 54m", "45m"), with seconds only for one under a minute ("40s").
    static func duration(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        guard seconds < 60 else { return SomaFormat.duration(seconds, locale: locale) }
        var style = Duration.UnitsFormatStyle(allowedUnits: [.seconds], width: .narrow)
        style.locale = locale
        return Duration.seconds(Int(seconds.rounded())).formatted(style)
    }
}
