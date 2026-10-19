//
//  MindJourneyLoad.swift
//  Prism
//
//  How Mind's deeper pages read Apple Health: the Mind lens's own inputs, and
//  what only these pages need (breathing overnight, daylight, and the
//  half-hour stress curves of recent days). A read that fails is left empty,
//  and what it fed renders as a dash.
//

import Foundation
import HealthExportCore

/// What the deeper pages read, beyond ``MindInputs``.
struct MindJourneyExtras: Equatable, Sendable {
    /// Respiratory rate over the last sixty days.
    var respiratory: [HealthReading] = []
    /// Time in daylight over the last week.
    var daylight: [HealthReading] = []
}

@MainActor
enum MindJourneyLoad {
    enum Metric {
        static let respiratory = "HKQuantityTypeIdentifierRespiratoryRate"
        static let daylight = "HKQuantityTypeIdentifierTimeInDaylight"
        static let all = MindInputs.Metric.all + [respiratory, daylight]
    }

    static func extras(_ health: HealthDashboard, now: Date = Date(), calendar: Calendar = .current) async -> MindJourneyExtras {
        guard let source = await health.prepare(Metric.all) else { return MindJourneyExtras() }
        let today = calendar.startOfDay(for: now)
        let sixty = calendar.date(byAdding: .day, value: -MindInputs.days, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        async let respiratory = samples(source, Metric.respiratory, from: sixty, to: now)
        async let daylight = samples(source, Metric.daylight, from: week, to: now)
        return MindJourneyExtras(respiratory: await respiratory, daylight: await daylight)
    }

    /// The stress curves of today and the `days` before it, oldest first.
    /// Each day's heart rate is read on its own and reduced at once, so at
    /// most a few days of samples are held at a time.
    static func curves(
        _ health: HealthDashboard,
        inputs: MindInputs,
        days: Int,
        calendar: Calendar = .current
    ) async -> [MindStressDayCurve] {
        guard let source = await health.prepare(MindInputs.Metric.all) else { return [] }
        let now = inputs.now
        let today = calendar.startOfDay(for: now)
        let nights = PulseNights.nights(from: inputs.sleep, calendar: calendar)
        let asleep = nights.map { $0.fellAsleep..<$0.woke }
        let wanted: [(Date, Double?)] = (0...days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, MindStress.resting(on: day, from: inputs.restingHeartRate, calendar: calendar))
        }
        let workouts = inputs.workouts
        let heartMetric = HealthMetricCatalog.metric(for: MindInputs.Metric.heartRate)

        return await withTaskGroup(of: MindStressDayCurve?.self) { group in
            var pending = wanted.makeIterator()
            func add(_ item: (Date, Double?)) {
                let (day, resting) = item
                let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? now, now)
                group.addTask {
                    guard end > day, let metric = heartMetric else { return nil }
                    let heart = (try? await source.samples(metric, from: day, to: end, limit: 0)) ?? []
                    return MindStressCurve.make(
                        day: day, now: end, heartRate: heart, resting: resting,
                        workouts: workouts.filter { $0.end > day && $0.start < end },
                        asleep: asleep.filter { $0.upperBound > day && $0.lowerBound < end }
                    )
                }
            }
            for _ in 0..<6 { if let next = pending.next() { add(next) } }
            var found: [MindStressDayCurve] = []
            for await curve in group {
                if let curve { found.append(curve) }
                if let next = pending.next() { add(next) }
            }
            return found.sorted { $0.day < $1.day }
        }
    }

    private static func samples(_ source: any HealthSampleSource, _ identifier: String, from start: Date, to end: Date) async -> [HealthReading] {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
        return (try? await source.samples(metric, from: start, to: end, limit: 0)) ?? []
    }

    /// Every feeling on record since `start`: Apple Health's State of Mind,
    /// and the entries kept on the phone that Health does not hold.
    static func moods(since start: Date, store: MindStore) async -> [MindMoodEntry] {
        let fromHealth = store.consent.stateOfMind ? await MindHealthBridge.moods(since: start) : []
        let local = store.moods.filter { $0.date >= start && (!$0.isInHealth || fromHealth.isEmpty) }
        return (fromHealth + local).sorted { $0.date < $1.date }
    }
}
