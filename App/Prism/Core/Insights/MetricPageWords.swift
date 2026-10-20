//
//  MetricPageWords.swift
//  Prism
//
//  What a metric's page says, worked out from its daily year: when the big
//  number is from, the one line on what it means, the few facts under the
//  chart, the chart's labels and readout, and where the readings came from.
//  Pure functions over values, so each is tested without a Health store.
//

import Foundation
import SomaUI

enum MetricPageWords {
    /// How a metric fills its days.
    enum Kind: Equatable, Sendable {
        /// A daily total that keeps growing until midnight (steps).
        case total
        /// A night, filed under the morning it ended.
        case night
        /// A reading taken through the day, read as the day's mean.
        case reading(manyADay: Bool)
        /// One of Soma's scores, or what the engine reads off a night.
        case score
    }

    // MARK: - The hero

    /// When the big number is from: "Today so far", "Last night", "Oct 12".
    static func caption(for day: Date?, kind: Kind, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let day else { return nil }
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: day)
        let back = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        switch back {
        case 0:
            return switch kind {
            case .total: "Today so far"
            case .night: "Last night"
            case .reading(manyADay: true): "Today's average"
            case .reading, .score: "Today"
            }
        case 1:
            return kind == .night ? "The night before" : "Yesterday"
        default:
            var style: Date.FormatStyle = back > 300
                ? .dateTime.month(.abbreviated).day().year()
                : .dateTime.month(.abbreviated).day()
            style.timeZone = calendar.timeZone
            return day.formatted(style)
        }
    }

    /// The line under the big number, and its tone.
    struct Meaning: Equatable, Sendable {
        var text: String
        var tone: SomaCueTone
    }

    /// One plain line on what the value means against the band: "Within
    /// your usual", "Above the typical range", or for a total on a day still
    /// adding up, how far it is from a usual day ("531 steps to a usual
    /// day"). Wellness words, never a verdict on health.
    ///
    /// - Parameters:
    ///   - value: the hero's value, in the unit the page shows.
    ///   - known: how many days hold a reading; under three there is no
    ///     usual yet.
    ///   - todayOpen: the value is a total for today, which is not over.
    static func meaning(
        value: Double?,
        band: ClosedRange<Double>?,
        isReference: Bool,
        known: Int,
        todayOpen: Bool,
        risingIsGood: Bool?,
        format: (Double) -> String,
        unit: String?
    ) -> Meaning? {
        guard let value else { return known == 0 ? Meaning(text: "Waiting for a first reading", tone: .neutral) : nil }
        guard let band else {
            return known < 3 ? Meaning(text: "Still learning your usual", tone: .neutral) : nil
        }
        // Out of the band is worth a look unless that way is good news.
        let above: SomaCueTone = risingIsGood == true ? .good : .watch
        let below: SomaCueTone = risingIsGood == false ? .good : .watch
        let within: SomaCueTone = .good

        if todayOpen {
            if value > band.upperBound { return Meaning(text: "Already above a usual day", tone: risingIsGood == true ? .good : .neutral) }
            if value >= band.lowerBound { return Meaning(text: "Already a usual day", tone: within) }
            let gap = format(band.lowerBound - value) + (unit.map { " \($0)" } ?? "")
            return Meaning(text: "\(gap) to a usual day", tone: .neutral)
        }

        let whose = isReference ? "the typical range" : "your usual"
        if value > band.upperBound { return Meaning(text: "Above \(whose)", tone: above) }
        if value < band.lowerBound { return Meaning(text: "Below \(whose)", tone: below) }
        return Meaning(text: isReference ? "In the typical range" : "Within your usual", tone: within)
    }

    // MARK: - Facts

    /// The usual as a fact: "7.1K to 9.4K".
    static func usualFact(band: ClosedRange<Double>?, isReference: Bool, format: (Double) -> String) -> SomaFact {
        let label = isReference ? "Typical range" : "Your usual"
        guard let band else { return SomaFact(label, value: nil, detail: "Needs a few days") }
        return SomaFact(label, value: "\(compact(band.lowerBound, format: format)) to \(compact(band.upperBound, format: format))")
    }

    /// How the last thirty finished days moved against the thirty before:
    /// "Up 4%" from the earlier mean, or "Steady" around the recent one.
    /// The tone says whether that way is good news.
    static func trendFact(
        days: [Double?],
        openDayTail: Int,
        risingIsGood: Bool?,
        accumulates: Bool,
        format: (Double) -> String
    ) -> SomaFact? {
        let label = "30 day trend"
        let finished = Array(days.dropLast(min(openDayTail, days.count)))
        let recent = finished.suffix(30).compactMap { $0 }
        let before = finished.dropLast(30).suffix(30).compactMap { $0 }
        guard recent.count >= 7, before.count >= 7 else { return nil }
        let mean = recent.reduce(0, +) / Double(recent.count)
        let past = before.reduce(0, +) / Double(before.count)
        guard abs(past) > 0.0001 else { return nil }
        let change = (mean - past) / abs(past)
        let dead = accumulates ? 0.03 : 0.015
        if abs(change) < dead {
            return SomaFact(label, value: "Steady", detail: "Around " + format(mean), tone: .neutral)
        }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        let rising = change > 0
        let tone: SomaCueTone = switch risingIsGood {
        case .some(let good): good == rising ? .good : .watch
        case .none: .neutral
        }
        return SomaFact(label, value: (rising ? "Up " : "Down ") + percent, detail: "From " + format(past), tone: tone)
    }

    /// How many of the last thirty finished days sat in the band: "21 of 30".
    static func daysInBandFact(days: [Double?], band: MetricDetailMath.Band?, openDayTail: Int) -> SomaFact? {
        guard let band else { return nil }
        let end = days.count - min(openDayTail, days.count)
        let start = max(0, end - 30)
        var inside = 0
        var known = 0
        for index in start..<end {
            guard let value = days[index], let range = band.range(at: index) else { continue }
            known += 1
            if range.contains(value) { inside += 1 }
        }
        guard known > 0 else { return nil }
        return SomaFact(band.isReference ? "Days in range" : "Usual days", value: "\(inside) of \(known)")
    }

    /// Where the line through the last months lands in thirty days.
    static func projectionFact(_ projections: [MetricDetailMath.Projection], format: (Double) -> String, unit: String?) -> SomaFact? {
        guard let month = projections.first(where: { $0.days == 30 }) else { return nil }
        return SomaFact(
            "In 30 days",
            value: format(month.value) + (unit.map { " \($0)" } ?? ""),
            detail: "\u{00B1} " + format(month.margin)
        )
    }

    /// A number shortened past a thousand, so two of them fit a third of the
    /// width: 7.1K.
    static func compact(_ value: Double, format: (Double) -> String) -> String {
        abs(value) >= 1000
            ? value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
            : format(value)
    }

    // MARK: - Ranges

    /// The spans a page offers: a day only when the metric is read through
    /// the day, so a once a day reading never opens on a single dot.
    static func ranges(dayIsUseful: Bool) -> [VaultPeriod] {
        dayIsUseful ? [.day, .week, .month, .year] : [.week, .month, .year]
    }

    /// The span a page opens on, among the ones it offers.
    static func opening(_ preferred: VaultPeriod, offered: [VaultPeriod]) -> VaultPeriod {
        let mapped: VaultPeriod = switch preferred {
        case .threeMonths: .month
        case .sixMonths: .year
        default: preferred
        }
        return offered.contains(mapped) ? mapped : (offered.contains(.month) ? .month : offered.first ?? .month)
    }

    /// The word on a range's segment.
    static func title(_ period: VaultPeriod) -> String {
        switch period {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .year: "Year"
        }
    }

    // MARK: - The chart's words

    /// The label under slot `index` of `count`, or nil for a slot that
    /// carries none: four hours of a day, every weekday, every seventh day
    /// counted back from today, every month as its initial.
    static func axisLabel(_ period: VaultPeriod, index: Int, count: Int, start: Date, calendar: Calendar = .current) -> String? {
        func words(_ style: Date.FormatStyle) -> String {
            var style = style
            style.timeZone = calendar.timeZone
            return start.formatted(style)
        }
        switch period {
        case .day:
            let hour = calendar.component(.hour, from: start)
            return hour % 6 == 0 ? words(.dateTime.hour()) : nil
        case .week:
            return words(.dateTime.weekday(.narrow))
        case .month, .threeMonths, .sixMonths:
            return (count - 1 - index) % 7 == 0 ? words(.dateTime.day()) : nil
        case .year:
            return words(.dateTime.month(.narrow))
        }
    }

    /// When a slot was, as the readout says it while a finger rests on it.
    static func readout(_ period: VaultPeriod, interval: DateInterval) -> String {
        switch period {
        case .day:
            return interval.start.formatted(.dateTime.hour()) + " to " + interval.end.formatted(.dateTime.hour())
        case .week, .month: return interval.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .threeMonths, .sixMonths: return "Week of " + interval.start.formatted(.dateTime.month(.abbreviated).day())
        case .year: return interval.start.formatted(.dateTime.month(.wide).year())
        }
    }

    /// What the readout says before a finger picks a slot: "Daily average,
    /// Sep 20 to Oct 19", "Total today".
    static func summaryLabel(_ period: VaultPeriod, kind: Kind, span: DateInterval, now: Date = .now, calendar: Calendar = .current) -> String {
        if period == .day {
            return kind == .total ? "Total today" : "Average today"
        }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        // A span ends at the close of the bucket holding today, which for a
        // year is the end of the month: the words stop at today.
        let last = min(span.end.addingTimeInterval(-1), now)
        let dates = span.start.formatted(style) + " to " + last.formatted(style)
        let what = switch kind {
        case .total: "Daily average"
        case .night: "Average night"
        case .reading, .score: "Average"
        }
        return "\(what), \(dates)"
    }

    // MARK: - Sources

    /// The sources as the page lists them: each one's share of the readings,
    /// a glyph for a kind of device the grade recognised, and a word on how
    /// the readings were taken.
    static func sources(_ origins: [VaultMasterReader.Origin]) -> [SomaSource] {
        let total = origins.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        return origins.map { origin in
            SomaSource(
                name: origin.name,
                symbol: symbol(origin),
                share: Double(origin.count) / Double(total),
                quality: quality(origin.quality.level)
            )
        }
    }

    static func symbol(_ origin: VaultMasterReader.Origin) -> String? {
        let text = [origin.name, origin.device ?? ""].joined(separator: " ").lowercased()
        if origin.quality.level == .manual { return "hand.point.up.left" }
        if text.contains("watch") { return "applewatch" }
        if text.contains("iphone") || text.contains("phone") { return "iphone" }
        return switch origin.quality.reason {
        case "Chest strap": "heart"
        case "Ring": "circle.circle"
        case "Scale": "scalemass"
        case "Glucose sensor": "drop"
        case "Cuff": "gauge.with.dots.needle.50percent"
        case "Wrist sensor": "applewatch"
        default: nil
        }
    }

    static func quality(_ level: ReadingQuality.Level) -> String? {
        switch level {
        case .reference: "Most precise"
        case .sensor: "Measured"
        case .estimated: "Estimated"
        case .manual: "Entered by hand"
        case .unknown: nil
        }
    }

    // MARK: - Names

    /// The name a page carries: the short one Soma uses where it has one
    /// ("Steps", "Blood oxygen"), else Health's.
    static func title(identifier: String, fallback: String) -> String {
        InsightMetric.metric(for: identifier)?.title ?? sentenceCase(fallback)
    }

    /// Health's title case as the app writes names: "Heart Rate" reads
    /// "Heart rate". A word in capitals or with a digit (HRV, VO2) keeps
    /// its case.
    static func sentenceCase(_ title: String) -> String {
        let words = title.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        return words.enumerated().map { index, word in
            guard index > 0, word.contains(where: \.isLowercase), !word.contains(where: \.isNumber) else { return word }
            return word.lowercased()
        }.joined(separator: " ")
    }

    /// The unit beside a value, where Health's own says nothing (a count of
    /// steps) or says it ambiguously (breaths, not beats, a minute).
    static func unit(identifier: String, fallback: String?) -> String? {
        switch identifier {
        case "HKQuantityTypeIdentifierStepCount": "steps"
        case "HKQuantityTypeIdentifierFlightsClimbed": "floors"
        case "HKQuantityTypeIdentifierRespiratoryRate": "breaths/min"
        default: fallback
        }
    }
}
