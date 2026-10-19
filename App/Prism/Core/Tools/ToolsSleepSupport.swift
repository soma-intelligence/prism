//
//  ToolsSleepSupport.swift
//  Prism
//
//  The small shared statistics the sleep tools lean on: clock arithmetic on
//  the 24 h circle, a robust personal baseline, the canonical sleep score
//  neutral and the one-night sleep debt saturation. Only the pieces the sleep
//  forecast, the nap architect and the smart alarm actually use are here.
//

import Foundation

extension SomaTools {

    nonisolated enum SleepSupport {

        // MARK: Clock

        /// Clock geometry on the 24 h circle. Duplicated geometry was a live
        /// source of bugs: a cutoff computed as `bedtime - 6` without a wrap
        /// goes negative for anyone asleep after midnight and silently
        /// disables a whole module.
        nonisolated enum Clock {
            /// Folds any hour onto [0, 24).
            static func wrap24(_ hour: Double) -> Double {
                let h = hour.truncatingRemainder(dividingBy: 24)
                return h < 0 ? h + 24 : h
            }

            /// Hours forward from `from` to `to` on the circle, always [0, 24).
            static func forward(from: Double, to: Double) -> Double {
                wrap24(to - from)
            }

            /// Shortest distance between two hours, [0, 12].
            static func distance(_ a: Double, _ b: Double) -> Double {
                let d = forward(from: a, to: b)
                return min(d, 24 - d)
            }

            /// Decimal clock hour of `date` (hour plus minutes / 60).
            static func hour(of date: Date, calendar: Calendar = .current) -> Double {
                let c = calendar.dateComponents([.hour, .minute], from: date)
                return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            }
        }

        // MARK: Robust baseline

        /// Hours of sleep: the minimum plausible spread of a sleep duration
        /// history, so a flat window cannot claim a spread of zero.
        static let sleepHoursSpreadFloor = 0.25

        /// Fewest observations a personal baseline is built from. Below it
        /// there is no personal distribution to speak of.
        static let minimumBaselineCount = 3

        /// A personal baseline: robust center (median), floored spread
        /// (1.4826 * MAD), and the sample size behind them. Median and MAD
        /// rather than mean and standard deviation, so one aberrant night
        /// cannot shift the center AND inflate the spread.
        nonisolated struct Baseline: Sendable, Equatable {
            let center: Double
            let spread: Double
            let count: Int
        }

        /// Robust center and floored spread of `values`, or nil below
        /// `minimumCount` finite observations.
        static func baseline(_ values: [Double],
                             spreadFloor: Double,
                             minimumCount: Int = minimumBaselineCount) -> Baseline? {
            let clean = values.filter { $0.isFinite }
            guard clean.count >= minimumCount else { return nil }
            let center = median(clean)
            let deviations = clean.map { abs($0 - center) }
            let spread = max(spreadFloor, 1.4826 * median(deviations))
            return Baseline(center: center, spread: spread, count: clean.count)
        }

        /// Median of an unsorted array. Zero for empty, which callers must
        /// gate on rather than pass through.
        static func median(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let s = values.sorted()
            let n = s.count
            return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        }

        // MARK: Score scale

        /// The value a typical night produces on the 0...100 sleep score.
        static let sleepScoreNeutral: Double = 50

        /// The three bands the whole app paints a 0...100 score with.
        nonisolated enum ScoreBand: String, Sendable, Equatable, CaseIterable {
            case low, fair, good

            /// Below 30 is low, below 60 fair, the rest good.
            init(score: Double) {
                if score < 30 { self = .low } else if score < 60 { self = .fair } else { self = .good }
            }
        }

        // MARK: Sleep debt

        /// One night's shortfall, `max(0, need minus asleep)`, or nil when either
        /// side is unknown or the need is not positive.
        static func nightShortfallHours(asleepHours: Double?, needHours: Double?) -> Double? {
            guard let asleepHours, let needHours, needHours > 0 else { return nil }
            return max(0, needHours - asleepHours)
        }

        /// How severe one night's shortfall has to be before an engine treats
        /// it as maximal sleep pressure. One number in one place, so a single
        /// short night never reads twice as severe on one screen as on another.
        nonisolated enum NightSleepDebtScale {
            /// Hours of shortfall in a single night at which pressure is full.
            static let saturationHours: Double = 4.0

            /// `hours` on 0...1 against that saturation. Never negative: a long
            /// night does not pre-pay a future one.
            static func pressure01(hours: Double) -> Double {
                guard saturationHours > 0 else { return 0 }
                return min(max(hours, 0) / saturationHours, 1)
            }
        }
    }
}
