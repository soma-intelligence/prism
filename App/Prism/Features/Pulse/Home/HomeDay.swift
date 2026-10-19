//
//  HomeDay.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// Today as the pages behind the Today page read it: the readings, the
/// scores, the night, the peaks and workouts, and the moves the engine ranks.
///
/// Read once when a page opens. Every part is optional: a page with nothing
/// behind a value draws a dash and says what fills it.
struct HomeDay: Sendable {
    var inputs: PulseInputs
    var scores: SomaScores?
    var lastNight: PulseNight?
    var nights: [PulseNight]
    var peaks: [PulsePeak]
    var workouts: [PulseWorkout]
    var context: NextMoveContext
    var moves: [NextMoveCandidate]
    /// Half hours of the day on the stress strip.
    var slots: [MindSlot]
    /// Today's energy from midnight to now.
    var curve: [MindEnergyPoint]

    var now: Date { inputs.now }

    static let empty = HomeDay(
        inputs: PulseInputs(now: Date()), scores: nil, lastNight: nil, nights: [], peaks: [], workouts: [],
        context: NextMoveContext(now: Date()), moves: [], slots: [], curve: []
    )

    /// Reads the day. The breathing and wrist temperature of the night are
    /// asked for here, when a page that shows them opens, not at launch.
    @MainActor
    static func load(health: HealthDashboard, log: HomeLog, track: TrackLogStore = .shared, calendar: Calendar = .current) async -> HomeDay {
        let now = Date()
        guard let source = await health.prepare([HomeMetric.respiratoryRate, HomeMetric.wristTemperature]) else {
            return make(inputs: PulseInputs(now: now), scores: nil, log: log, track: track, calendar: calendar)
        }
        async let scoresRead: Void = health.loadScores()
        async let respiratory = source.home(HomeMetric.respiratoryRate, days: 31, now: now, calendar: calendar)
        async let wrist = source.home(HomeMetric.wristTemperature, days: 31, now: now, calendar: calendar)
        let inputs = await PulseInputs.read(from: source, now: now, calendar: calendar)
        await scoresRead
        return make(
            inputs: inputs, scores: health.scores, log: log, track: track,
            respiratory: await respiratory, wristTemperature: await wrist, calendar: calendar
        )
    }

    @MainActor
    static func make(
        inputs: PulseInputs,
        scores: SomaScores?,
        log: HomeLog,
        track: TrackLogStore = .shared,
        respiratory: [HealthReading] = [],
        wristTemperature: [HealthReading] = [],
        calendar: Calendar = .current
    ) -> HomeDay {
        let now = inputs.now
        let today = calendar.startOfDay(for: now)
        let nights = PulseNights.nights(from: inputs.sleep, calendar: calendar)
        let lastNight = nights.last { $0.day == today && $0.woke <= now }
        let context = NextMoveContext.make(
            inputs: inputs, scores: scores, log: log, track: track,
            respiratory: respiratory, wristTemperature: wristTemperature, calendar: calendar
        )
        let workouts = PulseSignals.workouts(
            inputs.workouts.filter { $0.start >= today }, steps: inputs.workoutSteps,
            heartRate: inputs.heartRate, age: inputs.age
        )
        let peaks = PulseSignals.peaks(
            heartRate: inputs.heartRate, since: lastNight?.woke ?? today,
            resting: context.restingHeartRate ?? context.restingHeartRateBaseline,
            steps: inputs.steps, stepsToday: inputs.stepsToday, workouts: workouts
        )
        let readable = !inputs.heartRate.isEmpty
        let slots: [MindSlot] = (0..<48).map { index in
            let start = today.addingTimeInterval(Double(index) * 30 * 60)
            let end = start.addingTimeInterval(30 * 60)
            if start > now { return .later }
            if peaks.contains(where: { $0.start < end && $0.end >= start }) { return .raised }
            return readable ? .quiet : .later
        }
        let curve: [MindEnergyPoint] = (scores?.energyCurve ?? []).compactMap { point in
            let fraction = point.date.timeIntervalSince(today) / (24 * 60 * 60)
            guard fraction >= 0, fraction <= 1 else { return nil }
            return MindEnergyPoint(dayFraction: fraction, level: point.level)
        }
        return HomeDay(
            inputs: inputs, scores: scores, lastNight: lastNight, nights: nights, peaks: peaks,
            workouts: workouts, context: context, moves: NextMoveArbiter().rank(context),
            slots: slots, curve: curve
        )
    }
}
