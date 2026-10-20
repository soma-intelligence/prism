//
//  MuscleFreshness.swift
//  Prism
//

import Foundation
import SomaUI

/// How rested each muscle is, from the last month of sessions: recovered,
/// fatigued or depleted.
///
/// Each session's work points (``MuscleWork``) on a group fade with a half life
/// of a day and a half. What is left now is set against the group's usual day
/// over the month: more than twice a usual day still in the muscle reads as
/// depleted, more than half of one as fatigued, anything less as recovered. A
/// group the month never worked has no state.
nonisolated enum MuscleFreshness {
    typealias Group = FitnessActivities.MuscleGroup

    static let halfLife: TimeInterval = 36 * 3600
    static let days = 30.0

    static func states(_ workouts: [FitnessWorkout], now: Date) -> [Group: SomaMuscleState] {
        var month: [Group: Double] = [:]
        var lingering: [Group: Double] = [:]
        for workout in workouts where workout.end <= now {
            let work = MuscleWork(workouts: [workout])
            let age = now.timeIntervalSince(workout.end)
            let left = pow(0.5, age / halfLife)
            for (group, points) in work.points {
                month[group, default: 0] += points
                lingering[group, default: 0] += points * left
            }
        }
        var result: [Group: SomaMuscleState] = [:]
        for group in Group.allCases {
            guard let total = month[group], total > 0 else { continue }
            let usualDay = total / days
            let ratio = (lingering[group] ?? 0) / usualDay
            result[group] = ratio > 2 ? .depleted : ratio > 0.5 ? .fatigued : .recovered
        }
        return result
    }

    /// Each group as the freshness card reads it: its state, the end of the
    /// last session that worked it, and when it should read rested again
    /// (the moment what is left in it falls under half a usual day).
    static func readings(_ workouts: [FitnessWorkout], now: Date) -> [SomaMuscleReading] {
        var month: [Group: Double] = [:]
        var lingering: [Group: Double] = [:]
        var last: [Group: Date] = [:]
        for workout in workouts where workout.end <= now {
            let work = MuscleWork(workouts: [workout])
            let left = pow(0.5, now.timeIntervalSince(workout.end) / halfLife)
            for (group, points) in work.points where points > 0 {
                month[group, default: 0] += points
                lingering[group, default: 0] += points * left
                last[group] = max(last[group] ?? workout.end, workout.end)
            }
        }
        return Group.allCases.map { group in
            let target = somaGroup(group)
            guard let total = month[group], total > 0 else { return SomaMuscleReading(group: target, state: .none) }
            let ratio = (lingering[group] ?? 0) / (total / days)
            let state: SomaMuscleState = ratio > 2 ? .depleted : ratio > 0.5 ? .fatigued : .recovered
            let freshAt = ratio > 0.5 ? now.addingTimeInterval(halfLife * log2(ratio / 0.5)) : nil
            return SomaMuscleReading(group: target, state: state, lastWorked: last[group], freshAt: freshAt)
        }
    }

    /// The design system's name for a group.
    static func somaGroup(_ group: Group) -> SomaMuscleGroup {
        switch group {
        case .legs: .legs
        case .core: .core
        case .back: .back
        case .arms: .arms
        case .shoulders: .shoulders
        case .chest: .chest
        }
    }

    /// Which group a drawn muscle belongs to.
    static func group(of muscle: SomaMuscle) -> Group {
        switch muscle {
        case .chest: .chest
        case .shoulders: .shoulders
        case .biceps, .triceps, .forearms: .arms
        case .abs, .obliques, .lowerBack: .core
        case .traps, .lats: .back
        case .glutes, .quads, .adductors, .hamstrings, .calves: .legs
        }
    }

    /// The map's input: every drawn muscle with its group's state.
    static func map(_ groups: [Group: SomaMuscleState]) -> [SomaMuscle: SomaMuscleState] {
        Dictionary(uniqueKeysWithValues: SomaMuscle.allCases.map { ($0, groups[group(of: $0)] ?? .none) })
    }
}

#if DEBUG
extension MuscleFreshness {
    /// The freshness card under `-pulse.preview YES`: a leg day this
    /// morning, arms yesterday, the rest of the upper body rested, and no
    /// back session in the month.
    static var preview: [SomaMuscleReading] {
        let now = Date()
        return [
            SomaMuscleReading(group: .chest, state: .recovered, lastWorked: now.addingTimeInterval(-4 * 86_400)),
            SomaMuscleReading(group: .shoulders, state: .recovered, lastWorked: now.addingTimeInterval(-4 * 86_400)),
            SomaMuscleReading(group: .arms, state: .fatigued, lastWorked: now.addingTimeInterval(-30 * 3_600),
                              freshAt: now.addingTimeInterval(14 * 3_600)),
            SomaMuscleReading(group: .core, state: .recovered, lastWorked: now.addingTimeInterval(-3 * 86_400)),
            SomaMuscleReading(group: .back, state: .none),
            SomaMuscleReading(group: .legs, state: .depleted, lastWorked: now.addingTimeInterval(-5 * 3_600),
                              freshAt: now.addingTimeInterval(52 * 3_600)),
        ]
    }
}
#endif
