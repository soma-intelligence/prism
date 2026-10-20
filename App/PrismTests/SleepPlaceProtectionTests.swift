//
//  SleepPlaceProtectionTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// A sleep visit wakes the app while the phone is locked. If the visits or
/// the nights file does not read then, the empty state that read left must
/// never be saved over it, and what arrives meanwhile joins the file once it
/// reads.
@MainActor
@Suite("Sleep places: a file that does not read", .serialized)
struct SleepPlaceProtectionTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let home = SleepPlaceStore.Place(name: "Home", latitude: 37.4443, longitude: -122.1598)

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sleep-protection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func setReadable(_ readable: Bool, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: readable ? 0o644 : 0o200], ofItemAtPath: url.path)
    }

    private func visit(daysAgo: Int, latitude: Double) -> SleepVisit {
        let evening = calendar.startOfDay(for: Date()).addingTimeInterval(Double(-daysAgo) * 86_400 + 20 * 3_600)
        return SleepVisit(arrival: evening, departure: evening.addingTimeInterval(11 * 3_600),
                          latitude: latitude, longitude: home.longitude, accuracy: 30)
    }

    @Test("Visits arriving while the file is unreadable never overwrite it, and merge once it reads")
    func visitsWaitAndMerge() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sleep-visits.json")
        let nights = SleepPlaceStore(url: nil, calendar: calendar)

        let seed = SleepPlaceFinder(url: url, manual: nights, calendar: calendar)
        seed.record(visit(daysAgo: 3, latitude: home.latitude))
        seed.record(visit(daysAgo: 2, latitude: home.latitude))
        let bytes = try Data(contentsOf: url)

        try setReadable(false, url)
        defer { try? setReadable(true, url) }
        let locked = SleepPlaceFinder(url: url, manual: nights, calendar: calendar)
        #expect(locked.isHoldingUnread)
        #expect(locked.visits.isEmpty)
        locked.record(visit(daysAgo: 1, latitude: home.latitude))
        locked.refresh(nights: [])

        try setReadable(true, url)
        #expect(try Data(contentsOf: url) == bytes)

        locked.reloadIfUnread()
        #expect(!locked.isHoldingUnread)
        #expect(locked.visits.count == 3)
        #expect(SleepPlaceFinder(url: url, manual: nights, calendar: calendar).visits.count == 3)
    }

    @Test("Nights, bedroom and city set while the file is unreadable never overwrite it, and merge once it reads")
    func nightsWaitAndMerge() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sleep-places.json")
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let away = SleepPlaceStore.Place(name: "Lake", latitude: 39.1, longitude: -120.0)

        let seed = SleepPlaceStore(url: url, calendar: calendar)
        seed.setPlace(home, forNightEnding: day)
        seed.bedroom = SleepPlaceStore.Bedroom(temperature: 18, isDark: true)
        seed.weatherCity = home
        let bytes = try Data(contentsOf: url)

        try setReadable(false, url)
        defer { try? setReadable(true, url) }
        let locked = SleepPlaceStore(url: url, calendar: calendar)
        #expect(locked.isHoldingUnread)
        locked.setPlace(away, forNightEnding: day.addingTimeInterval(86_400))
        locked.bedroom = SleepPlaceStore.Bedroom(temperature: 17, isDark: nil)

        try setReadable(true, url)
        #expect(try Data(contentsOf: url) == bytes)

        locked.reloadIfUnread()
        let reread = SleepPlaceStore(url: url, calendar: calendar)
        #expect(reread.place(forNightEnding: day) == home)
        #expect(reread.place(forNightEnding: day.addingTimeInterval(86_400)) == away)
        #expect(reread.bedroom == SleepPlaceStore.Bedroom(temperature: 17, isDark: true))
        #expect(reread.weatherCity == home)
    }

    @Test("A missing file is not held: the first change creates it")
    func missingFileIsCreated() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sleep-visits.json")
        let finder = SleepPlaceFinder(url: url, manual: SleepPlaceStore(url: nil, calendar: calendar), calendar: calendar)
        #expect(!finder.isHoldingUnread)
        finder.record(visit(daysAgo: 1, latitude: home.latitude))
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }
}
