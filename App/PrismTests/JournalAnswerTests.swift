//
//  JournalAnswerTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The Journal's yes and no answers: a no is kept, a record written before
/// there were no answers still reads, and copying a day keeps what was
/// already answered.
@Suite("Journal answers")
@MainActor
struct JournalAnswerTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    @Test("Yes, no and clear each leave one answer or none")
    func answers() {
        let store = JournalStore(url: nil, calendar: calendar)
        store.answer("alcohol", true, on: day(2))
        #expect(store.day(day(2)).answer("alcohol") == true)
        store.answer("alcohol", false, on: day(2))
        #expect(store.day(day(2)).answer("alcohol") == false)
        #expect(!store.day(day(2)).tags.contains("alcohol"))
        store.answer("alcohol", nil, on: day(2))
        #expect(store.day(day(2)).answer("alcohol") == nil)
        #expect(store.day(day(2)).isEmpty)
    }

    @Test("A record from before the no answers decodes, every tag yes or unanswered")
    func decodesOldRecord() throws {
        let old = Data(#"{"tags":["alcohol"],"feeling":4}"#.utf8)
        let decoded = try JSONDecoder().decode(JournalDay.self, from: old)
        #expect(decoded.tags == ["alcohol"])
        #expect(decoded.declined.isEmpty)
        #expect(decoded.feeling == 4)

        let again = try JSONDecoder().decode(JournalDay.self, from: JSONEncoder().encode(
            JournalDay(tags: ["sauna"], declined: ["alcohol"], feeling: nil)))
        #expect(again.answer("alcohol") == false)
        #expect(again.answer("sauna") == true)
    }

    @Test("Copying a day brings its yes and no answers and keeps the target's own")
    func copyKeepsAnswers() {
        let store = JournalStore(url: nil, calendar: calendar)
        store.answer("alcohol", true, on: day(1))
        store.answer("late-meal", false, on: day(1))
        store.answer("sauna", true, on: day(1))
        store.answer("sauna", false, on: day(2))
        store.setFeeling(5, on: day(1))

        store.copyTags(from: day(1), to: day(2))
        let target = store.day(day(2))
        #expect(target.answer("alcohol") == true)
        #expect(target.answer("late-meal") == false)
        #expect(target.answer("sauna") == false)
        #expect(target.feeling == nil)
    }
}
