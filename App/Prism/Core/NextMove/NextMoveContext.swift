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

    /// Today's recovery score and the person's own usual one, 0 to 100.
    var recoveryScore: Int?
    var recoveryObjective: Int?
    var hrv: Double?
    var hrvBaseline: Double?

    var restingHeartRate: Double?
    var restingHeartRateBaseline: Double?

    /// Today's stress, 0 to 100, and the peaks counted since waking.
    var stressScore: Int?
    var stressPeaks: Int?
    var mindfulMinutes: Double?

    /// Exercise minutes so far, and what this person usually has by now.
    var exerciseMinutes: Double?
    var exerciseUsualByNow: Double?

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

    /// Whether today's evening check-in has been answered.
    var checkedInToday: Bool = false

    var hour: Int { calendar.component(.hour, from: now) }

    /// Minutes left before `hour` today, zero once it has gone by.
    func minutesLeft(untilHour hour: Int) -> Int {
        guard let cutoff = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { return 0 }
        return max(0, Int(cutoff.timeIntervalSince(now) / 60))
    }

    /// Minutes left before midnight.
    var minutesLeftToday: Int {
        guard let midnight = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) else { return 0 }
        return max(0, Int(midnight.timeIntervalSince(now) / 60))
    }

    /// Hours from now to the usual bedtime, measured on the clock face so a
    /// bedtime after midnight is a short way ahead rather than a day behind.
    /// Negative in the six hours after it: bedtime has gone by.
    var hoursUntilBedtime: Double? {
        guard let bed = habitualBedHour else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowHour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        let ahead = (bed - nowHour).truncatingRemainder(dividingBy: 24) + (bed < nowHour ? 24 : 0)
        return ahead > 18 ? ahead - 24 : ahead
    }

    /// Whether bedtime is within `lead` hours, or unknown.
    func isNearBedtime(lead: Double) -> Bool {
        guard let hours = hoursUntilBedtime else { return true }
        return hours <= lead
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
        case .eveningCheckIn: true
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

    /// Minutes as "1 h 10" or "40 min".
    static func span(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, rest)
    }
}
