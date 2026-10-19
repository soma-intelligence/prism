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
}
