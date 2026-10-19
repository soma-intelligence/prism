//
//  ToolsCircadianPhaseProvider.swift
//  Prism
//
//  The user's estimated circadian phase.
//

import Foundation

extension SomaTools {

    /// How much to trust the phase estimate. Tightens as more regular sleep is
    /// logged. `.high` is reserved for a later light-driven (Kronauer) refinement.
    nonisolated enum CircadianConfidence: String, Codable, Sendable {
        case seeded   // rMEQ questionnaire only
        case low      // some sleep data, under two weeks
        case medium   // two-plus weeks of regular sleep
        case high     // reserved (light-driven refinement)
    }

    /// The user's estimated circadian phase. Markers are clock hours in [0, 24).
    /// DLMO is CBTmin minus 7 h, an empirical lab mapping, presented as a window.
    nonisolated struct CircadianPhase: Codable, Sendable, Equatable {
        var cbtMinHours: Double
        var dlmoHours: Double
        var chronotype: Chronotype
        var confidence: CircadianConfidence
    }

    /// The single source of truth for the user's circadian phase. Resolves the
    /// best available estimate: behavioral (MSFsc) when enough sleep is logged,
    /// else the rMEQ seed, else nil (honest empty).
    nonisolated enum CircadianPhaseProvider {

        /// Behavioral becomes medium-confidence at this many nights.
        static let mediumConfidenceNights = 14

        /// CBTmin to DLMO offset (empirical lab mapping, not a model constant).
        static let dlmoOffsetHours = 7.0

        static func resolve(rMEQ: RMEQAnswers?,
                            nights: [ChronotypeEstimator.Night],
                            now: Date) -> CircadianPhase? {
            if let chrono = ChronotypeEstimator.estimate(nights), let cbt = chrono.msfScHours {
                let confidence: CircadianConfidence =
                    nights.count >= mediumConfidenceNights ? .medium : .low
                return CircadianPhase(cbtMinHours: cbt,
                                      dlmoHours: CircadianMath.wrap24(cbt - dlmoOffsetHours),
                                      chronotype: chrono,
                                      confidence: confidence)
            }
            if let rMEQ, rMEQ.isComplete {
                let cbt = ChronotypeEstimator.seedCBTminHours(for: rMEQ.category)
                let chrono = Chronotype(category: rMEQ.category,
                                        msfScHours: nil,
                                        socialJetlagHours: nil,
                                        source: .rMEQ)
                return CircadianPhase(cbtMinHours: cbt,
                                      dlmoHours: CircadianMath.wrap24(cbt - dlmoOffsetHours),
                                      chronotype: chrono,
                                      confidence: .seeded)
            }
            return nil
        }
    }
}
