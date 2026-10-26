//
//  EnvironmentReport.swift
//  Prism
//

import Foundation
import HealthExportCore

/// What surrounds you, worked out from ``EnvironmentInputs``: the Environment
/// lens and the Around you card on Today both read one of these.
///
/// Environment carries no score and no aspect. Every number is one the watch
/// recorded; air, UV, weather, sunset and the bedroom have no source yet and
/// stay nil, which the views draw as a dash.
struct EnvironmentReport: Equatable, Codable {
    var headline: String
    var reason: String

    /// Minutes of daylight today, or nil when the watch recorded none.
    var daylight: Double?
    /// The middle half of the last 30 days, rounded to five minutes.
    var daylightUsual: ClosedRange<Double>?
    var isDaylightLow: Bool
    /// Today's stretches outside as shares of the day, midnight to midnight.
    var daylightSpans: [ClosedRange<Double>]
    /// Where now sits in the day, as a share of it.
    var now: Double
    /// When today's first stretch outside began and the last one ended.
    var firstOutside: String?
    var lastOutside: String?

    /// Average sound around you today, in dBA.
    var sound: Double?
    var soundUsual: ClosedRange<Double>?
    /// Average headphone level over the last seven days, in dBA.
    var headphones: Double?

    /// The latest UV index today, or nil when nothing wrote one.
    var uvNow: Double?

    /// Thirty days, oldest first and today last, nil where nothing was
    /// recorded: minutes in daylight, the day's highest UV index, and the
    /// day's average sound around you and in your headphones.
    var daylightDays: [Double?] = []
    var uvDays: [Double?] = []
    var soundDays: [Double?] = []
    var headphoneDays: [Double?] = []
    /// The midnight the thirty days end on.
    var today: Date = .distantPast
    /// The weather where you are, set by the lens once it is read; nil
    /// until then, or when the service could not be reached.
    var outside: EnvironmentConditions?
    /// The last seven days, from Health alone; the lens lays the weather
    /// in with ``EnvironmentWeek/laying(_:)``. Nil in a report saved by an
    /// older build.
    var week: EnvironmentWeek?

    /// The line under the Around you card's value.
    var summary: String

    /// The one move the lens offers.
    var suggestionTitle: String
    var suggestionDetail: String

    /// Days this year with at least ``outsideMinutes`` of daylight.
    var daysOutside: String?
    var daysOutsideNote: String
    var grid: PulseYearGrid

    /// Daylight that makes a day one spent outside.
    static let outsideMinutes: Double = 30
    /// The level Apple warns at for headphones held over a week.
    static let headphoneLimit: Double = 80

    static func make(from inputs: EnvironmentInputs, calendar: Calendar = .current, locale: Locale = .current) -> EnvironmentReport {
        let words = PulseWording(calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: inputs.now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let dayLength = tomorrow.timeIntervalSince(today)

        // Daylight.
        let sampled = inputs.daylightToday.map(\.value)
        let daylight = inputs.daylightByDay[today] ?? (sampled.isEmpty ? nil : sampled.reduce(0, +))
        let pastDaylight = (1...30).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).flatMap { inputs.daylightByDay[$0] }
        }
        let daylightUsual = usual(pastDaylight, roundedTo: 5)
        let isLow = daylight.map { value in daylightUsual.map { value < $0.lowerBound } ?? false } ?? false
        let spans = inputs.daylightToday.compactMap { reading -> ClosedRange<Double>? in
            let start = max(0, reading.start.timeIntervalSince(today) / dayLength)
            let end = min(1, reading.end.timeIntervalSince(today) / dayLength)
            return end > start ? start...end : nil
        }

        // Sound.
        let soundToday = PulseTrends.mean(inputs.sound.filter { $0.start >= today }.map(\.value))
        let soundByDay = Dictionary(grouping: inputs.sound.filter { $0.start < today }) { calendar.startOfDay(for: $0.start) }
            .compactMapValues { PulseTrends.mean($0.map(\.value)) }
        let soundUsual = usual(Array(soundByDay.values), roundedTo: 1)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let headphones = PulseTrends.mean(inputs.headphones.filter { $0.start >= weekAgo }.map(\.value))

        // Thirty days, oldest first.
        let days = (0..<30).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        func byDay(_ readings: [HealthReading], _ fold: ([Double]) -> Double?) -> [Double?] {
            let grouped = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.start) }
            return days.map { day in grouped[day].flatMap { fold($0.map(\.value)) } }
        }
        let uvDays = byDay(inputs.uv) { $0.max() }
        let uvNow = inputs.uv.filter { $0.start >= today }.max { $0.start < $1.start }?.value

        // The lead.
        var headline: String
        var sentences: [String] = []
        if let daylight {
            let minutes = "\(words.whole(daylight)) \(Int(daylight.rounded()) == 1 ? "minute" : "minutes")"
            if let daylightUsual {
                let usualText = "\(words.whole(daylightUsual.lowerBound)) to \(words.whole(daylightUsual.upperBound))"
                if daylight < daylightUsual.lowerBound {
                    headline = "Not much light today."
                } else if daylight > daylightUsual.upperBound {
                    headline = "A bright day outside."
                } else {
                    headline = "A usual day for light."
                }
                sentences.append("You got \(minutes) of daylight so far, against a usual \(usualText).")
            } else {
                headline = "\(minutes.capitalizedFirst) of daylight so far."
                sentences.append("Your usual needs a week of days outside.")
            }
        } else if let soundToday {
            headline = "A \(loudness(soundToday)) day around you."
        } else {
            headline = "Nothing measured around you yet."
        }
        if let soundToday {
            sentences.append("The sound around you stayed near \(words.whole(soundToday)) dB.")
        }
        let gap = daylightUsual.flatMap { usual in daylight.map { max(0, usual.lowerBound - $0) } } ?? 0
        let more = roundedUp(gap, to: 5)
        if isLow, more > 0 {
            sentences.append("\(spelled(more)) more minutes outside would help tonight’s sleep.")
        }
        let reason: String
        if sentences.isEmpty {
            reason = "Your Apple Watch records time in daylight and the sound around you. Air quality, UV and the weather are read for where you are, once Soma knows the place."
        } else {
            reason = sentences.joined(separator: " ")
        }

        // The Today card's line.
        var summaryParts: [String] = []
        if let soundToday {
            summaryParts.append("A \(loudness(soundToday)) \(words.whole(soundToday)) dB around you.")
        }
        if let daylightUsual {
            summaryParts.append("Your usual is \(words.whole(daylightUsual.lowerBound)) to \(words.whole(daylightUsual.upperBound)) min of light.")
        }
        let summary = summaryParts.isEmpty
            ? "Time in daylight and the sound around you, from your watch, fill this card."
            : summaryParts.joined(separator: " ")

        // Days outside.
        let january = calendar.dateInterval(of: .year, for: inputs.now)?.start ?? today
        let thisYear = inputs.daylightByDay.filter { $0.key >= january && $0.key <= today }
        let grid = PulseYearGrid.make(thisYear, now: inputs.now, calendar: calendar, locale: locale)
        let outsideCount = thisYear.values.filter { $0 >= outsideMinutes }.count

        return EnvironmentReport(
            headline: headline,
            reason: reason,
            daylight: daylight,
            daylightUsual: daylightUsual,
            isDaylightLow: isLow,
            daylightSpans: spans,
            now: min(1, max(0, inputs.now.timeIntervalSince(today) / dayLength)),
            firstOutside: inputs.daylightToday.map(\.start).min().map(words.time),
            lastOutside: inputs.daylightToday.map(\.end).max().map(words.time),
            sound: soundToday,
            soundUsual: soundUsual,
            headphones: headphones,
            uvNow: uvNow,
            daylightDays: days.map { day in day == today ? daylight : inputs.daylightByDay[day] },
            uvDays: uvDays,
            soundDays: byDay(inputs.sound) { PulseTrends.mean($0) },
            headphoneDays: byDay(inputs.headphones) { PulseTrends.mean($0) },
            today: today,
            week: EnvironmentWeek.make(inputs: [inputs], now: inputs.now, calendar: calendar),
            summary: summary,
            suggestionTitle: isLow && more > 0 ? "\(spelled(more)) minutes outside" : "Time outside",
            suggestionDetail: "Days with more daylight tend to end in easier sleep. Your watch counts every minute.",
            daysOutside: thisYear.isEmpty ? nil : words.whole(Double(outsideCount)),
            daysOutsideNote: thisYear.isEmpty
                ? "Time in daylight from your watch fills one square a day."
                : "Days with \(words.whole(outsideMinutes)) minutes of daylight or more.",
            grid: grid
        )
    }

    // MARK: - Pure arithmetic

    /// The middle half of `values`, each end rounded to `step`. Nil under a
    /// week of values: a usual needs that many to mean anything.
    static func usual(_ values: [Double], roundedTo step: Double) -> ClosedRange<Double>? {
        guard values.count >= 7 else { return nil }
        let sorted = values.sorted()
        let low = (sorted[sorted.count / 4] / step).rounded() * step
        let high = (sorted[(sorted.count * 3) / 4] / step).rounded() * step
        return low...max(low, high)
    }

    static func roundedUp(_ value: Double, to step: Double) -> Int {
        guard value > 0 else { return 0 }
        return Int((value / step).rounded(.up) * step)
    }

    /// A sound level in one word. Apple warns at 80 dB held for long; under
    /// 65 is a quiet street.
    static func loudness(_ decibels: Double) -> String {
        switch decibels {
        case ..<65: "quiet"
        case ..<80: "busy"
        default: "loud"
        }
    }

    /// Minutes as a word, the way the page writes a suggestion: Twenty.
    static func spelled(_ minutes: Int) -> String {
        let names = [5: "Five", 10: "Ten", 15: "Fifteen", 20: "Twenty", 25: "Twenty five", 30: "Thirty",
                     40: "Forty", 45: "Forty five", 50: "Fifty", 60: "Sixty"]
        return names[minutes] ?? "\(minutes)"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#if DEBUG
extension EnvironmentReport {
    /// Made up readings for previews and the `-pulse.preview YES` launch
    /// argument only.
    static var preview: EnvironmentReport {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var inputs = EnvironmentInputs(now: now)
        for offset in 0..<300 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            inputs.daylightByDay[day] = offset == 0 ? 48 : Double((offset * 53) % 140)
            if offset < 31 {
                let at = day.addingTimeInterval(13 * 3600)
                inputs.sound.append(HealthReading(metric: EnvironmentInputs.Metric.sound, value: 55 + Double(offset % 10),
                                                  unit: .none, start: min(at, now), end: min(at, now)))
            }
            if offset < 31 {
                let at = day.addingTimeInterval(9 * 3600)
                inputs.headphones.append(HealthReading(metric: EnvironmentInputs.Metric.headphones,
                                                       value: 66 + Double((offset * 7) % 12),
                                                       unit: .none, start: at, end: at))
                let noon = min(day.addingTimeInterval(12 * 3600), now)
                inputs.uv.append(HealthReading(metric: EnvironmentInputs.Metric.uv, value: Double(2 + (offset * 3) % 6),
                                               unit: .none, start: noon, end: noon))
            }
        }
        let walk = today.addingTimeInterval(12 * 3600 + 5 * 60)
        inputs.daylightToday = [
            HealthReading(metric: EnvironmentInputs.Metric.daylight, value: 12, unit: .none,
                          start: today.addingTimeInterval(8 * 3600), end: today.addingTimeInterval(8 * 3600 + 12 * 60)),
            HealthReading(metric: EnvironmentInputs.Metric.daylight, value: 36, unit: .none,
                          start: walk, end: walk.addingTimeInterval(36 * 60)),
        ]
        return make(from: inputs, calendar: calendar)
    }

    /// Whether a Debug build was launched to draw the fixtures.
    static var usesPreview: Bool { UserDefaults.standard.bool(forKey: "pulse.preview") }
}
#endif
