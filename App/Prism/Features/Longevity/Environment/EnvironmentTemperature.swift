//
//  EnvironmentTemperature.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The temperature page: outside now with one plain line over today hour by
/// hour (or the last thirty days' highs), the low, high and humidity as one
/// quiet line. When
/// the watch reads it, your wrist overnight follows: last night against your
/// own usual and the last two weeks of nights as dots.
///
/// Opened from the Environment lens's temperature tiles and its place map.
struct EnvironmentTemperatureBody: View {
    let report: EnvironmentReport

    @Environment(HealthDashboard.self) private var health
    @Environment(\.somaTheme) private var theme
    @State private var wrist: EnvironmentTemperature.Wrist?
    @State private var span: EnvironmentTemperature.Span = .today

    var body: some View {
        let metrics = theme.metrics
        let outside = report.outside
        let calendar = Calendar.current
        let now = Date()
        let today = EnvironmentTemperature.today(outside?.hourly ?? [:], now: now, calendar: calendar)
        let month = Array((outside?.highDays ?? []).suffix(30))

        VStack(alignment: .leading, spacing: metrics.leadSpacing) {
            SomaMetricStage(
                lead: SomaMetricLead(
                    caption: String(localized: "Outside now"),
                    value: outside?.temperature.map(EnvironmentTemperature.degrees),
                    unit: "°C",
                    meaning: EnvironmentTemperature.meaning(now: outside?.temperature, low: outside?.low, high: outside?.high)
                ),
                buckets: span == .today
                    ? EnvironmentTemperature.hourBuckets(today, start: calendar.startOfDay(for: now))
                    : EnvironmentTemperature.dayBuckets(month, today: now, calendar: calendar),
                style: .line,
                hue: EnvironmentTemperature.hue,
                domain: EnvironmentTemperature.domain(span == .today ? today : month),
                average: span == .today ? nil : PulseTrends.mean(month.compactMap { $0 }).map {
                    SomaChartAverage(value: $0, text: String(localized: "Average high \(EnvironmentTemperature.degrees($0))°"))
                },
                summary: span == .today ? String(localized: "Today so far, hour by hour") : String(localized: "Each day’s high, last 30 days"),
                note: EnvironmentTemperature.note(low: outside?.low, high: outside?.high, humidity: outside?.humidity),
                periods: month.contains(where: { $0 != nil })
                    ? EnvironmentTemperature.Span.allCases.map { SomaSegment(id: $0, title: $0.title) }
                    : [],
                period: $span
            )

            if let wrist, wrist.last != nil {
                VStack(alignment: .leading, spacing: metrics.cardSpacing) {
                    EnvironmentTemperatureHeading(title: "Your wrist, overnight")
                    SomaMetricStage(
                        lead: SomaMetricLead(
                            caption: String(localized: "Last night"),
                            value: wrist.last.map(EnvironmentTemperature.signed),
                            unit: "°C",
                            meaning: wrist.meaning
                        ),
                        buckets: EnvironmentTemperature.dayBuckets(wrist.nights, today: now, calendar: calendar,
                                                                   band: wrist.band, format: EnvironmentTemperature.signed),
                        style: .points,
                        hue: .vitals,
                        domain: EnvironmentTemperature.domain(wrist.nights + [wrist.band?.lowerBound, wrist.band?.upperBound]),
                        usualLabel: wrist.band.map { String(localized: "Usual \(EnvironmentTemperature.signed($0.lowerBound)) to \(EnvironmentTemperature.signed($0.upperBound))") },
                        summary: String(localized: "Two weeks, against your usual")
                    )
                }
                .padding(.top, metrics.leadSpacing)
            }

            ScoreFootnote(text: "Outside is the forecast where you are. Your wrist is read by your watch as you sleep, against your own usual.")
        }
        .task { await loadWrist() }
    }

    private func loadWrist() async {
        let spec = BodyBiomarkerSpec.appleSleepingWristTemperature
        guard let source = await health.prepare([spec.identifier]) else { return }
        let now = Date()
        let readings = await BodyBiomarkers.read(spec, from: source, now: now, calendar: .current)
        let days = BodyBiomarkers.daily(spec, readings: readings, days: BodyBiomarkers.lookback, now: now, calendar: .current)
        wrist = EnvironmentTemperature.wrist(days)
    }
}

/// A small heading over a part of the temperature page.
private struct EnvironmentTemperatureHeading: View {
    let title: LocalizedStringResource

    @Environment(\.somaTheme) private var theme

    var body: some View {
        Text(title)
            .somaFont(theme.typography.eyebrow)
            .foregroundStyle(theme.colors.inkSecondary.color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The temperature page's numbers and words, pure so they are tested.
nonisolated enum EnvironmentTemperature {
    /// The hue the outside lines draw in: warm, as weather apps draw it.
    static let hue: SomaHealthHue = .mobility

    /// The two spans the outside chart offers.
    enum Span: CaseIterable, Hashable {
        case today, month

        var title: LocalizedStringResource {
            switch self {
            case .today: "Today"
            case .month: "30 days"
            }
        }
    }

    /// The quiet line under the outside chart: "Low 12°, high 20°, humidity 60%".
    static func note(low: Double?, high: Double?, humidity: Double?) -> String? {
        var parts: [String] = []
        if let low { parts.append(String(localized: "Low \(degrees(low))°")) }
        if let high { parts.append((parts.isEmpty ? String(localized: "High") : String(localized: "high")) + " \(degrees(high))°") }
        if let humidity { parts.append((parts.isEmpty ? String(localized: "Humidity") : String(localized: "humidity")) + " \(Int(humidity.rounded()))%") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Your wrist overnight: each night against your usual, in degrees.
    struct Wrist: Equatable, Sendable {
        /// The last fourteen nights, oldest first, as a difference from your
        /// usual; nil on a night with no reading.
        var nights: [Double?]
        /// Last night's difference, nil when last night has no reading.
        var last: Double?
        /// How far your nights usually stray, either side of zero.
        var band: ClosedRange<Double>?

        /// The line under last night's number.
        var meaning: String {
            guard let last else { return String(localized: "Waiting for a night with your watch") }
            guard let band else { return String(localized: "Still learning your usual") }
            if last > band.upperBound { return String(localized: "Warmer than your usual") }
            if last < band.lowerBound { return String(localized: "Cooler than your usual") }
            return String(localized: "Within your usual")
        }
    }

    /// Whole degrees: "14".
    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    /// A signed tenth of a degree: "+0.6", "-0.2", "0.0".
    static func signed(_ value: Double) -> String {
        let tenth = (value * 10).rounded() / 10
        let text = abs(tenth).formatted(.number.precision(.fractionLength(1)))
        return tenth > 0 ? "+" + text : tenth < 0 ? "-" + text : text
    }

    /// "12° to 20°", or nil without both.
    static func range(low: Double?, high: Double?) -> String? {
        guard let low, let high else { return nil }
        return "\(degrees(low))° to \(degrees(high))°"
    }

    /// One plain line on how it feels and where today runs.
    static func meaning(now: Double?, low: Double?, high: Double?) -> String {
        guard let now else { return String(localized: "Waiting for the weather where you are") }
        let feel = switch now {
        case ..<5: String(localized: "Cold")
        case ..<15: String(localized: "Cool")
        case ..<24: String(localized: "Mild")
        case ..<30: String(localized: "Warm")
        default: String(localized: "Hot")
        }
        guard let span = range(low: low, high: high) else { return feel }
        return String(localized: "\(feel), \(span) today")
    }

    /// Today's twenty four hours up to now from the hourly weather, nil for
    /// an hour still to come or one that has none, so the line ends where
    /// you are in the day.
    static func today(_ hourly: [Date: Double], now: Date, calendar: Calendar) -> [Double?] {
        let start = calendar.startOfDay(for: now)
        return (0..<24).map { hour in
            let at = start.addingTimeInterval(Double(hour) * 3_600)
            guard at <= now else { return nil }
            return hourly.first { abs($0.key.timeIntervalSince(at)) < 1_800 }?.value
        }
    }

    /// The values a plot spans, padded so a flat day still has room.
    static func domain(_ values: [Double?]) -> ClosedRange<Double> {
        let known = values.compactMap { $0 }
        guard let low = known.min(), let high = known.max() else { return 0...1 }
        let pad = max((high - low) * 0.18, 1)
        return (low - pad)...(high + pad)
    }

    /// The hours as chart slots, labelled every six hours.
    static func hourBuckets(_ hours: [Double?], start: Date) -> [SomaChartBucket] {
        hours.enumerated().map { index, value in
            let at = start.addingTimeInterval(Double(index) * 3_600)
            return SomaChartBucket(
                id: index,
                value: value,
                axisLabel: index % 6 == 0 ? at.formatted(.dateTime.hour()) : nil,
                readout: at.formatted(.dateTime.hour().minute()),
                valueText: value.map { degrees($0) + "°" }
            )
        }
    }

    /// Days as chart slots, oldest first and today last, labelled at the
    /// first and the middle.
    static func dayBuckets(
        _ days: [Double?],
        today: Date,
        calendar: Calendar,
        band: ClosedRange<Double>? = nil,
        format: (Double) -> String = { degrees($0) + "°" }
    ) -> [SomaChartBucket] {
        let start = calendar.startOfDay(for: today)
        return days.enumerated().map { index, value in
            let date = calendar.date(byAdding: .day, value: index - (days.count - 1), to: start) ?? start
            return SomaChartBucket(
                id: index,
                value: value,
                band: band,
                axisLabel: index == 0 || index == days.count / 2 ? date.formatted(.dateTime.month(.abbreviated).day()) : nil,
                readout: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                valueText: value.map { format($0) + (band == nil ? "" : "°") }
            )
        }
    }

    /// Your wrist from ninety nights, oldest first: the usual is the median
    /// of the nights before the last week, and the band how far they strayed
    /// from it (the middle half, at least a tenth of a degree either side).
    static func wrist(_ days: [Double?]) -> Wrist? {
        let earlier = days.dropLast(7).compactMap { $0 }.sorted()
        guard !days.compactMap({ $0 }).isEmpty else { return nil }
        guard earlier.count >= 5 else {
            return Wrist(nights: Array(repeating: nil, count: 14), last: nil, band: nil)
        }
        let usual = earlier[earlier.count / 2]
        let offsets = earlier.map { $0 - usual }.sorted()
        let low = min(offsets[offsets.count / 4], -0.1)
        let high = max(offsets[(offsets.count * 3) / 4], 0.1)
        let nights = days.suffix(14).map { $0.map { $0 - usual } }
        return Wrist(nights: nights, last: nights.last ?? nil, band: low...high)
    }
}
