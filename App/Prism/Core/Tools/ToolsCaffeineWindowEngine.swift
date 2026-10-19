//
//  ToolsCaffeineWindowEngine.swift
//  Prism
//
//  The dose-aware caffeine reading.
//

import Foundation

extension SomaTools {

    /// Layer 2 of the caffeine model: what the day's ACTUAL doses imply, instead of
    /// what one typical serving would imply.
    ///
    /// `CaffeineModel.recommendedCutoffHour` answers "if I drink one cup, when is
    /// the last moment I can have it". That question ignores the three coffees
    /// already on board, so after a heavy morning its answer is too generous: what
    /// sits in the blood at bedtime is the SUM of every dose, not just the next
    /// one. This engine keeps the same first-order elimination and the same
    /// bedtime threshold, and solves the same inequality against the caffeine
    /// already in the body:
    ///
    ///     residual(logged doses, bedtime) + nextDose * 2^(-lead / halfLife) <= threshold
    ///
    /// which gives `lead = halfLife * log2(nextDose / headroom)`: the existing
    /// formula with the fixed threshold replaced by the headroom that is actually
    /// LEFT at bedtime. With nothing logged the headroom is the whole threshold and
    /// the two agree exactly (asserted in the tests).
    ///
    /// Pure and clock free: every input is passed in.
    nonisolated enum CaffeineWindowEngine {

        /// The cup assumed when the user has never logged a caffeine serving.
        /// The cutoff model's own standard serving, so the engine and the plain
        /// formula it generalizes cannot assume different cups.
        static let fallbackServingMg = CaffeineModel.standardServingMg

        /// Sane bounds for a personal cup size, so one mis-typed 4000 mg entry
        /// cannot redefine what "a cup" means for the recommendation.
        static let servingBounds: ClosedRange<Double> = 30...400

        // MARK: Reading

        /// Everything the caffeine surfaces need for one moment in time.
        nonisolated struct Reading: Sendable, Equatable {
            /// Caffeine still circulating right now, from every dose handed in.
            let onBoardNowMg: Double
            /// What is left at bedtime if nothing more is drunk.
            let atBedtimeMg: Double
            /// How much more may still be on board at bedtime before crossing the
            /// threshold. Negative once the day has already overshot.
            let headroomMg: Double
            /// The largest single dose that can be drunk RIGHT NOW and still leave
            /// the bedtime residual under the threshold. Zero when there is no
            /// headroom left.
            let maxDoseNowMg: Double
            /// The cup `lastCall` was solved for.
            let nextDoseMg: Double
            /// Latest moment that cup can still be drunk. Nil when even drinking it
            /// now would push bedtime over the threshold, which is the honest
            /// "nothing more today" answer.
            let lastCall: Date?
            /// When the caffeine already on board falls back under the threshold.
            /// Nil when it is already under it.
            let clearsAt: Date?
            /// Total handed in, so a surface can say what the reading is built on.
            let totalMg: Double
            let doseCount: Int
            let bedtime: Date
            let now: Date

            /// The day already used up its bedtime budget: no cup left, whatever
            /// the hour.
            var isOverBudget: Bool { headroomMg <= 0 }

            /// True once the last useful moment is behind us (or gone entirely).
            var lastCallHasPassed: Bool {
                guard let lastCall else { return true }
                return lastCall < now
            }

            /// Clock hour of `lastCall`, for the timeline and the plan window.
            var lastCallHour: Double? { lastCall.map { Self.clockHour($0) } }
            var clearsAtHour: Double? { clearsAt.map { Self.clockHour($0) } }
            var bedtimeHour: Double { Self.clockHour(bedtime) }
            var nowHour: Double { Self.clockHour(now) }

            /// Hours from now to bedtime, never negative.
            var hoursToBedtime: Double { max(0, bedtime.timeIntervalSince(now) / 3600) }

            static func clockHour(_ date: Date, calendar: Calendar = .current) -> Double {
                let c = calendar.dateComponents([.hour, .minute], from: date)
                return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            }
        }

        /// The whole reading for one moment. `doses` are the caffeine intakes that
        /// still matter (the trailing 24 h is plenty: five half-lives leave 3 % of a
        /// dose), `nextDoseMg` is the cup the recommendation is solved for.
        static func read(doses: [CaffeineModel.Dose],
                         nextDoseMg: Double,
                         bedtime: Date,
                         now: Date,
                         halfLifeHours: Double = CaffeineModel.halfLifeHours,
                         thresholdMg: Double = CaffeineModel.bedtimeThresholdMg) -> Reading {
            let cup = max(1, nextDoseMg)
            let onBoard = CaffeineModel.residual(doses: doses, at: now)
            let atBed = CaffeineModel.residual(doses: doses, at: bedtime)
            let headroom = thresholdMg - atBed
            let hoursToBed = max(0, bedtime.timeIntervalSince(now) / 3600)

            // A dose drunk now decays by 2^(-hoursToBed / halfLife) before bedtime,
            // so the largest one that still fits under the threshold is the
            // headroom scaled back up by that same factor.
            let maxNow = headroom > 0 ? headroom * pow(2, hoursToBed / halfLifeHours) : 0

            return Reading(
                onBoardNowMg: onBoard,
                atBedtimeMg: atBed,
                headroomMg: headroom,
                maxDoseNowMg: maxNow,
                nextDoseMg: cup,
                lastCall: lastCall(headroomMg: headroom, nextDoseMg: cup,
                                   bedtime: bedtime, halfLifeHours: halfLifeHours),
                clearsAt: clearanceTime(doses: doses, from: now,
                                        thresholdMg: thresholdMg),
                totalMg: doses.reduce(0) { $0 + $1.mg },
                doseCount: doses.count,
                bedtime: bedtime,
                now: now)
        }

        // MARK: The one inequality

        /// Latest moment `nextDoseMg` can be drunk and still leave the bedtime
        /// residual under the threshold, given the headroom the logged doses left.
        /// Nil when the headroom is gone. A cup that already fits inside the
        /// headroom needs no lead at all, so it returns bedtime itself rather than
        /// a negative lead pushing the answer past bedtime.
        static func lastCall(headroomMg: Double,
                             nextDoseMg: Double,
                             bedtime: Date,
                             halfLifeHours: Double = CaffeineModel.halfLifeHours) -> Date? {
            guard headroomMg > 0, nextDoseMg > 0 else { return nil }
            guard nextDoseMg > headroomMg else { return bedtime }
            let leadHours = halfLifeHours * log2(nextDoseMg / headroomMg)
            return bedtime.addingTimeInterval(-leadHours * 3600)
        }

        /// When the caffeine already on board falls back under `thresholdMg`. Nil
        /// when it is under it already (or still over 36 h out, which cannot happen
        /// with a plausible dose). Bisection rather than a closed form: a sum of
        /// exponentials has no analytic inverse, and since no dose is added after
        /// `from` the residual is strictly decreasing, so 24 halvings land within
        /// seconds of the crossing.
        static func clearanceTime(doses: [CaffeineModel.Dose],
                                  from: Date,
                                  thresholdMg: Double = CaffeineModel.bedtimeThresholdMg) -> Date? {
            guard CaffeineModel.residual(doses: doses, at: from) > thresholdMg else { return nil }
            var lo = from
            var hi = from.addingTimeInterval(36 * 3600)
            guard CaffeineModel.residual(doses: doses, at: hi) <= thresholdMg else { return nil }
            for _ in 0..<24 {
                let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                if CaffeineModel.residual(doses: doses, at: mid) > thresholdMg {
                    lo = mid
                } else {
                    hi = mid
                }
            }
            return hi
        }

        // MARK: Curve

        /// Residual (mg) sampled evenly from `start` to `end`, oldest first: the
        /// real shape of the day, one step up per logged cup and an exponential
        /// slide between them. `count` points, so the chart never has to know the
        /// pharmacokinetics.
        static func curve(doses: [CaffeineModel.Dose],
                          from start: Date,
                          to end: Date,
                          count: Int = 64) -> [Double] {
            guard count > 1, end > start else { return [] }
            let span = end.timeIntervalSince(start)
            return (0..<count).map { i in
                let t = start.addingTimeInterval(span * Double(i) / Double(count - 1))
                return CaffeineModel.residual(doses: doses, at: t)
            }
        }

        /// The same curve with one hypothetical cup added at `at`: the "what if I
        /// have another one now" branch drawn dotted next to the real curve.
        static func curveAdding(doses: [CaffeineModel.Dose],
                                dose mg: Double,
                                at time: Date,
                                from start: Date,
                                to end: Date,
                                count: Int = 64) -> [Double] {
            curve(doses: doses + [CaffeineModel.Dose(mg: mg, time: time)],
                  from: start, to: end, count: count)
        }

        // MARK: Personal cup

        /// The user's own cup: the MEDIAN of the caffeine servings they logged over
        /// the trailing window. Median rather than mean so a single 400 mg
        /// pre-workout does not redefine what a cup is, and clamped to
        /// `servingBounds` so a mis-typed entry cannot either. Falls back to the
        /// 100 mg reference when nothing was ever logged, which the UI labels as an
        /// assumption.
        static func personalServingMg(servings: [Double],
                                      fallback: Double = fallbackServingMg) -> Double {
            let positive = servings.filter { $0 > 0 }.sorted()
            guard !positive.isEmpty else { return fallback }
            let mid = positive.count / 2
            let median = positive.count % 2 == 0
                ? (positive[mid - 1] + positive[mid]) / 2
                : positive[mid]
            return min(servingBounds.upperBound, max(servingBounds.lowerBound, median))
        }

        // MARK: Clock helpers

        /// The next moment the clock reads `hour`, at or after `now`. Bedtime is a
        /// habitual clock hour while the pharmacokinetics need real instants, so
        /// every caller resolves it through here rather than reinventing the
        /// wrap-past-midnight rule.
        static func nextOccurrence(ofHour hour: Double,
                                   after now: Date,
                                   calendar: Calendar = .current) -> Date {
            let wrapped = CircadianMath.wrap24(hour)
            let start = calendar.startOfDay(for: now)
            let today = start.addingTimeInterval(wrapped * 3600)
            return today > now ? today : today.addingTimeInterval(24 * 3600)
        }
    }
}
