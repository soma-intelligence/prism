//
//  LabMath.swift
//  Prism
//
//  The arithmetic the lab pages share: a marker read in the unit it is shown
//  in and placed on a rail against its range, the usual band of a series,
//  change over a period, and number formatting that keeps a dash for nothing.
//

import Foundation

nonisolated enum LabMath {
    // MARK: Formatting

    static func format(_ value: Double?, decimals: Int, locale: Locale = .current) -> String? {
        guard let value, value.isFinite else { return nil }
        return value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    /// Signed, with a real minus sign: "+1.5", "\u{2212}0.6".
    static func signed(_ value: Double?, decimals: Int, locale: Locale = .current) -> String? {
        guard let value, value.isFinite else { return nil }
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(decimals)).locale(locale))
        let rounded = (abs(value) * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        if rounded == 0 { return magnitude }
        return (value > 0 ? "+" : "\u{2212}") + magnitude
    }

    /// Decimals that suit a value's size: 1.8, 34, 0.31.
    static func decimals(for value: Double) -> Int {
        let a = abs(value)
        if a >= 100 { return 0 }
        if a >= 10 { return a.rounded() == a ? 0 : 1 }
        if a >= 1 { return 1 }
        return 2
    }

    // MARK: A marker on its rail

    /// A marker's value in its display unit, its range in the same unit,
    /// and where both sit on a rail from 0 to 1.
    struct MarkerReading: Sendable, Equatable {
        var value: Double
        var unit: String
        var low: Double?
        var high: Double?
        var status: BloodMarker.RangeStatus
        /// The rail's ends, in the display unit.
        var domain: ClosedRange<Double>

        var text: String {
            let number = LabMath.format(value, decimals: LabMath.decimals(for: value)) ?? "-"
            return unit.isEmpty || unit == "index" ? number : "\(number) \(unit)"
        }

        /// "under 130", "over 40", "70 to 99", or nil when there is no range.
        var rangeText: String? {
            func f(_ v: Double) -> String { LabMath.format(v, decimals: abs(v) >= 10 ? 0 : LabMath.decimals(for: v)) ?? "" }
            switch (low, high) {
            case let (low?, high?) where low > 0: return "\(f(low)) to \(f(high))"
            case let (_, high?): return "under \(f(high))"
            case let (low?, nil): return "over \(f(low))"
            default: return nil
            }
        }

        var isOutside: Bool { status == .low || status == .high }

        func position(_ x: Double) -> Double {
            let span = domain.upperBound - domain.lowerBound
            guard span > 0 else { return 0.5 }
            return min(max((x - domain.lowerBound) / span, 0), 1)
        }
    }

    static func reading(_ value: BloodMarkerValue) -> MarkerReading {
        let marker = BloodMarkerCatalog.definition(for: value)
        // A value converted out of its storage unit carries the conversion's
        // noise (90.09 mg/dL); above ten it reads as a whole number.
        let converted = marker.toDisplay(value.value)
        let isConverted = BloodMarkerCatalog.normalize(marker.storageUnit) != BloodMarkerCatalog.normalize(marker.displayUnit)
        let shown = isConverted && abs(converted) >= 10 ? converted.rounded() : converted
        let low = marker.refLow.map(marker.toDisplay)
        let high = marker.refHigh.map(marker.toDisplay)
        return MarkerReading(
            value: shown, unit: marker.displayUnit, low: low, high: high,
            status: marker.status(forStorage: value.value),
            domain: domain(value: shown, low: low, high: high)
        )
    }

    /// A rail wide enough for the range and the value with room either side.
    static func domain(value: Double, low: Double?, high: Double?) -> ClosedRange<Double> {
        let lo = low ?? 0
        let hi = high ?? max(value, lo) * 1.6
        let span = max(hi - lo, abs(value) * 0.2, 0.001)
        let start = max(0, min(lo - span * 0.5, value - span * 0.2))
        let end = max(hi + span * 0.5, value + span * 0.2)
        return start...end
    }

    // MARK: Series

    /// The middle half of a series: the band a reading is "usual" in.
    static func usualBand(_ values: [Double]) -> ClosedRange<Double>? {
        let sorted = values.filter(\.isFinite).sorted()
        guard sorted.count >= 4 else { return nil }
        func quantile(_ q: Double) -> Double {
            let position = q * Double(sorted.count - 1)
            let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
            return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
        }
        return quantile(0.25)...quantile(0.75)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The latest point against the newest one at or before `days` days ago.
    static func change(_ points: [LabPoint], days: Int, now: Date, calendar: Calendar) -> Double? {
        guard let latest = points.max(by: { $0.date < $1.date }) else { return nil }
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        guard let earlier = points.filter({ $0.date <= cutoff }).max(by: { $0.date < $1.date }) else { return nil }
        return latest.value - earlier.value
    }

    /// Body mass index from kilograms and metres.
    static func bmi(kilograms: Double?, metres: Double?) -> Double? {
        guard let kilograms, let metres, metres > 0.5 else { return nil }
        return kilograms / (metres * metres)
    }

    /// A sparse series carried day by day from its first sample to `now`,
    /// each day holding the last value known by then: how a weight or a
    /// VO2 max taken now and then becomes the longitudinal series the
    /// biological age averages.
    static func forwardFilled(_ points: [LabPoint], days: Int, now: Date, calendar: Calendar) -> [Double] {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        let today = calendar.startOfDay(for: now)
        let start = max(calendar.startOfDay(for: first.date),
                        calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today)
        var out: [Double] = []
        var index = 0
        var current: Double?
        var day = start
        while day <= today {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            while index < sorted.count, sorted[index].date < end {
                current = sorted[index].value
                index += 1
            }
            if let current { out.append(current) }
            day = end
        }
        return out
    }
}
