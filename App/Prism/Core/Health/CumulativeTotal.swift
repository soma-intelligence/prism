//
//  CumulativeTotal.swift
//  Prism
//

import Foundation
import HealthExportCore

/// A day's total from samples that may overlap, counted once.
///
/// An iPhone in a pocket and an Apple Watch on the wrist both count the same
/// walk, so a day of steps arrives twice. HealthKit's statistics (the
/// `cumulativeSum` every Soma total reads on a device) keep one source for
/// each stretch of time and drop the other; adding the raw samples up instead
/// doubles the day. This is that rule for the sources that are not HealthKit
/// (the simulator's fixture), so they count a day the way the device does.
enum CumulativeTotal {
    /// The sum of `readings` inside `from` to `to`. Readings are taken in
    /// order of `rank` (lowest first); each counts only for the share of its
    /// time no earlier reading already covered, its value spread evenly over
    /// its length. A reading with no length counts whole unless it falls
    /// inside a stretch already covered.
    static func deduplicated(
        _ readings: [HealthReading],
        from: Date,
        to: Date,
        rank: (HealthReading) -> Int
    ) -> Double {
        var covered: [DateInterval] = []
        var total = 0.0
        let ordered = readings.enumerated().sorted { a, b in
            let (left, right) = (rank(a.element), rank(b.element))
            return left != right ? left < right : a.offset < b.offset
        }.map(\.element)

        for reading in ordered {
            let length = reading.end.timeIntervalSince(reading.start)
            guard length > 0 else {
                guard reading.start >= from, reading.start < to,
                      !covered.contains(where: { $0.start <= reading.start && reading.start < $0.end }) else { continue }
                total += reading.value
                continue
            }
            let start = max(reading.start, from)
            let end = min(reading.end, to)
            guard end > start else { continue }
            let free = uncovered(DateInterval(start: start, end: end), by: covered)
            total += reading.value * free / length
            covered.append(DateInterval(start: start, end: end))
        }
        return total
    }

    /// How many seconds of `interval` no interval in `covered` reaches.
    private static func uncovered(_ interval: DateInterval, by covered: [DateInterval]) -> TimeInterval {
        let overlaps = covered.compactMap { $0.intersection(with: interval) }
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        var free = interval.duration
        var reach = interval.start
        for overlap in overlaps {
            let start = max(overlap.start, reach)
            guard overlap.end > start else { continue }
            free -= overlap.end.timeIntervalSince(start)
            reach = overlap.end
        }
        return max(0, free)
    }
}
