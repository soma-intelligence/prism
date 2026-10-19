//
//  ToolsCircadianAlignment.swift
//  Prism
//
//  The 0 to 100 circadian alignment score.
//

import Foundation

extension SomaTools {

    /// A 0 to 100 circadian alignment score built from three factors of the user's
    /// recent nights: how regular their sleep timing is, how close their duration
    /// is to their need, and how well their body clock lines up with their schedule.
    /// Weights renormalise over whichever factors are available, so a missing
    /// factor dilutes the score rather than zeroing it.
    nonisolated struct CircadianAlignment: Sendable, Equatable {

        /// One scored factor plus the raw hours it was scored from.
        nonisolated struct Factor: Sendable, Equatable {
            var score: Int      // 0 to 100
            var rawValue: Double // hours (SD, mean duration, or social jetlag)
        }

        var score: Int
        var regularity: Factor?
        var duration: Factor?
        var timing: Factor?
        var confidence: CircadianConfidence

        static let regularityWeight = 40.0
        static let durationWeight = 30.0
        static let timingWeight = 30.0

        /// Behavioral becomes medium-confidence at this many nights. This is
        /// applied to the plausible-duration nights (`valid`, filtered to 2 to 16
        /// hours), so the count it compares against can differ from
        /// CircadianPhaseProvider.mediumConfidenceNights, which compares against
        /// the unfiltered nights.
        static let mediumConfidenceNights = 14

        /// Resolve the score, or nil when there is nothing to score (under three
        /// nights and no timing signal either).
        static func resolve(nights: [ChronotypeEstimator.Night],
                            phase: CircadianPhase?,
                            sleepNeedHours: Double) -> CircadianAlignment? {
            let valid = nights.filter {
                let d = ChronotypeEstimator.sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour)
                return d >= 2 && d <= 16
            }

            let regularity = regularityFactor(valid)
            let duration = durationFactor(valid, needHours: sleepNeedHours)
            let timing = timingFactor(phase, nights: valid)

            var weighted = 0.0, totalWeight = 0.0
            if let r = regularity { weighted += Double(r.score) * regularityWeight; totalWeight += regularityWeight }
            if let d = duration { weighted += Double(d.score) * durationWeight; totalWeight += durationWeight }
            if let t = timing { weighted += Double(t.score) * timingWeight; totalWeight += timingWeight }
            guard totalWeight > 0 else { return nil }

            let score = Int((weighted / totalWeight).rounded())
            let confidence: CircadianConfidence = valid.count >= mediumConfidenceNights ? .medium
                : (regularity != nil || duration != nil) ? .low
                : phase?.confidence ?? .low
            return CircadianAlignment(score: min(100, max(0, score)),
                                      regularity: regularity, duration: duration,
                                      timing: timing, confidence: confidence)
        }

        /// Regularity from the circular SD of mid-sleep: 0h gives 100, 2h or more
        /// gives 0. nil under three nights.
        static func regularityFactor(_ nights: [ChronotypeEstimator.Night]) -> Factor? {
            guard nights.count >= 3 else { return nil }
            let mids = nights.map { ChronotypeEstimator.midSleepHour(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
            guard let sd = CircadianMath.circularStdDevHours(mids) else { return nil }
            let score = Int((100 * (1 - min(1, sd / 2))).rounded())
            return Factor(score: min(100, max(0, score)), rawValue: sd)
        }

        /// Duration from mean sleep vs need: full marks within 0.5h, 0 at a 2.5h
        /// deficit, oversleep penalised at half the rate. nil under three nights.
        static func durationFactor(_ nights: [ChronotypeEstimator.Night], needHours: Double) -> Factor? {
            guard nights.count >= 3 else { return nil }
            let mean = nights.map { ChronotypeEstimator.sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
                .reduce(0, +) / Double(nights.count)
            let delta = mean - needHours
            // Tolerance band of 0.5h at full marks; deficits reach 0 at -2.5h,
            // surplus is gentler (0 at +4.5h).
            let penalty: Double
            if delta < -0.5 {
                penalty = (abs(delta) - 0.5) / 2.0
            } else if delta > 0.5 {
                penalty = (delta - 0.5) / 4.0
            } else {
                penalty = 0
            }
            let score = Int((100 * (1 - min(1, penalty))).rounded())
            return Factor(score: min(100, max(0, score)), rawValue: mean)
        }

        /// Timing from social jetlag (0h gives 100, 4h or more gives 0), or nil
        /// when social jetlag is unknown.
        ///
        /// There is deliberately NO fallback. An earlier one compared the mean
        /// mid-sleep against MSFsc, which looks like an independent check but is
        /// not: social jetlag is only missing when there are no work nights, and in
        /// that case MSFsc is the circular mean of the free nights while the
        /// comparison mean is the circular mean of all nights, which are then the
        /// same nights. The distance was therefore exactly zero and the factor
        /// scored 100 out of 100 by construction, for any data at all. A factor that
        /// cannot fail is not a measurement; the score renormalises over the
        /// remaining factors instead.
        ///
        /// `nights` is kept in the signature so every factor reads the same way at
        /// the call site.
        static func timingFactor(_ phase: CircadianPhase?,
                                 nights: [ChronotypeEstimator.Night]) -> Factor? {
            guard let phase else { return nil }
            guard let sjl = phase.chronotype.socialJetlagHours else { return nil }
            let score = Int((100 * (1 - min(1, sjl / 4))).rounded())
            return Factor(score: min(100, max(0, score)), rawValue: sjl)
        }
    }
}
