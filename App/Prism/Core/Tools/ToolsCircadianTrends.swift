//
//  ToolsCircadianTrends.swift
//  Prism
//
//  Social jetlag trend series (`SocialJetlag.Band` names the bands).
//

import Foundation

extension SomaTools {

    /// Pure trend helpers for social jetlag. The bed/wake series are one value
    /// per day, oldest first, each attributed to its wake day (a 01:00 onset is
    /// stored as 25), matching `CircadianInputs`.
    nonisolated enum CircadianTrends {

        /// Upper edge of the healthy social-jetlag band, in hours. Under this reads
        /// as in range; at or above reads as out of range.
        static let healthyUpperHours: Double = 2.0

        /// Week-by-week social jetlag (hours) over the trailing `weeks` weeks
        /// ending at `endingOn`. Each point runs `ChronotypeEstimator` over a
        /// rolling `windowNights`-night window ending that week; a point is nil
        /// when the window lacks enough free-day nights to compute MSF (a normal,
        /// honest gap for new users). Result is oldest first, length `weeks`.
        static func socialJetlagSeries(bedHours: [Double?],
                                       wakeHours: [Double?],
                                       endingOn: Date,
                                       weeks: Int = 12,
                                       windowNights: Int = 28,
                                       calendar: Calendar = .current) -> [Double?] {
            let count = min(bedHours.count, wakeHours.count)
            var series = [Double?](repeating: nil, count: max(0, weeks))
            guard count > 0, weeks > 0 else { return series }
            let dayStart = calendar.startOfDay(for: endingOn)

            for w in 0..<weeks {
                let endIndex = count - 1 - 7 * w
                guard endIndex >= 0 else { continue }
                series[weeks - 1 - w] = jetlag(bedHours: bedHours, wakeHours: wakeHours,
                                               endIndex: endIndex, count: count,
                                               windowNights: windowNights,
                                               dayStart: dayStart, calendar: calendar)
            }
            return series
        }

        /// Day-by-day social jetlag (hours) over the trailing `days` days ending at
        /// `endingOn`, oldest first (index `days - 1` is the ending day). Each point
        /// runs `ChronotypeEstimator` over a rolling `windowNights`-night window
        /// ending that day, so the line drifts smoothly; nil where the window lacks
        /// enough free-day nights. This is the master series a detail chart
        /// windows over (30D / 3M / 6M / 1Y).
        static func socialJetlagDailySeries(bedHours: [Double?],
                                            wakeHours: [Double?],
                                            endingOn: Date,
                                            days: Int = 365,
                                            windowNights: Int = 28,
                                            calendar: Calendar = .current) -> [Double?] {
            let count = min(bedHours.count, wakeHours.count)
            var series = [Double?](repeating: nil, count: max(0, days))
            guard count > 0, days > 0 else { return series }
            let dayStart = calendar.startOfDay(for: endingOn)

            // Day offset d back from the ending day maps to master index days-1-d
            // and to source index count-1-d.
            for d in 0..<days {
                let endIndex = count - 1 - d
                guard endIndex >= 0 else { continue }
                series[days - 1 - d] = jetlag(bedHours: bedHours, wakeHours: wakeHours,
                                              endIndex: endIndex, count: count,
                                              windowNights: windowNights,
                                              dayStart: dayStart, calendar: calendar)
            }
            return series
        }

        /// Social jetlag over the `windowNights` nights ending at source `endIndex`.
        private static func jetlag(bedHours: [Double?], wakeHours: [Double?],
                                   endIndex: Int, count: Int, windowNights: Int,
                                   dayStart: Date, calendar: Calendar) -> Double? {
            let startIndex = max(0, endIndex - windowNights + 1)
            var nights: [ChronotypeEstimator.Night] = []
            for i in startIndex...endIndex {
                guard let bed = bedHours[i], let wake = wakeHours[i] else { continue }
                // Index i is (count - 1 - i) days before the ending day.
                guard let day = calendar.date(byAdding: .day,
                                              value: -(count - 1 - i),
                                              to: dayStart) else { continue }
                let weekday = calendar.component(.weekday, from: day) // 1 Sun, 7 Sat
                let isFree = weekday == 1 || weekday == 7
                nights.append(.init(bedHour: bed, wakeHour: wake, isFreeDay: isFree))
            }
            return ChronotypeEstimator.estimate(nights)?.socialJetlagHours
        }
    }
}
