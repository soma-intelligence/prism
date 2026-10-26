//
//  EnvironmentSunTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Sunrise and sunset are worked out on the device. Checked against the
/// published almanac for places on both sides of the equator and of
/// Greenwich, inside the couple of minutes the method claims, and for the
/// polar days when the sun never crosses the horizon.
@Suite("Environment sun")
@MainActor
struct EnvironmentSunTests {
    func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// Noon on `day` of `month` 2026 where `calendar` keeps time.
    func noon(_ month: Int, _ day: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    /// Minutes after local midnight.
    func minutes(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    func expectClose(_ date: Date?, _ hour: Int, _ minute: Int, _ calendar: Calendar,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        guard let date else {
            Issue.record("no time", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(minutes(date, calendar) - (hour * 60 + minute)) <= 3, sourceLocation: sourceLocation)
    }

    @Test("Paris at the solstices, in summer and in winter time")
    func paris() {
        let paris = calendar("Europe/Paris")
        let june = EnvironmentSun.day(for: noon(6, 21, paris), latitude: 48.8566, longitude: 2.3522, calendar: paris)
        expectClose(june?.rise, 5, 46, paris)
        expectClose(june?.set, 21, 58, paris)

        let december = EnvironmentSun.day(for: noon(12, 21, paris), latitude: 48.8566, longitude: 2.3522, calendar: paris)
        expectClose(december?.rise, 8, 41, paris)
        expectClose(december?.set, 16, 56, paris)
    }

    @Test("Sydney's longest day lands on the local day, though its sunrise is the day before in UTC")
    func sydney() {
        let sydney = calendar("Australia/Sydney")
        let date = noon(12, 21, sydney)
        let day = EnvironmentSun.day(for: date, latitude: -33.87, longitude: 151.21, calendar: sydney)
        expectClose(day?.rise, 5, 41, sydney)
        expectClose(day?.set, 20, 5, sydney)
        #expect(day.map { sydney.isDate($0.rise, inSameDayAs: date) } == true)
        #expect(day.map { sydney.isDate($0.set, inSameDayAs: date) } == true)
    }

    @Test("On the equator a day at the equinox runs about twelve hours")
    func equator() throws {
        let quito = calendar("America/Guayaquil")
        let day = try #require(EnvironmentSun.day(for: noon(3, 20, quito), latitude: -0.18, longitude: -78.47, calendar: quito))
        let hours = day.set.timeIntervalSince(day.rise) / 3600
        #expect(abs(hours - 12.1) < 0.15)
    }

    @Test("In the midnight sun and the polar night there is no sunrise to give")
    func polar() {
        let tromso = calendar("Europe/Oslo")
        #expect(EnvironmentSun.day(for: noon(6, 21, tromso), latitude: 69.65, longitude: 18.96, calendar: tromso) == nil)
        #expect(EnvironmentSun.day(for: noon(12, 21, tromso), latitude: 69.65, longitude: 18.96, calendar: tromso) == nil)
        #expect(EnvironmentSun.day(for: noon(3, 20, tromso), latitude: 69.65, longitude: 18.96, calendar: tromso) != nil)
    }

    @Test("Progress runs from 0 at sunrise to 1 at sunset, past either end outside the day")
    func progress() {
        let rise = Date(timeIntervalSince1970: 1_791_000_000)
        let day = EnvironmentSun.Day(rise: rise, set: rise.addingTimeInterval(10 * 3600))
        #expect(day.progress(at: rise) == 0)
        #expect(day.progress(at: rise.addingTimeInterval(5 * 3600)) == 0.5)
        #expect(day.progress(at: rise.addingTimeInterval(-3600)) < 0)
        #expect(day.progress(at: rise.addingTimeInterval(11 * 3600)) > 1)
        #expect(EnvironmentSun.Day(rise: rise, set: rise).progress(at: rise.addingTimeInterval(60)) == 0)
    }
}
