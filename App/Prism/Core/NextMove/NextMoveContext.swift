//
//  NextMoveContext.swift
//  Prism
//

import Foundation

/// Everything the rules may read, resolved before they run.
///
/// Every signal is optional and nil means not measured: the evidence gate
/// keeps a rule that needs it out of the race rather than letting it guess.
/// `now` and the calendar are injected, so a test builds a context by hand
/// and gets the same answer on any machine.
struct NextMoveContext: Sendable, Equatable {
    var now: Date
    var calendar: Calendar = .current

    /// Last night asleep, and what this person usually sleeps, in seconds.
    var sleepSeconds: Double?
    var sleepNeedSeconds: Double?
    /// How many nights the usual was read from. Nil when not counted.
    var sleepNights: Int?

    /// Today's recovery score and the person's own usual one, 0 to 100.
    var recoveryScore: Int?
    var recoveryObjective: Int?
    var hrv: Double?
    var hrvBaseline: Double?

    var restingHeartRate: Double?
    var restingHeartRateBaseline: Double?
    /// How many days the usual was read from, and whether the latest rate is
    /// this morning's rather than yesterday's.
    var restingHeartRateDays: Int?
    var restingHeartRateIsToday: Bool = true

    /// Today's stress, 0 to 100, and the peaks counted since waking.
    var stressScore: Int?
    var stressPeaks: Int?
    /// When the latest stress peak began and ended, and how far above
    /// resting it went.
    var lastPeakStart: Date?
    var lastPeakEnd: Date?
    var lastPeakAbove: Double?
    var mindfulMinutes: Double?

    /// Exercise minutes so far, and what this person usually has by now.
    var exerciseMinutes: Double?
    var exerciseUsualByNow: Double?
    /// Workouts started today. Nil when nothing about today's movement was
    /// read at all.
    var workoutsToday: Int?

    /// Water drunk today and the day's target, in millilitres.
    var waterMl: Int?
    var waterTargetMl: Int?

    /// Caffeine today, in milligrams, and the last dose.
    var caffeineMg: Int?
    var lastCaffeine: Date?

    /// Protein eaten today and what this person usually has by the evening.
    var proteinGrams: Int?
    var proteinUsualGrams: Int?

    var dietaryEnergyKcal: Int?
    var energyBurnedKcal: Int?

    /// Breathing asleep last night and the usual rate, per minute.
    var respiratoryRate: Double?
    var respiratoryRateBaseline: Double?
    /// Wrist temperature asleep and its usual, in degrees.
    var wristTemperature: Double?
    var wristTemperatureBaseline: Double?

    /// The hour this person usually goes to bed, as a decimal hour
    /// (23.5 is half past eleven).
    var habitualBedHour: Double?
    /// The hour this person usually wakes.
    var habitualWakeHour: Double?
    /// When this person woke today, once a night ending today is recorded.
    var wokeToday: Date?
    /// The bedtime of this person's longest nights of the month, and the
    /// latest of those bedtimes, as decimal hours.
    var bestBedHour: Double?
    var bestBedLatestHour: Double?

    /// Whether today's evening check-in has been answered. Nil when the log
    /// was not read, which is not the same as not answered.
    var checkedInToday: Bool?

    var hour: Int { calendar.component(.hour, from: now) }

    /// This person's day, from their own wake and bed times.
    var day: NextMoveDay {
        NextMoveDay(usualWakeHour: habitualWakeHour, usualBedHour: habitualBedHour, wokeToday: wokeToday)
    }

    /// The part of this person's day it is now.
    var part: NextMoveDayPart { day.part(at: now, calendar: calendar) }

    /// Minutes of sleep short of the usual, when both are known.
    var sleepDebtMinutes: Int? {
        guard let slept = sleepSeconds, let need = sleepNeedSeconds else { return nil }
        return Int((need - slept) / 60)
    }

    /// The clock hour caffeine should stop by: eight hours before the usual
    /// bedtime, or before a conventional one when the bedtime is unknown.
    var caffeineCutoffHour: Double {
        NextMoveDay.wrap(day.bedHour - CaffeineRule.clearHours)
    }

    /// Whether today's numbers ask for an easy day: recovery or the resting
    /// heart well off the usual, or a night well short of it. Effort is never
    /// offered on such a day, whatever part of it the advice for ease
    /// belongs to.
    var asksForEase: Bool {
        if let recovery = recoveryScore, let usual = recoveryObjective,
           usual - recovery >= RecoveryDeficitRule.minimumGap { return true }
        if let rate = restingHeartRate, let usual = restingHeartRateBaseline,
           (rate - usual).rounded() >= RestingHeartRateRule.minimumRise { return true }
        if let debt = sleepDebtMinutes, debt >= SleepDebtRule.easeDebtMinutes { return true }
        if let hrv, let usual = hrvBaseline, usual > 0, hrv <= usual * LowVariabilityRule.share { return true }
        return false
    }

    /// Minutes left before `hour` today, zero once it has gone by.
    func minutesLeft(untilHour hour: Int) -> Int {
        guard let cutoff = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { return 0 }
        return max(0, Int(cutoff.timeIntervalSince(now) / 60))
    }

    /// Minutes left before `lead` hours ahead of the usual bedtime, zero once
    /// that has gone by.
    func minutesLeft(beforeBedtime lead: Double) -> Int {
        let since = day.hoursSinceWake(at: now, calendar: calendar)
        let span = day.awakeSpan(calendar: calendar)
        return max(0, Int(((span - lead - since) * 60).rounded()))
    }

    /// Hours from now until a clock hour, measured forward on the clock face
    /// (0..<24): 13:00 to 15:00 is 2, 16:00 to 15:00 is 23.
    func hoursUntil(clockHour hour: Double) -> Double {
        NextMoveDay.wrap(hour - NextMoveDay.decimalHour(now, calendar: calendar))
    }

    /// Minutes left before midnight.
    var minutesLeftToday: Int {
        guard let midnight = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) else { return 0 }
        return max(0, Int(midnight.timeIntervalSince(now) / 60))
    }

    func has(_ signal: NextMoveSignal) -> Bool {
        switch signal {
        case .sleepDuration: sleepSeconds != nil
        case .sleepNeed: sleepNeedSeconds != nil
        case .recoveryScore: recoveryScore != nil
        case .recoveryObjective: recoveryObjective != nil
        case .restingHeartRate: restingHeartRate != nil
        case .restingHeartRateBaseline: restingHeartRateBaseline != nil
        case .stressScore: stressScore != nil
        case .stressPeaks: stressPeaks != nil
        case .heartRateVariability: hrv != nil && hrvBaseline != nil
        case .exercise: exerciseMinutes != nil
        case .exerciseUsual: exerciseUsualByNow != nil
        case .water: waterMl != nil
        case .waterTarget: waterTargetMl != nil
        case .caffeine: caffeineMg != nil
        case .protein: proteinGrams != nil
        case .proteinUsual: proteinUsualGrams != nil
        case .dietaryEnergy: dietaryEnergyKcal != nil
        case .energyBurned: energyBurnedKcal != nil
        case .respiratoryRate: respiratoryRate != nil
        case .respiratoryRateBaseline: respiratoryRateBaseline != nil
        case .habitualBedtime: habitualBedHour != nil
        case .eveningCheckIn: checkedInToday != nil
        }
    }
}

extension NextMoveContext {
    /// A clock time written the way the rules write it, 24 hour.
    func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// A decimal hour as a clock time: 23.5 reads 23:30.
    static func clock(hour: Double) -> String {
        let total = (Int((hour * 60).rounded()) % (24 * 60) + 24 * 60) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// A decimal hour as a clock time rounded down to the quarter hour.
    static func quarterClock(hour: Double) -> String {
        clock(hour: (NextMoveDay.wrap(hour) * 4).rounded(.down) / 4)
    }

    /// Minutes as "1 h 10" or "40 min".
    static func span(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, rest)
    }
}
