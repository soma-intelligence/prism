//
//  LiveActivityCopyTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaWidgetKit
@testable import Prism

@Suite("Live Activity words")
struct LiveActivityCopyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: hour, minute: minute))!
    }

    @Test("Wind down counts down to lights out, with the wake and the need")
    func windDown() {
        let content = SomaActivityCopy.windDown(now: at(22), lightsOut: at(22, 45), wake: at(23, 59).addingTimeInterval(7 * 3600),
                                                need: 7.5, calendar: calendar)
        #expect(content.title == "Lights out at 22:45")
        #expect(content.detail == "Wake at 06:59 · 7h 30m needed")
        #expect(content.end == at(22, 45))
        #expect(content.countsDown)
    }

    @Test("A nap ends after its minutes")
    func nap() {
        let content = SomaActivityCopy.nap(now: at(14), minutes: 20, calendar: calendar)
        #expect(content.end == at(14, 20))
        #expect(content.detail == "Wake at 14:20")
    }

    @Test("The cardio test counts up and flags a slow down")
    func cardio() {
        let content = SomaActivityCopy.cardioTest(name: "Six minute walk", start: at(9), metres: 211.6, heartRate: 117.6, slowDown: true)
        #expect(content.end == nil)
        #expect(content.value == "212 m")
        #expect(content.secondary == "118 bpm")
        #expect(content.alert)
    }

    @Test("A stopped clock reads minutes and seconds, hours past the hour")
    func stoppedClock() {
        #expect(SomaActivityContent.clock(360) == "6:00")
        #expect(SomaActivityContent.clock(3725) == "1:02:05")
    }

    @Test("Progress runs from 0 to 1 across a countdown")
    func progress() {
        let content = SomaActivityContent(title: "x", start: at(10), end: at(11))
        #expect(content.progress(at: at(10, 30)) == 0.5)
        #expect(content.progress(at: at(12)) == 1)
        #expect(SomaActivityContent(title: "x", start: at(10)).progress(at: at(11)) == nil)
    }

    @Test("The next clock hour lands after now, wrapping past midnight")
    func nextHour() {
        #expect(SleepTrends.next(hour: 22.5, after: at(21), calendar: calendar) == at(22, 30))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: at(7))!
        #expect(SleepTrends.next(hour: 31, after: at(22), calendar: calendar) == tomorrow)
    }
}
