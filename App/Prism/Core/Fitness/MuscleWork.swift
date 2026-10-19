//
//  MuscleWork.swift
//  Prism
//

import Foundation

/// Which muscle groups a month of sessions loaded, and how much.
///
/// The currency is the work point: one
/// point is one minute of moderate aerobic effort (zone 2). Heart rate zones
/// weigh a session whenever the watch recorded any; without them the
/// activity's MET stands in. Each session's points are then split across the
/// groups by the activity's shares (``FitnessActivities``). A session could also be
/// split by the exercises logged in it; there is no exercise log yet, so
/// every session takes its activity's generic split.
nonisolated struct MuscleWork: Equatable, Sendable {
    typealias Group = FitnessActivities.MuscleGroup

    /// Weight of one second in each zone, relative to zone 2.
    static let zoneWeights: [Double] = [0.6, 1.0, 1.4, 1.8, 2.2]
    /// Time under half the highest heart rate still counts, but least.
    static let calmWeight = 0.35
    /// The MET that maps to a weight of 1.
    static let referenceMET = 6.0
    /// The MET used when the catalog carries none.
    static let defaultMET = 5.0

    var points: [Group: Double] = [:]
    var sessions: [Group: Int] = [:]
    /// Sessions whose type carries no split, so they count toward nothing.
    var unattributed = 0
    var totalSessions = 0

    var totalPoints: Double { points.values.reduce(0, +) }

    /// A group's share of all the work, 0 to 1. Nil with no work at all.
    func share(_ group: Group) -> Double? {
        let total = totalPoints
        guard total > 0 else { return nil }
        return (points[group] ?? 0) / total
    }

    /// The groups, most worked first.
    var ranked: [Group] {
        Group.allCases.sorted { (points[$0] ?? 0) > (points[$1] ?? 0) }
    }

    /// Work points for one session.
    static func points(zoneSeconds: [Double], calmSeconds: Double, duration: TimeInterval, met: Double?) -> Double {
        guard duration > 0 else { return 0 }
        var weighted = max(0, calmSeconds) * calmWeight
        for (index, seconds) in zoneSeconds.prefix(zoneWeights.count).enumerated() {
            weighted += max(0, seconds) * zoneWeights[index]
        }
        if weighted > 0 { return weighted / 60 }
        let intensity = min(max((met ?? defaultMET) / referenceMET, calmWeight), zoneWeights[zoneWeights.count - 1])
        return duration / 60 * intensity
    }

    init() {}

    /// Muscle work over the workouts.
    init(workouts: [FitnessWorkout]) {
        for workout in workouts {
            let activity = FitnessActivities.activity(workout.activity)
            guard !activity.shares.isEmpty else {
                unattributed += 1
                continue
            }
            let value = Self.points(
                zoneSeconds: workout.zoneSeconds,
                calmSeconds: workout.calmSeconds,
                duration: workout.duration,
                met: activity.met
            )
            guard value > 0 else { continue }
            totalSessions += 1
            for (group, share) in activity.shares where share > 0 {
                points[group, default: 0] += value * share
                sessions[group, default: 0] += 1
            }
        }
    }

    /// The four regions a body figure is drawn in: the trunk carries chest,
    /// back, core and shoulders.
    enum Region: String, CaseIterable, Sendable {
        case arms = "Arms", trunk = "Trunk", legs = "Legs"
    }

    func share(_ region: Region) -> Double? {
        guard totalPoints > 0 else { return nil }
        let groups: [Group] = switch region {
        case .arms: [.arms]
        case .legs: [.legs]
        case .trunk: [.chest, .back, .core, .shoulders]
        }
        return groups.compactMap { share($0) }.reduce(0, +)
    }
}
