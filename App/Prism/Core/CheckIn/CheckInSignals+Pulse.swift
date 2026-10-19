//
//  CheckInSignals+Pulse.swift
//  Prism
//

import Foundation

extension CheckInSignals {
    /// The readings the Today page already worked out: last night against the
    /// week's other nights, and the latest resting rate against the fortnight
    /// before it. Nothing is read again from Health for a question.
    ///
    /// The usual sleep needs three earlier nights and the usual resting rate
    /// five earlier days, as on the Today page, so a question never leans on
    /// a usual made of one night.
    static func from(_ today: PulseToday?) -> CheckInSignals {
        guard let today else { return .none }
        var signals = CheckInSignals()

        if let last = today.nights.last ?? nil {
            let earlier = today.nights.dropLast().compactMap { $0 }
            signals.lastNightSleepMinutes = last * 60
            if earlier.count >= 3 {
                signals.usualSleepMinutes = PulseSignals.median(earlier).map { $0 * 60 }
            }
        }

        // Today's rate, or yesterday's when the watch has not written today's.
        let days = today.restingDays
        let latestIndex = days.indices.last { days[$0] != nil && $0 >= days.count - 2 }
        if let latestIndex, let latest = days[latestIndex] {
            let earlier = days[..<latestIndex].compactMap { $0 }
            signals.restingHeartRate = latest
            if earlier.count >= 5 {
                signals.usualRestingHeartRate = PulseSignals.median(earlier)
            }
        }
        return signals
    }
}
