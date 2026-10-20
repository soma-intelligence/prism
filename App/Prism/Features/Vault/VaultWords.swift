//
//  VaultWords.swift
//  Prism
//

import Foundation
import SomaUI

/// What the Vault writes beside a category, a score or a record: the short
/// words, kept out of the views so they can be tested.
enum VaultWords {
    /// "12 measures", "1 measure".
    static func measures(_ count: Int) -> String {
        count == 1 ? String(localized: "1 measure") : String(localized: "\(count) measures")
    }

    /// The placeholder of a search over the measures: "Search 115 measures".
    static func searchPrompt(_ count: Int) -> String {
        String(localized: "Search \(count) measures")
    }

    /// How many measures Apple Health gave a reading for, on the Settings
    /// tile: "6 measures with data". Not the measures there are, which the
    /// Vault counts.
    static func withData(_ count: Int) -> String {
        count == 1 ? String(localized: "1 measure with data") : String(localized: "\(count) measures with data")
    }

    /// The head's line: how much the Vault holds.
    static func holds(measures: Int, scores: Int) -> String {
        String(localized: "\(measures) measures, \(scores) scores")
    }

    /// When a day was, as a section of records or a row's caption reads it:
    /// "Today", "Yesterday", a weekday within the week, then a date, with the
    /// year once it is not this one.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        var style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days > 0 && days < 7 {
            style = style.weekday(.wide)
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            style = style.weekday(.abbreviated).month(.abbreviated).day()
        } else {
            style = style.month(.abbreviated).day().year()
        }
        return date.formatted(style)
    }

    /// A record's time of day, or its span when it lasted a minute or more:
    /// "10:00", "23:12 to 06:48".
    static func time(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: calendar.locale ?? .current,
                                     calendar: calendar, timeZone: calendar.timeZone)
        let first = start.formatted(style)
        guard end.timeIntervalSince(start) >= 60 else { return first }
        return String(localized: "\(first) to \(end.formatted(style))")
    }

    /// How many records a day holds: "24 readings", "1 reading".
    static func readings(_ count: Int) -> String {
        count == 1 ? String(localized: "1 reading") : String(localized: "\(count) readings")
    }
}

extension BodyCategory {
    /// The category's glyph as a line rather than a fill, the way every other
    /// glyph in the app is drawn.
    var lineSymbol: String {
        symbol.hasSuffix(".fill") ? String(symbol.dropLast(".fill".count)) : symbol
    }

    /// The name in sentence case: "Body measurements".
    var displayTitle: String { MetricPageWords.sentenceCase(title) }
}

extension ScoreMetric {
    /// The aspect whose tone a score wears in the Vault: the night's parts
    /// are sleep's, recovery and stress are the mind's, strain is activity's
    /// and the energy bank the body's.
    var aspect: SomaAspect {
        switch self {
        case .sleepScore, .remHours, .deepHours, .sleepDebt, .bedtime, .wakeTime: .sleep
        case .recovery, .stress: .mind
        case .strain: .activity
        case .energy: .body
        }
    }

    /// Whether it is a 0 to 100 score rather than something read off a night.
    var isScore: Bool { unit != nil }
}

/// What a score's row says: its latest value, when that was, and its last
/// seven days.
struct VaultScoreSummary: Equatable, Sendable {
    var value: String?
    var caption: String?
    var week: [Double?]

    /// - Parameter days: one value per day, oldest first, ending today.
    static func make(_ score: ScoreMetric, days: [Double?], now: Date = .now, calendar: Calendar = .current) -> VaultScoreSummary {
        let week = Array(days.suffix(7))
        guard let index = days.lastIndex(where: { $0 != nil }), let latest = days[index] else {
            return VaultScoreSummary(value: nil, caption: nil, week: week)
        }
        let back = days.count - 1 - index
        let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)) ?? now
        return VaultScoreSummary(
            value: format(score, latest, calendar: calendar),
            caption: VaultWords.day(day, now: now, calendar: calendar),
            week: week
        )
    }

    /// A score as a whole number, a night's part as hours and minutes, a
    /// bedtime or a wake time as a clock time.
    static func format(_ score: ScoreMetric, _ value: Double, calendar: Calendar = .current) -> String {
        if score.isDuration {
            return Duration.seconds((value * 3600).rounded()).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
        if score.isClock {
            let hour = value.truncatingRemainder(dividingBy: 24)
            return PulseWording(calendar: calendar, locale: calendar.locale ?? .current).clock((hour < 0 ? hour + 24 : hour) * 3600)
        }
        return VaultFormat.number(value.rounded())
    }
}
