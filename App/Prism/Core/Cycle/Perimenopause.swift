//
//  Perimenopause.swift
//  Prism
//
//  Signs of the menopause transition, read from the periods Health holds,
//  the symptoms logged, and the watch's wrist temperature at night. The
//  stages are STRAW+10's (Harlow et al., Menopause 2012;19:387), the frame
//  The Menopause Society (formerly NAMS) uses:
//
//  - early transition: a persistent difference of seven days or more in the
//    length of consecutive cycles, persistent meaning it comes back within
//    ten cycles of the first;
//  - late transition: sixty days or more without a period;
//  - postmenopause: twelve months without a period.
//
//  What comes out is a reading of signs, never a diagnosis: the page says
//  "signs consistent with" and points to a clinician, who can weigh what
//  the phone cannot (pregnancy, breastfeeding, contraception, thyroid,
//  medicines). Nothing here touches HealthKit: the days come in as values,
//  so the tests drive it directly.
//

import Foundation
import HealthExportCore

/// One period: its first day, its last day of flow so far, and whether it
/// may still be running.
nonisolated struct CyclePeriod: Equatable, Sendable {
    var start: Date
    var lastFlowDay: Date
    /// Flow yesterday or today: the period may not be over, so it has no
    /// length yet.
    var isOpen: Bool
    /// Days of flow, first to last, nil while the period is open.
    var days: Int?
}

/// Periods and cycle lengths from the days Health recorded flow on.
nonisolated enum CycleHistory {
    /// Every period on record, oldest first, from days with any flow.
    /// Flow ten days or more after the last flow day starts a new period,
    /// the same rule as `HomeCycle`.
    static func periods(flowDays: [Date], today: Date, calendar: Calendar) -> [CyclePeriod] {
        let todayStart = calendar.startOfDay(for: today)
        let days = Set(flowDays.map { calendar.startOfDay(for: $0) }).filter { $0 <= todayStart }.sorted()
        var periods: [CyclePeriod] = []
        for day in days {
            if var last = periods.last,
               let gap = calendar.dateComponents([.day], from: last.lastFlowDay, to: day).day, gap < HomeCycle.gapDays {
                last.lastFlowDay = day
                periods[periods.count - 1] = last
            } else {
                periods.append(CyclePeriod(start: day, lastFlowDay: day, isOpen: false, days: nil))
            }
        }
        if var last = periods.last,
           let since = calendar.dateComponents([.day], from: last.lastFlowDay, to: todayStart).day, since <= 1 {
            last.isOpen = true
            periods[periods.count - 1] = last
        }
        return periods.map { period in
            var period = period
            if !period.isOpen, let span = calendar.dateComponents([.day], from: period.start, to: period.lastFlowDay).day {
                period.days = span + 1
            }
            return period
        }
    }

    /// The length of each finished cycle, first day to the next first day,
    /// oldest first. The cycle running today has no length yet.
    static func cycleLengths(_ periods: [CyclePeriod], calendar: Calendar = .current) -> [Int] {
        zip(periods, periods.dropFirst()).compactMap { pair in
            calendar.dateComponents([.day], from: pair.0.start, to: pair.1.start).day
        }
    }
}

/// Where the signs place a person in the menopause transition.
nonisolated enum PerimenopauseStage: String, Sendable {
    /// Enough cycles on record and none of the signs.
    case none
    case earlyTransition
    case lateTransition
    case postmenopause
}

/// The signs, and the stage they are consistent with.
nonisolated struct PerimenopauseAssessment: Equatable, Sendable {
    enum Sign: Equatable, Sendable {
        /// Cycles in the last ten that ran seven days or more off the usual.
        case variableCycles(count: Int)
        /// The longest stretch without a period in the record, in days.
        case longGap(days: Int)
        /// Months since the last period, at twelve or more.
        case monthsWithoutPeriod(Int)
        /// Days with a hot flash in the last thirty.
        case hotFlashes(days: Int)
        /// Nights with night sweats in the last thirty, and how many of them
        /// the watch read a warmer wrist than usual.
        case nightSweats(nights: Int, warmNights: Int)
    }

    var stage: PerimenopauseStage?
    var signs: [Sign]
}

nonisolated enum PerimenopauseSignal {
    /// STRAW+10: a cycle that differs by seven days or more.
    static let variableDays = 7
    /// STRAW+10: the difference has to come back within ten cycles.
    static let windowCycles = 10
    /// STRAW+10: sixty days without a period marks the late transition.
    static let lateGapDays = 60
    /// STRAW+10: twelve months after the final period.
    static let postmenopauseDays = 365
    /// Three finished cycles before Soma says no sign shows. Soma's line,
    /// not a clinical one: fewer cycles cannot show a persistent change.
    static let minimumCycles = 3
    /// The Menopause Society: the transition usually starts in the forties.
    /// Under forty, long gaps have other common causes (and early ovarian
    /// insufficiency is its own question), so Soma does not stage them.
    static let minimumAge = 40
    /// Symptoms are counted over the last thirty days.
    static let symptomWindowDays = 30
    /// Hot flashes on this many days of the thirty make a sign. Soma's
    /// line, not a clinical cut off: once a week, every week.
    static let repeatedDays = 4
    /// A night's wrist temperature this far above the person's usual (the
    /// median of the thirty nights) counts as warm. Soma's line: Apple shows
    /// deviations of this size as a change from baseline.
    static let warmWristDelta = 0.3

    /// The stage the signs are consistent with, or nil when there is too
    /// little to read: no period on record, fewer than three finished
    /// cycles without a long gap, or a person under forty.
    static func evaluate(
        cycles: [CyclePeriod],
        symptoms: [CycleSymptom: [Date]],
        wristTemperature: [HealthReading],
        now: Date = .now,
        calendar: Calendar = .current,
        age: Int? = nil
    ) -> PerimenopauseStage? {
        assess(cycles: cycles, symptoms: symptoms, wristTemperature: wristTemperature, now: now, calendar: calendar, age: age).stage
    }

    /// The stage and every sign behind it, symptoms included. Symptoms are
    /// listed as signs but never set a stage on their own: hot flashes come
    /// with many things, and STRAW+10 stages on the cycle.
    static func assess(
        cycles: [CyclePeriod],
        symptoms: [CycleSymptom: [Date]],
        wristTemperature: [HealthReading],
        now: Date = .now,
        calendar: Calendar = .current,
        age: Int? = nil
    ) -> PerimenopauseAssessment {
        let today = calendar.startOfDay(for: now)
        var signs: [PerimenopauseAssessment.Sign] = []
        var stage: PerimenopauseStage?

        if let last = cycles.last {
            let lengths = Array(CycleHistory.cycleLengths(cycles, calendar: calendar).suffix(windowCycles))
            let sinceFlow = calendar.dateComponents([.day], from: last.lastFlowDay, to: today).day ?? 0
            let sinceStart = calendar.dateComponents([.day], from: last.start, to: today).day ?? 0
            // The running cycle counts as a gap once it is past sixty days.
            let longest = max(lengths.max() ?? 0, last.isOpen ? 0 : sinceStart)
            // Variability against the person's own usual length, so one long
            // cycle counts once rather than twice (once going, once back).
            let usual = PulseSignals.median(lengths.map(Double.init)) ?? 0
            let variable = lengths.filter { abs(Double($0) - usual) >= Double(variableDays) }.count

            if sinceFlow >= postmenopauseDays {
                stage = .postmenopause
                signs.append(.monthsWithoutPeriod(sinceFlow * 12 / 365))
            } else if longest >= lateGapDays {
                stage = .lateTransition
                signs.append(.longGap(days: longest))
            } else if variable >= 2 {
                stage = .earlyTransition
            } else if lengths.count >= minimumCycles {
                stage = PerimenopauseStage.none
            }
            if variable > 0 { signs.append(.variableCycles(count: variable)) }
        }

        if let age, age < minimumAge { stage = nil }

        let windowStart = calendar.date(byAdding: .day, value: -(symptomWindowDays - 1), to: today) ?? today
        func days(_ symptom: CycleSymptom) -> Set<Date> {
            Set((symptoms[symptom] ?? []).filter { $0 >= windowStart && $0 <= now }.map { calendar.startOfDay(for: $0) })
        }
        let flashes = days(.hotFlashes)
        if flashes.count >= repeatedDays { signs.append(.hotFlashes(days: flashes.count)) }

        let sweats = days(.nightSweats)
        if !sweats.isEmpty {
            let nights = wristTemperature.filter { $0.end >= windowStart && $0.end <= now }
            let usual = PulseSignals.median(nights.map(\.value))
            let warm = sweats.filter { night in
                guard let usual else { return false }
                return nights.contains { calendar.isDate($0.end, inSameDayAs: night) && $0.value - usual >= warmWristDelta }
            }
            signs.append(.nightSweats(nights: sweats.count, warmNights: warm.count))
        }
        return PerimenopauseAssessment(stage: stage, signs: signs)
    }
}
