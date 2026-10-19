//
//  ToolsCaffeineReopen.swift
//  Prism
//
//  When the caffeine window is open again: the next waking instant.
//
//  Built on the same `CaffeineWindowEngine.nextOccurrence(ofHour:after:)` the
//  reading already uses to place bedtime, so the two cannot round a clock hour
//  differently.
//

import Foundation

extension SomaTools {

    nonisolated enum CaffeineReopen {

        /// The next instant carrying `wakeHour`, strictly after `now`.
        ///
        /// nil in, nil out: with no habitual wake hour there is no honest answer,
        /// and the surfaces drop the row rather than invent one.
        static func instant(wakeHour: Double?,
                            after now: Date,
                            calendar: Calendar = .current) -> Date? {
            guard let wakeHour else { return nil }
            return CaffeineWindowEngine.nextOccurrence(ofHour: wakeHour,
                                                       after: now,
                                                       calendar: calendar)
        }

        /// The clock minute caffeine is available again: the plan's `.sleep`
        /// window end hour when the day has one, else the persisted wake-time
        /// preference.
        ///
        /// nil in, nil out on both sides: with neither a live plan nor a captured
        /// habit there is no honest reopen minute to quote. The plan wins over
        /// the preference because it is a living prediction for THIS day; the
        /// preference is only a fallback for a day whose circadian plan carries
        /// no sleep window at all. The plan's hour is converted with
        /// `Int((hour * 60).rounded())`, the same rule a neighbouring bedtime stat
        /// uses, so two hours quoted on one card cannot round differently.
        static func reopenMinutes(planSleepEndHour: Double?,
                                  persistedWakeMinutes: Int?) -> Int? {
            if let planSleepEndHour {
                return Int((planSleepEndHour * 60).rounded())
            }
            return persistedWakeMinutes
        }

        /// Minutes left until the last call, to the minute, when a reading
        /// exists; the clock-hour fallback otherwise.
        ///
        /// A reading holds the actual instant the last call is due, not just a
        /// clock hour rounded to the nearest minute, so it is preferred whenever
        /// it exists; `clockHourFallback` only applies before any reading has been
        /// captured. Clamped to zero so a deadline already behind `now` cannot
        /// surface as a negative, or absurdly large, duration.
        static func exactMinutesRemaining(lastCall: Date?,
                                          now: Date,
                                          clockHourFallback: Int) -> Int {
            guard let lastCall else { return clockHourFallback }
            return Int(max(0, lastCall.timeIntervalSince(now)) / 60)
        }
    }
}
