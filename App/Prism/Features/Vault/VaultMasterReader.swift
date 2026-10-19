//
//  VaultMasterReader.swift
//  Prism
//
//  Reads what a data type page windows into: a year of one value per day,
//  in the unit the page shows, plus the sources behind a window.
//

import Foundation
import HealthExportCore

struct VaultMasterReader: Sendable {
    let source: any HealthSampleSource
    var calendar: Calendar = .current

    /// Samples a discrete metric may fold by hand before it is read day by
    /// day as statistics instead.
    static let sampleLimit = 60_000

    /// The year ending today for `metric`, with diastolic beside systolic.
    func master(_ metric: HealthMetric, now: Date) async -> MetricMaster {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(MetricMaster.length - 1), to: today) ?? today
        let days: [Double?]
        if metric.identifier == MetricProfile.sleep {
            days = await nights(from: start, now: now)
        } else {
            days = await daily(metric, from: start, now: now)
        }
        var master = MetricMaster(today: today, days: days)
        if metric.identifier == MetricProfile.systolic || metric.identifier == MetricProfile.diastolic,
           let systolic = HealthMetricCatalog.metric(for: MetricProfile.systolic),
           let diastolic = HealthMetricCatalog.metric(for: MetricProfile.diastolic) {
            // Systolic leads, whichever one opened the page.
            master.days = metric.identifier == MetricProfile.systolic ? days : await daily(systolic, from: start, now: now)
            master.secondary = metric.identifier == MetricProfile.diastolic ? days : await daily(diastolic, from: start, now: now)
        }
        return master
    }

    /// One value per day: a daily total from the store's statistic (which
    /// counts a step once across phone and watch), the mean of the day's
    /// readings for anything else, and a count of records for a category.
    private func daily(_ metric: HealthMetric, from start: Date, now: Date) async -> [Double?] {
        let dayStarts = (0..<MetricMaster.length).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        if metric.kind == .quantity, metric.aggregation == .cumulative {
            return await perDay(metric, days: dayStarts, now: now)
        }
        let readings = (try? await source.samples(metric, from: start, to: now, limit: Self.sampleLimit)) ?? []
        if metric.kind == .quantity, readings.count >= Self.sampleLimit, metric.aggregation != .none {
            return await perDay(metric, days: dayStarts, now: now)
        }
        var buckets: [Date: [Double]] = [:]
        for reading in readings {
            buckets[calendar.startOfDay(for: reading.start), default: []].append(reading.value)
        }
        return dayStarts.map { day in
            guard let values = buckets[day], !values.isEmpty else { return nil }
            if metric.kind == .category { return Double(values.count) }
            return VaultFormat.scaled(values.reduce(0, +) / Double(values.count), unit: metric.unit)
        }
    }

    private func perDay(_ metric: HealthMetric, days: [Date], now: Date) async -> [Double?] {
        await withTaskGroup(of: (Int, Double?).self) { group in
            for (index, day) in days.enumerated() {
                group.addTask { [source, calendar] in
                    let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? now, now)
                    guard day < end else { return (index, nil) }
                    let reading = try? await source.summary(metric, from: day, to: end)
                    return (index, reading.map { VaultFormat.scaled($0.value, unit: metric.unit) })
                }
            }
            var values = [Double?](repeating: nil, count: days.count)
            for await (index, value) in group { values[index] = value }
            return values
        }
    }

    /// Hours asleep each night, filed under the morning it ended on.
    private func nights(from start: Date, now: Date) async -> [Double?] {
        guard let metric = HealthMetricCatalog.metric(for: MetricProfile.sleep) else {
            return Array(repeating: nil, count: MetricMaster.length)
        }
        let from = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let samples = (try? await source.samples(metric, from: from, to: now, limit: Self.sampleLimit)) ?? []
        var byDay: [Date: Double] = [:]
        for night in PulseNights.nights(from: samples, calendar: calendar) {
            byDay[night.day] = night.asleep / 3600
        }
        return (0..<MetricMaster.length).map { offset in
            calendar.date(byAdding: .day, value: offset, to: start).flatMap { byDay[$0] }
        }
    }

    // MARK: - Sources

    /// One app or device behind a window's records, with how much weight
    /// its readings bear.
    struct Origin: Identifiable, Equatable, Sendable {
        var id: String { name + "|" + (device ?? "") }
        var name: String
        var device: String?
        var count: Int
        var quality: ReadingQuality
    }

    /// The distinct sources in `interval`, most records first.
    func origins(_ metric: HealthMetric, in interval: DateInterval) async -> [Origin] {
        let readings = (try? await source.samples(metric, from: interval.start, to: interval.end, limit: 5_000)) ?? []
        return Self.origins(readings)
    }

    static func origins(_ readings: [HealthReading]) -> [Origin] {
        var found: [String: Origin] = [:]
        for reading in readings {
            let name = reading.source ?? "Unknown source"
            let key = name + "|" + (reading.device ?? "")
            let quality = ReadingQuality.grade(reading)
            if var origin = found[key] {
                origin.count += 1
                if quality.level > origin.quality.level { origin.quality = quality }
                found[key] = origin
            } else {
                found[key] = Origin(name: name, device: reading.device, count: 1, quality: quality)
            }
        }
        return found.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
