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
        var ctx = make(
            inputs: inputs, scores: scores,
            respiratory: respiratory, wristTemperature: wristTemperature, calendar: calendar
        )
        let now = inputs.now
        let today = calendar.startOfDay(for: now)

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
        return ctx
    }

    /// The context from Health alone: what the Today page read and the
    /// scores. The person's own log is left unknown, so no rule that needs it
    /// speaks.
    static func make(
        inputs: PulseInputs,
        scores: SomaScores?,
        respiratory: [HealthReading] = [],
        wristTemperature: [HealthReading] = [],
        calendar: Calendar = .current
    ) -> NextMoveContext {
        let now = inputs.now
        let today = calendar.startOfDay(for: now)
        var ctx = NextMoveContext(now: now, calendar: calendar)

        // Sleep: last night against the median of the fortnight before, and
        // the person's own day from the same nights.
        let nights = PulseNights.nights(from: inputs.sleep, calendar: calendar)
        let lastNight = nights.last { $0.day == today && $0.woke <= now }
        let before = nights.filter { $0.day < today }.suffix(14)
        ctx.sleepSeconds = lastNight?.asleep
        if before.count >= 3 {
            ctx.sleepNeedSeconds = PulseSignals.median(before.map(\.asleep))
            ctx.sleepNights = before.count
        }
        ctx.habitualBedHour = habitualBedHour(Array(before), calendar: calendar)
        ctx.habitualWakeHour = habitualHour(Array(before).map(\.woke), calendar: calendar)
        ctx.wokeToday = lastNight?.woke
        let month = nights.filter {
            $0.day >= (calendar.date(byAdding: .day, value: -30, to: today) ?? today) && $0.woke <= now
        }
        if let best = bestBedtimes(month, calendar: calendar) {
            ctx.bestBedHour = best.target
            ctx.bestBedLatestHour = best.latest
        }

        // Recovery against the person's own usual, the median of the month.
        ctx.recoveryScore = scores?.recovery
        let recoveries = (scores?.recoverySeries ?? []).dropLast().compactMap { $0 }
        if recoveries.count >= 7 {
            ctx.recoveryObjective = PulseSignals.median(recoveries).map { Int($0.rounded()) }
        }
        ctx.stressScore = scores?.stress

        // The heart, as the Today page reads it.
        let resting = PulseSignals.daily(inputs.restingHeartRate, calendar: calendar) { PulseSignals.median($0) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        if let todayRate = resting[today] {
            ctx.restingHeartRate = todayRate
            ctx.restingHeartRateIsToday = true
        } else if let yesterdayRate = resting[yesterday] {
            ctx.restingHeartRate = yesterdayRate
            ctx.restingHeartRateIsToday = false
        }
        let earlierRates = resting.filter { $0.key < today }.map(\.value)
        if earlierRates.count >= 5 {
            ctx.restingHeartRateBaseline = PulseSignals.median(earlierRates)
            ctx.restingHeartRateDays = earlierRates.count
        }

        let variability = inputs.heartRateVariability
        let recentVariability = variability.filter { $0.start >= (lastNight?.fellAsleep ?? today) && $0.start <= now }.map(\.value)
        if !recentVariability.isEmpty {
            ctx.hrv = recentVariability.reduce(0, +) / Double(recentVariability.count)
        }
        let dailyVariability = PulseSignals.daily(variability.filter { $0.start < (lastNight?.fellAsleep ?? today) }, calendar: calendar) { values in
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        if dailyVariability.count >= 5 { ctx.hrvBaseline = PulseSignals.median(Array(dailyVariability.values)) }

        let workouts = PulseSignals.workouts(
            inputs.workouts.filter { $0.start >= today && $0.start <= now }, steps: inputs.workoutSteps,
            heartRate: inputs.heartRate, age: inputs.age
        )
        let peaks = PulseSignals.peaks(
            heartRate: inputs.heartRate, since: lastNight?.woke ?? today,
            resting: ctx.restingHeartRate ?? ctx.restingHeartRateBaseline,
            steps: inputs.steps, stepsToday: inputs.stepsToday, workouts: workouts
        )
        ctx.stressPeaks = inputs.heartRate.isEmpty ? nil : peaks.count
        if let last = peaks.max(by: { $0.end < $1.end }) {
            ctx.lastPeakStart = last.start
            ctx.lastPeakEnd = last.end
            ctx.lastPeakAbove = last.above
        }
        ctx.mindfulMinutes = inputs.mindful.filter { $0.start >= today }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }

        ctx.exerciseMinutes = inputs.exerciseToday
        if inputs.exerciseByNowBefore.count >= 5 {
            ctx.exerciseUsualByNow = PulseSignals.median(inputs.exerciseByNowBefore)
        }
        // A day with any movement read knows whether a workout happened.
        if inputs.exerciseToday != nil || inputs.stepsToday != nil || !workouts.isEmpty {
            ctx.workoutsToday = workouts.count
        }

        // The night's breathing and wrist temperature, against the month.
        (ctx.respiratoryRate, ctx.respiratoryRateBaseline) = lastAgainstUsual(respiratory, today: today, calendar: calendar)
        (ctx.wristTemperature, ctx.wristTemperatureBaseline) = lastAgainstUsual(wristTemperature, today: today, calendar: calendar)
        return ctx
    }

    /// The bedtime of the month's longest nights: the middle of their
    /// bedtimes, rounded down to the quarter hour, and the latest of them.
    /// Needs a week of nights.
    static func bestBedtimes(_ month: [PulseNight], calendar: Calendar) -> (target: Double, latest: Double)? {
        guard month.count >= 7 else { return nil }
        let longest = month.sorted { $0.asleep > $1.asleep }.prefix(max(3, month.count / 3))
        // Hours since six in the evening, so a bedtime after midnight sorts
        // after one before it.
        let clocks = longest.map { NextMoveDay.wrap(NextMoveDay.decimalHour($0.bedtime, calendar: calendar) - 18) }
        guard let middle = PulseSignals.median(clocks), let latest = clocks.max() else { return nil }
        return (NextMoveDay.wrap(18 + (middle * 4).rounded(.down) / 4), NextMoveDay.wrap(18 + latest))
    }

    /// The circular mean of the fortnight's bedtimes, as a decimal hour.
    static func habitualBedHour(_ nights: [PulseNight], calendar: Calendar) -> Double? {
        habitualHour(nights.map(\.bedtime), calendar: calendar)
    }

    /// The circular mean of a fortnight of clock times, as a decimal hour,
    /// so 23:30 and 00:30 average to midnight. Needs five.
    static func habitualHour(_ times: [Date], calendar: Calendar) -> Double? {
        guard times.count >= 5 else { return nil }
        var x = 0.0
        var y = 0.0
        for time in times {
            let hour = NextMoveDay.decimalHour(time, calendar: calendar)
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
