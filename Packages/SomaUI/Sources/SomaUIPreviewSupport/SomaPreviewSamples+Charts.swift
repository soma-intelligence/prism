//
//  SomaPreviewSamples+Charts.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

/// Sample values for the house charts in the gallery: a month of breathing
/// rate and one night in stages.
public extension SomaPreviewSamples {
    /// Breaths a minute over thirty nights, one missing.
    static let breathing: [Double?] = [
        17.3, 17.0, 16.9, 17.2, 16.6, 17.4, 17.8, 18.0, 17.7, 17.4,
        17.1, 17.5, 17.3, nil, 17.0, 17.6, 17.9, 18.2, 17.8, 17.4,
        17.2, 17.0, 17.3, 18.4, 17.6, 17.1, 17.5, 17.8, 17.9, 18.5,
    ]
    /// The usual range for that rate.
    static let breathingBand: ClosedRange<Double> = 17.0...18.2

    /// A kept read and the fresh one after it, for a number rolling
    /// between them: HRV in milliseconds.
    static let rollingValues: [Double] = [58, 64]
    /// When a kept read was taken, old enough for the updated note.
    static var keptReadAt: Date { .now.addingTimeInterval(-3 * 3_600) }

    /// One night, 23:34 to 06:39, in stages: 15 min awake, 1 h 50 REM,
    /// 4 h 16 core and 45 min deep, the awake moments short, as a watch sees them.
    static let night: [SomaStageRun] = {
        let start = Date(timeIntervalSince1970: 1_790_033_640)
        let stretches: [(SomaSleepStage, Double)] = [
            (.awake, 3), (.core, 16), (.deep, 24), (.core, 8), (.deep, 10), (.core, 22), (.rem, 14),
            (.awake, 1), (.rem, 6), (.core, 26), (.awake, 1), (.core, 14), (.rem, 18), (.core, 30),
            (.awake, 2), (.core, 20), (.rem, 16), (.core, 12), (.deep, 11), (.core, 24), (.rem, 14),
            (.awake, 1), (.rem, 6), (.core, 28), (.awake, 2), (.rem, 22), (.core, 18), (.awake, 1),
            (.core, 16), (.rem, 14), (.awake, 2), (.core, 22), (.awake, 1),
        ]
        var at = start
        return stretches.map { stage, minutes in
            defer { at = at.addingTimeInterval(minutes * 60) }
            return SomaStageRun(stage: stage, start: at, end: at.addingTimeInterval(minutes * 60))
        }
    }()

    /// Seconds in each stage of that night.
    static let nightStages: [SomaSleepStage: TimeInterval] = night.reduce(into: [:]) { totals, run in
        totals[run.stage, default: 0] += run.end.timeIntervalSince(run.start)
    }

    /// That night graded part by part.
    static let nightGrades: [SomaSleepFactorGrade] = [
        SomaSleepFactorGrade(factor: .timeAsleep, grade: .good, progress: 0.78),
        SomaSleepFactorGrade(factor: .heartRateDip, grade: .poor, progress: 0.1),
        SomaSleepFactorGrade(factor: .rem, grade: .excellent, progress: 1),
        SomaSleepFactorGrade(factor: .deep, grade: .fair, progress: 0.46),
        SomaSleepFactorGrade(factor: .efficiency, grade: .excellent, progress: 0.94),
        SomaSleepFactorGrade(factor: .continuity, grade: .fair, progress: 0.6),
    ]
}
