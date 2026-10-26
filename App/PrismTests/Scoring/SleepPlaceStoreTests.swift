//
//  SleepPlaceStoreTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Where each night was slept is set by hand and never inferred, so the store
/// must give back exactly what was set, on the right night, after a relaunch.
@Suite("Sleep places")
@MainActor
struct SleepPlaceStoreTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    let paris = SleepPlaceStore.Place(name: "Paris", latitude: 48.8566, longitude: 2.3522)
    let lyon = SleepPlaceStore.Place(name: "Lyon", latitude: 45.764, longitude: 4.8357)

    func day(_ day: Int, _ hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("A night belongs to the day it ended on, whatever the hour it is read at")
    func nightsByDay() {
        let store = SleepPlaceStore(url: nil, calendar: calendar)
        store.setPlace(paris, forNightEnding: day(3, 7))
        #expect(store.place(forNightEnding: day(3, 23)) == paris)
        #expect(store.place(forNightEnding: day(3, 0)) == paris)
        #expect(store.place(forNightEnding: day(2, 23)) == nil)
        #expect(store.stamp(day(3)) == "2026-10-03")
    }

    @Test("Clearing a night's place leaves the night unset")
    func clear() {
        let store = SleepPlaceStore(url: nil, calendar: calendar)
        store.setPlace(paris, forNightEnding: day(3))
        store.setPlace(nil, forNightEnding: day(3))
        #expect(store.place(forNightEnding: day(3)) == nil)
        #expect(store.nights.isEmpty)
    }

    @Test("Recent places run newest first, each place once")
    func recentPlaces() {
        let store = SleepPlaceStore(url: nil, calendar: calendar)
        store.setPlace(paris, forNightEnding: day(1))
        store.setPlace(lyon, forNightEnding: day(2))
        store.setPlace(paris, forNightEnding: day(3))
        #expect(store.recentPlaces == [paris, lyon])
    }

    @Test("Nights, the bedroom and the weather city survive a relaunch")
    func persistence() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "sleep-places.json")
            let store = SleepPlaceStore(url: url, calendar: calendar)
            store.setPlace(lyon, forNightEnding: day(3))
            store.bedroom = SleepPlaceStore.Bedroom(temperature: 18.5, isDark: true)
            store.weatherCity = paris

            let reopened = SleepPlaceStore(url: url, calendar: calendar)
            #expect(reopened.place(forNightEnding: day(3)) == lyon)
            #expect(reopened.bedroom == SleepPlaceStore.Bedroom(temperature: 18.5, isDark: true))
            #expect(reopened.weatherCity == paris)
        }
    }

    @Test("A file that does not read opens an empty store rather than failing")
    func unreadableFile() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "sleep-places.json")
            try Data("not json".utf8).write(to: url)
            let store = SleepPlaceStore(url: url, calendar: calendar)
            #expect(store.nights.isEmpty)
            #expect(store.bedroom == SleepPlaceStore.Bedroom())
            #expect(store.weatherCity == nil)
        }
    }

    @Test("Two places with one name are told apart by where they are")
    func placeIdentity() {
        let other = SleepPlaceStore.Place(name: "Paris", latitude: 33.6609, longitude: -95.5555)
        #expect(paris.id != other.id)
        #expect(paris.id == "Paris|48.857,2.352")
    }
}
