//
//  TrackCaffeine.swift
//  Prism
//
//  First order elimination with a five hour half life (Drake 2013), a bedtime
//  residual of
//  25 mg as the line not to cross, and the last call solved against the
//  caffeine already on board rather than against one imagined cup.
//
//  Pure and clock free: every input is passed in.
//

import Foundation

nonisolated enum TrackCaffeine {
    static let halfLifeHours = 5.0
    /// What may still be on board at bedtime. A 100 mg cup lands ten hours
    /// before bed with it, which is the published recommendation (Gardiner
    /// 2023) reached with the model's own arithmetic.
    static let bedtimeThresholdMg = 25.0
    /// The cup assumed when nothing has been logged: a standard brewed coffee.
    static let standardServingMg = 100.0

    struct Dose: Codable, Equatable, Sendable {
        var mg: Double
        var time: Date
    }

    /// Caffeine still circulating at `time` from the doses before it.
    static func residual(doses: [Dose], at time: Date, halfLifeHours: Double = halfLifeHours) -> Double {
        let ke = log(2) / halfLifeHours
        return doses.reduce(0) { total, dose in
            let hours = time.timeIntervalSince(dose.time) / 3600
            guard hours >= 0 else { return total }
            return total + dose.mg * exp(-ke * hours)
        }
    }

    /// Everything the intake page needs for one moment.
    struct Reading: Equatable, Sendable {
        /// Circulating now.
        var onBoardNowMg: Double
        /// Left at bedtime if nothing more is drunk.
        var atBedtimeMg: Double
        /// Room left under the threshold at bedtime. Negative once over.
        var headroomMg: Double
        /// The latest moment the next cup still fits. Nil when it no longer
        /// fits at all: the honest "nothing more today".
        var lastCall: Date?
        /// When what is on board falls back under the threshold. Nil when it
        /// is already under.
        var clearsAt: Date?
        /// Everything logged in the window.
        var totalMg: Double
        var bedtime: Date
        var now: Date

        var isOverBudget: Bool { headroomMg <= 0 }
    }

    static func read(
        doses: [Dose],
        nextDoseMg: Double = standardServingMg,
        bedtime: Date,
        now: Date,
        thresholdMg: Double = bedtimeThresholdMg
    ) -> Reading {
        let atBed = residual(doses: doses, at: bedtime)
        let headroom = thresholdMg - atBed
        return Reading(
            onBoardNowMg: residual(doses: doses, at: now),
            atBedtimeMg: atBed,
            headroomMg: headroom,
            lastCall: lastCall(headroomMg: headroom, nextDoseMg: max(1, nextDoseMg), bedtime: bedtime),
            clearsAt: clearanceTime(doses: doses, from: now, thresholdMg: thresholdMg),
            totalMg: doses.reduce(0) { $0 + $1.mg },
            bedtime: bedtime,
            now: now
        )
    }

    /// residual(bedtime) + next * 2^(-lead / halfLife) <= threshold, solved
    /// for the lead: halfLife * log2(next / headroom).
    static func lastCall(headroomMg: Double, nextDoseMg: Double, bedtime: Date) -> Date? {
        guard headroomMg > 0, nextDoseMg > 0 else { return nil }
        guard nextDoseMg > headroomMg else { return bedtime }
        let lead = halfLifeHours * log2(nextDoseMg / headroomMg)
        return bedtime.addingTimeInterval(-lead * 3600)
    }

    /// When the residual falls under `thresholdMg`, by bisection: a sum of
    /// exponentials has no closed inverse, but with nothing added after
    /// `from` it only falls.
    static func clearanceTime(doses: [Dose], from: Date, thresholdMg: Double = bedtimeThresholdMg) -> Date? {
        guard residual(doses: doses, at: from) > thresholdMg else { return nil }
        var low = from
        var high = from.addingTimeInterval(36 * 3600)
        guard residual(doses: doses, at: high) <= thresholdMg else { return nil }
        for _ in 0..<24 {
            let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            if residual(doses: doses, at: middle) > thresholdMg { low = middle } else { high = middle }
        }
        return high
    }

    /// The residual sampled evenly from `start` to `end`, for a curve.
    static func curve(doses: [Dose], from start: Date, to end: Date, count: Int = 48) -> [Double] {
        guard count > 1, end > start else { return [] }
        let span = end.timeIntervalSince(start)
        return (0..<count).map { index in
            residual(doses: doses, at: start.addingTimeInterval(span * Double(index) / Double(count - 1)))
        }
    }
}
