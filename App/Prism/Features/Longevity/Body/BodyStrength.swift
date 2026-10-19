//
//  BodyStrength.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// What the Strength part is built from.
struct BodyStrengthInputs: Sendable, Equatable {
    var now: Date
    /// Lean body mass over the last sixteen weeks, in kilograms.
    var leanMass: [HealthReading] = []
    /// Every workout since the start of the week eight weeks back, each
    /// carrying its coded activity type.
    var workouts: [HealthReading] = []

    static let metrics = [BodyMetric.leanBodyMass, BodyMetric.workout]

    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> BodyStrengthInputs {
        let trendStart = calendar.date(byAdding: .day, value: -BodyMetric.trendLookbackDays, to: now) ?? now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let workoutStart = calendar.date(byAdding: .day, value: -7 * (BodyMath.trendWeeks - 1), to: weekStart) ?? now

        async let lean = BodyMetric.samples(BodyMetric.leanBodyMass, from: trendStart, to: now, in: source)
        async let workouts = BodyMetric.samples(BodyMetric.workout, from: workoutStart, to: now, in: source)
        return BodyStrengthInputs(now: now, leanMass: await lean, workouts: await workouts)
    }
}

/// The Strength part's words and numbers.
struct BodyStrength: Equatable {
    var eyebrow: String?
    var headline: String
    var reason: String

    var leanMass: String?
    var leanTrend: SomaTrend?
    /// Strength sessions a week, averaged over the complete weeks. Nil when
    /// Health returned no workouts of any kind, since then zero would be a
    /// guess.
    var sessionsPerWeek: String?
    /// Sessions in each of the eight weeks, oldest first, the last one the
    /// week in progress. Empty when there is nothing to count.
    var weeks: [Int]
    /// The Monday, or the calendar's first weekday, of the oldest week.
    var firstWeek: Date?
    var sessionsNote: String

    /// Traditional and functional strength training.
    static let strengthTypes: Set<Int> = [50, 20]

    static func make(from inputs: BodyStrengthInputs, calendar: Calendar = .current, locale: Locale = .current) -> BodyStrength {
        let lean = BodyMath.change(inputs.leanMass, now: inputs.now, calendar: calendar)
        let hasWorkouts = !inputs.workouts.isEmpty
        let counts = hasWorkouts
            ? BodyMath.weeklyCounts(inputs.workouts, types: strengthTypes, now: inputs.now, calendar: calendar)
            : []
        let average = hasWorkouts ? BodyMath.averagePerWeek(counts) : nil
        let total = counts.reduce(0, +)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: inputs.now)?.start
        let firstWeek = thisWeek.flatMap { calendar.date(byAdding: .day, value: -7 * (BodyMath.trendWeeks - 1), to: $0) }

        var page = BodyStrength(
            eyebrow: "Last eight weeks",
            headline: "Strength, week by week.",
            reason: "Nothing here yet. Strength workouts from your watch fill the sessions below, and a Soma visit adds grip and lean mass by region.",
            leanMass: BodyMath.format(lean?.latest, decimals: 1, locale: locale),
            leanTrend: BodyMath.trend(lean?.delta, tolerance: 0.1),
            sessionsPerWeek: BodyMath.formatCount(average, locale: locale),
            weeks: counts,
            firstWeek: firstWeek,
            sessionsNote: hasWorkouts
                ? (total == 0 ? "No strength workouts in eight weeks. The next one you log lands here." : "Averaged over the weeks already finished.")
                : "Strength workouts from your watch or another app fill this."
        )

        if let average {
            let each = BodyMath.formatCount(average, locale: locale) ?? ""
            switch average {
            case 2...:
                page.headline = "Strength is part of your week."
                page.reason = "About \(each) strength sessions a week for eight weeks."
            case 0.5..<2:
                page.headline = "Strength comes and goes."
                page.reason = "\(total) strength \(total == 1 ? "session" : "sessions") in eight weeks. Two a week is what holds lean mass."
            case let value where value > 0 || total > 0:
                page.headline = "Strength is just starting."
                page.reason = "\(total) strength \(total == 1 ? "session" : "sessions") in eight weeks. Two a week is what holds lean mass."
            default:
                page.headline = "No strength work yet."
                page.reason = "No strength workouts in eight weeks. Two sessions a week is what holds lean mass."
            }
        }

        if let lean, let delta = lean.delta {
            let amount = BodyMath.format(abs(delta), decimals: 1, locale: locale) ?? ""
            switch BodyMath.trend(delta, tolerance: 0.1) {
            case .up: page.reason += " Lean mass rose \(amount) kg in the same time."
            case .down: page.reason += " Lean mass fell \(amount) kg in the same time."
            case nil: page.reason += " Lean mass held steady."
            }
        }

        return page
    }
}

#if DEBUG
extension BodyStrength {
    static var preview: BodyStrength {
        let now = Date()
        let workouts = (0..<16).map { index in
            let date = now.addingTimeInterval(-Double(index) * 3.4 * 86_400)
            return HealthReading(metric: BodyMetric.workout, value: 50, unit: .none, start: date, end: date.addingTimeInterval(2400))
        }
        return make(from: BodyStrengthInputs(now: now, workouts: workouts))
    }
}
#endif
