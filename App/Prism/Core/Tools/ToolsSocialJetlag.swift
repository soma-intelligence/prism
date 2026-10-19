//
//  ToolsSocialJetlag.swift
//  Prism
//
//  Social jetlag as a page reads it: the weekday against weekend mid-sleep
//  comparison, the verdict band the gap falls in, and the personal baseline.
//  The science itself is
//  `ChronotypeEstimator` (Roenneberg MCTQ).
//

import Foundation

extension SomaTools {

    nonisolated enum SocialJetlag {

        // MARK: The band: one cut, one word

        /// The ONE verdict vocabulary for a social-jetlag gap. Every surface reads
        /// the band from here, so the word and the colour cannot disagree.
        nonisolated enum Band: String, Sendable, CaseIterable {
            /// Under `alignedUpperHours`.
            case aligned
            /// From `alignedUpperHours` up to the healthy edge.
            case drifting
            /// At or above `CircadianTrends.healthyUpperHours`.
            case outOfRange
        }

        /// First cut of the ramp, in hours. The upper edge is the shared
        /// `CircadianTrends.healthyUpperHours` (2 h).
        static let alignedUpperHours: Double = 1.0

        /// The band a gap falls in. Every number here is a magnitude, so the sign
        /// is dropped first.
        static func band(hours: Double) -> Band {
            let gap = abs(hours)
            if gap < alignedUpperHours { return .aligned }
            if gap < CircadianTrends.healthyUpperHours { return .drifting }
            return .outOfRange
        }

        /// True once the gap reaches the healthy edge: the threshold at which a
        /// home card surfaces and a regularity programme is worth proposing.
        /// Under it there is nothing to correct.
        static func isOutOfRange(hours: Double?) -> Bool {
            guard let hours else { return false }
            return abs(hours) >= CircadianTrends.healthyUpperHours
        }

        // MARK: Weekday against weekend

        /// The weekday against weekend comparison behind one social-jetlag number.
        nonisolated struct Comparison: Sendable, Equatable {
            /// Circular mean mid-sleep on work nights (MSW), clock hours [0, 24).
            let workdayMidSleepHour: Double
            /// Circular mean mid-sleep on free nights (MSF), clock hours [0, 24).
            let freeDayMidSleepHour: Double
            /// Shortest signed distance from MSW to MSF in hours, in (-12, 12].
            /// Positive means weekends sleep later than weekdays, the usual case.
            let signedGapHours: Double
            let workNights: Int
            let freeNights: Int

            /// The social jetlag magnitude |MSF minus MSW|, the value
            /// `ChronotypeEstimator` reports.
            var gapHours: Double { abs(signedGapHours) }
            var band: Band { SocialJetlag.band(hours: signedGapHours) }
        }

        /// Minimum free nights for a comparison, the same floor the chronotype
        /// estimate uses.
        static let minimumFreeNights = ChronotypeEstimator.minFreeNights
        /// Minimum work nights for a comparison: one, as in the estimator.
        static let minimumWorkNights = 1

        /// Compare weekday against weekend mid-sleep. Nights are filtered to a
        /// plausible 2 to 16 h exactly like `ChronotypeEstimator.estimate`, so the
        /// gap here equals the estimator's social jetlag. nil when either side
        /// lacks enough nights or its mean is undefined.
        static func compare(_ nights: [ChronotypeEstimator.Night]) -> Comparison? {
            let valid = nights.filter {
                let d = ChronotypeEstimator.sleepDuration(bedHour: $0.bedHour, wakeHour: $0.wakeHour)
                return d >= 2 && d <= 16
            }
            let free = valid.filter { $0.isFreeDay }
            let work = valid.filter { !$0.isFreeDay }
            guard free.count >= minimumFreeNights, work.count >= minimumWorkNights else { return nil }
            let mid: (ChronotypeEstimator.Night) -> Double = {
                ChronotypeEstimator.midSleepHour(bedHour: $0.bedHour, wakeHour: $0.wakeHour)
            }
            guard let msf = CircadianMath.circularMeanHours(free.map(mid)),
                  let msw = CircadianMath.circularMeanHours(work.map(mid)) else { return nil }
            return Comparison(workdayMidSleepHour: msw,
                              freeDayMidSleepHour: msf,
                              signedGapHours: CircadianMath.signedDeltaHours(from: msw, to: msf),
                              workNights: work.count,
                              freeNights: free.count)
        }

        /// Convenience: the comparison straight from the daily bed/wake series
        /// (oldest first, last element is `today`), over the same eight-week
        /// lookback the chronotype estimate uses.
        static func compare(bedHours: [Double?],
                            wakeHours: [Double?],
                            today: Date,
                            calendar: Calendar = .current) -> Comparison? {
            compare(CircadianInputs.nights(bedHours: bedHours, wakeHours: wakeHours,
                                           today: today, calendar: calendar))
        }

        // MARK: Personal baseline

        /// Trailing window the page charts, in days (12 weeks).
        static let trendDays = 84

        /// Minimum non-nil days before the personal average is honest enough to
        /// show. The daily series is nil for any day whose rolling window lacked
        /// enough free-day nights: counting those as zero would read "no shift"
        /// for a user with no data yet. 14 means a new user waits about two weeks
        /// of any estimate at all, not twelve.
        static let baselineMinimumDays = 14

        /// The personal average social-jetlag magnitude over every day in
        /// `series` except the trailing (today) slot, so today is always compared
        /// against history rather than partly against itself. Averages `abs` of
        /// each day, like every other number here, so it is directly comparable to
        /// today's value. Nil when fewer than `baselineMinimumDays` resolved.
        static func personalBaseline(_ series: [Double?]) -> Double? {
            let prior = series.dropLast().compactMap { $0 }.map(abs)
            guard prior.count >= baselineMinimumDays else { return nil }
            return prior.reduce(0, +) / Double(prior.count)
        }

        /// How many prior days actually resolved, for a "9/14 days" progress
        /// until the average is honest.
        static func resolvedPriorDays(_ series: [Double?]) -> Int {
            series.dropLast().compactMap { $0 }.count
        }

        /// True when the series holds at least one resolved day to chart.
        static func hasTrend(_ series: [Double?]) -> Bool {
            series.contains { $0 != nil }
        }
    }
}
