//
//  ToolsEveningCloseTests.swift
//  PrismTests
//
//  Evening Close, the digital curfew: the close time from bedtime and sleep
//  debt, the windows it keeps, the schedule with its days and exceptions, and
//  the stats read off the logged sessions. Plus the deep work planner, whose
//  choice has to land in the free part of a real day.
//

import Foundation
import Testing
@testable import Prism

private func approx(_ a: Double?, _ b: Double, _ tolerance: Double = 0.0001) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

// MARK: - Close time and windows

@Suite("Tools: Evening Close time")
struct ToolsEveningCloseTimeTests {

    typealias Close = SomaTools.EveningClose

    func inputs(windDown: Double? = 22.5,
                wake: Double? = 7,
                peak: (Double, Double)? = (9.5, 12)) -> Close.TriggerInputs {
        Close.TriggerInputs(windDownHour: windDown, wakeHour: wake,
                            deepWorkStartHour: peak?.0, deepWorkEndHour: peak?.1,
                            sleepDebtHours: 0)
    }

    // MARK: The debt shift

    @Test func noDebtLeavesTheCloseWhereTheDayPlanPutIt() {
        #expect(approx(Close.closeHour(windDownHour: 22.5, sleepDebtHours: 0), 22.5))
    }

    /// Below the floor nothing moves. A quarter hour of debt is noise.
    @Test func debtUnderTheFloorMovesNothing() {
        #expect(approx(Close.closeHour(windDownHour: 22.5, sleepDebtHours: 1.9), 22.5))
    }

    @Test func debtPullsTheCloseEarlier() {
        // 3 h of debt: one hour past the floor, so half an hour earlier.
        #expect(approx(Close.closeHour(windDownHour: 22.5, sleepDebtHours: 3), 22.0))
        #expect(Close.debtShiftMinutes(sleepDebtHours: 3) == 30)
    }

    /// Capped at one hour.
    @Test func theShiftIsCapped() {
        #expect(approx(Close.closeHour(windDownHour: 22.5, sleepDebtHours: 40), 21.5))
        #expect(Close.debtShiftMinutes(sleepDebtHours: 40) == 60)
    }

    /// A bank of sleep must not push the close LATER.
    @Test func aSleepBankDoesNotPushTheCloseLater() {
        #expect(approx(Close.closeHour(windDownHour: 22.5, sleepDebtHours: -5), 22.5))
    }

    /// A wind down just after midnight, shifted back, lands the evening before.
    @Test func theShiftWrapsPastMidnight() {
        #expect(approx(Close.closeHour(windDownHour: 0.5, sleepDebtHours: 4), 23.5))
    }

    @Test func noWindDownMeansNoClose() {
        #expect(Close.closeHour(windDownHour: nil, sleepDebtHours: 3) == nil)
    }

    @Test func closeFromBedtimeStartsWindDownFortyFiveMinutesEarly() {
        #expect(approx(Close.closeHour(bedtimeHour: 23), 22.25))
        #expect(approx(Close.closeHour(bedtimeHour: 0.5), 23.75))
        #expect(approx(Close.closeHour(bedtimeHour: 23, sleepDebtHours: 3), 21.75))
    }

    // MARK: Which windows exist

    @Test func bothTriggersOffProduceNothing() {
        #expect(Close.triggerWindows(curfewEnabled: false, deepWorkEnabled: false, inputs: inputs()).isEmpty)
    }

    @Test func theCurfewRunsFromCloseToWake() {
        let w = Close.triggerWindows(curfewEnabled: true, deepWorkEnabled: false, inputs: inputs())
        #expect(w.count == 1)
        #expect(w.first?.kind == .curfew)
        #expect(approx(w.first?.startHour, 22.5))
        #expect(approx(w.first?.endHour, 7))
        #expect(approx(w.first?.lengthHours, 8.5))
    }

    @Test func theDeepWorkWindowFollowsThePeak() {
        let w = Close.triggerWindows(curfewEnabled: false, deepWorkEnabled: true, inputs: inputs())
        #expect(w.count == 1)
        #expect(w.first?.kind == .deepWork)
        #expect(approx(w.first?.startHour, 9.5))
    }

    @Test func bothOnProduceBoth() {
        #expect(Close.triggerWindows(curfewEnabled: true, deepWorkEnabled: true, inputs: inputs()).count == 2)
    }

    /// A trigger switched on with nothing to read is not an error and not a
    /// window.
    @Test func aTriggerWithNoReadingProducesNoWindow() {
        #expect(Close.triggerWindows(curfewEnabled: true, deepWorkEnabled: true,
                                     inputs: inputs(windDown: nil, peak: nil)).isEmpty)
    }

    @Test func aWindowUnderTheMinimumIsDropped() {
        let tight = Close.TriggerInputs(deepWorkStartHour: 9.0, deepWorkEndHour: 9.1)
        #expect(Close.triggerWindows(curfewEnabled: false, deepWorkEnabled: true, inputs: tight).isEmpty)
    }

    @Test func labelsReadAsClockAndDuration() {
        #expect(Close.clockLabel(22.5) == "22:30")
        #expect(Close.clockLabel(24) == "00:00")
        #expect(Close.durationLabel(hours: 8.5) == "8h 30")
        #expect(Close.durationLabel(hours: 0.75) == "45 min")
    }
}

// MARK: - Schedule and stats

@Suite("Tools: Evening Close schedule")
struct ToolsEveningCloseScheduleTests {

    typealias Close = SomaTools.EveningClose

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Tuesday 29 September 2026, 12:00 UTC.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))! }

    func evening(_ daysAgo: Int, hour: Double) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(hour * 3600)
    }

    func schedule(weekdays: Set<Int> = Close.Schedule.allWeekdays) -> Close.Schedule {
        Close.Schedule(isEnabled: true, closeHour: 22, openHour: 7, weekdays: weekdays, followsBedtime: false)
    }

    /// A session closed at `hour` on the evening `daysAgo`, opened at 07:00.
    func closed(_ daysAgo: Int, at hour: Double,
                reason: Close.Session.EndReason = .completed) -> Close.Session {
        Close.Session(startedAt: evening(daysAgo, hour: hour),
                      endedAt: evening(daysAgo - 1, hour: 7),
                      endReason: reason)
    }

    // MARK: Schedule

    @Test func aDisabledScheduleClosesNothing() {
        var s = schedule()
        s.isEnabled = false
        #expect(s.window(on: now, calendar: calendar) == nil)
    }

    @Test func weekdaysGateTheEvening() {
        // 29 September 2026 is a Tuesday, weekday 3.
        #expect(calendar.component(.weekday, from: now) == 3)
        #expect(schedule(weekdays: [3]).isScheduled(on: now, calendar: calendar))
        #expect(!schedule(weekdays: [1, 7]).isScheduled(on: now, calendar: calendar))
    }

    @Test func anExceptionCanSkipOrMoveOneEvening() {
        var s = schedule()
        let key = Close.dayKey(now, calendar: calendar)
        #expect(key == "2026-09-29")
        s.setException(Close.Exception(dayKey: key, skip: true))
        #expect(!s.isScheduled(on: now, calendar: calendar))

        s.setException(Close.Exception(dayKey: key, closeHour: 23.5))
        #expect(s.exceptions.count == 1, "one exception per evening, the latest wins")
        #expect(approx(s.window(on: now, calendar: calendar)?.startHour, 23.5))

        s.removeException(dayKey: key)
        #expect(approx(s.window(on: now, calendar: calendar)?.startHour, 22))
    }

    @Test func followingBedtimeDerivesTheCloseHour() {
        var s = schedule()
        s.followsBedtime = true
        #expect(approx(s.window(on: now, bedtimeHour: 23, calendar: calendar)?.startHour, 22.25))
        // No bedtime known: the stored hour stands.
        #expect(approx(s.window(on: now, calendar: calendar)?.startHour, 22))
    }

    @Test func anEveningClosingAfterMidnightStaysOnItsEvening() {
        let interval = Close.interval(closeHour: 0.5, openHour: 7, evening: now, calendar: calendar)
        let dayStart = calendar.startOfDay(for: now)
        #expect(interval.start == dayStart.addingTimeInterval(24.5 * 3600))
        #expect(interval.end == dayStart.addingTimeInterval(31 * 3600))
    }

    @Test func theScheduleSurvivesARoundTripAndDecodesLeniently() throws {
        var s = schedule(weekdays: [2, 3, 4])
        s.setException(Close.Exception(dayKey: "2026-10-01", skip: true, note: "Late dinner"))
        let decoded = try JSONDecoder().decode(Close.Schedule.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)

        let partial = try JSONDecoder().decode(Close.Schedule.self, from: Data(#"{"closeHour":21}"#.utf8))
        #expect(partial.closeHour == 21)
        #expect(partial.weekdays == Close.Schedule.allWeekdays)
        #expect(!partial.isEnabled)
    }

    @Test func pruningDropsPastExceptionsOnly() {
        var s = schedule()
        s.setException(Close.Exception(dayKey: "2026-09-20", skip: true))
        s.setException(Close.Exception(dayKey: "2026-10-02", skip: true))
        s.pruneExceptions(before: now, calendar: calendar)
        #expect(s.exceptions.map(\.dayKey) == ["2026-10-02"])
    }

    // MARK: Sessions

    @Test func elapsedStopsAtTheEndDate() {
        let s = closed(1, at: 22)
        #expect(s.elapsed(at: now) == 9 * 3600)
    }

    @Test func theEscapeHatchIsRecordedAsAbandoned() {
        #expect(Close.manualStopReason(isEmergency: true) == .abandoned)
        #expect(Close.manualStopReason(isEmergency: false) == .completed)
    }

    @Test func aTimedSessionClosesItselfAtItsOpenTime() {
        let running = Close.Session(startedAt: evening(1, hour: 22), endsAt: evening(0, hour: 7))
        #expect(Close.forcedEnd(now: evening(0, hour: 6), running: running) == nil)
        #expect(Close.forcedEnd(now: evening(0, hour: 7), running: running) == .completed)
        #expect(running.remaining(at: evening(0, hour: 6)) == 3600)
    }

    // MARK: Days closed on time

    @Test func aCloseWithinTheGraceIsOnTime() {
        let outcome = Close.outcome(on: evening(1, hour: 0), schedule: schedule(),
                                    sessions: [closed(1, at: 22.2)], now: now, calendar: calendar)
        #expect(outcome == .closedOnTime)
    }

    @Test func closingEarlyCountsAsOnTime() {
        let outcome = Close.outcome(on: evening(1, hour: 0), schedule: schedule(),
                                    sessions: [closed(1, at: 21)], now: now, calendar: calendar)
        #expect(outcome == .closedOnTime)
    }

    @Test func aCloseAfterTheGraceIsLate() {
        let outcome = Close.outcome(on: evening(1, hour: 0), schedule: schedule(),
                                    sessions: [closed(1, at: 23)], now: now, calendar: calendar)
        #expect(outcome == .closedLate)
    }

    @Test func theEmergencyExitMarksTheEveningOpenedEarly() {
        let outcome = Close.outcome(on: evening(1, hour: 0), schedule: schedule(),
                                    sessions: [closed(1, at: 22, reason: .abandoned)], now: now, calendar: calendar)
        #expect(outcome == .openedEarly)
    }

    @Test func tonightIsPendingAndAPastEmptyEveningIsMissed() {
        #expect(Close.outcome(on: now, schedule: schedule(), sessions: [], now: now, calendar: calendar) == .pending)
        #expect(Close.outcome(on: evening(1, hour: 0), schedule: schedule(), sessions: [],
                              now: now, calendar: calendar) == .missed)
    }

    @Test func theStreakStepsOverTonightAndUnscheduledEvenings() {
        // Tuesday today. Monday closed, Sunday off the schedule, Saturday and
        // Friday closed, Thursday missed.
        let s = schedule(weekdays: [2, 3, 4, 5, 6, 7])
        let sessions = [closed(1, at: 22), closed(3, at: 21.9), closed(4, at: 22.1)]
        #expect(Close.streak(endingOn: now, schedule: s, sessions: sessions, calendar: calendar) == 3)
    }

    @Test func aLateCloseBreaksTheStreak() {
        let sessions = [closed(1, at: 22), closed(2, at: 23.5), closed(3, at: 22)]
        #expect(Close.streak(endingOn: now, schedule: schedule(), sessions: sessions, calendar: calendar) == 1)
    }

    @Test func theWeekSummaryCountsTheSameDaysAsTheBars() {
        let sessions = [closed(1, at: 22), closed(2, at: 22, reason: .abandoned), closed(3, at: 22),
                        closed(10, at: 22)]
        let summary = Close.summary(endingOn: now, schedule: schedule(), sessions: sessions, calendar: calendar)
        #expect(summary.sessionCount == 3)
        #expect(summary.emergencyExits == 1)
        #expect(summary.daysClosedOnTime == 2)
        // Six decided evenings (tonight is pending).
        #expect(summary.scheduledDays == 6)
        #expect(summary.streak == 1)
        #expect(summary.closedSeconds == 3 * 9 * 3600)

        let records = Close.dayRecords(days: 7, endingOn: now, schedule: schedule(),
                                       sessions: sessions, calendar: calendar)
        #expect(records.count == 7)
        #expect(records.last?.outcome == .pending)
        #expect(records[records.count - 2].closedMinutes == 540)
    }
}

// MARK: - Deep work planner

/// The planner of the deep work window. A badly chosen window does not print a
/// wrong number, it protects the wrong hours: the four cases below are the
/// ways that choice can go wrong.
@Suite("Tools: Deep work planner")
struct ToolsAirlockDeepWorkTests {

    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))! }

    func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }

    func agenda(_ spans: [(Double, Double)]) -> SomaTools.AirlockAgenda {
        SomaTools.AirlockAgenda(day: day,
                                events: spans.map { SomaTools.AirlockAgenda.Event(start: at($0.0), end: at($0.1)) },
                                calendar: calendar)
    }

    func window(_ start: Double, _ end: Double, _ spans: [(Double, Double)]) -> SomaTools.AirlockDeepWorkPlanner.Outcome {
        SomaTools.AirlockDeepWorkPlanner.window(peakStartHour: start, peakEndHour: end,
                                                agenda: agenda(spans), day: day, calendar: calendar)
    }

    /// Empty agenda: the band comes out UNCHANGED. Empty also means "no
    /// access", so shrinking here would act on information nobody has.
    @Test func emptyAgendaLeavesTheBandAlone() {
        #expect(window(9, 13, []) == .band(startHour: 9, endHour: 13))
    }

    /// A meeting in the middle: the window folds onto the longest free stretch.
    @Test func narrowsToTheLongestFreeStretch() {
        // 9 to 13 with a meeting 10 to 10.5: 10.5 to 13 (150 min) beats 9 to 10.
        #expect(window(9, 13, [(10, 10.5)]) == .band(startHour: 10.5, endHour: 13))
    }

    /// Band taken end to end: NO window, and the caller must say so.
    @Test func bookedOutWhenNothingClearsTheFloor() {
        #expect(window(9, 13, [(9, 11), (11.25, 13)]) == .bookedOut)
    }

    /// A peak band shorter than the usable block is not punished for being
    /// short.
    @Test func shortBandIsNotPunishedForBeingShort() {
        #expect(window(14, 15, [(9, 10)]) == .band(startHour: 14, endHour: 15))
    }

    /// A degenerate or inverted band is left alone: no guessing.
    @Test func degenerateBandIsLeftAlone() {
        #expect(window(13, 13, [(9, 10)]) == .band(startHour: 13, endHour: 13))
    }

    @Test func declinedAndAllDayEventsAreNotBusyTime() {
        let a = SomaTools.AirlockAgenda(day: day, events: [
            .init(start: at(10), end: at(11), accepted: false),
            .init(start: at(0), end: at(24), isAllDay: true)
        ], calendar: calendar)
        #expect(a.isEmpty)
    }
}
