//
//  TrainingLoad.swift
//  Prism
//

import Foundation

/// Cardio load: the last seven days of effort read against what the body is
/// used to.
///
/// Each day's
/// load is Edwards' TRIMP (minutes in each zone weighted by the zone's
/// number). The acute load is a 7 day exponentially weighted mean of it, the
/// chronic load a 42 day one, after Banister's model of training impulse.
/// The productive band runs from 0.8 to 1.5 times the chronic load, and the
/// ratio of the two says whether the week is building, holding or too much.
nonisolated enum TrainingLoad {
    static let acuteDays = 7.0
    static let chronicDays = 42.0
    static let bandLow = 0.8
    static let bandHigh = 1.5

    /// Where the acute load sits against the chronic one. Finer labels fold
    /// into the four the page names: peaking reads as productive, and
    /// fatigued and overtraining both read as too much.
    enum Status: String, CaseIterable, Sendable, Identifiable {
        case productive = "Productive"
        case tooMuch = "Too much"
        case maintaining = "Maintaining"
        case detraining = "Detraining"
        /// Under three points of chronic load: too little history to say.
        case calibrating = "Calibrating"

        var id: String { rawValue }
        var title: String { rawValue }

        /// The four a person sees counted, in the page's order.
        static let counted: [Status] = [.productive, .tooMuch, .maintaining, .detraining]
    }

    /// The ratio cut points between the four.
    static func status(acute: Double, chronic: Double) -> Status {
        guard chronic > 3 else { return .calibrating }
        let ratio = acute / max(0.5, chronic)
        switch ratio {
        case ..<0.8: return .detraining
        case ..<1.0: return .maintaining
        case ..<1.5: return .productive
        default: return .tooMuch
        }
    }

    /// Edwards' TRIMP for zone seconds, index 0 is zone 1.
    static func trimp(zoneSeconds: [Double]) -> Double {
        zoneSeconds.prefix(5).enumerated().reduce(0) { $0 + $1.element / 60 * Double($1.offset + 1) }
    }

    /// Daily TRIMP over the `days` days ending today, oldest first. A day
    /// without a workout is zero load: rest is a value here, not a gap.
    static func dailyTrimp(_ workouts: [FitnessWorkout], days: Int, now: Date, calendar: Calendar) -> [Double] {
        let today = calendar.startOfDay(for: now)
        var loads = Array(repeating: 0.0, count: days)
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.start)
            guard let ago = calendar.dateComponents([.day], from: day, to: today).day, ago >= 0, ago < days else { continue }
            loads[days - 1 - ago] += trimp(zoneSeconds: workout.zoneSeconds)
        }
        return loads
    }

    /// An exponentially weighted mean over `tau` days, seeded on the first day.
    static func ewma(_ values: [Double], tau: Double) -> [Double] {
        let alpha = 2 / (tau + 1)
        var current = values.first ?? 0
        return values.map { value in
            current += alpha * (value - current)
            return current
        }
    }

    /// The model over a daily load series.
    struct Model: Equatable, Sendable {
        /// Acute load per day, the last `shown` days, oldest first.
        var acute: [Double]
        var bandLower: [Double]
        var bandUpper: [Double]
        /// Status per day over the same days.
        var statuses: [Status]
        var today: Double
        var todayBand: ClosedRange<Double>
        var todayStatus: Status

        /// Days of each counted status, and the share of the shown days.
        func count(_ status: Status) -> (days: Int, share: Double) {
            let days = statuses.filter { $0 == status }.count
            return (days, statuses.isEmpty ? 0 : Double(days) / Double(statuses.count))
        }

        /// The longest run of days above the band, oldest first, as indexes
        /// into the shown days. Nil when none.
        var longestSpike: ClosedRange<Int>? {
            var best: ClosedRange<Int>?
            var start: Int?
            for index in statuses.indices {
                if statuses[index] == .tooMuch {
                    if start == nil { start = index }
                } else if let first = start {
                    let run = first...(index - 1)
                    if run.count > (best?.count ?? 0) { best = run }
                    start = nil
                }
            }
            if let first = start {
                let run = first...(statuses.count - 1)
                if run.count > (best?.count ?? 0) { best = run }
            }
            return best
        }
    }

    /// The model over `daily`, showing the last `shown` days. Nil with under
    /// two days of history, or with no load at all.
    static func model(daily: [Double], shown: Int) -> Model? {
        guard daily.count >= 2, daily.contains(where: { $0 > 0 }) else { return nil }
        let acute = ewma(daily, tau: acuteDays)
        let chronic = ewma(daily, tau: chronicDays)
        let statuses = zip(acute, chronic).map { status(acute: $0, chronic: $1) }
        let keep = min(shown, daily.count)
        let lastChronic = chronic[chronic.count - 1]
        return Model(
            acute: Array(acute.suffix(keep)),
            bandLower: Array(chronic.suffix(keep).map { $0 * bandLow }),
            bandUpper: Array(chronic.suffix(keep).map { $0 * bandHigh }),
            statuses: Array(statuses.suffix(keep)),
            today: acute[acute.count - 1],
            todayBand: (lastChronic * bandLow)...(lastChronic * bandHigh),
            todayStatus: statuses[statuses.count - 1]
        )
    }
}
