//
//  ToolsCaffeineModel.swift
//  Prism
//
//  Caffeine pharmacokinetics.
//

import Foundation

extension SomaTools {

    /// Caffeine pharmacokinetics, Layer 1: a first-order elimination residual and a
    /// recommended cutoff. This is a PK proxy, not the validated UMP/2B-Alert
    /// pharmacodynamic model. Half-life 5 h (Drake 2013; range 1.5 to 9.5 h
    /// population).
    nonisolated enum CaffeineModel {

        static let halfLifeHours = 5.0

        /// What may still be on board at bedtime.
        ///
        /// 25 mg, not 50 mg. 50 mg is a quarter of a strong coffee still
        /// circulating at lights-out, and it put the cutoff only 5 h before bed
        /// for a standard cup, later than any published recommendation.
        /// Gardiner 2023 (meta-analysis of caffeine and sleep) lands on ~8.8 h
        /// before bed for a standard coffee; 25 mg puts a 100 mg cup at 10 h,
        /// which is that recommendation with the model's own arithmetic rather
        /// than a second hard-coded number.
        static let bedtimeThresholdMg = 25.0

        /// The cup assumed when nothing has been logged: a standard brewed
        /// coffee. Used by the cutoff fallback so an unknown dose still goes
        /// through the SAME formula as a known one.
        static let standardServingMg = 100.0

        /// A whole day's common health guidance, for scaling a day-long curve
        /// and nothing else. EFSA and the FDA both point to about 400 mg/day as
        /// the amount that is not a safety concern for a healthy, non-pregnant
        /// adult. That is what this number IS: a population-level daily-intake
        /// guideline, borrowed here only to give a chart with no natural top a
        /// top that means something. It is NOT a personal limit, NOT a medical
        /// threshold (this app makes no clinical claim), and NOT
        /// `bedtimeThresholdMg` under a different name: that constant answers
        /// "may I still have this in me at bedtime", a deliberately small
        /// residual, while this one answers "how much of a whole day's common
        /// guidance is this". Four `standardServingMg` cups sum to exactly this
        /// ceiling, so one cup reads as a quarter of the day on any curve
        /// plotted against it.
        static let dailyGuidanceCeilingMg = 400.0

        nonisolated struct Dose: Sendable, Equatable {
            var mg: Double
            var time: Date
        }

        /// Residual caffeine (mg) at `time` from past doses (future doses ignored).
        static func residual(doses: [Dose], at time: Date) -> Double {
            let ke = log(2) / halfLifeHours
            return doses.reduce(0) { acc, dose in
                let hours = time.timeIntervalSince(dose.time) / 3600
                guard hours >= 0 else { return acc }
                return acc + dose.mg * exp(-ke * hours)
            }
        }

        /// Recommended last-caffeine clock hour to keep the residual under the
        /// threshold at bedtime: bedtime minus halfLife * log2(dose / threshold).
        ///
        /// An unknown dose falls back to `standardServingMg` through the same
        /// formula (10 h ahead of bed), NOT to a separate hard-coded lead: a
        /// second number there is how "we do not know what you drink" ends up
        /// more permissive than "you drink a standard coffee". A dose at or
        /// under the threshold needs no cutoff at all and returns bedtime.
        static func recommendedCutoffHour(bedtimeHour: Double, typicalDoseMg: Double?) -> Double {
            let dose = typicalDoseMg ?? standardServingMg
            guard dose > bedtimeThresholdMg else { return CircadianMath.wrap24(bedtimeHour) }
            let lead = halfLifeHours * log2(dose / bedtimeThresholdMg)
            return CircadianMath.wrap24(bedtimeHour - lead)
        }
    }
}
