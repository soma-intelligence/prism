import Foundation
import HealthExportCore
import SyncCore

/// Works out `health_daily` rows from the source itself, one local day at a
/// time.
///
/// The totals come from the source's statistics rather than from adding up
/// uploaded rows: a phone and a watch both count steps, and only Health knows
/// which of the overlapping samples to keep.
public struct HealthDailyAggregator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// `yyyy-MM-dd` for the local day `date` falls on.
    public func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The start and end of a day key, or nil when it is not one.
    public func interval(of day: String) -> DateInterval? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Every day a sample touches, from its start to its end: a night of
    /// sleep counts on both days it spans.
    public func days(touchedBy reading: HealthReading) -> Set<String> {
        var days: Set<String> = [dayKey(reading.start)]
        var cursor = calendar.startOfDay(for: reading.start)
        var guardrail = 0
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next < reading.end, guardrail < 31 {
            days.insert(dayKey(next))
            cursor = next
            guardrail += 1
        }
        return days
    }

    /// The row for one metric and one day, or nil when the day holds nothing.
    public func row(
        for metric: HealthMetric,
        day: String,
        userID: UserID,
        source: any HealthSampleSource
    ) async throws -> HealthDailyRow? {
        guard let interval = interval(of: day) else { return nil }
        let zone = calendar.timeZone.identifier
        switch (metric.kind, metric.aggregation) {
        case (.quantity, .cumulative):
            guard let total = try await source.total(metric, from: interval.start, to: interval.end) else { return nil }
            return HealthDailyRow(userID: userID, metric: metric.identifier, day: day, timeZone: zone, unit: metric.unit.rawValue,
                                  sum: total.value, avg: nil, min: nil, max: nil, count: nil)
        case (.quantity, _):
            let samples = try await source.samples(metric, from: interval.start, to: interval.end, limit: 0)
            let values = samples.map(\.value).filter(\.isFinite)
            guard !values.isEmpty else { return nil }
            let total = values.reduce(0, +)
            return HealthDailyRow(userID: userID, metric: metric.identifier, day: day, timeZone: zone, unit: metric.unit.rawValue,
                                  sum: nil, avg: total / Double(values.count), min: values.min(), max: values.max(), count: values.count)
        case (.category, _), (.workout, _):
            let samples = try await source.samples(metric, from: interval.start, to: interval.end, limit: 0)
            guard !samples.isEmpty else { return nil }
            // Seconds inside this day only, so a night split over two days
            // is not counted twice.
            let seconds = samples.reduce(0.0) { running, sample in
                let start = max(sample.start, interval.start)
                let end = min(sample.end, interval.end)
                return running + max(0, end.timeIntervalSince(start))
            }
            return HealthDailyRow(userID: userID, metric: metric.identifier, day: day, timeZone: zone, unit: HealthUnit.second.rawValue,
                                  sum: seconds, avg: nil, min: nil, max: nil, count: samples.count)
        case (.correlation, _), (.characteristic, _):
            return nil
        }
    }
}
