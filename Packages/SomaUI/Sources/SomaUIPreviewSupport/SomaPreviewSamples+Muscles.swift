//
//  SomaPreviewSamples+Muscles.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

/// Sample freshness for the muscle map in the gallery: an upper body day,
/// a leg day on top of it, and grip left empty for want of a session.
public extension SomaPreviewSamples {
    static let muscleStates: [SomaMuscle: SomaMuscleState] = [
        .chest: .recovered, .shoulders: .recovered, .abs: .recovered, .lats: .recovered,
        .biceps: .recovered, .triceps: .recovered, .traps: .recovered, .obliques: .recovered,
        .quads: .fatigued, .hamstrings: .fatigued, .calves: .fatigued, .adductors: .fatigued,
        .glutes: .depleted,
    ]

    /// The six groups as the freshness card reads them: a leg day this
    /// morning, arms yesterday, the rest of the upper body rested, and no
    /// back session in the month.
    static var muscleReadings: [SomaMuscleReading] {
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
