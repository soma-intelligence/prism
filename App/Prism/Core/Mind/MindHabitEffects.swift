//
//  MindHabitEffects.swift
//  Prism
//
//  What a person's days do to the next morning's recovery and to that night's
//  sleep. Each habit is measured with `EffectMath` on their own days: the
//  mornings after a day with it against the mornings after a day without.
//

import Foundation

nonisolated enum MindHabitLens: String, CaseIterable, Sendable {
    case recovery, sleep

    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        }
    }

    /// When the outcome is read, relative to the day of the habit.
    var when: String {
        switch self {
        case .recovery: "next morning"
        case .sleep: "that night"
        }
    }
}

struct MindHabitEffects: Equatable, Sendable {
    /// Days with a habit before its effect counts as clear.
    static let clearDays = 8
    /// Under this many points, an effect with enough days is no effect.
    static let noEffectPoints = 2.0

    struct Habit: Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        /// Days it happened with an outcome to compare.
        var days: Int
        /// Points: positive lifts, negative costs. Nil until both sides hold
        /// enough days.
        var delta: Double?
        var isCost: Bool { (delta ?? 0) < 0 }
    }

    var lens: MindHabitLens
    /// Days in the window with an outcome.
    var window: Int
    var clear: [Habit]
    var needsMore: [Habit]
    var none: [Habit]
    var reason: String

    /// - Parameters:
    ///   - habits: each habit's id, title and the days it happened.
    ///   - outcome: the score, keyed by the day of the habit it answers to
    ///     (the day before, for a next morning or a night).
    static func make(
        lens: MindHabitLens,
        habits: [(id: String, title: String, days: Set<Date>)],
        outcome: [Date: Double]
    ) -> MindHabitEffects {
        var clear: [Habit] = []
        var needsMore: [Habit] = []
        var none: [Habit] = []
        for habit in habits {
            let effect = EffectMath.effect(causeDays: habit.days, outcome: outcome, better: .higher)
            guard effect.tries > 0 else { continue }
            let row = Habit(id: habit.id, title: habit.title, days: effect.tries, delta: effect.delta)
            if effect.tries < clearDays || effect.delta == nil {
                needsMore.append(row)
            } else if abs(effect.delta ?? 0) < noEffectPoints {
                none.append(row)
            } else {
                clear.append(row)
            }
        }
        clear.sort { abs($0.delta ?? 0) > abs($1.delta ?? 0) }
        needsMore.sort { $0.days > $1.days }
        none.sort { $0.days > $1.days }

        var sentences: [String] = []
        if let cost = clear.filter(\.isCost).first, let delta = cost.delta {
            sentences.append("\(cost.title) costs you the most: \(points(delta)) \(lens.when).")
        }
        if let lift = clear.filter({ !$0.isCost }).first, let delta = lift.delta {
            sentences.append("\(lift.title) gives back \(points(delta)).")
        }
        let reason: String
        if outcome.isEmpty {
            reason = "Nothing to compare yet. Once Apple Health holds a week of nights, each habit you tag in the Journal is measured here."
        } else if sentences.isEmpty {
            reason = "No clear effect yet. Each habit is measured once it has \(clearDays) days with it and a few without."
        } else {
            reason = sentences.joined(separator: " ") + " Each effect compares days with the habit against days without, over the last \(outcome.count) days."
        }
        return MindHabitEffects(lens: lens, window: outcome.count, clear: clear, needsMore: needsMore, none: none, reason: reason)
    }

    static func points(_ delta: Double) -> String {
        let whole = Int(abs(delta).rounded())
        return whole == 1 ? "1 point" : "\(whole) points"
    }

    /// A daily series ending today, keyed by the day before each value: the
    /// day whose habits the morning answers to.
    static func keyedByDayBefore(_ series: [Double?], today: Date, calendar: Calendar) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for (index, value) in series.enumerated() {
            guard let value,
                  let day = calendar.date(byAdding: .day, value: index - series.count, to: calendar.startOfDay(for: today)) else { continue }
            result[day] = value
        }
        return result
    }
}
