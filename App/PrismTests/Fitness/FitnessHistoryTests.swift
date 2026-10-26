//
//  FitnessHistoryTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The fitness pages read one history out of Health: the window's workouts,
/// the heart rate taken during each, a distance for the ones done on foot,
/// Apple's recovery readings and the age the zones are cut from. What is held
/// here is that each workout gets its own heart rate and nothing else's, that
/// the window is honoured, and that a missing age or a refused store leaves
/// dashes rather than invented zones.
@Suite("Fitness history")
@MainActor
struct FitnessHistoryTests {
    typealias Metric = FitnessHistory.Metric

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    var now: Date { at(15) }

    /// A run yesterday evening, a strength session three days ago, and a run
    /// forty days ago that a four week window leaves out.
    var month: [HealthReading] {
        [
            .test(Metric.workout, 37, from: at(18, day: -1), to: at(19, day: -1)),
            .test(Metric.workout, 50, from: at(7, day: -3), to: at(8, day: -3)),
            .test(Metric.workout, 37, from: at(7, day: -40), to: at(8, day: -40)),
            .test(Metric.heartRate, 150, at: at(18, 10, day: -1)),
            .test(Metric.heartRate, 160, at: at(18, 40, day: -1)),
            .test(Metric.heartRate, 110, at: at(7, 20, day: -3)),
            .test(Metric.heartRate, 62, at: at(12, day: -1)),
            .test(Metric.distance, 3_000, at: at(18, 20, day: -1)),
            .test(Metric.distance, 2_000, at: at(18, 50, day: -1)),
            .test(Metric.distance, 400, at: at(7, 30, day: -3)),
            .test(Metric.recovery, 24, at: at(19, 1, day: -1)),
            .test(Metric.dateOfBirth, 35, at: at(0, day: -400)),
        ]
    }

    func read(_ readings: [HealthReading], fails: Bool = false) async -> FitnessHistory {
        await FitnessHistory.read(from: ScriptedHealthSource(readings, fails: fails), days: 28, now: now, calendar: calendar)
    }

    @Test("The highest heart rate is 220 less the age, and only for an age that can be true")
    func maxHeartRate() {
        #expect(FitnessHistory(now: now, age: 35).maxHeartRate == 185)
        #expect(FitnessHistory(now: now, age: 119).maxHeartRate == 101)
        #expect(FitnessHistory(now: now, age: nil).maxHeartRate == nil)
        #expect(FitnessHistory(now: now, age: 0).maxHeartRate == nil)
        #expect(FitnessHistory(now: now, age: 120).maxHeartRate == nil)
    }

    @Test("Every metric the fitness pages read is one the Health catalog knows")
    func metricsAreInTheCatalog() {
        for identifier in FitnessHistory.metrics + [Metric.steps, Metric.activeEnergy] {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    @Test("Workouts in the window come oldest first, each with its own heart rate, and a distance only on foot")
    func readsTheWindow() async throws {
        let history = await read(month)
        #expect(history.workouts.map(\.activity) == [50, 37])
        #expect(history.workouts.map(\.start) == [at(7, day: -3), at(18, day: -1)])

        let strength = try #require(history.workouts.first)
        let run = try #require(history.workouts.last)
        #expect(run.heartRate == [150, 160])
        #expect(strength.heartRate == [110])
        #expect(run.distance == 5_000)
        #expect(strength.distance == nil)
        #expect(run.hasZones)

        #expect(history.recovery.map(\.value) == [24])
        #expect(history.age == 35)
        #expect(history.maxHeartRate == 185)
    }

    @Test("Without an age the workouts still come, with their heart rate but no zones cut")
    func noAge() async {
        let history = await read(month.filter { $0.metric != Metric.dateOfBirth })
        #expect(history.age == nil)
        #expect(history.workouts.count == 2)
        #expect(history.workouts.allSatisfy { !$0.hasZones })
        #expect(history.workouts.last?.heartRate == [150, 160])
    }

    @Test("A store that refuses every read gives an empty history, not a crash")
    func refusedStore() async {
        let history = await read(month, fails: true)
        #expect(history == FitnessHistory(now: now))
    }
}
