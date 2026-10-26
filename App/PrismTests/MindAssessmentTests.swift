//
//  MindAssessmentTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// PHQ-9 and GAD-7: the bands of the papers that made them, nothing scored
/// from a questionnaire left half way, and item 9 answered above "Not at
/// all" read as a reason to show the support lines first.
@Suite("Mind questionnaires")
@MainActor
struct MindAssessmentTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Answers on `instrument` that add up to `total`, filled from the first
    /// item at the top answer, so every total in range has one.
    func answers(_ instrument: MindInstrument, summing total: Int) -> [Int] {
        var left = total
        return instrument.items.indices.map { _ in
            let step = min(left, instrument.maxAnswer)
            left -= step
            return step
        }
    }

    func assessment(_ instrument: MindInstrument, _ total: Int, on day: Date? = nil) -> MindAssessment {
        MindAssessment(instrument: instrument, date: day ?? date(2026, 10, 1), answers: answers(instrument, summing: total))
    }

    @Test("The instruments hold the official items and four answers")
    func instruments() {
        #expect(MindInstrument.phq9.items.count == 9)
        #expect(MindInstrument.gad7.items.count == 7)
        #expect(MindInstrument.phq9.options == ["Not at all", "Several days", "More than half the days", "Nearly every day"])
        #expect(MindInstrument.gad7.options == MindInstrument.phq9.options)
        #expect(MindInstrument.phq9.items[0] == "Little interest or pleasure in doing things")
        #expect(MindInstrument.gad7.items[0] == "Feeling nervous, anxious or on edge")
        #expect(MindInstrument.phq9.maxScore == 27)
        #expect(MindInstrument.gad7.maxScore == 21)
    }

    /// Kroenke, Spitzer and Williams 2001: 5, 10, 15 and 20 are the cut points.
    @Test func phq9Bands() {
        let expected: [(Int, MindSeverity)] = [
            (0, .minimal), (4, .minimal), (5, .mild), (9, .mild), (10, .moderate), (14, .moderate),
            (15, .moderatelySevere), (19, .moderatelySevere), (20, .severe), (27, .severe),
        ]
        for (total, band) in expected {
            let taken = assessment(.phq9, total)
            #expect(taken.score == total)
            #expect(taken.severity == band, "PHQ-9 \(total)")
        }
    }

    /// Spitzer, Kroenke, Williams and Löwe 2006: 5, 10 and 15. GAD-7 has no
    /// moderately severe band.
    @Test func gad7Bands() {
        let expected: [(Int, MindSeverity)] = [
            (0, .minimal), (4, .minimal), (5, .mild), (9, .mild), (10, .moderate), (14, .moderate), (15, .severe), (21, .severe),
        ]
        for (total, band) in expected {
            let taken = assessment(.gad7, total)
            #expect(taken.score == total)
            #expect(taken.severity == band, "GAD-7 \(total)")
        }
    }

    @Test func item9TriggersCrisis() {
        let taken = MindAssessment(instrument: .phq9, date: date(2026, 10, 1), answers: [0, 0, 0, 0, 0, 0, 0, 0, 1])
        #expect(taken.needsCrisisCare)
        #expect(taken.severity == .minimal)
        #expect(!MindAssessment(instrument: .phq9, date: date(2026, 10, 1), answers: Array(repeating: 3, count: 8) + [0]).needsCrisisCare)
        // GAD-7 has no item 9, and its seventh item is not about harm.
        #expect(!MindAssessment(instrument: .gad7, date: date(2026, 10, 1), answers: Array(repeating: 3, count: 7)).needsCrisisCare)
    }

    @Test func partialIsNotScored() {
        let draft = MindAssessment(instrument: .phq9, date: date(2026, 10, 1), answers: Array(repeating: 1, count: 8))
        #expect(!draft.isComplete)
        #expect(draft.score == nil)
        #expect(draft.severity == nil)
        // An answer off the scale is not a score either.
        let off = MindAssessment(instrument: .gad7, date: date(2026, 10, 1), answers: [0, 0, 0, 0, 0, 0, 4])
        #expect(off.score == nil)
    }

    @Test func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "mind-assessment-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = MindStore(url: url)
        #expect(store.assessments.isEmpty)
        let older = assessment(.phq9, 12, on: date(2026, 9, 1))
        let newer = assessment(.phq9, 6, on: date(2026, 10, 1))
        store.save(newer)
        store.save(older)
        // Left half way: kept as a draft, never in the history.
        store.save(MindAssessment(instrument: .gad7, date: date(2026, 10, 2), answers: [1, 2]))

        let read = MindStore(url: url)
        #expect(read.assessments.count == 2)
        #expect(read.latest(.phq9) == newer)
        #expect(read.latest(.gad7) == nil)
        #expect(read.draft(.gad7)?.answers == [1, 2])

        // Finishing the draft moves it into the history and clears it.
        let finished = MindAssessment(instrument: .gad7, date: date(2026, 10, 2), answers: [1, 2, 0, 0, 0, 0, 0])
        read.save(finished)
        #expect(read.draft(.gad7) == nil)
        #expect(MindStore(url: url).latest(.gad7)?.score == 3)
    }

    @Test("An older file without questionnaires still opens")
    func olderFileOpens() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "mind-old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"consent":{"stateOfMind":true,"calendar":true,"voice":false},"moods":[],"checkIns":[],"notes":[],"corrections":{}}"#.utf8).write(to: url)
        let store = MindStore(url: url)
        #expect(store.assessments.isEmpty)
        #expect(store.draft(.phq9) == nil)
    }

    // MARK: Every two weeks

    @Test("The two week reminder is off until asked for")
    func reminderOptIn() {
        let now = date(2026, 10, 25)
        #expect(!NotificationSchedule().assessmentReminders)
        #expect(MindQuestionnaireReminders.reminders(
            lastAssessment: date(2026, 10, 20), lastConnection: nil, schedule: NotificationSchedule(),
            prefs: NotificationPreferences(), now: now, calendar: calendar).isEmpty)

        var silent = NotificationSchedule()
        silent.assessmentReminders = true
        silent.isEnabled = false
        #expect(MindQuestionnaireReminders.reminders(
            lastAssessment: date(2026, 10, 20), lastConnection: nil, schedule: silent,
            prefs: NotificationPreferences(), now: now, calendar: calendar).isEmpty)
    }

    /// Fourteen days after the last one, at 10:00 local, across the change
    /// of time on 1 November 2026 in New York.
    @Test("Every two weeks, at 10:00 wherever the phone is")
    func reminderFortnightly() throws {
        var schedule = NotificationSchedule()
        schedule.assessmentReminders = true
        let now = date(2026, 10, 25)
        let planned = MindQuestionnaireReminders.reminders(
            lastAssessment: date(2026, 10, 20, hour: 8), lastConnection: nil, schedule: schedule,
            prefs: NotificationPreferences(), now: now, calendar: calendar)
        #expect(planned.count == 1)
        let reminder = try #require(planned.first)
        #expect(reminder.kind == .assessment)
        #expect(SomaNotificationKind.kind(forIdentifier: reminder.id) == .assessment)
        #expect(reminder.link == .mindAssessments)
        let fire = try #require(NotificationPlanner.nextFire(reminder.trigger, after: now, calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                == DateComponents(year: 2026, month: 11, day: 3, hour: 10, minute: 0))

        // Overdue: the next 10:00 still ahead, never a date in the past.
        let late = MindQuestionnaireReminders.reminders(
            lastAssessment: date(2026, 9, 1), lastConnection: nil, schedule: schedule,
            prefs: NotificationPreferences(), now: date(2026, 10, 25, hour: 11), calendar: calendar)
        let lateFire = try #require(late.first.flatMap { NotificationPlanner.nextFire($0.trigger, after: date(2026, 10, 25, hour: 11), calendar: calendar) })
        #expect(calendar.dateComponents([.month, .day, .hour], from: lateFire) == DateComponents(month: 10, day: 26, hour: 10))
    }
}
