//
//  EnvironmentMeasureTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
import SwiftUI
import HealthExportCore
@testable import Prism

/// Each thing the Environment lens measures carries the word for where a value
/// stands. The words follow the published bands (the UV index, the US air
/// quality index) and the listening limits, so they are pinned at the edges.
@Suite("Environment measures")
@MainActor
struct EnvironmentMeasureTests {
    let colors = SomaTheme.standard.colors
    let now = Date(timeIntervalSince1970: 1_791_046_800)

    var report: EnvironmentReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return EnvironmentReport.make(from: EnvironmentInputs(now: now), calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    func word(_ measure: EnvironmentMeasure, _ value: Double, report: EnvironmentReport? = nil) -> String? {
        measure.status(value, report: report ?? self.report, colors: colors)?.word
    }

    @Test("UV reads on the WHO index bands")
    func uv() {
        let cases: [(Double, String)] = [(0, "Low"), (2.9, "Low"), (3, "Moderate"), (6, "High"), (8, "Very high"), (11, "Extreme")]
        for (value, expected) in cases {
            #expect(word(.uv, value) == expected, "UV \(value)")
        }
    }

    @Test("Air quality reads on the US AQI bands, each band holding its upper edge")
    func air() {
        let cases: [(Double, String)] = [
            (50, "Good"), (51, "Moderate"), (100, "Moderate"), (150, "Sensitive groups"),
            (200, "Unhealthy"), (300, "Very unhealthy"), (301, "Hazardous"),
        ]
        for (value, expected) in cases {
            #expect(word(.air, value) == expected, "AQI \(value)")
        }
    }

    @Test("Temperature reads from cold to hot")
    func temperature() {
        let cases: [(Double, String)] = [(-3, "Cold"), (5, "Cool"), (15, "Mild"), (24, "Warm"), (30, "Hot")]
        for (value, expected) in cases {
            #expect(word(.temperature, value) == expected, "\(value) degrees")
        }
    }

    @Test("Sound is safe under its limit, over it at the limit, and too loud five decibels past it")
    func sound() {
        #expect(EnvironmentMeasure.sound.limit == 70)
        #expect(EnvironmentMeasure.headphones.limit == 80)
        #expect(word(.sound, 69) == "Safe")
        #expect(word(.sound, 70) == "Over limit")
        #expect(word(.sound, 75) == "Too loud")
        #expect(word(.headphones, 79) == "Safe")
        #expect(word(.headphones, 80) == "Over limit")
        #expect(word(.headphones, 85) == "Too loud")
        // A theme colour is a dynamic colour made fresh on each read, so two
        // reads of the same token are equal only once resolved.
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let drawn = EnvironmentMeasure.headphones.status(85, report: report, colors: colors)?.color.resolve(in: environment)
            let alert = colors.statusAlert.color.resolve(in: environment)
            #expect(drawn == alert, "\(scheme)")
        }
    }

    @Test("Daylight is read against the usual, and says nothing before there is one")
    func daylight() {
        var withUsual = report
        withUsual.daylightUsual = 40...90
        #expect(word(.daylight, 30, report: withUsual) == "Below usual")
        #expect(word(.daylight, 60, report: withUsual) == "Usual")
        #expect(word(.daylight, 120, report: withUsual) == "Above usual")
        #expect(word(.daylight, 60) == nil)
        #expect(EnvironmentMeasure.daylight.status(nil, report: withUsual, colors: colors) == nil)
    }

    @Test("What Health records links to its type in the Vault; the weather's measures have none")
    func identifiers() {
        for measure in EnvironmentMeasure.allCases {
            if let identifier = measure.identifier {
                #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(measure)")
            }
        }
        #expect(EnvironmentMeasure.allCases.filter { $0.identifier == nil } == [.air, .temperature])
    }

    @Test("The headline value comes from Health first, then from the weather")
    func current() {
        var report = self.report
        report.outside = EnvironmentConditions(temperature: 18, uv: 5, aqi: 42)
        #expect(EnvironmentMeasure.uv.current(report) == 5)
        report.uvNow = 3
        #expect(EnvironmentMeasure.uv.current(report) == 3)
        #expect(EnvironmentMeasure.air.current(report) == 42)
        #expect(EnvironmentMeasure.temperature.current(report) == 18)
    }

    @Test("Daylight left reads in minutes under an hour, hours and minutes above, and zero after sunset")
    func daylightLeft() {
        let rise = now.addingTimeInterval(-6 * 3600)
        func sky(setIn seconds: TimeInterval) -> EnvironmentSky {
            EnvironmentSky(now: now, day: EnvironmentSun.Day(rise: rise, set: now.addingTimeInterval(seconds)), place: nil)
        }
        #expect(sky(setIn: 45 * 60).left == "45 min")
        #expect(sky(setIn: 2 * 3600 + 10 * 60).left == "2 h 10")
        #expect(sky(setIn: -60).left == "0 min")
        #expect(EnvironmentSky(now: now, day: nil, place: nil).left == nil)
        #expect(EnvironmentSky.make(now: now, place: nil).day == nil)
    }

    @Test("Sleep places group the month's nights by place, most nights first, with their scores")
    func sleepPlaces() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }

        let home = SleepPlaceStore.Place(name: "Home", latitude: 48.85, longitude: 2.35)
        let away = SleepPlaceStore.Place(name: "Away", latitude: 45.76, longitude: 4.84)
        let store = SleepPlaceStore(url: nil, calendar: calendar)
        store.setPlace(home, forNightEnding: day(0))
        store.setPlace(home, forNightEnding: day(1))
        store.setPlace(away, forNightEnding: day(2))
        store.setPlace(home, forNightEnding: day(40))

        var scores = [Double?](repeating: nil, count: 30)
        scores[29] = 80
        scores[28] = 70
        scores[27] = 60

        let places = EnvironmentSleepPlace.make(store: store, scores: scores, now: now, calendar: calendar)
        #expect(places.map(\.name) == ["Home", "Away"])
        #expect(places.map(\.nights) == [2, 1])
        #expect(places.first?.score == 75)
        #expect(places.first?.isLastNight == true)
        #expect(places.last?.score == 60)
        #expect(places.last?.isLastNight == false)
    }
}
