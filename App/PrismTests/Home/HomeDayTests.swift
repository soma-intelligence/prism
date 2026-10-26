//
//  HomeDayTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The pages behind Today read one day. Its stress strip has a slot per half
/// hour: what has not been lived yet, or cannot be read, stays blank rather
/// than calm, and the energy curve keeps only today's points.
@Suite("Home day")
@MainActor
struct HomeDayTests {
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

    func day(_ inputs: PulseInputs, scores: SomaScores? = nil) -> HomeDay {
        HomeDay.make(
            inputs: inputs, scores: scores,
            log: HomeLog(url: nil, calendar: calendar), track: TrackLogStore(url: nil, calendar: calendar),
            calendar: calendar
        )
    }

    @Test("Without a heart rate every slot is blank, lived or not")
    func unreadable() {
        let home = day(PulseInputs(now: at(10, 15)))
        #expect(home.slots.count == 48)
        #expect(home.slots.allSatisfy { $0 == .later })
    }

    @Test("With a heart rate and nothing raised, the lived half hours are quiet and the rest blank")
    func quietMorning() {
        var inputs = PulseInputs(now: at(10, 15))
        inputs.heartRate = [
            .test(PulseInputs.Metric.heartRate, 62, at: at(8)),
            .test(PulseInputs.Metric.heartRate, 64, at: at(9)),
        ]
        let home = day(inputs)
        let lived = 10 * 2 + 1
        #expect(home.slots.prefix(lived).allSatisfy { $0 == .quiet })
        #expect(home.slots.dropFirst(lived).allSatisfy { $0 == .later })
        #expect(home.peaks.isEmpty)
    }

    @Test("The energy curve keeps today's points, placed as shares of the day")
    func energyCurve() {
        var scores = SomaScores.fixture
        scores.energyCurve = [
            SomaScores.EnergyPoint(date: at(23, day: -1), level: 80),
            SomaScores.EnergyPoint(date: at(6), level: 70),
            SomaScores.EnergyPoint(date: at(9), level: 64),
        ]
        let home = day(PulseInputs(now: at(10, 15)), scores: scores)
        #expect(home.curve == [MindEnergyPoint(dayFraction: 0.25, level: 70), MindEnergyPoint(dayFraction: 0.375, level: 64)])
    }

    @Test("An empty day is still a day: no night, no peaks, no workouts")
    func empty() {
        let home = day(PulseInputs(now: at(10, 15)))
        #expect(home.lastNight == nil)
        #expect(home.nights.isEmpty)
        #expect(home.workouts.isEmpty)
        #expect(home.now == at(10, 15))
    }
}
