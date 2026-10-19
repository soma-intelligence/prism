//
//  ToolsChronotypeEstimator.swift
//  Prism
//
//  Behavioral chronotype from sleep timing.
//

import Foundation

extension SomaTools {

    /// Behavioral chronotype from sleep timing (Roenneberg MCTQ: MSFsc and social
    /// jetlag), plus an rMEQ-category-to-CBTmin seed. Pure and testable: callers
    /// pass per-night bed/wake clock hours and a weekend (free-day) flag.
    nonisolated enum ChronotypeEstimator {

        /// One night, attributed to its wake day. `bedHour` is a decimal clock hour
        /// that may exceed 24 for after-midnight onsets (a 01:00 onset is stored
        /// as 25).
        nonisolated struct Night: Sendable, Equatable {
            var bedHour: Double
            var wakeHour: Double
            var isFreeDay: Bool
        }

        /// Minimum free-day nights needed to compute MSF (and thus MSFsc).
        static let minFreeNights = 2

        /// Sleep duration in hours for one night.
        static func sleepDuration(bedHour: Double, wakeHour: Double) -> Double {
            let onset = bedHour >= 24 ? bedHour - 24 : bedHour
            var dur = wakeHour - onset
            if dur < 0 { dur += 24 }
            return dur
        }

        /// Mid-sleep clock hour for one night, in [0, 24).
        static func midSleepHour(bedHour: Double, wakeHour: Double) -> Double {
            let onset = bedHour >= 24 ? bedHour - 24 : bedHour
            let dur = sleepDuration(bedHour: bedHour, wakeHour: wakeHour)
            return CircadianMath.wrap24(onset + dur / 2)
        }

        /// Behavioral chronotype, or nil when there are too few free-day nights.
        static func estimate(_ nights: [Night]) -> Chronotype? {
            // Keep physiologically plausible nights only (2 to 16 h).
            let valid = nights.filter {
                let d = sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour)
                return d >= 2 && d <= 16
            }
            let free = valid.filter { $0.isFreeDay }
            let work = valid.filter { !$0.isFreeDay }
            guard free.count >= minFreeNights else { return nil }

            let freeMids = free.map { midSleepHour(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
            guard let msf = CircadianMath.circularMeanHours(freeMids) else { return nil }

            let sdF = free
                .map { sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
                .reduce(0, +) / Double(free.count)
            let sdWeek = valid
                .map { sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
                .reduce(0, +) / Double(valid.count)

            // Sleep-debt correction: only when free-day sleep exceeds the weekly mean.
            let msfSc = sdF <= sdWeek ? msf : CircadianMath.wrap24(msf - (sdF - sdWeek) / 2)

            // Social jetlag uses work-day mid-sleep; nil when no work nights recorded.
            var sjl: Double? = nil
            if !work.isEmpty {
                let workMids = work.map { midSleepHour(bedHour: $0.bedHour, wakeHour: $0.wakeHour) }
                if let msw = CircadianMath.circularMeanHours(workMids) {
                    sjl = CircadianMath.circularDistanceHours(msf, msw)
                }
            }

            return Chronotype(category: category(forMSFsc: msfSc),
                              msfScHours: msfSc,
                              socialJetlagHours: sjl,
                              source: .behavioral)
        }

        /// Clock hour the intermediate band is centred on, and its half-width. The
        /// pair reproduces a 3.5 to 5.5 band exactly, expressed as an anchor plus
        /// a tolerance so it can be compared circularly.
        static let intermediateAnchorHours = 4.5
        static let intermediateHalfWidthHours = 1.0

        /// Approximate behavioral category from MSFsc clock hour.
        ///
        /// Compared as a SIGNED CIRCULAR distance to the anchor, not with `<` and
        /// `>` on the raw hour. MSFsc is wrapped into [0, 24), so a linear
        /// comparison mislabels everyone whose mid-sleep falls before midnight: a
        /// 20:00 to 03:00 sleeper has MSFsc 23.5, which is neither `< 3.5` nor
        /// outside `5.5...`, so the linear form returned `.evening` for one of the
        /// most extreme morning types there is. Circularly, 23.5 sits five hours
        /// BEFORE the anchor, which is what it actually is.
        static func category(forMSFsc msfSc: Double) -> ChronotypeCategory {
            let delta = CircadianMath.signedDeltaHours(from: intermediateAnchorHours, to: msfSc)
            if delta < -intermediateHalfWidthHours { return .morning }
            if delta > intermediateHalfWidthHours { return .evening }
            return .intermediate
        }

        /// Coarse CBTmin clock-hour seed from an rMEQ category, used before enough
        /// sleep is logged. CBTmin sits a few hours before habitual wake; morning
        /// types earlier, evening types later.
        static func seedCBTminHours(for category: ChronotypeCategory) -> Double {
            switch category {
            case .morning: return 3.5
            case .intermediate: return 4.5
            case .evening: return 5.5
            }
        }
    }
}
