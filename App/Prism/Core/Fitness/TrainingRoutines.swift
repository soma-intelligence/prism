//
//  TrainingRoutines.swift
//  Prism
//

import Foundation

/// The starter routines the training menu offers, and what each holds.
///
/// Content, not a person's data: a routine is a written plan, the same for
/// everyone, like a page of a training book. There is no exercise catalog or
/// routine editor yet, so it ships two common split days, named with plain
/// exercise names. No load is prescribed, because a weight is
/// personal and nothing here knows yours.
nonisolated enum TrainingRoutines {
    struct Exercise: Equatable, Sendable, Identifiable {
        var name: String
        var prescription: String
        var target: String
        var id: String { name }
    }

    struct Routine: Equatable, Sendable, Identifiable, Hashable {
        var id: String
        var name: String
        var summary: String
        /// The muscle groups the routine is written for.
        var groups: [FitnessActivities.MuscleGroup]
        var minutes: Int

        var exercises: [Exercise] { TrainingRoutines.exercises[id] ?? [] }
        /// Working sets, the warm-up left out.
        var sets: Int {
            exercises.filter { $0.target != "Easy" }.compactMap { Int($0.prescription.prefix { $0.isNumber }) }.reduce(0, +)
        }
        var exerciseCount: Int { exercises.filter { $0.target != "Easy" }.count }

        static func == (lhs: Routine, rhs: Routine) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    static let upperBody = Routine(
        id: "upper",
        name: "Upper body",
        summary: "Chest, back, shoulders and arms",
        groups: [.chest, .back, .shoulders, .arms],
        minutes: 40
    )

    static let lowerBody = Routine(
        id: "lower",
        name: "Lower body",
        summary: "Legs and the core that holds them",
        groups: [.legs, .core],
        minutes: 45
    )

    static let all = [upperBody, lowerBody]

    static func routine(_ id: String) -> Routine? { all.first { $0.id == id } }

    private static let exercises: [String: [Exercise]] = [
        "upper": [
            Exercise(name: "Warm-up", prescription: "5 minutes on the rower", target: "Easy"),
            Exercise(name: "Dumbbell bench press", prescription: "3 sets of 10", target: "Chest"),
            Exercise(name: "One arm row", prescription: "3 sets of 10, each side", target: "Back"),
            Exercise(name: "Overhead press", prescription: "3 sets of 8", target: "Shoulders"),
            Exercise(name: "Curl and triceps extension", prescription: "3 supersets of 12", target: "Arms"),
            Exercise(name: "Farmer carry", prescription: "2 carries of 40 m", target: "Grip"),
        ],
        "lower": [
            Exercise(name: "Warm-up", prescription: "5 minutes on the bike", target: "Easy"),
            Exercise(name: "Goblet squat", prescription: "3 sets of 10", target: "Legs"),
            Exercise(name: "Romanian deadlift", prescription: "3 sets of 8", target: "Legs"),
            Exercise(name: "Reverse lunge", prescription: "3 sets of 8, each side", target: "Legs"),
            Exercise(name: "Calf raise", prescription: "3 sets of 15", target: "Legs"),
            Exercise(name: "Dead bug", prescription: "3 sets of 10", target: "Core"),
        ],
    ]

    /// The routine whose groups got the least of the month's work, and that
    /// share. Nil when there is no work to compare.
    static func leastWorked(_ work: MuscleWork) -> (routine: Routine, share: Double)? {
        let shares = all.compactMap { routine -> (Routine, Double)? in
            let values = routine.groups.compactMap { work.share($0) }
            guard !values.isEmpty else { return nil }
            return (routine, values.reduce(0, +))
        }
        return shares.min { $0.1 < $1.1 }.map { (routine: $0.0, share: $0.1) }
    }

    /// Ways to start without a routine, as the menu lists them.
    struct Start: Equatable, Sendable, Identifiable {
        var id: String { title }
        var title: String
        var detail: String
        var symbol: String
    }

    static let starts = [
        Start(title: "Run", detail: "Outdoors, with your heart rate zones", symbol: "figure.run"),
        Start(title: "Walk", detail: "Counts toward steps and zone 2", symbol: "figure.walk"),
        Start(title: "Yoga and mobility", detail: "Slow work that recovery likes", symbol: "figure.yoga"),
        Start(title: "Empty session", detail: "Add exercises as you go", symbol: "plus"),
    ]
}
