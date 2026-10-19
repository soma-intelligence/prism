//
//  VaultPeriod.swift
//  Prism
//

import Foundation
import HealthExportCore

/// The spans a data type page reads over, a day by the
/// hour, a week and a month by the day, three and six months by the week, a
/// year by the month.
enum VaultPeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case day
    case week
    case month
    case threeMonths
    case sixMonths
    case year

    var id: String { rawValue }

    /// The letter on the picker.
    var short: String {
        switch self {
        case .day: "D"
        case .week: "W"
        case .month: "M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .year: "1Y"
        }
    }

    /// What one bar or one dot stands for.
    var bucket: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .threeMonths, .sixMonths: .weekOfYear
        case .year: .month
        }
    }

    /// The span shown, ending at the close of the bucket that holds `now`, so
    /// today's bar sits at the right edge and the chart never starts mid bar.
    func interval(endingAt now: Date, calendar: Calendar) -> DateInterval {
        let end = calendar.dateInterval(of: bucket, for: now)?.end ?? now
        let start: Date
        switch self {
        case .day:
            let dayStart = calendar.startOfDay(for: now)
            return DateInterval(start: dayStart, end: calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end)
        case .week:
            start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
        case .month:
            start = calendar.date(byAdding: .month, value: -1, to: end) ?? end
        case .threeMonths:
            start = calendar.date(byAdding: .weekOfYear, value: -13, to: end) ?? end
        case .sixMonths:
            start = calendar.date(byAdding: .weekOfYear, value: -26, to: end) ?? end
        case .year:
            start = calendar.date(byAdding: .month, value: -12, to: end) ?? end
        }
        return DateInterval(start: start, end: end)
    }

    /// `date` moved back `pages` whole spans (forward when negative): where
    /// the chevrons page to.
    func shifted(_ date: Date, by pages: Int, calendar: Calendar) -> Date {
        guard pages != 0 else { return date }
        let (component, size): (Calendar.Component, Int) = switch self {
        case .day: (.day, 1)
        case .week: (.day, 7)
        case .month: (.month, 1)
        case .threeMonths: (.weekOfYear, 13)
        case .sixMonths: (.weekOfYear, 26)
        case .year: (.month, 12)
        }
        return calendar.date(byAdding: component, value: -pages * size, to: date) ?? date
    }

    /// The buckets of the span, oldest first, each one bucket long.
    func buckets(endingAt now: Date, calendar: Calendar) -> [DateInterval] {
        let span = interval(endingAt: now, calendar: calendar)
        var result: [DateInterval] = []
        var cursor = span.start
        while cursor < span.end {
            guard let next = calendar.date(byAdding: bucket, value: 1, to: cursor), next > cursor else { break }
            result.append(DateInterval(start: cursor, end: min(next, span.end)))
            cursor = next
        }
        return result
    }
}

/// One bucket's value on the chart. Nil when nothing was recorded in it: an
/// empty hour draws no bar rather than a zero.
struct VaultPoint: Identifiable, Hashable, Sendable {
    let interval: DateInterval
    let value: Double?

    var id: Date { interval.start }
}

/// Folding raw readings into buckets, for the metrics HealthKit has no
/// statistic for: category types, and quantities with no aggregation.
enum VaultBucketing {
    /// Category samples are counted; quantities are averaged.
    static func fold(_ readings: [HealthReading], into buckets: [DateInterval], counting: Bool) -> [VaultPoint] {
        buckets.map { bucket in
            let inside = readings.filter { $0.start >= bucket.start && $0.start < bucket.end }
            guard !inside.isEmpty else { return VaultPoint(interval: bucket, value: nil) }
            if counting { return VaultPoint(interval: bucket, value: Double(inside.count)) }
            let mean = inside.map(\.value).reduce(0, +) / Double(inside.count)
            return VaultPoint(interval: bucket, value: mean)
        }
    }

    /// The summary under the chart: the total of the buckets for a sum, and
    /// the mean of the buckets that hold something for anything else.
    static func average(_ points: [VaultPoint]) -> Double? {
        let values = points.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func total(_ points: [VaultPoint]) -> Double? {
        let values = points.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    /// Readings grouped by the day they started on, newest day first, each
    /// day's readings in the order given.
    static func byDay(_ readings: [HealthReading], calendar: Calendar) -> [(day: Date, readings: [HealthReading])] {
        var order: [Date] = []
        var groups: [Date: [HealthReading]] = [:]
        for reading in readings {
            let day = calendar.startOfDay(for: reading.start)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(reading)
        }
        return order.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
}
