//
//  MindCalendarInsightsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthScoring
@testable import Prism

/// A fixed clock: Tuesday 2026-10-20 in UTC.
private enum Clock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    static let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!

    /// `hours` from today's midnight (negative for the evening before).
    static func at(_ hours: Double, from day: Date = today) -> Date {
        day.addingTimeInterval(hours * 3_600)
    }

    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }
}

@Suite("Mind: the calendar against stress")
struct MindCalendarInsightsTests {
    private let calendar = Clock.calendar

    private func event(_ day: Date, _ from: Double, _ to: Double, _ title: String) -> MindCalendarEvent {
        MindCalendarEvent(id: "\(day)-\(from)", title: title, calendarTitle: "", start: Clock.at(from, from: day), end: Clock.at(to, from: day))
    }

    /// A curve with `morning` from 08:00 to noon and `afternoon` to 18:00.
    private func curve(_ day: Date, morning: Double, afternoon: Double) -> MindStressDayCurve {
        var samples = [Double?](repeating: nil, count: MindStressDayCurve.buckets)
        for index in 16..<24 { samples[index] = morning }
        for index in 24..<36 { samples[index] = afternoon }
        return MindStressDayCurve(day: day, samples: samples)
    }

    /// Four weeks before today: Tuesdays and Thursdays with four back to back
    /// afternoon meetings, the other weekdays with one morning standup.
    private func month(busyAfternoon: Double = 50, quietAfternoon: Double = 20) -> (curves: [MindStressDayCurve], events: [MindCalendarEvent]) {
        var curves: [MindStressDayCurve] = []
        var events: [MindCalendarEvent] = []
        for offset in -28 ... -1 {
            let day = Clock.day(offset)
            let weekday = calendar.component(.weekday, from: day)
            let busy = weekday == 3 || weekday == 5
            curves.append(curve(day, morning: 20, afternoon: busy ? busyAfternoon : quietAfternoon))
            guard weekday != 1, weekday != 7 else { continue }
            events.append(event(day, 9.5, 9.75, "Standup"))
            if busy {
                events.append(event(day, 13, 14, "Design review"))
                events.append(event(day, 14, 14.5, "1:1"))
                events.append(event(day, 14.5, 15.5, "Planning meeting"))
                events.append(event(day, 16, 16.5, "Budget call"))
            }
        }
        return (curves, events)
    }

    @Test("A day is counted: meetings, afternoon meetings, back to back, minutes")
    func dayCounts() {
        let (curves, events) = month()
        let days = MindCalendarInsights.days(curves: curves, events: events, hrvByDay: [:], now: Clock.today, calendar: calendar)
        let tuesday = days.first { calendar.component(.weekday, from: $0.day) == 3 }!
        #expect(tuesday.meetings == 5)
        #expect(tuesday.afternoonMeetings == 4)
        #expect(tuesday.backToBack == 2, "14:00 and 14:30 follow at once; 16:00, half an hour on, does not")
        #expect(tuesday.busyMinutes == 15 + 60 + 30 + 60 + 30)
        #expect(tuesday.afternoonStress == 50)
        #expect(tuesday.stress == Double(8 * 20 + 12 * 50) / 20)
        #expect(!tuesday.isWeekend)
        #expect(days.count == 28, "Today is not over, so it is left out")
    }

    @Test("Busy afternoons that run higher make a line, strongest first, no title in it")
    func busyAfternoons() {
        let (curves, events) = month()
        let lines = MindCalendarInsights.lines(curves: curves, events: events, hrv: [], now: Clock.today, calendar: calendar)
        let first = lines.first
        #expect(first?.kind == .busyAfternoons)
        #expect(first?.text == "Afternoons with three or more meetings line up with higher stress.")
        #expect(first?.detail == "30 points higher, 8 days against 12")
        #expect(first?.isCost == true)
        #expect(lines.count <= MindCalendarInsights.limit)
        #expect(lines == lines.sorted { $0.strength >= $1.strength })
        for line in lines {
            for title in ["Standup", "Design review", "1:1", "Planning", "Budget"] {
                #expect(!line.text.contains(title) && !line.detail.contains(title))
            }
        }
    }

    @Test("A gap under the floor, or a side under three days, says nothing")
    func floors() {
        let (curves, events) = month(busyAfternoon: 25, quietAfternoon: 20)
        #expect(MindCalendarInsights.lines(curves: curves, events: events, hrv: [], now: Clock.today, calendar: calendar).isEmpty)

        let busy = month()
        let twoBusyDays = busy.curves.filter { $0.day >= Clock.day(-6) }
        let lines = MindCalendarInsights.lines(curves: twoBusyDays, events: busy.events, hrv: [], now: Clock.today, calendar: calendar)
        #expect(!lines.contains { $0.kind == .busyAfternoons }, "Two busy afternoons are not a pattern")
    }

    @Test("Weekends never stand in for a quiet weekday")
    func weekendsLeftOut() {
        var (curves, events) = month()
        // Calm weekends, and weekdays that are all alike: nothing to say.
        curves = curves.map { curve in
            let weekend = calendar.isDateInWeekend(curve.day)
            return self.curve(curve.day, morning: 20, afternoon: weekend ? 5 : 50)
        }
        events = events.filter { calendar.component(.weekday, from: $0.start) == 3 || calendar.component(.weekday, from: $0.start) == 5 }
        let lines = MindCalendarInsights.lines(curves: curves, events: events, hrv: [], now: Clock.today, calendar: calendar)
        #expect(!lines.contains { $0.kind == .busyAfternoons })
    }

    private func day(_ offset: Int, meetings: Int, afternoonMeetings: Int = 0, afternoon: Double? = nil,
                     nextHRV: Double? = nil) -> MindCalendarInsights.Day {
        MindCalendarInsights.Day(day: Clock.day(offset), isWeekend: calendar.isDateInWeekend(Clock.day(offset)),
                                 meetings: meetings, afternoonMeetings: afternoonMeetings, busyMinutes: 0, backToBack: 0,
                                 hasBreak: false, stress: nil, afternoonStress: afternoon, nextHRV: nextHRV)
    }

    /// The weekdays of the four weeks before today.
    private var weekdays: [Int] {
        (-28 ... -1).filter { !calendar.isDateInWeekend(Clock.day($0)) }
    }

    @Test("The weekday whose meeting afternoons run highest is named")
    func weekday() {
        let days = weekdays.map { offset in
            let tuesday = calendar.component(.weekday, from: Clock.day(offset)) == 3
            return day(offset, meetings: 1, afternoonMeetings: 1, afternoon: tuesday ? 50 : 20)
        }
        let line = MindCalendarInsights.weekdayLine(days, calendar: calendar)
        #expect(line?.text == "Tuesday afternoons with meetings line up with your highest stress.")
        #expect(line?.isCost == true)

        let even = weekdays.map { day($0, meetings: 1, afternoonMeetings: 1, afternoon: 30) }
        #expect(MindCalendarInsights.weekdayLine(even, calendar: calendar) == nil)
    }

    @Test("HRV the morning after busy days, against light ones, in milliseconds")
    func nextMorningHRV() {
        let days = weekdays.map { offset in
            let busy = [3, 5].contains(calendar.component(.weekday, from: Clock.day(offset)))
            return day(offset, meetings: busy ? 5 : 1, nextHRV: busy ? 42 : 50)
        }
        let lines = MindCalendarInsights.insights(days, calendar: calendar)
        #expect(lines.first?.kind == .nextMorningHRV)
        #expect(lines.first?.text == "After days with four or more meetings, your HRV the next morning runs 8 ms lower.")

        let close = weekdays.map { offset in
            let busy = [3, 5].contains(calendar.component(.weekday, from: Clock.day(offset)))
            return day(offset, meetings: busy ? 5 : 1, nextHRV: busy ? 49 : 50)
        }
        #expect(MindCalendarInsights.insights(close, calendar: calendar).isEmpty, "1 ms is under the floor")
    }

    @Test("A day's HRV is the mean of its readings")
    func hrvByDay() {
        let byDay = MindCalendarInsights.hrvByDay([
            (start: Clock.at(2), value: 40), (start: Clock.at(6), value: 50), (start: Clock.at(30), value: 70),
        ], calendar: calendar)
        #expect(byDay[Clock.today] == 45)
        #expect(byDay[Clock.day(1)] == 70)
    }

    @Test("Time with people or movement on a day that runs calmer makes a line")
    func breaks() {
        var (curves, events) = month(busyAfternoon: 40, quietAfternoon: 40)
        curves = curves.map { curve in
            calendar.component(.weekday, from: curve.day) == 4 ? self.curve(curve.day, morning: 10, afternoon: 15) : curve
        }
        for curve in curves where calendar.component(.weekday, from: curve.day) == 4 {
            events.append(event(curve.day, 12.5, 13.5, "Coffee with Sam"))
        }
        let lines = MindCalendarInsights.lines(curves: curves, events: events, hrv: [], now: Clock.today, calendar: calendar)
        let line = lines.first { $0.kind == .breaks }
        #expect(line?.isCost == false)
        #expect(line?.text == "Days with time for people or movement on the calendar run calmer.")
    }
}
