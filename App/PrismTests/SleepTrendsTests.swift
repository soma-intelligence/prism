//
//  SleepTrendsTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Sleep page trends")
struct SleepTrendsTests {
    @Test("The latest is judged against the band, and nothing without one")
    func status() {
        #expect(SleepTrends.status(7, 6...8) == .normal)
        #expect(SleepTrends.status(5, 6...8) == .below)
        #expect(SleepTrends.status(9, 6...8) == .above)
        #expect(SleepTrends.status(nil, 6...8) == .none)
        #expect(SleepTrends.status(7, nil) == .none)
    }

    @Test("A night prints as hours and minutes")
    func hm() {
        #expect(SleepTrends.hm(6.9167) == "6h 55m")
        #expect(SleepTrends.hm(0.75) == "45m")
    }

    @Test("The middle of a night crosses midnight")
    func midpoint() {
        // Bed 23:00, up 07:00: the middle is 03:00, 27 in the evening's frame.
        #expect(SleepTrends.midpoints(bedHour: [23], wakeHour: [7]) == [27])
        // Bed 01:00 (25), up 09:00: 05:00.
        #expect(SleepTrends.midpoints(bedHour: [25], wakeHour: [9]) == [29])
        #expect(SleepTrends.midpoints(bedHour: [nil], wakeHour: [7]) == [nil])
    }

    @Test("Social jetlag is weekend mid sleep against weekdays")
    func socialJetlag() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Sunday 2026-10-25.
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
        var bed: [Double?] = [], wake: [Double?] = []
        for offset in stride(from: 13, through: 0, by: -1) {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            if calendar.isDateInWeekend(day) { bed.append(25); wake.append(9) } else { bed.append(23); wake.append(7) }
        }
        let jetlag = SleepTrends.socialJetlag(bedHour: bed, wakeHour: wake, now: now, calendar: calendar)
        #expect(jetlag.map { abs($0 - 2) < 0.001 } == true)
        // Too few nights to compare.
        #expect(SleepTrends.socialJetlag(bedHour: [23, 23], wakeHour: [7, 7], now: now, calendar: calendar) == nil)
    }

    @Test("The dip row is judged against 10 to 20 percent")
    func dipBand() {
        let rows = SleepTrends.rows(scores: nil, inputs: nil, dip: nil)
        #expect(rows.first { $0.title == "Heart rate dip" }?.band == 10...20)
    }
}
