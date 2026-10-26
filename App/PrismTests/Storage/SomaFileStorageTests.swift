//
//  SomaFileStorageTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

@Suite("Local file persistence")
@MainActor
struct SomaFileStorageTests {
    @Test("Journal changes survive reopening their JSON file")
    func journalRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let url = directory.appending(path: "journal.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = Date(timeIntervalSince1970: 1_790_700_000)

        let store = JournalStore(url: url, calendar: calendar)
        store.toggle("meditation", on: day)
        store.setFeeling(5, on: day)
        store.setOffered(true, tag: "nap")
        store.questions.asksEnergy = true

        let reopened = JournalStore(url: url, calendar: calendar)
        #expect(reopened.day(day).tags == ["meditation"])
        #expect(reopened.day(day).feeling == 5)
        #expect(reopened.tags.first(where: { $0.id == "nap" })?.isOffered == true)
        #expect(reopened.questions.asksEnergy)
    }
}
