//
//  SleepPlaceRecorderTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// A calendar pinned to one zone, so 02:00 is 02:00 wherever the tests run.
private func pinnedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
    return calendar
}

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, calendar: Calendar = pinnedCalendar()) -> Date {
    let parts = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return calendar.date(from: parts) ?? .distantPast
}

@Suite("Sleep places: the store")
@MainActor
struct SleepPlaceAutomaticTests {
    private let night = date(20, 8)
    private let home = SleepPlaceStore.Place(name: "12 Rue des Lilas, Lyon", latitude: 45.764_12, longitude: 4.835_67,
                                             address: "12 Rue des Lilas, 69003 Lyon")
    private let away = SleepPlaceStore.Place(name: "3 Main St, Boston", latitude: 42.360_08, longitude: -71.058_88)

    @Test("A place set by hand is never replaced by a detected one")
    func handSetStays() {
        let store = SleepPlaceStore(url: nil, calendar: pinnedCalendar())
        store.setPlace(away, forNightEnding: night)
        let changed = store.setAutomatic(home, forNightEnding: night)
        #expect(!changed)
        #expect(store.place(forNightEnding: night)?.name == away.name)
        #expect(store.place(forNightEnding: night)?.wasDetected == false)
    }

    @Test("A detected place gives way to a later detection")
    func automaticReplacesAutomatic() {
        let store = SleepPlaceStore(url: nil, calendar: pinnedCalendar())
        #expect(store.setAutomatic(away, forNightEnding: night))
        #expect(store.setAutomatic(home, forNightEnding: night))
        let kept = store.place(forNightEnding: night)
        #expect(kept?.name == home.name)
        #expect(kept?.address == home.address)
        #expect(kept?.wasDetected == true)
    }

    @Test("Picking a detected place by hand makes it the person's")
    func pickingClearsDetectedMark() {
        let store = SleepPlaceStore(url: nil, calendar: pinnedCalendar())
        store.setAutomatic(home, forNightEnding: night)
        guard let detected = store.place(forNightEnding: night) else {
            Issue.record("no place recorded")
            return
        }
        store.setPlace(detected, forNightEnding: night)
        #expect(store.place(forNightEnding: night)?.wasDetected == false)
        #expect(!store.setAutomatic(away, forNightEnding: night))
    }

    @Test("A file written before address and detection still decodes, as set by hand")
    func oldFileDecodes() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sleep-places-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sleep-places.json")
        let old = """
        {"nights":{"2026-10-20":{"name":"Lyon","latitude":45.76,"longitude":4.84}},
         "bedroom":{"temperature":18.5},
         "weatherCity":{"name":"Lyon","latitude":45.76,"longitude":4.84}}
        """
        try Data(old.utf8).write(to: url)

        let store = SleepPlaceStore(url: url, calendar: pinnedCalendar())
        let place = store.place(forNightEnding: night)
        #expect(place?.name == "Lyon")
        #expect(place?.address == nil)
        #expect(place?.wasDetected == false)
        #expect(store.bedroom.temperature == 18.5)
        #expect(store.weatherCity?.name == "Lyon")
    }

    @Test("A detected place survives a round trip through the file")
    func detectedRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sleep-places-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sleep-places.json")
        let store = SleepPlaceStore(url: url, calendar: pinnedCalendar())
        store.setAutomatic(home, forNightEnding: night)

        let again = SleepPlaceStore(url: url, calendar: pinnedCalendar())
        let place = again.place(forNightEnding: night)
        #expect(place?.address == home.address)
        #expect(place?.wasDetected == true)
        // Precise is the point: nothing is rounded on the way.
        #expect(place?.latitude == home.latitude)
        #expect(place?.longitude == home.longitude)
    }
}

@Suite("Sleep places: which night a stay held")
struct SleepPlaceNightTests {
    private let calendar = pinnedCalendar()

    @Test("A stay covering last night's window is that night's place")
    func stayCoversWindow() {
        let window = DateInterval(start: date(19, 23, 30), end: date(20, 7, 10))
        let nights = SleepPlaceRecorder.nights(heldByArrival: date(19, 18), departure: date(20, 8, 30),
                                               lastNight: window, now: date(20, 9), calendar: calendar)
        #expect(nights == [calendar.startOfDay(for: date(20, 0))])
    }

    @Test("A stay that ends early in the night does not hold it")
    func stayOutsideNight() {
        let window = DateInterval(start: date(19, 23, 30), end: date(20, 7, 10))
        // Dinner at a friend's, home at one in the morning.
        let nights = SleepPlaceRecorder.nights(heldByArrival: date(19, 19), departure: date(20, 1),
                                               lastNight: window, now: date(20, 9), calendar: calendar)
        #expect(nights.isEmpty)
    }

    @Test("A daytime stay holds no night")
    func daytimeStay() {
        let nights = SleepPlaceRecorder.nights(heldByArrival: date(20, 9), departure: date(20, 18),
                                               lastNight: nil, now: date(20, 19), calendar: calendar)
        #expect(nights.isEmpty)
    }

    @Test("Without a window, the stay has to hold most of 02:00 to 05:00")
    func fallbackCore() {
        let held = SleepPlaceRecorder.nights(heldByArrival: date(19, 22), departure: date(20, 6),
                                             lastNight: nil, now: date(20, 9), calendar: calendar)
        #expect(held == [calendar.startOfDay(for: date(20, 0))])

        // Leaving at 03:00 covers one hour of three.
        let left = SleepPlaceRecorder.nights(heldByArrival: date(19, 22), departure: date(20, 3),
                                             lastNight: nil, now: date(20, 9), calendar: calendar)
        #expect(left.isEmpty)
    }

    @Test("A weekend stay holds every night in it, and open ends are clipped")
    func openEndedStay() {
        let nights = SleepPlaceRecorder.nights(heldByArrival: date(17, 19), departure: .distantFuture,
                                               lastNight: nil, now: date(20, 9), calendar: calendar)
        #expect(nights == [18, 19, 20].map { calendar.startOfDay(for: date($0, 0)) })

        let unknownArrival = SleepPlaceRecorder.nights(heldByArrival: .distantPast, departure: date(20, 8),
                                                       lastNight: nil, now: date(20, 9), calendar: calendar)
        // Clipped to the last week: seven cores at most, never a crash.
        #expect(unknownArrival.count == 7)
    }

    @Test("A stay still going counts only what was already lived")
    func stayInProgress() {
        let nights = SleepPlaceRecorder.nights(heldByArrival: date(19, 22), departure: .distantFuture,
                                               lastNight: nil, now: date(20, 2, 30), calendar: calendar)
        #expect(nights.isEmpty)
    }

    @Test("A departure before the arrival yields nothing")
    func reversedStay() {
        let nights = SleepPlaceRecorder.nights(heldByArrival: date(20, 8), departure: date(19, 8),
                                               lastNight: nil, now: date(20, 9), calendar: calendar)
        #expect(nights.isEmpty)
    }
}

@Suite("Sleep places: the morning fix")
struct SleepPlaceMorningTests {
    private let calendar = pinnedCalendar()
    private let window = DateInterval(start: date(19, 23, 30), end: date(20, 7, 10))

    @Test("From waking to four hours after, the fix belongs to the night that ended")
    func withinMorning() {
        let day = calendar.startOfDay(for: date(20, 0))
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 7, 15), lastNight: window, calendar: calendar) == day)
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 11), lastNight: window, calendar: calendar) == day)
    }

    @Test("Past the morning, or before waking, there is no fix")
    func outsideMorning() {
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 11, 30), lastNight: window, calendar: calendar) == nil)
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 3), lastNight: window, calendar: calendar) == nil)
    }

    @Test("Without a window, 04:00 to 12:00 is the morning")
    func fallbackMorning() {
        let day = calendar.startOfDay(for: date(20, 0))
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 4), lastNight: nil, calendar: calendar) == day)
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 11, 59), lastNight: nil, calendar: calendar) == day)
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 12), lastNight: nil, calendar: calendar) == nil)
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 3, 59), lastNight: nil, calendar: calendar) == nil)
    }

    @Test("A window from an older night is ignored for today's morning")
    func staleWindow() {
        let old = DateInterval(start: date(17, 23), end: date(18, 7))
        let day = calendar.startOfDay(for: date(20, 0))
        #expect(SleepPlaceRecorder.morningNight(now: date(20, 8), lastNight: old, calendar: calendar) == day)
    }
}

@Suite("Sleep places: fixes and names")
struct SleepPlaceFixTests {
    @Test("Only a fresh fix within 65 m names the night")
    func fixAccuracy() {
        #expect(SleepPlaceRecorder.accepts(accuracy: 12, age: 3))
        #expect(SleepPlaceRecorder.accepts(accuracy: 65, age: 3))
        #expect(!SleepPlaceRecorder.accepts(accuracy: 66, age: 3))
        #expect(!SleepPlaceRecorder.accepts(accuracy: -1, age: 3))
        #expect(!SleepPlaceRecorder.accepts(accuracy: 10, age: 600))
        #expect(!SleepPlaceRecorder.accepts(accuracy: 10, age: .nan))
    }

    @Test("A fix next to a detected place takes it; one across town does not")
    func nearestPlace() {
        let home = SleepPlaceStore.Place(name: "12 Rue des Lilas, Lyon", latitude: 45.764_12, longitude: 4.835_67,
                                         isAutomatic: true)
        // About 40 m north.
        #expect(SleepPlaceRecorder.nearest(latitude: 45.764_48, longitude: 4.835_67, among: [home]) == home)
        // About 2 km away.
        #expect(SleepPlaceRecorder.nearest(latitude: 45.782, longitude: 4.835_67, among: [home]) == nil)
        #expect(SleepPlaceRecorder.nearest(latitude: .nan, longitude: 4.8, among: [home]) == nil)
    }

    @Test("The name is the street and the city")
    func label() {
        #expect(SleepPlaceRecorder.label(street: "12 Rue des Lilas", city: "Lyon", fallback: nil) == "12 Rue des Lilas, Lyon")
        #expect(SleepPlaceRecorder.label(street: "1 Lyon Street", city: "Lyon", fallback: nil) == "1 Lyon Street")
        #expect(SleepPlaceRecorder.label(street: nil, city: "Lyon", fallback: "Somewhere") == "Lyon")
        #expect(SleepPlaceRecorder.label(street: "  ", city: nil, fallback: "Parc") == "Parc")
        #expect(SleepPlaceRecorder.label(street: nil, city: nil, fallback: nil) == nil)
    }
}
