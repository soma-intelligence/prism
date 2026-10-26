//
//  MindParts.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

// MARK: - Shared arithmetic

enum MindMath {
    /// Days in a row with something in `days`, counted back from today, or
    /// from yesterday when today holds nothing yet: a streak is not broken by
    /// an evening that has not happened.
    static func streak(_ days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        let normalized = Set(days.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !normalized.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while normalized.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// A signed whole number: +5, -3, and a plain 0.
    nonisolated static func signed(_ value: Double) -> String {
        let whole = Int(value.rounded())
        if whole == 0 { return "0" }
        return whole > 0 ? "+\(whole)" : "\(whole)"
    }

    /// Up when `value` sits more than `margin` above `usual`, down when more
    /// than `margin` below.
    static func trend(_ value: Double?, against usual: Double?, by margin: Double) -> SomaTrend? {
        guard let value, let usual, margin > 0 else { return nil }
        if value > usual + margin { return .up }
        if value < usual - margin { return .down }
        return nil
    }

    /// The latest reading from the last day and a half, and the median of the
    /// daily values over the month before today.
    static func latestAndUsual(
        _ readings: [HealthReading],
        now: Date,
        calendar: Calendar,
        reduce: ([Double]) -> Double?
    ) -> (latest: Double?, usual: Double?) {
        let today = calendar.startOfDay(for: now)
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let latest = readings
            .filter { $0.start <= now && now.timeIntervalSince($0.end) < 36 * 60 * 60 }
            .max { $0.end < $1.end }?.value
        let daily = PulseSignals.daily(readings.filter { $0.start >= monthAgo && $0.start < today }, calendar: calendar, reduce: reduce)
        let usual = daily.count >= 5 ? PulseSignals.median(Array(daily.values)) : nil
        return (latest, usual)
    }

    nonisolated static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Inner space

/// One half hour of today on the stress strip.
enum MindSlot: Equatable, Sendable {
    case quiet
    case raised
    /// Not lived yet, or nothing to read.
    case later
}

/// One moment on today's energy line.
struct MindEnergyPoint: Equatable, Sendable {
    /// Where in the day, midnight 0 to the next midnight 1.
    var dayFraction: Double
    /// The bank's level, 0 to 100.
    var level: Double
}

/// One day of mindful minutes on the week's bars.
struct MindBar: Equatable, Sendable, Identifiable, Codable {
    var day: Date
    var letter: String
    /// Nil when Health holds no mindful session at all: not measured.
    var minutes: Double?
    var isToday: Bool

    var id: Date { day }
}

struct MindInnerSpace: Equatable, Sendable {
    var reason: String
    var variability: Double?
    var variabilityTrend: SomaTrend?
    var usualVariability: Double?
    var resting: Double?
    var restingTrend: SomaTrend?
    var mindfulToday: Double?
    var energyNote: String
    /// The energy bank now, 0 to 100. Nil until the bank has seen a night.
    var energy: Double? = nil
    /// Today's energy from midnight to now, from `SomaScores`.
    var energyCurve: [MindEnergyPoint] = []
    var slots: [MindSlot]
    var week: [MindBar]
    var mindfulNote: String
    var ritualDetail: String

    static let slotsPerDay = 48
    /// Minutes in a day that make it a mindful day for the note.
    static let mindfulDayMinutes: Double = 10

    static func make(from inputs: MindInputs, scores: SomaScores? = nil, calendar: Calendar, locale: Locale = .current) -> MindInnerSpace {
        let words = PulseWording(calendar: calendar, locale: locale)
        let now = inputs.now
        let today = calendar.startOfDay(for: now)

        let hrv = MindMath.latestAndUsual(inputs.heartRateVariability, now: now, calendar: calendar, reduce: MindMath.mean)
        let resting = MindMath.latestAndUsual(inputs.restingHeartRate, now: now, calendar: calendar, reduce: PulseSignals.median)

        let minutes = MindDaily.minutesByDay(inputs.mindful, calendar: calendar)
        let hasMindful = !inputs.mindful.isEmpty
        let mindfulToday = hasMindful ? (minutes[today] ?? 0) : nil

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let week: [MindBar] = (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let letter = symbols[(calendar.component(.weekday, from: day) - 1) % symbols.count]
            return MindBar(day: day, letter: letter, minutes: hasMindful ? (minutes[day] ?? 0) : nil, isToday: offset == 0)
        }

        // Evening HRV on days with ten mindful minutes or more against the
        // others. Tonight is not over, so today stays out.
        let evenings = MindDaily.eveningVariability(inputs.heartRateVariability, calendar: calendar).filter { $0.key < today }
        let mindfulDays = Set(minutes.filter { $0.value >= mindfulDayMinutes }.keys)
        let effect = EffectMath.effect(causeDays: mindfulDays, outcome: evenings, better: .higher)
        let mindfulNote: String
        if let delta = effect.delta, Int(delta.rounded()) != 0 {
            let way = delta > 0 ? "higher" : "lower"
            mindfulNote = "On days with ten minutes or more, your evening HRV runs \(words.whole(abs(delta))) ms \(way)."
        } else {
            mindfulNote = "Sessions from Apple Health and mindfulness apps count here. Ten minutes on a few days is enough to measure what they do."
        }

        let peaks = inputs.today?.peaks ?? []
        let slots: [MindSlot] = (0..<slotsPerDay).map { index in
            let start = today.addingTimeInterval(Double(index) * 30 * 60)
            let end = start.addingTimeInterval(30 * 60)
            if start > now { return .later }
            if peaks.contains(where: { $0.start < end && $0.end >= start }) { return .raised }
            // A day with nothing to read has no quiet stretches either.
            return inputs.today?.isReadable == true ? .quiet : .later
        }

        // The line is the energy bank from `SomaScores`, cut to today: from
        // midnight (or last night's bedtime, whichever is later) to now.
        let energyCurve: [MindEnergyPoint] = (scores?.energyCurve ?? []).compactMap { point in
            let fraction = point.date.timeIntervalSince(today) / (24 * 60 * 60)
            guard fraction >= 0, fraction <= 1 else { return nil }
            return MindEnergyPoint(dayFraction: fraction, level: point.level)
        }
        var energyNote: String
        if let energy = scores?.energy {
            energyNote = "Your energy bank is at \(energy) of 100: charged by last night's sleep, spent by the hours awake and today's activity."
            if let stress = scores?.stress {
                energyNote += " Stress today is \(stress) of 100."
            }
        } else {
            energyNote = "The energy line fills in once Apple Health holds a night of sleep to charge from."
        }
        if !peaks.isEmpty {
            energyNote += " The strip is real: heart rate raised while you were still, \(words.count(peaks.count, "time", "times")) today."
        } else if inputs.today?.isReadable == true {
            energyNote += " The strip is real, and quiet: no heart rate raised at rest today."
        } else {
            energyNote += " The strip fills from your watch’s heart rate and steps."
        }

        var sentences: [String] = []
        if let value = hrv.latest {
            if let usual = hrv.usual {
                let relation: String
                switch MindMath.trend(value, against: usual, by: usual * 0.07) {
                case .up: relation = "above"
                case .down: relation = "under"
                case nil: relation = "close to"
                }
                sentences.append("Your HRV is \(words.whole(value)) ms, \(relation) your usual \(words.whole(usual)).")
            } else {
                sentences.append("Your HRV is \(words.whole(value)) ms.")
            }
        }
        if let highest = peaks.max(by: { $0.above < $1.above }) {
            let count = words.count(peaks.count, "stress peak", "stress peaks")
            sentences.append("\(count.prefix(1).uppercased() + count.dropFirst()) today, the highest \(words.whole(highest.above)) beats over resting at \(words.time(highest.start)).")
        } else if inputs.today?.isReadable == true {
            sentences.append("No stress peaks so far today.")
        }
        let reason = sentences.isEmpty
            ? "Nothing to read yet. HRV, resting heart rate and mindful minutes from Apple Health fill this page."
            : sentences.joined(separator: " ")

        let ritualDetail = hrv.usual.map { "Slow breathing can bring your HRV back toward \(words.whole($0)) ms." }
            ?? "Ten slow minutes. Soma measures what they do for you."

        return MindInnerSpace(
            reason: reason,
            variability: hrv.latest,
            variabilityTrend: MindMath.trend(hrv.latest, against: hrv.usual, by: (hrv.usual ?? 0) * 0.07),
            usualVariability: hrv.usual,
            resting: resting.latest,
            restingTrend: MindMath.trend(resting.latest, against: resting.usual, by: 2),
            mindfulToday: mindfulToday,
            energyNote: energyNote,
            energy: scores?.energy.map(Double.init),
            energyCurve: energyCurve,
            slots: slots,
            week: week,
            mindfulNote: mindfulNote,
            ritualDetail: ritualDetail
        )
    }
}

// MARK: - Insights

/// Something that often comes before a hard afternoon, and how often it did.
struct MindPrecursor: Equatable, Sendable, Identifiable {
    var title: String
    var count: Int
    var id: String { title }
}

struct MindInsights: Equatable, Sendable {
    var hardDays: Int?
    var shortNights: Int?
    var calmDays: Int?
    var heatmap: MindHeatmap
    /// The busiest weekdays, short: Tue, Thu.
    var peakDays: String?
    /// The busiest part of the day: afternoons.
    var peakPart: String?
    var hardAfternoons: Int
    var precursors: [MindPrecursor]
    var reason: String

    /// Asleep under this makes a short night.
    static let shortNight: TimeInterval = 7 * 60 * 60
    /// A workout this long, walks aside, counts as hard training.
    static let hardWorkoutMinutes: Double = 45

    /// Of the days given, how many have each thing before them.
    static func precursors(
        before days: [Date],
        shortNights: Set<Date>,
        hardTraining: Set<Date>,
        journal: MindJournal,
        calendar: Calendar
    ) -> [MindPrecursor] {
        var night = 0, dinner = 0, coffee = 0, training = 0
        for day in days {
            let before = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            if shortNights.contains(day) { night += 1 }
            if journal.has("late-meal", on: before) { dinner += 1 }
            if journal.has("coffee-late", on: day) { coffee += 1 }
            if hardTraining.contains(before) || journal.has("hard-training", on: before) { training += 1 }
        }
        return [
            MindPrecursor(title: "A night under seven hours", count: night),
            MindPrecursor(title: "A late dinner the night before", count: dinner),
            MindPrecursor(title: "Coffee after 14:00", count: coffee),
            MindPrecursor(title: "Hard training the day before", count: training),
        ]
    }

    static func make(
        from inputs: MindInputs,
        stress: [MindStressDay],
        journal: MindJournal,
        calendar: Calendar,
        locale: Locale = .current
    ) -> MindInsights {
        let words = PulseWording(calendar: calendar, locale: locale)
        let readable = stress.filter(\.isReadable)
        let heatmap = MindHeatmap.make(stress, calendar: calendar)

        let nights = PulseNights.nights(from: inputs.sleep, calendar: calendar)
        let shortNights = Set(nights.filter { $0.asleep < shortNight }.map(\.day))

        let hardTraining = Set(inputs.workouts.filter { workout in
            workout.code != MindRituals.walkingActivity
                && workout.end.timeIntervalSince(workout.start) / 60 >= hardWorkoutMinutes
        }.map { calendar.startOfDay(for: $0.start) })

        let afternoons = stress.filter { $0.hasAfternoonPeak(calendar: calendar) }.map(\.day)
        let precursors = precursors(
            before: afternoons, shortNights: shortNights, hardTraining: hardTraining,
            journal: journal, calendar: calendar
        )

        let symbols = calendar.shortStandaloneWeekdaySymbols
        let rows = heatmap.topRows
        // Row 0 is Monday; the calendar's symbols start on Sunday.
        let peakDays = rows.isEmpty ? nil : rows.map { symbols[($0 + 1) % 7] }.joined(separator: ", ")
        let fullDays = rows.map { calendar.standaloneWeekdaySymbols[($0 + 1) % 7] }
        let peakPart: String? = switch heatmap.topPart {
        case .morning: "mornings"
        case .afternoon: "afternoons"
        case .evening: "evenings"
        case nil: nil
        }

        var sentences: [String] = []
        if let peakPart, !fullDays.isEmpty {
            sentences.append("Stress peaks cluster on \(words.list(fullDays)) \(peakPart).")
        }
        if let top = precursors.max(by: { $0.count < $1.count }), top.count > 0, !afternoons.isEmpty {
            sentences.append("\(top.count) of \(afternoons.count) hard afternoons came after \(top.title.prefix(1).lowercased() + top.title.dropFirst()).")
        }
        let reason: String
        if !sentences.isEmpty {
            reason = sentences.joined(separator: " ")
        } else if readable.isEmpty {
            reason = "Nothing to read yet. Heart rate and steps from a watch, over a few weeks, show when stress peaks."
        } else {
            reason = "A quiet stretch. No heart rate raised at rest shows a pattern over the last sixty days."
        }

        return MindInsights(
            hardDays: readable.isEmpty ? nil : stress.filter(\.isHard).count,
            shortNights: nights.isEmpty ? nil : shortNights.count,
            calmDays: readable.isEmpty ? nil : stress.filter(\.isCalm).count,
            heatmap: heatmap,
            peakDays: peakDays,
            peakPart: peakPart,
            hardAfternoons: afternoons.count,
            precursors: precursors,
            reason: reason
        )
    }
}
