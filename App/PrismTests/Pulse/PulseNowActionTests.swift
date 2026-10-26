//
//  PulseNowActionTests.swift
//  PrismTests
//

import Foundation
import Testing
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

    @Test("Without a move the hour picks the action")
    func hourDecides() {
        #expect(PulseNowAction.make(moves: [], at: at(8), calendar: calendar).aspect == .body)
        #expect(PulseNowAction.make(moves: [], at: at(13), calendar: calendar).aspect == .activity)
        #expect(PulseNowAction.make(moves: [], at: at(17), calendar: calendar).aspect == .mind)
        #expect(PulseNowAction.make(moves: [], at: at(22), calendar: calendar).aspect == .sleep)
    }

    @Test("The day's first move wins over the hour")
    func moveWins() {
        let move = PulseToday.Move(aspect: .heart, title: "Ease off", reason: "")
        #expect(PulseNowAction.make(moves: [move], at: at(8), calendar: calendar).aspect == .heart)
    }
}
