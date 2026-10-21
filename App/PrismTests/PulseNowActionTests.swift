//
//  PulseNowActionTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

@Suite("Orb action for now")
struct PulseNowActionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour))!
    }

    @Test("Before anything is read the hour picks the action")
    func hourDecides() {
        #expect(PulseNowAction.make(today: nil, at: at(8), calendar: calendar).aspect == .body)
        #expect(PulseNowAction.make(today: nil, at: at(13), calendar: calendar).aspect == .activity)
        #expect(PulseNowAction.make(today: nil, at: at(17), calendar: calendar).aspect == .mind)
        #expect(PulseNowAction.make(today: nil, at: at(22), calendar: calendar).aspect == .sleep)
    }

    /// A day whose resting heart sits eight above a steady month.
    private func raisedHeart(at hour: Int) -> PulseToday {
        let metric = "HKQuantityTypeIdentifierRestingHeartRate"
        var readings = (1...20).map { offset -> HealthReading in
            let date = calendar.date(byAdding: .day, value: -offset, to: at(7))!
            return HealthReading(metric: metric, value: 56, unit: .none, start: date, end: date)
        }
        readings.append(HealthReading(metric: metric, value: 64, unit: .none, start: at(7), end: at(7)))
        return PulseToday.make(from: PulseInputs(now: at(hour), restingHeartRate: readings), calendar: calendar)
    }

    @Test("The engine's cue wins over the hour, in its own words")
    func cueWins() {
        let action = PulseNowAction.make(today: raisedHeart(at: 8), at: at(8), calendar: calendar)
        #expect(action.aspect == .heart)
        #expect(String(localized: action.label) == "Ease off")
    }

    @Test("A move ticked off hands the orb to the calm default")
    func tickedMoveSteps() {
        let action = PulseNowAction.make(today: raisedHeart(at: 8), done: [.heart], at: at(8), calendar: calendar)
        #expect(String(localized: action.label) == "Steady day")
    }
}
