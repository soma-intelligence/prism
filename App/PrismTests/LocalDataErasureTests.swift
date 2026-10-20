//
//  LocalDataErasureTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

@Suite("Delete my data: what the phone erases")
@MainActor
struct LocalDataErasureTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let day = Date(timeIntervalSince1970: 1_790_000_000)

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path())
    }

    @Test("Sleep places, the bedroom, rituals and the Longevity snapshot go, files and memory")
    func erasesEverythingKeptOnThePhone() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "erase-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshotURL = folder.appending(path: "longevity-snapshot.json")
        let visitsURL = folder.appending(path: "sleep-visits.json")
        let nightsURL = folder.appending(path: "sleep-places.json")
        let ritualsURL = folder.appending(path: "rituals.json")

        // Something in each file.
        let snapshot = LongevitySnapshotStore(url: snapshotURL, owner: { "device" })
        snapshot.save(mind: .preview, at: day)
        await snapshot.settle()

        let nights = SleepPlaceStore(url: nightsURL, calendar: calendar)
        let home = SleepPlaceStore.Place(name: "Home", latitude: 37.4443, longitude: -122.1598)
        nights.setPlace(home, forNightEnding: day)
        nights.bedroom = SleepPlaceStore.Bedroom(temperature: 18, isDark: true)
        nights.weatherCity = home

        let finder = SleepPlaceFinder(url: visitsURL, manual: nights, calendar: calendar)
        let evening = calendar.startOfDay(for: day).addingTimeInterval(-5 * 3_600)
        finder.record(SleepVisit(arrival: evening, departure: evening.addingTimeInterval(13 * 3_600),
                                 latitude: home.latitude, longitude: home.longitude, accuracy: 30))
        finder.refresh(nights: [DateInterval(start: evening.addingTimeInterval(4 * 3_600), duration: 8 * 3_600)], now: day)
        let place = try #require(finder.places.first)
        finder.name(place, "Home")

        let rituals = TrackRitualStore(url: ritualsURL, calendar: calendar)
        let daylight = rituals.ritual(.morning).steps[0]
        rituals.toggle(daylight, on: day)
        rituals.addStep("Cold shower", glyph: .cold, to: .morning)

        #expect(exists(snapshotURL) && exists(visitsURL) && exists(nightsURL) && exists(ritualsURL))
        #expect(!finder.visits.isEmpty && !finder.decisions.isEmpty)

        LocalDataErasure.run(snapshot: snapshot, sleepPlaces: finder, nights: nights, rituals: rituals)
        await snapshot.settle()

        // Files gone.
        #expect(!exists(snapshotURL))
        #expect(!exists(visitsURL))
        #expect(!exists(nightsURL))
        #expect(!exists(ritualsURL))

        // Memory reset, so nothing is written back.
        #expect(snapshot.mind == nil)
        #expect(finder.visits.isEmpty && finder.found.isEmpty && finder.decisions.isEmpty && finder.places.isEmpty)
        #expect(nights.nights.isEmpty && nights.detected.isEmpty && nights.weatherCity == nil)
        #expect(nights.bedroom == SleepPlaceStore.Bedroom())
        #expect(nights.place(forNightEnding: day) == nil)
        #expect(rituals.rituals == TrackRitualStore.starter)
        #expect(rituals.done.isEmpty && rituals.undone.isEmpty)
        #expect(!rituals.isDone(daylight, on: day))

        // A relaunch reads nothing back.
        #expect(SleepPlaceFinder(url: visitsURL, manual: SleepPlaceStore(url: nightsURL, calendar: calendar), calendar: calendar).visits.isEmpty)
        #expect(TrackRitualStore(url: ritualsURL, calendar: calendar).done.isEmpty)
        #expect(LongevitySnapshotStore(url: snapshotURL, owner: { "device" }).mind == nil)
    }

    @Test("Erase data on this iPhone: the Journal, Track logs, moods and Explore reads go too, files and memory")
    func erasesTheDeviceInLocalMode() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "erase-device-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journalURL = folder.appending(path: "journal.json")
        let logURL = folder.appending(path: "track-log.json")
        let mindURL = folder.appending(path: "mind.json")
        let defaultsName = "erase-device-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let journal = JournalStore(url: journalURL, calendar: calendar)
        journal.toggle("meditation", on: day)
        journal.setFeeling(4, on: day)
        let logs = TrackLogStore(url: logURL, calendar: calendar)
        _ = logs.addDrink(.water, ml: 330, at: day)
        let mind = MindStore(url: mindURL)
        mind.add(MindMoodEntry(date: day, kind: .momentary, valence: 0.5, note: "Calm"))
        let interest = ExploreInterest(defaults: defaults)
        interest.noteVisit(.sleep, at: day)
        #expect(exists(journalURL) && exists(logURL) && !mind.moods.isEmpty && interest.log != ExploreInterestLog())

        LocalDataErasure.runOnDevice(
            journal: journal,
            snapshot: LongevitySnapshotStore(url: nil, owner: { "device" }),
            sleepPlaces: SleepPlaceFinder(url: nil, manual: SleepPlaceStore(url: nil, calendar: calendar), calendar: calendar),
            nights: SleepPlaceStore(url: nil, calendar: calendar),
            rituals: TrackRitualStore(url: nil, calendar: calendar),
            mind: mind,
            interest: interest,
            logs: logs
        )

        #expect(!exists(journalURL) && !exists(logURL))
        #expect(journal.day(day).isEmpty && journal.tags == JournalStore.starterTags)
        #expect(logs.drinks.isEmpty)
        #expect(mind.moods.isEmpty)
        #expect(interest.log == ExploreInterestLog())
        #expect(ExploreInterest(defaults: defaults).log == ExploreInterestLog())
        #expect(JournalStore(url: journalURL, calendar: calendar).day(day).isEmpty)
        #expect(TrackLogStore(url: logURL, calendar: calendar).drinks.isEmpty)
        #expect(MindStore(url: mindURL).moods.isEmpty)
    }
}
