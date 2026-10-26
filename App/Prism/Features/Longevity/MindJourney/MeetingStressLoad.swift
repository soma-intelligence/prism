//
//  MeetingStressLoad.swift
//  Prism
//
//  How the meetings page reads Apple Health for ``MeetingStressAnalysis``:
//  heart rate and steps around each day's meetings, read a day at a time and
//  reduced at once, so a month of heart rate is never held whole. Only the
//  span from an hour before the day's first meeting to just after its last
//  is read. A read that fails leaves its meetings unread, never calm.
//

import Foundation
import HealthExportCore

@MainActor
enum MeetingStressLoad {
    /// Every meeting in `meetings` that has started, read against its day.
    static func assessments(
        _ health: HealthDashboard,
        inputs: MindInputs,
        meetings: [MindCalendarEvent],
        calendar: Calendar = .current
    ) async -> [MeetingStressAnalysis.Assessment] {
        let now = inputs.now
        let past = meetings.filter { $0.start < now }
        guard !past.isEmpty, let source = await health.prepare(MindInputs.Metric.all) else { return [] }
        let heartMetric = HealthMetricCatalog.metric(for: MindInputs.Metric.heartRate)
        let stepMetric = HealthMetricCatalog.metric(for: MindInputs.Metric.steps)
        let lead = MeetingStressAnalysis.baselineWindow + MeetingStressAnalysis.stepWindow
        let tail = MeetingStressAnalysis.stepWindow

        struct Day: Sendable {
            var meetings: [MindCalendarEvent]
            var resting: Double?
            var workouts: [HealthReading]
            var span: Range<Date>
        }
        let days: [Day] = Dictionary(grouping: past) { calendar.startOfDay(for: $0.start) }
            .compactMap { day, meetings in
                guard let first = meetings.map(\.start).min(), let last = meetings.map(\.end).max() else { return nil }
                let span = first.addingTimeInterval(-lead)..<max(first, min(last.addingTimeInterval(tail), now))
                return Day(
                    meetings: meetings.sorted { $0.start < $1.start },
                    resting: MindStress.resting(on: day, from: inputs.restingHeartRate, calendar: calendar),
                    workouts: inputs.workouts.filter { $0.end > span.lowerBound.addingTimeInterval(-MeetingStressAnalysis.workoutMargin) && $0.start < span.upperBound },
                    span: span
                )
            }

        return await withTaskGroup(of: [MeetingStressAnalysis.Assessment].self) { group in
            var pending = days.makeIterator()
            func add(_ day: Day) {
                group.addTask {
                    async let heart = read(source, heartMetric, day.span)
                    async let steps = read(source, stepMetric, day.span)
                    return MeetingStressAnalysis.assessDay(
                        day.meetings, heartRate: await heart, steps: await steps,
                        workouts: day.workouts, resting: day.resting
                    )
                }
            }
            for _ in 0..<6 { if let next = pending.next() { add(next) } }
            var found: [MeetingStressAnalysis.Assessment] = []
            for await batch in group {
                found += batch
                if let next = pending.next() { add(next) }
            }
            return found.sorted { $0.event.start < $1.event.start }
        }
    }

    private nonisolated static func read(_ source: any HealthSampleSource, _ metric: HealthMetric?, _ span: Range<Date>) async -> [HealthReading] {
        guard let metric else { return [] }
        return (try? await source.samples(metric, from: span.lowerBound, to: span.upperBound, limit: 0)) ?? []
    }
}
