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
