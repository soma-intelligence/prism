//
//  ToolsCircadianInputs.swift
//  Prism
//
//  Daily sleep-timing series to circadian engine inputs.
//

import Foundation

extension SomaTools {

    /// Pure adapter from a daily sleep-timing series to the circadian engine
    /// inputs. The `bedHour`/`wakeHour` series are one value per day, oldest
    /// first, each night attributed to its wake day; `bedHour` may exceed 24 for
    /// after-midnight onsets (a 01:00 onset is stored as 25), matching the
    /// encoding `ChronotypeEstimator.Night` expects.
    nonisolated enum CircadianInputs {

        /// Lookback window for chronotype estimation (about eight weeks).
        static let maxDays = 56

        /// Fallback habitual hours when there is not yet enough sleep data.
        static let fallbackWakeHour = 7.0
        static let fallbackSleepHour = 23.0

        /// Build engine nights from the bed/wake series, flagging weekend wake days
        /// as free days. Skips days missing either value.
        static func nights(bedHours: [Double?],
                           wakeHours: [Double?],
                           today: Date,
                           calendar: Calendar = .current) -> [ChronotypeEstimator.Night] {
            let count = min(bedHours.count, wakeHours.count)
            guard count > 0 else { return [] }
            let dayStart = calendar.startOfDay(for: today)
            let start = max(0, count - maxDays)
            var nights: [ChronotypeEstimator.Night] = []
            for i in start..<count {
                guard let bed = bedHours[i], let wake = wakeHours[i] else { continue }
                // Oldest first: index i is (count - 1 - i) days before today.
                guard let day = calendar.date(byAdding: .day, value: -(count - 1 - i), to: dayStart)
                else { continue }
                let weekday = calendar.component(.weekday, from: day) // 1 = Sunday, 7 = Saturday
                let isFree = weekday == 1 || weekday == 7
                nights.append(ChronotypeEstimator.Night(bedHour: bed, wakeHour: wake, isFreeDay: isFree))
            }
            return nights
        }

        /// Same as `nights(bedHours:wakeHours:today:calendar:)`, except the series
        /// is sliced first so its positional assumption ("the last element IS
        /// `today`") is actually true instead of merely trusted.
        ///
        /// `bedHours`/`wakeHours` are a trailing window that ends on
        /// `seriesEndDay`, not necessarily on `today`. Handing the two arrays to
        /// `nights(...)` unsliced for any OTHER `today` does not select different
        /// nights: `nights(...)` derives every date from array POSITION alone, so
        /// it just relabels the same trailing nights under a different date (only
        /// the imputed weekday shifts). This slices to the position `today`
        /// actually occupies first, so the two agree.
        ///
        /// Three deliberate outcomes at the edges:
        /// . `today` at or after `seriesEndDay`: there is no later data to slice
        ///   to, so this answers with the full window, identical to calling
        ///   `nights(...)` with the unsliced arrays.
        /// . `today` further back than the arrays reach: nothing recorded that
        ///   far back to slice to, so this returns no nights rather than a guess
        ///   built from an unrelated window.
        /// . `today` inside the window but close to its start: the slice is
        ///   simply short. `nights(...)`'s own `maxDays` cap only trims the
        ///   OTHER end (the most recent side), so a short slice degrades to
        ///   fewer nights, never a fabricated one.
        static func nights(bedHours: [Double?],
                           wakeHours: [Double?],
                           today: Date,
                           seriesEndDay: Date,
                           calendar: Calendar = .current) -> [ChronotypeEstimator.Night] {
            let count = min(bedHours.count, wakeHours.count)
            guard count > 0 else { return [] }
            // Clamped, not `today` itself: the slice point can be no later than
            // the window's own end. `today` is still passed through unclamped
            // below, so the weekday flagging `nights(...)` derives from it is
            // whatever it always was for a `today` this window cannot reach.
            let clamped = min(today, seriesEndDay)
            let back = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: clamped),
                to: calendar.startOfDay(for: seriesEndDay)
            ).day ?? -1
            guard back >= 0, back < count else { return [] }
            let length = count - back
            return nights(bedHours: Array(bedHours.prefix(length)),
                          wakeHours: Array(wakeHours.prefix(length)),
                          today: today,
                          calendar: calendar)
        }

        /// Circular-mean habitual wake clock hour, or nil for no nights.
        static func habitualWakeHour(_ nights: [ChronotypeEstimator.Night]) -> Double? {
            guard !nights.isEmpty else { return nil }
            return CircadianMath.circularMeanHours(nights.map { $0.wakeHour })
        }

        /// Circular-mean habitual sleep-onset clock hour, or nil for no nights.
        /// (bedHour values above 24 fold to their clock equivalent in the mean.)
        static func habitualSleepHour(_ nights: [ChronotypeEstimator.Night]) -> Double? {
            guard !nights.isEmpty else { return nil }
            return CircadianMath.circularMeanHours(nights.map { $0.bedHour })
        }
    }
}
