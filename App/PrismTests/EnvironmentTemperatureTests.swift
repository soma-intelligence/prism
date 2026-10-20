//
//  EnvironmentTemperatureTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
import HealthExportCore
@testable import Prism

@Suite("Environment: temperature and places")
struct EnvironmentTemperatureTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test("Today's hours stop at now")
    func hoursStopAtNow() {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        let hourly = Dictionary(uniqueKeysWithValues: (0..<24).map { (start.addingTimeInterval(Double($0) * 3_600), Double($0)) })
        let hours = EnvironmentTemperature.today(hourly, now: start.addingTimeInterval(9.5 * 3_600), calendar: calendar)
        #expect(hours.count == 24)
        #expect(hours.compactMap { $0 }.count == 10)
        #expect(hours[9] == 9)
        #expect(hours[10] == nil)
    }

    @Test("One plain line: how it feels and where today runs")
    func meaning() {
        #expect(EnvironmentTemperature.meaning(now: 14, low: 12, high: 20) == "Cool, 12° to 20° today")
        #expect(EnvironmentTemperature.meaning(now: 26, low: nil, high: nil) == "Warm")
        #expect(EnvironmentTemperature.meaning(now: nil, low: nil, high: nil) == "Waiting for the weather where you are")
        #expect(EnvironmentTemperature.signed(0.64) == "+0.6")
        #expect(EnvironmentTemperature.signed(-0.21) == "-0.2")
        #expect(EnvironmentTemperature.signed(0.02) == "0.0")
    }

    @Test("The wrist reads against your own usual, last night against how far nights stray")
    func wrist() {
        let steady: [Double?] = Array(repeating: 35.9, count: 80) + [35.9, nil, 35.9, 35.9, 35.9, 35.9, 35.9, 35.9, 35.9, 36.6]
        let read = EnvironmentTemperature.wrist(steady)
        #expect(read?.nights.count == 14)
        #expect(abs((read?.last ?? 0) - 0.7) < 0.0001)
        #expect(read?.meaning == "Warmer than your usual")
        #expect(EnvironmentTemperature.wrist(Array(repeating: nil, count: 90)) == nil)
        let short = EnvironmentTemperature.wrist([35.9, 36.0])
        #expect(short?.last == nil)
    }

    @Test("A precise place reads its street and its city")
    func preciseNames() {
        #expect(CityPickerSheet.preciseName(street: "12 Lytton Ave", city: "Palo Alto") == "12 Lytton Ave, Palo Alto")
        #expect(CityPickerSheet.preciseName(street: "Paris", city: "Paris") == "Paris")
        #expect(CityPickerSheet.preciseName(street: nil, city: "Paris") == "Paris")
        #expect(CityPickerSheet.preciseName(street: nil, city: nil) == nil)
    }

    @Test("What leaves the device stays rounded: the name lookup to 0.01, the weather to 0.1")
    func rounding() {
        let place = EnvironmentLocation.rounded(37.442_62, -122.161_01)
        #expect(place.latitude == 37.44)
        #expect(place.longitude == -122.16)
    }

    @Test("The quiet line under the outside chart: low, high and humidity, as many as are known")
    func outsideNote() {
        #expect(EnvironmentTemperature.note(low: 11.6, high: 19.8, humidity: 61.4) == "Low 12°, high 20°, humidity 61%")
        #expect(EnvironmentTemperature.note(low: nil, high: 19.8, humidity: nil) == "High 20°")
        #expect(EnvironmentTemperature.note(low: nil, high: nil, humidity: nil) == nil)
    }
}
