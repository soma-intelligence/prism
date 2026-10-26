//
//  PulseTodayPageTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

@Suite("Today's words and numbers")
struct PulseTodayPageTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23)) ?? .now
        return day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func page(now: Date, name: String? = "Alex", status: HealthDashboard.Status = .ready) -> PulseTodayPage {
        PulseTodayPage(today: nil, status: status, scores: nil, insights: .empty, peak: nil,
                       firstName: name, now: now, calendar: calendar)
    }

    @Test("The greeting follows the hour and the first name")
    func greeting() {
        #expect(page(now: at(7, 42)).greeting == "Good morning, Alex.")
        #expect(page(now: at(14)).greeting == "Good afternoon, Alex.")
        #expect(page(now: at(21), name: nil).greeting == "Good evening.")
    }

    @Test("Before the first read the page says it is reading, never inventing a day")
    func pending() {
        let loading = page(now: at(8), status: .loading)
        #expect(loading.isPending)
        #expect(loading.summary == "Reading last night from Apple Health.")
    }

    @Test("Durations hold one line and read as hours and minutes")
    func durations() {
        #expect(TodayFormat.duration(seconds: 7 * 3600 + 12 * 60) == "7\u{00A0}h\u{00A0}12")
        #expect(TodayFormat.duration(text: "7:05") == "7\u{00A0}h\u{00A0}05")
        #expect(TodayFormat.span(seconds: 28 * 60) == "28 min")
        #expect(TodayFormat.like("14.2", 13.6) == "13.6")
        #expect(TodayFormat.like("52", 51.4) == "51")
        #expect(TodayFormat.sentence("resting heart rate is above your usual") == "Resting heart rate is above your usual.")
    }

    @Test("Past moments are done and the first one to come is next")
    func staged() {
        let items = [
            SomaPlanItem(id: "bed", title: "In bed", detail: nil, state: .later, start: at(23, 15)),
            SomaPlanItem(id: "wake", title: "Woke up", detail: nil, state: .later, start: at(7, 21)),
            SomaPlanItem(id: "focus", title: "Focus window", detail: nil, state: .later, start: at(10, 30), end: at(13)),
            SomaPlanItem(id: "coffee", title: "Last coffee", detail: nil, state: .later, start: at(14)),
        ]
        let staged = PulseTodayPage.staged(items, now: at(11))
        #expect(staged.map(\.id) == ["wake", "focus", "coffee", "bed"])
        #expect(staged.map(\.state) == [.done, .next, .later, .later])
    }
}
