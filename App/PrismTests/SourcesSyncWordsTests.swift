//
//  SourcesSyncWordsTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// The short words of the sources and sync page.
@Suite("Sources and sync words")
struct SourcesSyncWordsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Apple Health's line says what it feeds when on and why when off")
    func healthLine() {
        let on = SourcesSyncWords.health(.ready)
        #expect(on.value == "On" && on.tone == .good && on.hint.contains("sleep"))
        let off = SourcesSyncWords.health(.unavailable)
        #expect(off.value == "Off" && off.tone == .watch && off.hint == "Not on this device")
        #expect(SourcesSyncWords.head(.ready).tone == .good)
        #expect(SourcesSyncWords.head(.idle).tone == .watch)
    }

    @Test("Motion says why it is off")
    func motionLine() {
        #expect(SourcesSyncWords.motion(.authorized).tone == .good)
        let denied = SourcesSyncWords.motion(.denied)
        #expect(denied.value == "Off" && denied.hint.contains("Settings"))
        #expect(SourcesSyncWords.motion(.notDetermined).tone == .neutral)
    }

    @Test("What you add reads None until there is something")
    func addedLines() {
        #expect(SourcesSyncWords.blood(nil).value == "None")
        #expect(SourcesSyncWords.journal(days: 0).value == "None")
        #expect(SourcesSyncWords.journal(days: 1).value == "1 day")
        #expect(SourcesSyncWords.journal(days: 12).value == "12 days")
    }

    @Test("The last read is a time today, with a twelve hour clock's mark as the unit")
    func lastRead() {
        let now = date(20, 18)
        #expect(SourcesSyncWords.lastRead(nil, now: now, calendar: calendar).value == nil)
        let today = SourcesSyncWords.lastRead(date(20, 12, 41), now: now, calendar: calendar)
        #expect(today.value == "12:41")
        #expect(today.unit == "PM")
        #expect(SourcesSyncWords.lastRead(date(19, 12), now: now, calendar: calendar).value == "Yesterday")
    }

    @Test("Short words: no sentence on the page, no dashes in the info sheet")
    func shortWords() {
        let lines = [SourcesSyncWords.health(.ready), SourcesSyncWords.motion(.denied), SourcesSyncWords.blood(nil),
                     SourcesSyncWords.journal(days: 3)]
        for line in lines {
            #expect(!line.hint.hasSuffix("."))
            #expect(line.hint.split(separator: " ").count <= 6)
        }
        for section in SourcesSyncWords.about {
            #expect(!section.body.contains("\u{2014}") && !section.body.contains("\u{2013}"))
        }
    }
}
