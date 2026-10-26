//
//  ToolsStoreTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// What a person tells the tools (a shift, a trip, the supplements they take,
/// the screenings they have had) lives in one file on the phone. It has to
/// come back after a relaunch, and a file from an older build has to keep
/// everything it holds.
@Suite("Tools store")
@MainActor
struct ToolsStoreTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    let opened = Date(timeIntervalSince1970: 1_791_028_800)

    @Test("A tool is on until switched off, and its first visit is kept, not moved")
    func switchesAndVisits() {
        let store = ToolsStore(url: nil)
        #expect(ToolKind.allCases.allSatisfy { store.isOn($0) })
        store.setOn(false, .travel)
        #expect(!store.isOn(.travel))
        store.setOn(true, .travel)
        #expect(store.isOn(.travel))

        store.markOpened(.travel, now: opened)
        store.markOpened(.travel, now: opened.addingTimeInterval(86_400))
        #expect(store.record.since[.travel] == opened)
    }

    @Test("A day's stamp is its calendar date")
    func stamp() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 23, minute: 59))!
        #expect(ToolsStore.stamp(late, calendar: calendar) == "2026-03-09")
    }

    @Test("Everything entered survives a relaunch")
    func persistence() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "tools.json")
            let store = ToolsStore(url: url)
            store.setOn(false, .sunBudget)
            store.markOpened(.travel, now: opened)
            store.update {
                $0.skinType = 3
                $0.trip = TripPrefs(place: "Tokyo", timeZone: "Asia/Tokyo", departs: opened, flightHours: 13)
                $0.supplements = [SupplementItem(name: "Magnesium", dose: "300 mg")]
                $0.lifts = [LiftSet(exercise: "Squat", date: opened, reps: 5, kilograms: 80)]
                $0.forecasts["2026-10-04"] = 78
            }

            let reopened = ToolsStore(url: url)
            #expect(reopened.record == store.record)
        }
    }

    @Test("A change that changes nothing writes nothing")
    func noOpWrites() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "tools.json")
            let store = ToolsStore(url: url)
            store.setOn(true, .travel)
            #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
    }

    @Test("A file from a build that lacked some fields keeps the ones it has")
    func olderFile() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "tools.json")
            let store = ToolsStore(url: url)
            store.update {
                $0.supplements = [SupplementItem(name: "Vitamin D", dose: "1000 IU")]
                $0.skinType = 2
                $0.alarm.isOn = true
            }

            let written = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            var stored = try #require(written as? [String: Any])
            stored["forecasts"] = nil
            stored["lifts"] = nil
            stored["evening"] = ["closes": "late"]
            try JSONSerialization.data(withJSONObject: stored).write(to: url)

            let reopened = ToolsStore(url: url)
            #expect(reopened.record.supplements == store.record.supplements)
            #expect(reopened.record.skinType == 2)
            #expect(reopened.record.alarm.isOn)
            #expect(reopened.record.evening == EveningPrefs())
            #expect(reopened.record.lifts.isEmpty)
        }
    }

    @Test("A file that does not read opens an empty record")
    func unreadableFile() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "tools.json")
            try Data("[]".utf8).write(to: url)
            #expect(ToolsStore(url: url).record == ToolsStore.Record())
        }
    }
}
