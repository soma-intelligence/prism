//
//  ScoreMath.swift
//  Prism
//

import Foundation
import HealthScoring

/// The small arithmetic and wording every score page shares: means over a
/// window, a value against a person's usual band, the trend table, and the
/// way a clock time, a duration or a signed change reads.
nonisolated enum ScoreMath {
    /// The mean of the values present, or nil when none are.
    static func mean<S: Sequence>(_ values: S) -> Double? where S.Element == Double? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
    }

    /// The median of the values present, or nil when none are.
    static func median<S: Sequence>(_ values: S) -> Double? where S.Element == Double? {
        let sorted = values.compactMap { $0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The last non-nil value.
    static func latest(_ values: [Double?]) -> Double? {
        values.last { $0 != nil } ?? nil
    }

    /// The value before today's: the last non-nil one before the final entry.
    static func previous(_ values: [Double?]) -> Double? {
        values.dropLast().last { $0 != nil } ?? nil
    }

    // MARK: - Usual

    /// One signal against its usual band, placed on a shared scale so the
    /// band and the value can be drawn as a track.
    struct UsualLine: Equatable, Identifiable, Sendable {
        var id: String { title }
        var title: String
        /// "usual 42 to 54", or what fills the line when there is no band.
        var detail: String
        var value: String?
        /// Where the value sits on the track, 0 to 1. Nil without a value.
        var position: Double?
        /// Where the usual band sits on the track, 0 to 1.
        var band: ClosedRange<Double>?
        /// True when the value sits outside the band on the worse side.
        var isOff: Bool
    }

    /// Which side of the band reads as worse.
    enum Worse: Sendable { case higher, lower, either, neither }

    static func usualLine(title: String, value: Double?, usual: ScoringUsual?, worse: Worse,
                          format: (Double) -> String, unit: String = "",
                          empty: String = "Fills in after seven readings") -> UsualLine {
        let shown = value.map { format($0) + unit }
        guard let usual else {
            return UsualLine(title: title, detail: empty, value: shown, position: nil, band: nil, isOff: false)
        }
        let low = min(usual.low, value ?? usual.low)
        let high = max(usual.high, value ?? usual.high)
        let pad = max((high - low) * 0.35, 0.0001)
        let lower = low - pad, span = (high + pad) - lower
        func place(_ x: Double) -> Double { min(1, max(0, (x - lower) / span)) }
        let off: Bool = {
            guard let value else { return false }
            switch worse {
            case .higher: return value > usual.high
            case .lower: return value < usual.low
            case .either: return !usual.contains(value)
            case .neither: return false
            }
        }()
        return UsualLine(title: title, detail: "usual \(format(usual.low)) to \(format(usual.high))",
                         value: shown, position: value.map(place), band: place(usual.low)...place(usual.high),
                         isOff: off)
    }

    // MARK: - Trend table

    struct TrendRow: Equatable, Identifiable, Sendable {
        var id: Int { days }
        var days: Int
        var period: String
        var change: String
        var direction: String
        /// The change points the worse way for this score.
        var isWorse: Bool
    }

    /// Each row compares the last seven days' mean with the seven days that
    /// ended `days` ago. A row with nothing on either side is left out.
    static func trendRows(_ series: [Double?], unit: String = "", periods: [Int] = [3, 7, 14, 30, 90],
                          deadBand: Double, higherIsWorse: Bool, decimals: Int = 1,
                          words: (up: String, down: String, flat: String) = ("Rising", "Falling", "Steady"),
                          format: ((Double) -> String)? = nil) -> [TrendRow] {
        guard let now = mean(series.suffix(7)) else { return [] }
        return periods.compactMap { days in
            let end = series.count - days
            guard end >= 1 else { return nil }
            guard let then = mean(series[max(0, end - 7)..<end]) else { return nil }
            let change = now - then
            let direction = abs(change) < deadBand ? words.flat : (change > 0 ? words.up : words.down)
            let worse = abs(change) >= deadBand && (change > 0) == higherIsWorse
            let text = format.map { signedPrefix(change) + $0(abs(change)) }
                ?? signed(change, decimals: decimals) + unit
            return TrendRow(days: days, period: "\(days) days", change: text, direction: direction, isWorse: worse)
        }
    }

    // MARK: - Words for numbers

    /// "+2.1", "\u{2212}0.4", "0".
    static func signed(_ value: Double, decimals: Int = 0) -> String {
        let factor = pow(10, Double(decimals))
        guard (abs(value) * factor).rounded() > 0 else { return number(0, decimals: decimals) }
        return signedPrefix(value) + number(abs(value), decimals: decimals)
    }

    static func signedPrefix(_ value: Double) -> String {
        value < 0 ? "\u{2212}" : "+"
    }

    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// Hours as a clock duration: 7.2 reads "7:12".
    static func hoursMinutes(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Hours as words: "1 h 10", "40 min".
    static func duration(hours: Double) -> String {
        let minutes = Int((abs(hours) * 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, rest)
    }

    /// A clock hour on a 24 hour face: 23.17 reads "23:10".
    static func clock(_ hour: Double) -> String {
        var minutes = Int((HealthStatsClock.wrap(hour) * 60).rounded())
        minutes %= 24 * 60
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The clock hour of a date, with minutes as a fraction.
    static func hour(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// Wraps an hour onto the 24 hour face.
    enum HealthStatsClock {
        static func wrap(_ hour: Double) -> Double {
            let h = hour.truncatingRemainder(dividingBy: 24)
            return h < 0 ? h + 24 : h
        }
    }

    /// A score's band on the common three step scale: under 34, 34 to 66,
    /// 67 and over.
    enum Band: Int, Sendable, Comparable {
        case low, middle, high

        init(_ score: Int) {
            switch score {
            case ..<34: self = .low
            case ..<67: self = .middle
            default: self = .high
            }
        }

        static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
    }
}
