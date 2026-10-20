//
//  SleepPlaceDetectionTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

@Suite("Sleep places: nights to places, and their heat")
@MainActor
struct SleepPlaceDetectionTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let day = Date(timeIntervalSince1970: 1_790_000_000)
    let home = (37.4443, -122.1598)
    let friend = (37.4502, -122.1462)

    private func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// The night ending on the morning `back` days before `day`: 23:00 to 07:00.
    private func night(_ back: Int) -> DateInterval {
        let morning = calendar.startOfDay(for: day).addingTimeInterval(Double(-back) * 86_400)
        return DateInterval(start: morning.addingTimeInterval(-3_600), end: morning.addingTimeInterval(7 * 3_600))
    }

    private func visit(_ spot: (Double, Double), from: Date?, to: Date?, accuracy: Double = 30) -> SleepVisit {
        SleepVisit(arrival: from, departure: to, latitude: spot.0, longitude: spot.1, accuracy: accuracy)
    }

    @Test("A night goes to the stay that covers most of it")
    func mostOfTheNight() throws {
        let n = night(0)
        let visits = [
            // Out until half past midnight, then home until morning.
            visit(friend, from: n.start.addingTimeInterval(-4 * 3_600), to: n.start.addingTimeInterval(1.5 * 3_600)),
            visit(home, from: n.start.addingTimeInterval(2 * 3_600), to: nil),
        ]
        let spots = SleepPlaceDetection.attribute(visits: visits, nights: [n], stamp: stamp)
        let spot = try #require(spots[stamp(n.end)])
        #expect(spot.latitude == home.0)
        #expect(abs(spot.hours - 6) < 0.001)
        #expect(!spot.isByHand)
    }

    @Test("No place when no stay covers half the night, or the stay is too vague")
    func noPlace() {
        let n = night(0)
        let short = visit(home, from: n.start, to: n.start.addingTimeInterval(3 * 3_600))
        #expect(SleepPlaceDetection.attribute(visits: [short], nights: [n], stamp: stamp).isEmpty)
        let vague = visit(home, from: nil, to: nil, accuracy: 900)
        #expect(SleepPlaceDetection.attribute(visits: [vague], nights: [n], stamp: stamp).isEmpty)
        // A stay with unknown ends covers the whole night.
        let open = visit(home, from: nil, to: nil)
        #expect(SleepPlaceDetection.attribute(visits: [open], nights: [n], stamp: stamp).count == 1)
    }

    @Test("Nights near each other are one place; a decision holds its nights and its name")
    func clusters() throws {
        let spots = (0..<5).map { i in
            SleepSpot(night: "2026-10-1\(i)", latitude: home.0 + Double(i) * 0.000_1, longitude: home.1, hours: 8)
        } + [SleepSpot(night: "2026-10-15", latitude: friend.0, longitude: friend.1, hours: 7)]
        let found = SleepPlaceDetection.clusters(spots: spots, decisions: [])
        #expect(found.count == 2)
        #expect(found[0].nights.count == 5)
        #expect(found[0].nights.first == "2026-10-14")
        #expect(found[0].name == nil)
        #expect(!found[0].isConfirmed)
        #expect(abs(found[0].latitude - (home.0 + 0.000_2)) < 0.000_001)

        let named = SleepPlaceDecision(id: UUID(), latitude: home.0, longitude: home.1, name: "Home")
        let forgotten = SleepPlaceDecision(id: UUID(), latitude: friend.0, longitude: friend.1, isForgotten: true)
        let decided = SleepPlaceDetection.clusters(spots: spots, decisions: [named, forgotten])
        #expect(decided.count == 1)
        #expect(decided[0].name == "Home")
        #expect(decided[0].decision == named.id)
    }

    @Test("A place set by hand carries its name")
    func byHand() {
        let spots = [
            SleepSpot(night: "2026-10-10", latitude: friend.0, longitude: friend.1, hours: 8, name: "Sam's"),
            SleepSpot(night: "2026-10-11", latitude: friend.0, longitude: friend.1, hours: 8),
        ]
        let places = SleepPlaceDetection.clusters(spots: spots, decisions: [])
        #expect(places.count == 1)
        #expect(places[0].name == "Sam's")
    }

    @Test("The heat sums hours in cells, the busiest at 1, and keeps each cell's id")
    func heat() throws {
        let spots = (0..<4).map { SleepSpot(night: "n\($0)", latitude: home.0, longitude: home.1, hours: 8) }
            + [SleepSpot(night: "x", latitude: friend.0, longitude: friend.1, hours: 8)]
        let heat = SleepPlaceDetection.heat(spots: spots)
        #expect(heat.count == 2)
        #expect(heat[0].weight == 1)
        #expect(abs(heat[1].weight - 0.25) < 0.000_1)
        #expect(abs(heat[0].latitude - home.0) < 0.000_001)
        // The same spot lands in the same cell whatever it is summed with.
        let alone = SleepPlaceDetection.heat(spots: [spots[4]])
        #expect(alone.first?.id == heat[1].id)
        #expect(SleepPlaceDetection.heat(spots: []).isEmpty)
    }

    @Test("The finder keeps a place set by hand over a found one, names, forgets, and hands named nights to the store")
    func finder() throws {
        let store = SleepPlaceStore(url: nil, calendar: calendar)
        let finder = SleepPlaceFinder(url: nil, manual: store, calendar: calendar)
        let nights = (0..<3).map(night)
        for n in nights {
            finder.record(visit(home, from: n.start.addingTimeInterval(-3_600), to: n.end.addingTimeInterval(3_600)))
        }
        finder.refresh(nights: nights, now: day)
        let place = try #require(finder.pending)
        #expect(place.nights.count == 3)
        #expect(store.place(forNightEnding: nights[0].end) == nil)

        finder.name(place, "  Home ")
        #expect(finder.pending == nil)
        #expect(finder.places.first?.name == "Home")
        #expect(store.place(forNightEnding: nights[0].end)?.name == "Home")
        #expect(!store.isSetByHand(forNightEnding: nights[0].end))

        // A night set by hand elsewhere wins over the found one.
        store.setPlace(SleepPlaceStore.Place(name: "Sam's", latitude: friend.0, longitude: friend.1),
                       forNightEnding: nights[1].end)
        #expect(finder.places.count == 2)
        #expect(finder.places.first?.nights.count == 2)
        #expect(!finder.heat().framing.isEmpty)

        let home = try #require(finder.places.first { $0.name == "Home" })
        finder.forget(home)
        #expect(finder.places.map(\.name) == ["Sam's"])
        #expect(finder.visits.isEmpty)
        // Found again later, a forgotten place stays forgotten.
        finder.record(visit(self.home, from: nights[2].start, to: nights[2].end))
        finder.refresh(nights: nights, now: day)
        #expect(finder.places.map(\.name) == ["Sam's"])
    }
}
