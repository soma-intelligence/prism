//
//  MeetingHeadsUpTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Today's word before a meeting: only one starting within a day, the
/// likely tense one before the one that could be, the soonest first.
@Suite("Meetings: heads up")
struct MeetingHeadsUpTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func forecast(_ id: String, inHours hours: Double, likelihood: Double?) -> MeetingStressAnalysis.Forecast {
        let start = now.addingTimeInterval(hours * 3600)
        let event = MindCalendarEvent(id: id, title: id, calendarTitle: "Work", start: start, end: start.addingTimeInterval(1800))
        return MeetingStressAnalysis.Forecast(event: event, likelihood: likelihood, basis: .series, reason: "")
    }

    @Test("A likely tense meeting wins over a sooner one that could be")
    func likelyFirst() {
        let picked = MeetingHeadsUp.pick([forecast("could", inHours: 1, likelihood: 0.4),
                                          forecast("likely", inHours: 5, likelihood: 0.8)], now: now)
        #expect(picked?.event.id == "likely")
    }

    @Test("Nothing past a day, nothing calm, nothing already started")
    func outOfReach() {
        #expect(MeetingHeadsUp.pick([forecast("far", inHours: 30, likelihood: 0.9),
                                     forecast("calm", inHours: 2, likelihood: 0.1),
                                     forecast("past", inHours: -1, likelihood: 0.9),
                                     forecast("new", inHours: 2, likelihood: nil)], now: now) == nil)
    }

    @Test("The soonest of two likely ones")
    func soonest() {
        let picked = MeetingHeadsUp.pick([forecast("later", inHours: 8, likelihood: 0.9),
                                          forecast("sooner", inHours: 3, likelihood: 0.7)], now: now)
        #expect(picked?.event.id == "sooner")
    }

    // MARK: The notification

    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    /// 2026-10-26 at `hour`:`minute`, Paris.
    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute))!
    }

    func meeting(at start: Date, likelihood: Double?) -> MeetingStressAnalysis.Forecast {
        let event = MindCalendarEvent(id: "standup", title: "Standup", calendarTitle: "Work", start: start, end: start.addingTimeInterval(1800))
        return MeetingStressAnalysis.Forecast(event: event, likelihood: likelihood, basis: .series, reason: "4 of 5 times it ran above your usual.")
    }

    func alert(_ forecast: MeetingStressAnalysis.Forecast, now: Date, schedule: NotificationSchedule = NotificationSchedule()) -> PlannedNotification? {
        DataAlertRules.meetingHeadsUp(forecast, title: "Standup", reason: forecast.reason, schedule: schedule,
                                      prefs: NotificationPreferences(), now: now, calendar: paris)
    }

    @Test("Twenty minutes before, with the time on the 24 hour clock and a link to the meetings page")
    func twentyMinutesBefore() {
        let planned = alert(meeting(at: at(16), likelihood: 0.8), now: at(9))
        #expect(planned?.trigger == .at(at(15, 40)))
        #expect(planned?.title == "Standup at 16:00 is likely to run tense")
        #expect(planned?.link == .meetings)
        #expect(planned.map { SomaNotificationKind.kind(forIdentifier: $0.id) } == .dataAlert)
    }

    @Test("Inside the last twenty minutes it comes now; once begun, never")
    func lateOrStarted() {
        let soon = alert(meeting(at: at(16), likelihood: 0.5), now: at(15, 50))
        #expect(soon?.trigger == .at(at(15, 50).addingTimeInterval(1)))
        #expect(alert(meeting(at: at(16), likelihood: 0.9), now: at(16, 5)) == nil)
    }

    @Test("Calm, new, switched off or in quiet hours: no word")
    func silent() {
        #expect(alert(meeting(at: at(16), likelihood: 0.1), now: at(9)) == nil)
        #expect(alert(meeting(at: at(16), likelihood: nil), now: at(9)) == nil)
        var off = NotificationSchedule()
        off.meetingAlerts = false
        #expect(alert(meeting(at: at(16), likelihood: 0.9), now: at(9), schedule: off) == nil)
        // 07:00 lands in the default quiet hours (22:30 to 07:00).
        #expect(alert(meeting(at: at(7, 15), likelihood: 0.9), now: at(6)) == nil)
    }
}
