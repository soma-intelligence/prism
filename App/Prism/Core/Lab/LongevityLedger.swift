//
//  LongevityLedger.swift
//  Prism
//
//  The Longevity Ledger: each day earns or spends
//  minutes of life expectancy from five factors, steps, exercise, sleep,
//  alcohol and late caffeine, on coefficients taken from the published
//  dose response curves.
//
//  Steps, exercise and sleep come from Health. Alcohol and late caffeine
//  come from the Journal's tags, which record that a thing happened and not
//  how much: a tagged day counts one drink (free, since the model only
//  charges from the second) and one cup of about 100 mg.
//

import Foundation

nonisolated enum LongevityLedger {
    struct Coefficients: Sendable, Equatable {
        var minutesPer1kSteps = 1.0
        var stepPlateau = 10_000.0
        var minutesPerExerciseMinute = 0.3
        var sleepInWindowMinutes = 2.0
        var sleepOutOfWindowMinutes = -3.0
        var healthySleepLowHours = 7.0
        var healthySleepHighHours = 9.0
        var shortSleepHours = 6.0
        var minutesPerExtraDrink = -5.0
        var minutesPer100mgLateCaffeine = -2.0

        static let standard = Coefficients()
    }

    /// One day's inputs. Nil means not measured, which counts nothing.
    struct Day: Sendable, Equatable {
        var date: Date
        var steps: Double?
        var exerciseMinutes: Double?
        var sleepHours: Double?
        var drinks: Double?
        var lateCaffeineMg: Double?
    }

    enum Factor: String, CaseIterable, Sendable, Identifiable {
        case steps, exercise, sleep, alcohol, caffeine

        var id: String { rawValue }

        var title: String {
            switch self {
            case .steps: "Steps"
            case .exercise: "Exercise"
            case .sleep: "Sleep"
            case .alcohol: "Alcohol"
            case .caffeine: "Late caffeine"
            }
        }
    }

    struct Breakdown: Sendable, Equatable {
        /// Minutes per factor; nil when the factor was not measured that day.
        var minutes: [Factor: Double]

        var earned: Double { minutes.values.filter { $0 > 0 }.reduce(0, +) }
        var spent: Double { minutes.values.filter { $0 < 0 }.reduce(0, +) }
        var net: Double { minutes.values.reduce(0, +) }
        var isEmpty: Bool { minutes.isEmpty }
    }

    static func stepMinutes(_ steps: Double, _ c: Coefficients = .standard) -> Double {
        min(max(0, steps), c.stepPlateau) / 1_000 * c.minutesPer1kSteps
    }

    static func exerciseMinutes(_ minutes: Double, _ c: Coefficients = .standard) -> Double {
        max(0, minutes) * c.minutesPerExerciseMinute
    }

    static func sleepMinutes(_ hours: Double, _ c: Coefficients = .standard) -> Double {
        guard hours > 0 else { return 0 }
        if hours >= c.healthySleepLowHours && hours <= c.healthySleepHighHours { return c.sleepInWindowMinutes }
        if hours < c.shortSleepHours || hours > c.healthySleepHighHours { return c.sleepOutOfWindowMinutes }
        return 0
    }

    static func alcoholMinutes(_ drinks: Double, _ c: Coefficients = .standard) -> Double {
        max(0, drinks - 1) * c.minutesPerExtraDrink
    }

    static func caffeineMinutes(_ mg: Double, _ c: Coefficients = .standard) -> Double {
        max(0, mg) / 100 * c.minutesPer100mgLateCaffeine
    }

    static func breakdown(_ day: Day, _ c: Coefficients = .standard) -> Breakdown {
        var minutes: [Factor: Double] = [:]
        if let steps = day.steps, steps > 0 { minutes[.steps] = stepMinutes(steps, c) }
        if let exercise = day.exerciseMinutes, exercise > 0 { minutes[.exercise] = exerciseMinutes(exercise, c) }
        if let sleep = day.sleepHours, sleep > 0 { minutes[.sleep] = sleepMinutes(sleep, c) }
        if let drinks = day.drinks { minutes[.alcohol] = alcoholMinutes(drinks, c) }
        if let caffeine = day.lateCaffeineMg { minutes[.caffeine] = caffeineMinutes(caffeine, c) }
        return Breakdown(minutes: minutes)
    }

    /// The Journal's tags for a day, read as amounts.
    static let journalAlcoholTag = "alcohol"
    static let journalCaffeineTag = "coffee-late"
    static let cupMilligrams = 100.0

    /// Days from Health's daily series (oldest first, last is today) and the
    /// Journal's tags.
    static func days(from daily: LabDaily, tags: (Date) -> Set<String>, now: Date, calendar: Calendar) -> [Day] {
        let count = max(daily.steps.count, daily.sleepHours.count, daily.exerciseMinutes.count)
        let today = calendar.startOfDay(for: now)
        return (0..<count).map { index in
            let offset = index - (count - 1)
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let dayTags = tags(date)
            func at(_ series: [Double?]) -> Double? {
                let i = series.count - count + index
                return series.indices.contains(i) ? series[i] : nil
            }
            return Day(
                date: date,
                steps: at(daily.steps),
                exerciseMinutes: at(daily.exerciseMinutes),
                sleepHours: at(daily.sleepHours),
                drinks: dayTags.contains(journalAlcoholTag) ? 1 : nil,
                lateCaffeineMg: dayTags.contains(journalCaffeineTag) ? cupMilligrams : nil
            )
        }
    }
}
