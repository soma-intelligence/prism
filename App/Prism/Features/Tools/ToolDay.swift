//
//  ToolDay.swift
//  Prism
//

import Foundation
import HealthExportCore

/// The day as the circadian and sleep tools see it, worked out once from the
/// inputs: the nights in the engines' encoding, the habitual bed and wake
/// hours, the body clock's phase, the day's windows and the caffeine on board.
///
/// Every tool that needs a bedtime reads it here, so Phase Alignment, the
/// Caffeine Window and the Sleep Forecast cannot quote three different ones.
nonisolated struct ToolDay: Sendable {
    let inputs: ToolsInputs
    let calendar: Calendar
    /// Bed and wake hours for the engines' eight week window, oldest first.
    let bedHours: [Double?]
    let wakeHours: [Double?]
    let nights: [SomaTools.ChronotypeEstimator.Night]
    let habitualSleepHour: Double?
    let habitualWakeHour: Double?
    let phase: SomaTools.CircadianPhase?
    let doses: [SomaTools.CaffeineModel.Dose]
    let sleepNeedHours: Double

    /// - Parameter cups: caffeine logged in Soma (``TrackLogStore/caffeineCups``),
    ///   merged with Apple Health's without counting a cup twice.
    init(inputs: ToolsInputs, cups: [SomaTools.CaffeineModel.Dose], sleepNeedHours: Double?, calendar: Calendar = .current) {
        self.inputs = inputs
        self.calendar = calendar
        let series = inputs.series(days: SomaTools.CircadianInputs.maxDays, calendar: calendar)
        bedHours = series.bed
        wakeHours = series.wake
        nights = SomaTools.CircadianInputs.nights(bedHours: series.bed, wakeHours: series.wake,
                                                   today: inputs.now, calendar: calendar)
        // The habitual window reads the last two weeks, so a changed routine
        // shows within days rather than being averaged away over eight weeks.
        let recent = Array(nights.suffix(14))
        habitualSleepHour = SomaTools.CircadianInputs.habitualSleepHour(recent)
        habitualWakeHour = SomaTools.CircadianInputs.habitualWakeHour(recent)
        phase = SomaTools.CircadianPhaseProvider.resolve(rMEQ: nil, nights: nights, now: inputs.now)
        let since = inputs.now.addingTimeInterval(-36 * 3600)
        let health = inputs.caffeine.filter { $0.start >= since }.map { SomaTools.CaffeineModel.Dose(mg: $0.value, time: $0.start) }
        let logged = cups.filter { $0.time >= since && $0.time <= inputs.now }
        doses = Self.merged(health: health, logged: logged)
        self.sleepNeedHours = sleepNeedHours ?? 8
    }

    /// Apple Health's caffeine and the cups logged in Soma, one dose per cup.
    /// A cup logged in Soma is also written to Health, and comes back in
    /// Health's read at the same moment with the same milligrams: that Health
    /// dose is dropped, and the logged one kept. Oldest first.
    static func merged(health: [SomaTools.CaffeineModel.Dose], logged: [SomaTools.CaffeineModel.Dose]) -> [SomaTools.CaffeineModel.Dose] {
        var unmatched = logged
        var fromHealth: [SomaTools.CaffeineModel.Dose] = []
        for dose in health {
            if let index = unmatched.firstIndex(where: { abs($0.time.timeIntervalSince(dose.time)) < 60 && abs($0.mg - dose.mg) < 0.5 }) {
                unmatched.remove(at: index)
            } else {
                fromHealth.append(dose)
            }
        }
        return (fromHealth + logged).sorted { $0.time < $1.time }
    }

    /// Nights recorded in the engines' window.
    var nightCount: Int { nights.count }

    /// Seven nights before any score, the rule every Soma score keeps.
    var hasEnoughNights: Bool { nightCount >= SomaScores.minimumNights }

    /// The next bedtime at or after now, from the habitual sleep hour.
    var nextBedtime: Date? {
        habitualSleepHour.map { SomaTools.CaffeineWindowEngine.nextOccurrence(ofHour: $0, after: inputs.now, calendar: calendar) }
    }

    /// Now as a decimal clock hour.
    var nowHour: Double {
        let parts = calendar.dateComponents([.hour, .minute], from: inputs.now)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    /// The caffeine reading for tonight, from the day's doses and the person's
    /// own cup.
    var caffeine: SomaTools.CaffeineWindowEngine.Reading? {
        guard let bedtime = nextBedtime else { return nil }
        let cup = SomaTools.CaffeineWindowEngine.personalServingMg(servings: inputs.caffeine.map(\.value))
        return SomaTools.CaffeineWindowEngine.read(doses: doses, nextDoseMg: cup, bedtime: bedtime, now: inputs.now)
    }

    /// Today's windows, or nil before there is a phase and a habit to anchor
    /// them.
    var plan: SomaTools.CircadianPlan? {
        guard let phase, let wake = habitualWakeHour, let sleep = habitualSleepHour else { return nil }
        return SomaTools.CircadianPlanner.plan(phase: phase, habitualWakeHour: wake, habitualSleepHour: sleep,
                                               typicalDoseMg: nil, caffeineCutoffHour: caffeine?.lastCallHour,
                                               now: inputs.now)
    }

    var alignment: SomaTools.CircadianAlignment? {
        guard hasEnoughNights else { return nil }
        return SomaTools.CircadianAlignment.resolve(nights: nights, phase: phase, sleepNeedHours: sleepNeedHours)
    }

    /// One window of the plan by kind.
    func window(_ kind: SomaTools.CircadianWindow.Kind) -> SomaTools.CircadianWindow? {
        plan?.windows.first { $0.kind == kind }
    }
}

extension TrackLogStore {
    /// Every caffeinated drink logged in Soma, from Pulse, Track or the
    /// Caffeine Window, as the tools' doses.
    var caffeineCups: [SomaTools.CaffeineModel.Dose] {
        drinks.filter { $0.caffeineMg > 0 }.map { SomaTools.CaffeineModel.Dose(mg: $0.caffeineMg, time: $0.date) }
    }
}
