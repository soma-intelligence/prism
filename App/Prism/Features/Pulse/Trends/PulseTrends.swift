//
//  PulseTrends.swift
//  Prism
//

import Foundation
import HealthExportCore
import HealthScoring
import SomaUI

/// The Trends page, worked out from what Health returned: which of sleep, HRV
/// and exercise moved most over the last 30 days, the three of them as lines,
/// the month's steps against last month's, a year of nights and the active
/// days of the year.
///
/// Every number is one Health really holds, or a score worked out from them.
/// The three rows carry Soma's 0 to 100 scores from ``SomaScores`` (their last
/// 30 days as the line, today's score as the number); what each row says moved
/// is the raw signal under it. A missing one is a dash.
struct PulseTrends: Equatable {
    /// One of the three rows: the aspect, how it moved and its last 30 days.
    struct Row: Equatable, Identifiable {
        var aspect: SomaAspect
        var name: String
        var change: String
        /// One value a day over the last 30 days, oldest first. Nil where
        /// Health holds nothing for the day.
        var series: [Double?]
        /// The middle half of those values, drawn behind the line.
        var band: ClosedRange<Double>?
        var value: String?
        var unit: String

        var id: SomaAspect { aspect }
    }

    /// The month so far, in cumulative steps against the month before.
    struct Month: Equatable {
        var eyebrow: String
        var total: String?
        var note: String
        /// Steps by the end of each day of this month, through today.
        var thisMonth: [Double]
        /// Steps by the end of each day of last month.
        var lastMonth: [Double]
        /// Days in this month, which sets the width of the plot.
        var days: Int
        var startLabel: String
        var endLabel: String
        /// The top of the scale, a round number. Nil when there is nothing
        /// to draw.
        var top: Double?
    }

    /// A year of nights, oldest first, ending last night.
    struct Year: Equatable {
        var nights: [Double?]
        var average: String?
        var note: String
        /// The month nights ran longest, named where it sits on the spiral.
        var peakLabel: String?
        var peakNights: [Int]
        /// The weekday of the first night, Monday as zero, which sets each
        /// night's place along its week's spoke.
        var firstRow: Int = 0
    }

    struct ActiveDays: Equatable {
        var grid: PulseYearGrid
        var count: String?
        var note: String
        /// The weeks the longest streak spans, which carry a glow.
        var streakColumns: ClosedRange<Int>?
    }

    var headline: String
    var reason: String
    var rows: [Row]
    var month: Month
    var year: Year
    var active: ActiveDays

    static func make(
        from inputs: PulseTrendsInputs,
        scores: SomaScores? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> PulseTrends {
        PulseTrendsBuilder(
            inputs: inputs,
            scores: scores,
            calendar: calendar,
            words: PulseWording(calendar: calendar, locale: locale),
            locale: locale
        ).build()
    }

    // MARK: - Pure arithmetic

    /// Exercise minutes that make a day an active one: Apple's own default.
    static let activeMinutes: Double = 30
    /// A change smaller than this share of the month before reads as steady.
    static let steadyShare: Double = 0.03
    /// Days a 30 day window needs before its mean is compared with another.
    static let minimumDays = 7

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The aspect whose mean moved furthest, as a share of where it was, and
    /// that share. Nil when none moved more than ``steadyShare``.
    static func movedMost(_ windows: [SomaAspect: (now: Double, before: Double)]) -> (aspect: SomaAspect, share: Double)? {
        let shares = windows.compactMap { aspect, window -> (SomaAspect, Double)? in
            guard window.before > 0 else { return nil }
            return (aspect, (window.now - window.before) / window.before)
        }
        // Ties go to the order the page lists them in, so the result is stable.
        let order: [SomaAspect] = [.sleep, .mind, .activity]
        let best = shares
            .filter { abs($0.1) >= steadyShare }
            .sorted { lhs, rhs in
                abs(lhs.1) != abs(rhs.1)
                    ? abs(lhs.1) > abs(rhs.1)
                    : (order.firstIndex(of: lhs.0) ?? 9) < (order.firstIndex(of: rhs.0) ?? 9)
            }
            .first
        return best.map { ($0.0, $0.1) }
    }

    /// Running totals: the value by the end of each day. A day with nothing
    /// adds nothing.
    static func cumulative(_ daily: [Double?]) -> [Double] {
        var total = 0.0
        return daily.map { value in
            total += value ?? 0
            return total
        }
    }

    /// The days in `days` at or over `threshold`.
    static func activeDays(_ days: [Date: Double], threshold: Double = activeMinutes) -> Int {
        days.values.filter { $0 >= threshold }.count
    }

    /// The longest run of consecutive days at or over `threshold`, with the
    /// day it began and the day it ended. Nil when no day reaches it.
    static func longestStreak(
        _ days: [Date: Double],
        threshold: Double = activeMinutes,
        calendar: Calendar
    ) -> (length: Int, start: Date, end: Date)? {
        let active = days.filter { $0.value >= threshold }.keys.map { calendar.startOfDay(for: $0) }.sorted()
        guard let first = active.first else { return nil }
        var best = (length: 1, start: first, end: first)
        var run = (length: 1, start: first, end: first)
        for day in active.dropFirst() {
            if let next = calendar.date(byAdding: .day, value: 1, to: run.end), calendar.isDate(next, inSameDayAs: day) {
                run = (run.length + 1, run.start, day)
            } else if !calendar.isDate(run.end, inSameDayAs: day) {
                run = (1, day, day)
            }
            if run.length > best.length { best = run }
        }
        return best
    }

    /// A round top for a scale holding `value`: one, two, three, four, five,
    /// six or eight times a power of ten, so its half is round too.
    static func niceTop(_ value: Double) -> Double? {
        guard value > 0 else { return nil }
        let power = pow(10, floor(log10(value)))
        for step in [1.0, 2, 3, 4, 5, 6, 8, 10] where step * power >= value {
            return step * power
        }
        return 10 * power
    }

    /// An axis value, short: 300k, 1.5k, 800.
    static func axisLabel(_ value: Double) -> String {
        guard value >= 1000 else { return "\(Int(value.rounded()))" }
        let thousands = value / 1000
        let rounded = (thousands * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))k"
            : String(format: "%.1fk", rounded)
    }
}

// MARK: - Building the page

private struct PulseTrendsBuilder {
    let inputs: PulseTrendsInputs
    let scores: SomaScores?
    let calendar: Calendar
    let words: PulseWording
    let locale: Locale

    var today: Date { calendar.startOfDay(for: inputs.now) }

    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    func build() -> PulseTrends {
        let nights = PulseNights.nights(from: inputs.sleep, calendar: calendar)
        let asleepByDay = Dictionary(nights.map { ($0.day, $0.asleep) }, uniquingKeysWith: max)
        let hrvByDay = dailyMeans(inputs.heartRateVariability)

        // Sleep and HRV run to today, since last night is today's. Exercise
        // stops at yesterday, so a day half done does not drag its mean down.
        let sleep = window(asleepByDay, endingAt: 0)
        let mind = window(hrvByDay, endingAt: 0)
        let activity = window(inputs.exerciseByDay, endingAt: -1)

        var comparable: [SomaAspect: (now: Double, before: Double)] = [:]
        for (aspect, window) in [(SomaAspect.sleep, sleep), (.mind, mind), (.activity, activity)] {
            if let now = window.nowMean, let before = window.beforeMean { comparable[aspect] = (now, before) }
        }

        // Mind is recovery, or 100 minus stress where recovery is missing:
        // see `SomaScores.mind`. Activity is strain.
        let rows = [
            row(.sleep, name: "Sleep", window: sleep, series: scores?.sleepSeries, score: scores?.sleep),
            row(.mind, name: "Mind", window: mind, series: scores?.mindSeries, score: scores?.mind),
            row(.activity, name: "Activity", window: activity, series: scores?.strainSeries, score: scores?.strain),
        ]

        let (headline, reason) = lead(comparable)
        return PulseTrends(
            headline: headline,
            reason: reason,
            rows: rows,
            month: month(),
            year: year(asleepByDay),
            active: activeDays()
        )
    }

    // MARK: Windows

    struct Window {
        var series: [Double?]
        var nowMean: Double?
        var beforeMean: Double?
        var hasAny: Bool
    }

    /// The 30 days ending `end` days from today, and the 30 before them.
    func window(_ byDay: [Date: Double], endingAt end: Int) -> Window {
        let series = (0..<30).map { byDay[day(end - 29 + $0)] }
        let before = (0..<30).compactMap { byDay[day(end - 59 + $0)] }
        let known = series.compactMap { $0 }
        return Window(
            series: series,
            nowMean: known.isEmpty ? nil : PulseTrends.mean(known),
            beforeMean: before.count >= PulseTrends.minimumDays && known.count >= PulseTrends.minimumDays
                ? PulseTrends.mean(before) : nil,
            hasAny: !known.isEmpty
        )
    }

    func dailyMeans(_ readings: [HealthReading]) -> [Date: Double] {
        let grouped = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.start) }
        return grouped.compactMapValues { PulseTrends.mean($0.map(\.value)) }
    }

    // MARK: Rows

    /// One row: the score's last 30 days and today's score, with the raw
    /// window under it saying what moved.
    func row(_ aspect: SomaAspect, name: String, window: Window, series: [Double?]?, score: Int?) -> PulseTrends.Row {
        let series = series ?? Array(repeating: nil, count: SomaScores.seriesDays)
        let known = series.compactMap { $0 }.sorted()
        var band: ClosedRange<Double>?
        if known.count >= 4 {
            let low = known[known.count / 4]
            let high = known[(known.count * 3) / 4]
            band = low...max(low, high)
        }
        return PulseTrends.Row(
            aspect: aspect,
            name: name,
            change: change(aspect, window: window),
            series: series,
            band: band,
            value: score.map(words.score),
            unit: "of 100"
        )
    }

    func change(_ aspect: SomaAspect, window: Window) -> String {
        guard window.hasAny else {
            switch aspect {
            case .sleep: return "No nights yet"
            case .mind: return "No HRV yet"
            default: return "No exercise yet"
            }
        }
        guard let now = window.nowMean, let before = window.beforeMean else { return "Nothing to compare yet" }
        let gap = now - before
        if before > 0, abs(gap) / before < PulseTrends.steadyShare { return "Holding steady" }
        let direction = gap > 0 ? "up" : "down"
        switch aspect {
        case .sleep: return "\(direction) \(words.span(abs(gap))) a night"
        case .mind: return "\(direction) \(words.whole(abs(gap))) ms"
        default: return "\(direction) \(words.whole(abs(gap))) min a day"
        }
    }

    // MARK: Lead

    func lead(_ comparable: [SomaAspect: (now: Double, before: Double)]) -> (String, String) {
        guard !comparable.isEmpty else {
            return ("Trends need two months of data.",
                    "Soma sets your last 30 days against the 30 before. Sleep, HRV and exercise from Apple Health fill this page as they come in.")
        }
        guard let moved = PulseTrends.movedMost(comparable), let window = comparable[moved.aspect] else {
            return ("Your month held steady.",
                    "Sleep, HRV and exercise each sit within a few percent of the 30 days before.")
        }

        let first = movement(moved.aspect, gap: window.now - window.before)
        // The one to watch: another aspect that slipped, the furthest first.
        let slipping = comparable
            .filter { $0.key != moved.aspect && $0.value.before > 0 }
            .map { ($0.key, ($0.value.now - $0.value.before) / $0.value.before, $0.value.now - $0.value.before) }
            .filter { $0.1 <= -PulseTrends.steadyShare }
            .sorted { $0.1 < $1.1 }
            .first
        let second: String
        if let slipping {
            second = " \(name(slipping.0)) is the one to watch: \(watch(slipping.0, gap: slipping.2))."
        } else if comparable.count > 1 {
            second = comparable.count == 2 ? " The other held or rose." : " The other two held or rose."
        } else {
            second = ""
        }
        return ("\(name(moved.aspect)) moved most this month.", first + second)
    }

    func name(_ aspect: SomaAspect) -> String {
        switch aspect {
        case .sleep: "Sleep"
        case .mind: "Mind"
        default: "Activity"
        }
    }

    func movement(_ aspect: SomaAspect, gap: Double) -> String {
        switch aspect {
        case .sleep:
            "You slept \(words.span(abs(gap))) \(gap > 0 ? "longer" : "less") a night than the 30 days before."
        case .mind:
            "Your HRV \(gap > 0 ? "rose" : "fell") \(words.whole(abs(gap))) ms against the 30 days before."
        default:
            "You exercised \(words.whole(abs(gap))) min \(gap > 0 ? "more" : "less") a day than the 30 days before."
        }
    }

    func watch(_ aspect: SomaAspect, gap: Double) -> String {
        switch aspect {
        case .sleep: "nights are \(words.span(abs(gap))) shorter"
        case .mind: "HRV is down \(words.whole(abs(gap))) ms"
        default: "exercise is down \(words.whole(abs(gap))) min a day"
        }
    }

    // MARK: Month

    func formatted(_ date: Date, _ style: Date.FormatStyle) -> String {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return date.formatted(style)
    }

    func month() -> PulseTrends.Month {
        let interval = calendar.dateInterval(of: .month, for: inputs.now)
        let start = interval?.start ?? today
        let days = calendar.range(of: .day, in: .month, for: inputs.now)?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: inputs.now)
        let lastStart = calendar.date(byAdding: .month, value: -1, to: start) ?? start
        let lastDays = calendar.range(of: .day, in: .month, for: lastStart)?.count ?? 30

        func daily(from first: Date, count: Int) -> [Double?] {
            (0..<count).map { offset in
                calendar.date(byAdding: .day, value: offset, to: first).flatMap { inputs.stepsByDay[$0] }
            }
        }
        let thisDaily = daily(from: start, count: dayOfMonth)
        let lastDaily = daily(from: lastStart, count: lastDays)
        let hasThis = thisDaily.contains { $0 != nil }
        let hasLast = lastDaily.contains { $0 != nil }
        let thisRun = hasThis ? PulseTrends.cumulative(thisDaily) : []
        let lastRun = hasLast ? PulseTrends.cumulative(lastDaily) : []

        let monthName = formatted(inputs.now, Date.FormatStyle().month(.wide))
        let lastName = formatted(lastStart, Date.FormatStyle().month(.wide))

        let note: String
        if let total = thisRun.last {
            if let same = lastRun.isEmpty ? nil : lastRun[min(dayOfMonth, lastRun.count) - 1] {
                let gap = total - same
                note = abs(gap) < 1
                    ? "Level with \(lastName) on the same day."
                    : "\(words.whole(abs(gap))) \(gap > 0 ? "ahead of" : "behind") \(lastName) on the same day."
            } else {
                note = "Nothing from \(lastName) to set this against."
            }
        } else {
            note = "Steps from Apple Health draw this month against \(lastName)."
        }

        let end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? start
        let visibleLast = Array(lastRun.prefix(days))
        let highest = max(thisRun.last ?? 0, visibleLast.last ?? 0)
        return PulseTrends.Month(
            eyebrow: "\(monthName) so far",
            total: thisRun.last.map(words.whole),
            note: note,
            thisMonth: thisRun,
            lastMonth: visibleLast,
            days: days,
            startLabel: formatted(start, Date.FormatStyle().month(.abbreviated).day()),
            endLabel: formatted(end, Date.FormatStyle().month(.abbreviated).day()),
            top: PulseTrends.niceTop(highest)
        )
    }

    // MARK: Year of sleep

    func year(_ asleepByDay: [Date: TimeInterval]) -> PulseTrends.Year {
        let days = (0..<365).map { day(-364 + $0) }
        let nights: [Double?] = days.map { asleepByDay[$0].map { $0 / 3600 } }
        let firstRow = (calendar.component(.weekday, from: days[0]) + 5) % 7
        var result = yearReport(days: days, nights: nights)
        result.firstRow = firstRow
        return result
    }

    func yearReport(days: [Date], nights: [Double?]) -> PulseTrends.Year {
        let known = zip(days, nights).compactMap { day, hours in hours.map { (day, $0) } }
        guard !known.isEmpty else {
            return PulseTrends.Year(nights: nights, average: nil,
                                    note: "A year of nights from Apple Health draws this spiral, one dot a night.",
                                    peakLabel: nil, peakNights: [])
        }
        let average = PulseTrends.mean(known.map(\.1)) ?? 0
        guard known.count >= 30 else {
            return PulseTrends.Year(nights: nights, average: words.clock(average * 3600),
                                    note: "\(words.count(known.count, "night", "nights").capitalizedFirst) so far. The spiral fills one night at a time.",
                                    peakLabel: nil, peakNights: [])
        }

        // Months with enough nights to speak for themselves.
        let byMonth = Dictionary(grouping: known) { calendar.dateInterval(of: .month, for: $0.0)?.start ?? $0.0 }
            .filter { $0.value.count >= 4 }
            .mapValues { PulseTrends.mean($0.map(\.1)) ?? 0 }
        var sentences: [String] = []
        var peakLabel: String?
        var peakNights: [Int] = []
        if byMonth.count >= 2,
           let longest = byMonth.max(by: { $0.value < $1.value }),
           let shortest = byMonth.min(by: { $0.value < $1.value }) {
            let long = formatted(longest.key, Date.FormatStyle().month(.wide))
            let short = formatted(shortest.key, Date.FormatStyle().month(.wide))
            sentences.append("Longest in \(long), shortest in \(short).")
            peakLabel = long
            peakNights = days.indices.filter {
                nights[$0] != nil && calendar.isDate(days[$0], equalTo: longest.key, toGranularity: .month)
            }
        }

        // A night belongs to the morning it ends on: Saturday and Sunday
        // mornings are the nights of the weekend.
        let weekend = known.filter { [1, 7].contains(calendar.component(.weekday, from: $0.0)) }.map(\.1)
        let week = known.filter { ![1, 7].contains(calendar.component(.weekday, from: $0.0)) }.map(\.1)
        if weekend.count >= 4, week.count >= 4,
           let weekendMean = PulseTrends.mean(weekend), let weekMean = PulseTrends.mean(week) {
            let gap = (weekendMean - weekMean) * 3600
            if abs(gap) < 10 * 60 {
                sentences.append("Weekends sleep like the week.")
            } else {
                sentences.append("Weekends \(gap > 0 ? "add" : "take off") \(words.span(abs(gap))).")
            }
        }

        return PulseTrends.Year(
            nights: nights,
            average: words.clock(average * 3600),
            note: sentences.isEmpty ? "Nights over the last year, one dot each." : sentences.joined(separator: " "),
            peakLabel: peakLabel,
            peakNights: peakNights
        )
    }

    // MARK: Active days

    func activeDays() -> PulseTrends.ActiveDays {
        let january = calendar.dateInterval(of: .year, for: inputs.now)?.start ?? today
        let thisYear = inputs.exerciseByDay.filter { $0.key >= january && $0.key <= today }
        let grid = PulseYearGrid.make(thisYear, now: inputs.now, calendar: calendar, locale: locale)

        guard !thisYear.isEmpty else {
            return PulseTrends.ActiveDays(grid: grid, count: nil,
                                          note: "Exercise minutes from Apple Health fill one dot a day.",
                                          streakColumns: nil)
        }

        let count = PulseTrends.activeDays(thisYear)
        let streak = PulseTrends.longestStreak(thisYear, calendar: calendar)
        let note: String
        var streakColumns: ClosedRange<Int>?
        if let streak {
            let length = "\(streak.length) \(streak.length == 1 ? "day" : "days")"
            if calendar.isDate(streak.end, inSameDayAs: today) || calendar.isDate(streak.end, inSameDayAs: day(-1)), streak.length > 1 {
                note = "Longest streak: \(length), running now."
            } else {
                let middle = calendar.date(byAdding: .day, value: streak.length / 2, to: streak.start) ?? streak.start
                note = "Longest streak: \(length), in \(formatted(middle, Date.FormatStyle().month(.wide)))."
            }
            if streak.length >= 3 {
                streakColumns = grid.column(of: streak.start, calendar: calendar)...grid.column(of: streak.end, calendar: calendar)
            }
        } else {
            note = "No day has reached \(words.whole(PulseTrends.activeMinutes)) minutes of exercise yet."
        }

        return PulseTrends.ActiveDays(
            grid: grid,
            count: words.whole(Double(count)),
            note: note,
            streakColumns: streakColumns
        )
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#if DEBUG
extension PulseTrends {
    /// A month of made up readings for previews only.
    static var preview: PulseTrends {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var inputs = PulseTrendsInputs(now: now)
        for offset in 0..<365 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let wave = sin(Double(offset) / 58)
            let hours = 7 + wave * 0.6 + Double(offset % 7 == 1 ? 1 : 0) * 0.5 - (offset < 30 ? 0 : 0.4)
            let fell = day.addingTimeInterval(-60 * 60)
            inputs.sleep.append(HealthReading(metric: PulseInputs.Metric.sleep, value: 1, unit: .none,
                                              start: fell, end: fell.addingTimeInterval(hours * 3600)))
            inputs.exerciseByDay[day] = Double((offset * 37) % 70)
            if offset < 62 {
                inputs.stepsByDay[day] = 6000 + Double((offset * 1733) % 6000)
                inputs.heartRateVariability.append(HealthReading(
                    metric: PulseInputs.Metric.heartRateVariability, value: 44 + 6 * cos(Double(offset) / 4),
                    unit: .none, start: day.addingTimeInterval(3 * 3600), end: day.addingTimeInterval(3 * 3600 + 60)))
            }
        }
        // The scores are the engine's own, worked out from the same made up
        // readings, so the rows draw real score lines over them.
        let starts = SomaScoresReader.dayStarts(days: SomaScoresReader.days, now: now, calendar: calendar)
        let scoring = ScoringInputs(
            now: now,
            calendar: calendar,
            heartRateVariability: SomaScoresReader.dailyMeans(inputs.heartRateVariability, dayStarts: starts, calendar: calendar),
            steps: starts.map { inputs.stepsByDay[$0] },
            exerciseMinutes: starts.map { inputs.exerciseByDay[$0] },
            sleepSamples: inputs.sleep.compactMap {
                ScoringSleepSample(code: $0.code, start: $0.start, end: $0.end, source: "Preview")
            }
        )
        return make(from: inputs, scores: SomaScores.compute(scoring), calendar: calendar)
    }
}
#endif
