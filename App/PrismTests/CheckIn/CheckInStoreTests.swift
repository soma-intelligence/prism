//
//  CheckInStoreTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// "Soma asks" keeps one record a day of what it asked and what was put
/// off, and whether the app has been opened before. A record that lands on
/// the wrong day asks a question twice; one that survives too long grows the
/// file without end; a first launch noted twice would open a question on the
/// very first screen.
@Suite("Check-in store")
@MainActor
struct CheckInStoreTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    @Test("A day nothing was asked on reads as an empty record")
    func emptyDay() {
        let store = CheckInStore(url: nil, calendar: calendar)
        #expect(store.record(on: at(9)) == CheckInDayRecord())
        #expect(store.stamp(at(9)) == "2026-10-03")
    }

    @Test("A change lands on the day it was made, whatever the hour")
    func updateByDay() {
        let store = CheckInStore(url: nil, calendar: calendar)
        store.update(on: at(8)) { $0.skipped.insert("mood") }
        store.update(on: at(22)) { $0.asked["energy"] = "How is your energy?" }

        let record = store.record(on: at(0))
        #expect(record.skipped == ["mood"])
        #expect(record.asked == ["energy": "How is your energy?"])
        #expect(record.isSettled("mood"))
        #expect(store.record(on: at(9, day: -1)) == CheckInDayRecord())
    }

    @Test("Only the thirty newest days are kept")
    func prune() {
        let store = CheckInStore(url: nil, calendar: calendar)
        for offset in -34...0 {
            store.update(on: at(9, day: offset)) { $0.skipped.insert("mood") }
        }
        #expect(store.days.count == CheckInStore.keptDays)
        #expect(store.record(on: at(9, day: -30)) == CheckInDayRecord())
        #expect(store.record(on: at(9, day: -29)).skipped == ["mood"])
        #expect(store.record(on: at(9)).skipped == ["mood"])
    }

    @Test("The first launch is noted once, and a relaunch remembers it")
    func firstLaunch() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "check-in.json")
            let store = CheckInStore(url: url, calendar: calendar)
            #expect(!store.hasLaunchedBefore)
            #expect(store.noteLaunch())
            #expect(!store.noteLaunch())

            let reopened = CheckInStore(url: url, calendar: calendar)
            #expect(reopened.hasLaunchedBefore)
            #expect(!reopened.noteLaunch())
        }
    }

    @Test("The day's record survives a relaunch")
    func persistence() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "check-in.json")
            let store = CheckInStore(url: url, calendar: calendar)
            store.update(on: at(9)) { $0.asked["energy"] = "How is your energy?" }

            let reopened = CheckInStore(url: url, calendar: calendar)
            #expect(reopened.record(on: at(20)).asked == ["energy": "How is your energy?"])
        }
    }

    @Test("A file that does not read opens an empty store that has never launched")
    func unreadableFile() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "check-in.json")
            try Data("not json".utf8).write(to: url)
            let store = CheckInStore(url: url, calendar: calendar)
            #expect(store.days.isEmpty)
            #expect(!store.hasLaunchedBefore)
        }
    }
}
