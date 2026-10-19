//
//  ToolsSleepForecastEngine.swift
//  Prism
//
//  Pure forecast of tonight's sleep from a compact evening feature vector,
//  plus a morning reconciliation of that prediction against the night that
//  was actually recorded. No I/O, no HealthKit, no live state: every value
//  comes in through `Inputs`, so the math is verifiable on fixtures.
//
//  This is a transparent, documented heuristic blend, NOT a learned model.
//  The weights are fixed and physiologically motivated (caffeine PK, sleep
//  debt, circadian regularity, autonomic recovery), each capped so no single
//  term can dominate the score.
//
//  Also holds the pure history helpers the forecast page used to carry
//  (causal windows, stage shares, the recent mean anchor), the score band and
//  the evening rail "still ahead tonight" test.
//

import Foundation

extension SomaTools {

    nonisolated enum SleepForecastEngine {

        private typealias Stats = SleepSupport

        // MARK: - Inputs

        /// One evening's feature vector.
        nonisolated struct Inputs: Sendable, Equatable {
            /// Personalized sleep target (hours).
            var sleepNeedHours: Double
            /// Recent mean sleep score (0-100). Anchors the score forecast.
            /// Zero or negative means "no history": the engine falls back to a
            /// neutral anchor rather than predicting from nothing.
            var baselineScore: Double
            /// Caffeine logged today, the day's total in mg. Zero when nothing
            /// was logged.
            var caffeineMg: Double
            /// Shortfall of the most recent recorded night
            /// (need minus asleep, floored at zero). Zero when unknown.
            var priorNightDebtHours: Double
            /// Overnight HRV divided by the HRV baseline. 1.0 is normal; below 1
            /// signals reduced autonomic recovery. Unknown is passed as 1.0.
            var hrvRatio: Double
            /// Social jetlag in hours (schedule irregularity). Zero when unknown.
            var socialJetlagHours: Double

            // MARK: History
            //
            // Without these the engine cannot predict, only restate its own
            // inputs. All are trailing windows, oldest first, gaps already
            // dropped by the caller, and all default to empty so a caller with
            // no history is a supported state (it yields NO prediction).

            /// Nights of time asleep (hours).
            var recentSleepHours: [Double] = []
            /// Deep-sleep SHARES of time asleep (0...1), not hours.
            var recentDeepFractions: [Double] = []
            /// REM SHARES of time asleep (0...1), not hours.
            var recentRemFractions: [Double] = []
            /// Caffeine logged per day (mg), the user's habitual dose.
            var recentCaffeineMg: [Double] = []
            /// Social jetlag per day (hours), the habitual irregularity.
            var recentSocialJetlagHours: [Double] = []
        }

        // MARK: - Outputs

        nonisolated enum LeverKind: String, Sendable, Equatable, CaseIterable {
            case caffeine       // last coffee too late / too much
            case consistency    // irregular sleep timing (social jetlag)
            case recovery       // autonomic state (low HRV vs baseline)
            case sleepDebt      // carrying debt from recent short nights
        }

        /// One ranked, actionable driver of tonight's forecast, with the sleep
        /// score points it puts at stake.
        nonisolated struct Lever: Sendable, Equatable, Identifiable {
            var kind: LeverKind
            var pointsAtStake: Int
            var id: String { kind.rawValue }
        }

        nonisolated struct Forecast: Sendable, Equatable {
            /// Duration to SHOW: the prediction when there is one and the sleep
            /// target otherwise. A view presenting it as a forecast must gate on
            /// `hasDurationPrediction` first.
            var predictedHours: Double
            /// Population stage shares unless predicted: gate on
            /// `hasStagePrediction` before calling either one a prediction.
            var deepFraction: Double
            var remFraction: Double
            var predictedScore: Int
            /// Top actionable levers, most impactful first (at most three).
            var levers: [Lever]

            /// Tonight's duration predicted from this user's own nights, or nil
            /// when there is no duration history to predict from.
            var predictedHoursEstimate: Double?
            /// Plus or minus one personal spread around the estimate. Present
            /// exactly when `predictedHoursEstimate` is.
            var predictedHoursRange: ClosedRange<Double>?
            /// Predicted shares of time asleep, or nil with no stage history.
            var deepFractionEstimate: Double?
            var remFractionEstimate: Double?

            var hasDurationPrediction: Bool { predictedHoursEstimate != nil }
            /// Both stages or neither: a predicted deep share next to a
            /// constant REM share would read as two measurements.
            var hasStagePrediction: Bool {
                deepFractionEstimate != nil && remFractionEstimate != nil
            }

            /// Sum of the shown levers' points, the deductions a budget bar
            /// draws between the anchor and the predicted score.
            var leverTotal: Int { levers.reduce(0) { $0 + $1.pointsAtStake } }
        }

        /// Morning comparison of the evening prediction against the recorded
        /// night. Deltas are actual minus predicted, so positive means the
        /// night beat the forecast.
        nonisolated struct Reconciliation: Sendable, Equatable {
            var predictedHours: Double
            var actualHours: Double
            var predictedScore: Int
            var actualScore: Int
            /// False when `predictedHours` is the sleep target rather than a
            /// prediction: the morning card must not present it as a variance.
            var durationWasPredicted: Bool

            var hoursDelta: Double { actualHours - predictedHours }
            var scoreDelta: Int { actualScore - predictedScore }
        }

        // MARK: - Tuning constants (documented, fixed)

        /// Caffeine EXCESS (mg over the habitual dose) at which the model
        /// applies its full caffeine penalty. 100 mg means one extra coffee
        /// over the personal habit.
        private static let caffeineFullEffectMg: Double = 100
        /// Hours of predicted duration lost at the full caffeine effect.
        private static let caffeineMaxHourLoss: Double = 1.0
        /// Score points at stake for each capped driver.
        private static let caffeineMaxPoints = 15
        private static let consistencyMaxPoints = 12
        private static let recoveryMaxPoints = 10
        private static let sleepDebtMaxPoints = 12
        /// Social jetlag (hours) at which the consistency penalty saturates.
        private static let consistencyFullEffectHours: Double = 3
        /// HRV shortfall (fraction below baseline) at which recovery saturates.
        private static let recoveryFullEffectDrop: Double = 0.3
        /// Hours of predicted duration added at FULL sleep pressure, before
        /// the half-hour cap. Pressure comes from the shared one-night debt
        /// scale.
        private static let pressureMaxHourGain: Double = 1.0
        private static let pressureMaxHourGainCap: Double = 0.5
        /// Deep-sleep share added at full sleep pressure. Higher pressure
        /// deepens slow-wave sleep.
        private static let pressureMaxDeepShift: Double = 0.06
        /// REM share added per unit of HRV above baseline (better autonomic
        /// state lifts REM), over a +/- 0.3 ratio window.
        private static let remPerHRVRatio: Double = 0.10

        /// The median adult's stage shares, used only when this user's own
        /// history cannot support a prediction. Not a measurement.
        static let populationDeepFraction: Double = 0.16
        static let populationRemFraction: Double = 0.22
        /// A lever must put at least this many points at stake to be shown.
        private static let leverMinPoints = 2

        /// The most points a given lever can ever put at stake.
        static func leverCap(_ kind: LeverKind) -> Int {
            switch kind {
            case .caffeine: return caffeineMaxPoints
            case .consistency: return consistencyMaxPoints
            case .recovery: return recoveryMaxPoints
            case .sleepDebt: return sleepDebtMaxPoints
            }
        }

        // MARK: - Forecast

        static func forecast(_ inputs: Inputs) -> Forecast {
            let debt = max(0, inputs.priorNightDebtHours)
            let pressure01 = Stats.NightSleepDebtScale.pressure01(hours: debt)
            let hrvDrop01 = clamp((1 - inputs.hrvRatio) / recoveryFullEffectDrop, 0, 1)

            // Caffeine and consistency are charged on the EXCESS over what this
            // user habitually does. The score anchor is their own recent mean
            // score, so it already contains their habits; charging the
            // absolute level on top billed a regular coffee drinker twice.
            let caffeineExcess = max(0, inputs.caffeineMg - habitual(inputs.recentCaffeineMg))
            let caffeine01 = clamp(caffeineExcess / caffeineFullEffectMg, 0, 1)
            let jetlagExcess = max(0, inputs.socialJetlagHours - habitual(inputs.recentSocialJetlagHours))
            let jetlag01 = clamp(jetlagExcess / consistencyFullEffectHours, 0, 1)

            let caffeineHourLoss = caffeine01 * caffeineMaxHourLoss
            let pressureHourGain = min(pressureMaxHourGainCap, pressure01 * pressureMaxHourGain)

            // Duration: predicted from the HABITUAL duration this user actually
            // sleeps, shifted by tonight's pressure and caffeine. Absent a
            // duration history there is no prediction at all.
            var hoursEstimate: Double?
            var hoursRange: ClosedRange<Double>?
            if let habit = Stats.baseline(inputs.recentSleepHours,
                                          spreadFloor: Stats.sleepHoursSpreadFloor) {
                let estimate = clamp(habit.center + pressureHourGain - caffeineHourLoss, 4.5, 10)
                hoursEstimate = estimate
                hoursRange = (estimate - habit.spread)...(estimate + habit.spread)
            }
            let hours = hoursEstimate ?? inputs.sleepNeedHours

            // Stage architecture, same rule: predicted from this user's own
            // stage shares, or not predicted.
            var deepEstimate: Double?
            var remEstimate: Double?
            if !inputs.recentDeepFractions.isEmpty {
                deepEstimate = clamp(Stats.median(inputs.recentDeepFractions)
                                        + pressure01 * pressureMaxDeepShift, 0.10, 0.24)
            }
            if !inputs.recentRemFractions.isEmpty {
                remEstimate = clamp(Stats.median(inputs.recentRemFractions)
                                        + clamp(inputs.hrvRatio - 1, -0.3, 0.3) * remPerHRVRatio,
                                    0.12, 0.30)
            }
            let deep = deepEstimate ?? populationDeepFraction
            let rem = remEstimate ?? populationRemFraction

            // Score: recent baseline minus each capped, independent penalty.
            let caffeinePts = Int((caffeine01 * Double(caffeineMaxPoints)).rounded())
            let consistencyPts = Int((jetlag01 * Double(consistencyMaxPoints)).rounded())
            let recoveryPts = Int((hrvDrop01 * Double(recoveryMaxPoints)).rounded())
            let sleepDebtPts = Int((pressure01 * Double(sleepDebtMaxPoints)).rounded())

            let anchor = inputs.baselineScore > 0 ? inputs.baselineScore : Stats.sleepScoreNeutral
            let rawScore = anchor - Double(caffeinePts + consistencyPts + recoveryPts + sleepDebtPts)
            let score = Int(clamp(rawScore, 30, 100).rounded())

            let candidates: [Lever] = [
                Lever(kind: .caffeine, pointsAtStake: caffeinePts),
                Lever(kind: .consistency, pointsAtStake: consistencyPts),
                Lever(kind: .recovery, pointsAtStake: recoveryPts),
                Lever(kind: .sleepDebt, pointsAtStake: sleepDebtPts)
            ]
            let levers = candidates
                .filter { $0.pointsAtStake >= leverMinPoints }
                .sorted { $0.pointsAtStake > $1.pointsAtStake }
                .prefix(3)

            return Forecast(predictedHours: hours,
                            deepFraction: deep,
                            remFraction: rem,
                            predictedScore: score,
                            levers: Array(levers),
                            predictedHoursEstimate: hoursEstimate,
                            predictedHoursRange: hoursRange,
                            deepFractionEstimate: deepEstimate,
                            remFractionEstimate: remEstimate)
        }

        /// The user's habitual level for a behaviour, or 0 with no history, so
        /// the excess equals the absolute level.
        private static func habitual(_ history: [Double]) -> Double {
            history.isEmpty ? 0 : Stats.median(history)
        }

        // MARK: - Reconciliation

        static func reconcile(forecast prediction: Forecast,
                              actualHours: Double,
                              actualScore: Int) -> Reconciliation {
            Reconciliation(predictedHours: prediction.predictedHoursEstimate ?? prediction.predictedHours,
                           actualHours: actualHours,
                           predictedScore: prediction.predictedScore,
                           actualScore: actualScore,
                           durationWasPredicted: prediction.hasDurationPrediction)
        }

        // MARK: - History helpers

        /// Trailing days of history fed to the engine. Long enough to clear
        /// 14 confident nights with room for gaps, short enough that a changed
        /// routine is not averaged with a season-old one.
        static let historyDays = 28

        /// Nights of scoring history the anchor averages over.
        static let anchorNights = 14

        /// Mean of the usable (positive) sleep scores, or 0 when there is
        /// none. Zero is the engine's "no personal anchor" signal.
        static func recentMean(_ values: [Double]) -> Double {
            let usable = values.filter { $0 > 0 }
            guard !usable.isEmpty else { return 0 }
            return usable.reduce(0, +) / Double(usable.count)
        }

        /// Values of `series` for the days ending STRICTLY BEFORE `index`,
        /// oldest first, gaps dropped. Strictly before, so the night the
        /// morning card reconciles against never feeds its own prediction.
        static func causalTail(_ series: [Double?], endingBefore index: Int, days: Int) -> [Double] {
            let upper = min(max(0, index), series.count)
            let lower = max(0, upper - max(0, days))
            guard lower < upper else { return [] }
            return series[lower..<upper].compactMap { $0 }.filter { $0.isFinite }
        }

        /// Stage SHARES of time asleep for the nights strictly before `index`,
        /// oldest first. A night counts only when both its total and that stage
        /// are recorded: a missing stage stays missing, never a zero share.
        static func stageFractions(asleep: [Double?],
                                   stage: [Double?],
                                   endingBefore index: Int,
                                   days: Int) -> [Double] {
            let upper = min(max(0, index), asleep.count)
            let lower = max(0, upper - max(0, days))
            guard lower < upper else { return [] }
            var fractions: [Double] = []
            for i in lower..<upper {
                guard let total = asleep[i], total > 0,
                      i < stage.count, let hours = stage[i], hours > 0 else { continue }
                let fraction = hours / total
                guard fraction.isFinite, fraction > 0, fraction < 1 else { continue }
                fractions.append(fraction)
            }
            return fractions
        }

        /// Display sibling of `causalTail`, with GAPS PRESERVED as nil so a
        /// trend chart shows a missing night as a break in the line.
        static func trendWindow(_ series: [Double?], endingBefore index: Int, days: Int) -> [Double?] {
            let upper = min(max(0, index), series.count)
            let lower = max(0, upper - max(0, days))
            guard lower < upper else { return [] }
            return Array(series[lower..<upper])
        }

        /// Logged caffeine per day for the `days` days strictly before `date`,
        /// oldest first, as the day's uncapped TOTAL in mg. A day with no
        /// journal entry (nil from `totalMg`) is SKIPPED: filling it with zero
        /// would drag the habit down and make an ordinary coffee read as excess.
        static func caffeineHistory(endingBefore date: Date,
                                    days: Int,
                                    calendar: Calendar = .current,
                                    totalMg: (Date) -> Double?) -> [Double] {
            var out: [Double] = []
            guard days > 0 else { return out }
            for offset in stride(from: days, through: 1, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: date),
                      let mg = totalMg(day) else { continue }
                out.append(mg)
            }
            return out
        }

        // MARK: - Presentation helpers

        /// The score's band as a value (low below 30, fair below 60, good).
        static func band(_ score: Int) -> SleepSupport.ScoreBand {
            SleepSupport.ScoreBand(score: Double(score))
        }

        /// Is `hour` still ahead of `now` on tonight's rail? The comparison
        /// wraps, because the rail crosses midnight (00:30 is ahead of 23:00),
        /// and it is bounded to twelve hours: an unconditional wrap would make
        /// every hour "ahead" of every other.
        static func isAhead(_ hour: Double, of now: Double) -> Bool {
            var delta = hour - now
            if delta < 0 { delta += 24 }
            return delta > 0 && delta <= 12
        }

        // MARK: - Helpers

        private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
            min(max(value, low), high)
        }
    }
}
