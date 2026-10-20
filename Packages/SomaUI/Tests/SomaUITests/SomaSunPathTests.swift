//
//  SomaSunPathTests.swift
//  SomaUITests
//

import Testing
import Foundation
@testable import SomaUI

@Suite("Sun path")
struct SomaSunPathTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    var day: SomaSunGeometry {
        SomaSunGeometry(rise: start.addingTimeInterval(7 * 3_600), set: start.addingTimeInterval(19 * 3_600), dayStart: start)!
    }

    @Test("No day without both times, or with a sunset before sunrise")
    func needsBothTimes() {
        #expect(SomaSunGeometry(rise: nil, set: start, dayStart: start) == nil)
        #expect(SomaSunGeometry(rise: start.addingTimeInterval(10), set: start, dayStart: start) == nil)
    }

    @Test("The sun is on the horizon at sunrise and sunset, highest at noon, lowest at midnight")
    func heights() {
        #expect(abs(day.height(atShare: day.x(day.sunrise))) < 0.0001)
        #expect(abs(day.height(atShare: day.x(day.sunset))) < 0.0001)
        // Solar noon halfway between 07:00 and 19:00, solar midnight twelve
        // hours from it.
        #expect(abs(day.height(atShare: 13.0 / 24) - 1) < 0.0001)
        #expect(abs(day.height(atShare: 1.0 / 24) + 1) < 0.0001)
        #expect(day.height(atShare: 0.25) < 0)
        #expect(day.height(atShare: 0.75) > 0)
    }

    @Test("A moment is a share of the local day, held inside it")
    func shares() {
        #expect(day.x(start.addingTimeInterval(12 * 3_600)) == 0.5)
        #expect(day.x(start.addingTimeInterval(-60)) == 0)
        #expect(day.x(start.addingTimeInterval(30 * 3_600)) == 1)
    }

    @Test("Daylight and what comes next, in hours and minutes")
    func words() {
        #expect(SomaSunGeometry.duration(day.length) == "12h 0m")
        #expect(SomaSunGeometry.duration(45 * 60) == "45m")
        #expect(day.isUp(at: start.addingTimeInterval(12 * 3_600)))
        #expect(!day.isUp(at: start.addingTimeInterval(20 * 3_600)))
        let before = String(localized: day.next(at: start.addingTimeInterval(5 * 3_600)))
        let during = String(localized: day.next(at: start.addingTimeInterval(17 * 3_600)))
        let after = String(localized: day.next(at: start.addingTimeInterval(20 * 3_600)))
        #expect(before == "Sunrise in 2h 0m")
        #expect(during == "Sunset in 2h 0m")
        #expect(after == "Sun set 1h 0m ago")
    }
}
