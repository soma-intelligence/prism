//
//  NextMoveContext+Soma.swift
//  Prism
//

import Foundation
import HealthExportCore

extension NextMoveContext {
    /// The context for what Soma holds: the Today page's readings, the scores,
    /// the person's own log (the Pulse home's and Track's), and the night's breathing and wrist temperature
    /// when the page that asked has read them.
    @MainActor
    static func make(
        inputs: PulseInputs,
        scores: SomaScores?,
        log: HomeLog,
        track: TrackLogStore = .shared,
        respiratory: [HealthReading] = [],
        wristTemperature: [HealthReading] = [],
        calendar: Calendar = .current
    ) -> NextMoveContext {
        let now = inputs.now
        let today = calendar.startOfDay(for: now)
        var ctx = NextMoveContext(now: now, calendar: calendar)

        // Sleep: last night against the median of the fortnight before.
        let nights = PulseNights.nights(from: inputs.sleep, calendar: calendar)
        let lastNight = nights.last { $0.day == today && $0.woke <= now }
        let before = nights.filter { $0.day < today }.suffix(14)
        ctx.sleepSeconds = lastNight?.asleep
        if before.count >= 3 {
            ctx.sleepNeedSeconds = PulseSignals.median(before.map(\.asleep))
        }
        ctx.habitualBedHour = habitualBedHour(Array(before), calendar: calendar)

        // Recovery against the person's own usual, the median of the month.
        ctx.recoveryScore = scores?.recovery
        let recoveries = (scores?.recoverySeries ?? []).dropLast().compactMap { $0 }
        if recoveries.count >= 7 {
            ctx.recoveryObjective = PulseSignals.median(recoveries).map { Int($0.rounded()) }
        }
        ctx.stressScore = scores?.stress

        // The heart, as the Today page reads it.
        let resting = PulseSignals.daily(inputs.restingHeartRate, calendar: calendar) { PulseSignals.median($0) }
        if let todayRate = resting[today] ?? resting[calendar.date(byAdding: .day, value: -1, to: today) ?? today] {
            ctx.restingHeartRate = todayRate
        }
        let earlierRates = resting.filter { $0.key < today }.map(\.value)
        if earlierRates.count >= 5 { ctx.restingHeartRateBaseline = PulseSignals.median(earlierRates) }

        let variability = inputs.heartRateVariability
        let recentVariability = variability.filter { $0.start >= (lastNight?.fellAsleep ?? today) }.map(\.value)
        if !recentVariability.isEmpty {
            ctx.hrv = recentVariability.reduce(0, +) / Double(recentVariability.count)
        }
        let dailyVariability = PulseSignals.daily(variability.filter { $0.start < today }, calendar: calendar) { values in
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        if dailyVariability.count >= 5 { ctx.hrvBaseline = PulseSignals.median(Array(dailyVariability.values)) }

        let workouts = PulseSignals.workouts(
            inputs.workouts.filter { $0.start >= today }, steps: inputs.workoutSteps,
            heartRate: inputs.heartRate, age: inputs.age
        )
        let peaks = PulseSignals.peaks(
            heartRate: inputs.heartRate, since: lastNight?.woke ?? today,
            resting: ctx.restingHeartRate ?? ctx.restingHeartRateBaseline,
            steps: inputs.steps, stepsToday: inputs.stepsToday, workouts: workouts
        )
        ctx.stressPeaks = inputs.heartRate.isEmpty ? nil : peaks.count
        ctx.mindfulMinutes = inputs.mindful.filter { $0.start >= today }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }

        ctx.exerciseMinutes = inputs.exerciseToday
        if inputs.exerciseByNowBefore.count >= 5 {
            ctx.exerciseUsualByNow = PulseSignals.median(inputs.exerciseByNowBefore)
        }

        // What the person logged.
        ctx.waterMl = track.waterMl(on: now).map { Int($0.rounded()) }
        if ctx.waterMl != nil { ctx.waterTargetMl = Int(track.waterGoalMl.rounded()) }
        ctx.caffeineMg = track.caffeineMg(on: now).map { Int($0.rounded()) }
        ctx.lastCaffeine = track.lastCaffeine(on: now)
        let meals = track.meals(on: now)
        if !meals.isEmpty {
            ctx.proteinGrams = Int(meals.reduce(0) { $0 + $1.proteinEaten }.rounded())
            ctx.dietaryEnergyKcal = Int(meals.reduce(0) { $0 + $1.kilocalories }.rounded())
        }
        ctx.proteinUsualGrams = usualDaily(track.meals, before: today, calendar: calendar) { $0.proteinEaten }
        ctx.checkedInToday = log.checkIn(on: now) != nil

        // The night's breathing and wrist temperature, against the month.
        (ctx.respiratoryRate, ctx.respiratoryRateBaseline) = lastAgainstUsual(respiratory, today: today, calendar: calendar)
        (ctx.wristTemperature, ctx.wristTemperatureBaseline) = lastAgainstUsual(wristTemperature, today: today, calendar: calendar)
        return ctx
    }

    /// The circular mean of the fortnight's bedtimes, as a decimal hour.
    static func habitualBedHour(_ nights: [PulseNight], calendar: Calendar) -> Double? {
        guard nights.count >= 5 else { return nil }
        var x = 0.0
        var y = 0.0
        for night in nights {
            let parts = calendar.dateComponents([.hour, .minute], from: night.bedtime)
            let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            let angle = hour / 24 * 2 * .pi
            x += cos(angle)
            y += sin(angle)
        }
        var hour = atan2(y, x) / (2 * .pi) * 24
        if hour < 0 { hour += 24 }
        return hour
    }

    /// The median daily total of a meal value over the days logged before
    /// `day`, when at least five were.
    static func usualDaily(_ meals: [TrackMealEntry], before day: Date, calendar: Calendar, _ value: (TrackMealEntry) -> Double) -> Int? {
        var byDay: [Date: Double] = [:]
        for meal in meals where meal.date < day {
            byDay[calendar.startOfDay(for: meal.date), default: 0] += value(meal)
        }
        guard byDay.count >= 5 else { return nil }
        return PulseSignals.median(Array(byDay.values)).map { Int($0.rounded()) }
    }

    /// The latest day's mean against the median of the thirty days before it.
    static func lastAgainstUsual(_ readings: [HealthReading], today: Date, calendar: Calendar) -> (Double?, Double?) {
        let daily = PulseSignals.daily(readings, calendar: calendar) { values in
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        guard let latestDay = daily.keys.filter({ $0 >= (calendar.date(byAdding: .day, value: -1, to: today) ?? today) }).max(),
              let latest = daily[latestDay] else { return (nil, nil) }
        let earlier = daily.filter { $0.key < latestDay }.map(\.value)
        return (latest, earlier.count >= 5 ? PulseSignals.median(earlier) : nil)
    }
}
