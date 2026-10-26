//
//  GlobalLaneTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// The app wide logic: activity status, reminders, the calendar month, chat
/// history, programs and share cards.
@Suite("Global lane")
@MainActor
struct GlobalLaneTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }

    func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: Activity status

    @Test("The five older statuses fold into Soma's four")
    func olderStatusesMapIn() {
        #expect(ActivityStatus(storedName: "active") == .training)
        #expect(ActivityStatus(storedName: "sick") == .unwell)
        #expect(ActivityStatus(storedName: "injured") == .unwell)
        #expect(ActivityStatus(storedName: "vacation") == .resting)
        #expect(ActivityStatus(storedName: "travel") == .travelling)
        #expect(ActivityStatus(storedName: "resting") == .resting)
        #expect(ActivityStatus(storedName: "nonsense") == nil)
    }

    @Test("A day reads the last change made on or before it, one per day")
    func statusHistory() {
        var changes: [ActivityStatusChange] = []
        changes = ActivityStatusHistory.recording(.unwell, at: day(2026, 9, 10, 9), in: changes, calendar: calendar)
        changes = ActivityStatusHistory.recording(.resting, at: day(2026, 9, 10, 20), in: changes, calendar: calendar)
        changes = ActivityStatusHistory.recording(.training, at: day(2026, 9, 14), in: changes, calendar: calendar)
        #expect(changes.count == 2)
        #expect(ActivityStatusHistory.status(on: day(2026, 9, 9), changes: changes, calendar: calendar) == .training)
        #expect(ActivityStatusHistory.status(on: day(2026, 9, 10, 1), changes: changes, calendar: calendar) == .resting)
        #expect(ActivityStatusHistory.status(on: day(2026, 9, 13), changes: changes, calendar: calendar) == .resting)
        #expect(ActivityStatusHistory.status(on: day(2026, 9, 20), changes: changes, calendar: calendar) == .training)
    }

    @Test("Unwell or resting holds a hard session back in Ask")
    func statusShapesTraining() {
        let unwell = Ask.answer(to: "Can I train hard tomorrow?", facts: AskFacts(status: .unwell))
        #expect(unwell.lead == "I\u{2019}d keep tomorrow easy.")
        let ready = AskFacts(variability: "60", sleep: "7:40", status: .resting)
        #expect(Ask.answer(to: "Can I train hard tomorrow?", facts: ready).rest?.contains("planned rest") == true)
    }

    // MARK: Reminders

    @Test("Only switched on reminders with something behind them are planned")
    func reminderPlan() {
        var prefs = NotificationPreferences()
        prefs.quietHours = false
        let planned = ReminderPlan.reminders(prefs, lastMealBy: ClockTime(hour: 20, minute: 30))
        #expect(planned.map(\.id) == [ReminderPlan.Identifier.morning, ReminderPlan.Identifier.evening, ReminderPlan.Identifier.lastMeal])
        #expect(planned.last?.time == ClockTime(hour: 20))
        #expect(planned.last?.title == "Eat before 20:30")

        prefs.morningCheckIn = false
        prefs.eveningNudges = false
        #expect(ReminderPlan.reminders(prefs, lastMealBy: ClockTime(hour: 20)).map(\.id) == [ReminderPlan.Identifier.evening])
    }

    @Test("A reminder inside quiet hours waits for them to end")
    func quietHoursMoveReminders() {
        var prefs = NotificationPreferences()
        prefs.quietFrom = ClockTime(hour: 22, minute: 30)
        prefs.quietUntil = ClockTime(hour: 7)
        prefs.morningTime = ClockTime(hour: 6, minute: 15)
        prefs.eveningTime = ClockTime(hour: 23)
        let planned = ReminderPlan.reminders(prefs, lastMealBy: ClockTime(hour: 20, minute: 30))
        #expect(planned.first { $0.id == ReminderPlan.Identifier.morning }?.time == ClockTime(hour: 7))
        #expect(planned.first { $0.id == ReminderPlan.Identifier.evening }?.time == ClockTime(hour: 7))
        #expect(planned.first { $0.id == ReminderPlan.Identifier.lastMeal }?.time == ClockTime(hour: 20))
    }

    @Test("A window can run past midnight")
    func clockWindows() {
        let from = ClockTime(hour: 22), until = ClockTime(hour: 7)
        #expect(ClockTime(hour: 23).isInside(from: from, until: until))
        #expect(ClockTime(hour: 3).isInside(from: from, until: until))
        #expect(!ClockTime(hour: 7).isInside(from: from, until: until))
        #expect(!ClockTime(hour: 12).isInside(from: from, until: until))
        #expect(ClockTime(hour: 0, minute: 10).adding(minutes: -30) == ClockTime(hour: 23, minute: 40))
        #expect(ClockTime(hour: 7, minute: 5).text == "07:05")
    }

    // MARK: Calendar

    @Test("A month starts on the chosen weekday and scores fall on their day")
    func calendarMonth() {
        let today = day(2026, 9, 16)
        // Thirty days ending today: the last is today's, the one before yesterday's.
        var series = [Double?](repeating: nil, count: 30)
        series[29] = 81
        series[28] = 76.4
        let month = CalendarMonth.make(
            month: today, today: today, series: series,
            journalDays: [calendar.startOfDay(for: day(2026, 9, 3))],
            status: { $0 == self.calendar.startOfDay(for: self.day(2026, 9, 2)) ? .unwell : .training },
            calendar: calendar
        )
        let days = month.weeks.flatMap { $0 }
        #expect(days.count % 7 == 0)
        // 1 September 2026 is a Tuesday: one leading Monday from August.
        #expect(days.first?.isInMonth == false)
        #expect(days[1].number == 1)
        #expect(days.first { $0.isToday }?.score == 81)
        #expect(days.first { $0.isInMonth && $0.number == 15 }?.score == 76)
        #expect(days.first { $0.isInMonth && $0.number == 14 }?.score == nil)
        #expect(days.first { $0.isInMonth && $0.number == 17 }?.isFuture == true)
        #expect(days.first { $0.isInMonth && $0.number == 3 }?.hasJournal == true)
        #expect(days.first { $0.isInMonth && $0.number == 2 }?.status == .unwell)
        #expect(days.first { $0.isInMonth && $0.number == 4 }?.status == nil)
    }

    // MARK: Chat history

    @Test("Conversations group by this week, earlier this month, then by month")
    func historySections() {
        let now = day(2026, 9, 16)
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let sections = ChatHistorySections.group([
            (a, day(2026, 9, 15)), (b, day(2026, 9, 3)), (c, day(2026, 8, 29)), (d, day(2026, 9, 16, 8)),
        ], now: now, calendar: calendar)
        #expect(sections.map(\.ids) == [[d, a], [b], [c]])
        #expect(sections.first?.title == "This week")
    }

    @Test("A conversation is kept and read back whole")
    func historyStore() {
        let store = AskHistoryStore(inMemory: true)
        let turn = StoredAskTurn(question: "How did I sleep?", asked: Date(), lead: "You slept 7:12.", rest: nil,
                                 signals: 1, sources: ["sleep"], moveTitle: nil, moveReason: nil, moveAspect: nil,
                                 isModelMissing: false)
        let id = store.append(turn, to: nil)
        #expect(id != nil)
        store.append(turn, to: id)
        #expect(store.conversations.count == 1)
        #expect(store.conversation(id!)?.turns.count == 2)
        #expect(store.conversation(id!)?.title == "How did I sleep?")
        store.delete(id!)
        #expect(store.conversations.isEmpty)
    }

    // MARK: Programs and shortcuts

    @Test("Program progress counts from the day you joined")
    func programProgress() {
        let program = ProgramCatalog.program("zone-two-base")!
        let enrollment = ProgramEnrollment(programID: program.id, joined: day(2026, 9, 1, 20))
        let progress = ProgramProgress.of(enrollment, program: program, on: day(2026, 9, 16, 8), calendar: calendar)
        #expect(progress.day == 16)
        #expect(progress.label(for: program) == "Week 3 of 8")

        let short = ProgramCatalog.program("sleep-debt-reset")!
        let shortProgress = ProgramProgress.of(ProgramEnrollment(programID: short.id, joined: day(2026, 9, 12)),
                                               program: short, on: day(2026, 9, 16), calendar: calendar)
        #expect(shortProgress.label(for: short) == "Day 5 of 14")
        #expect(!shortProgress.isFinished)
    }

    @Test("Shortcuts keep their order, hide what is off, and append new ones")
    func shortcutOrder() {
        var prefs = ShortcutPreferences()
        prefs.order = [.sleep, .meal]
        prefs.hidden = [.meal]
        #expect(prefs.offered.first == .sleep)
        #expect(!prefs.offered.contains(.meal))
        #expect(prefs.fullOrder.count == LogShortcut.allCases.count)
    }

    // MARK: Share cards

    @Test("With exact numbers off a card says only which way it went")
    func shareHeadline() {
        let card = ShareCard(kind: .sleep, score: 81, trend: .up, series: [], detail: "7:12 asleep")
        #expect(card.headline(exact: true) == "81")
        #expect(card.headline(exact: false) == "Better than usual")
        #expect(ShareCard.cards(from: nil, sleepClock: nil).isEmpty)
    }
}
