//
//  MindConnectionTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Connection: the three item UCLA loneliness scale (Hughes, Waite, Hawkley
/// and Cacioppo 2004), one item on purpose, and the week's time with people
/// from the calendar, the moods and the Journal.
@Suite("Mind connection")
@MainActor
struct MindConnectionTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    /// Sunday 25 October 2026 at `hour`, or a day before or after.
    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    @Test("The three items, three answers, 3 to 9")
    func uclaThreeItemRange() {
        #expect(MindInstrument.ucla3.items.count == 3)
        #expect(MindInstrument.ucla3.options == ["Hardly ever", "Some of the time", "Often"])
        #expect(LonelinessScore.score(answers: [0, 0, 0]) == 3)
        #expect(LonelinessScore.score(answers: [2, 2, 2]) == 9)
        #expect(LonelinessScore.score(answers: [1, 0, 2]) == 6)
        #expect(LonelinessScore.score(answers: [3, 0, 0]) == nil)
        // The assessment scores the same way.
        #expect(MindAssessment(instrument: .ucla3, date: at(12), answers: [1, 1, 1]).score == 6)
    }

    @Test("6 and over reads as lonely")
    func lonelyThreshold() {
        #expect(!LonelinessScore.isLonely(5))
        #expect(LonelinessScore.isLonely(6))
        #expect(LonelinessScore.isLonely(9))
        #expect(MindAssessment(instrument: .ucla3, date: at(12), answers: [0, 1, 1]).reading?.word == "Rarely lonely")
        #expect(MindAssessment(instrument: .ucla3, date: at(12), answers: [1, 1, 1]).reading?.word == "Often lonely")
    }

    @Test func partialNotScored() {
        #expect(LonelinessScore.score(answers: [1, 1]) == nil)
        #expect(MindAssessment(instrument: .ucla3, date: at(12), answers: [1, 1]).score == nil)
        #expect(MindAssessment(instrument: .purpose, date: at(12), answers: []).reading == nil)
    }

    @Test("Purpose is one item on six steps of agreement, read as a word")
    func purposeItem() {
        #expect(MindInstrument.purpose.items.count == 1)
        #expect(MindInstrument.purpose.options.count == 6)
        let agree = MindAssessment(instrument: .purpose, date: at(12), answers: [4])
        #expect(agree.reading?.word == "Moderately agree")
        #expect(!agree.needsCrisisCare)
    }

    @Test("Minutes with people this week, from events read as social")
    func socialCalendarMinutes() {
        let events = [
            MindCalendarEvent(id: "a", title: "Dinner with Léa", calendarTitle: "", start: at(19, day: -1), end: at(21, day: -1)),
            MindCalendarEvent(id: "b", title: "Budget review", calendarTitle: "", start: at(10, day: -2), end: at(11, day: -2)),
            MindCalendarEvent(id: "c", title: "Coffee with Sam", calendarTitle: "", start: at(9, day: -3), end: at(9, 30, day: -3)),
            // Eight days ago: last week.
            MindCalendarEvent(id: "d", title: "Drinks with friends", calendarTitle: "", start: at(20, day: -8), end: at(22, day: -8)),
        ]
        let social: Set<String> = ["a", "c", "d"]
        let week = ConnectionWeek.make(
            moods: [], events: events, calendarAllowed: true, journal: [:],
            now: at(12), calendar: calendar, category: { social.contains($0.id) ? .social : .meeting }
        )
        #expect(week.socialMinutes == 150)

        // No calendar access: a dash, not zero.
        let blind = ConnectionWeek.make(
            moods: [], events: [], calendarAllowed: false, journal: [:],
            now: at(12), calendar: calendar, category: { _ in .social }
        )
        #expect(blind.socialMinutes == nil)
    }

    @Test("Days with a social tag, and moods with people, this week")
    func journalTagsCount() {
        let journal: [Date: Set<String>] = [
            calendar.startOfDay(for: at(12, day: -1)): [SocialTag.sawFriends, "alcohol"],
            calendar.startOfDay(for: at(12, day: -2)): [SocialTag.calledFamily, SocialTag.volunteered],
            calendar.startOfDay(for: at(12, day: -3)): ["sauna"],
            calendar.startOfDay(for: at(12, day: -10)): [SocialTag.sawFriends],
        ]
        let moods = [
            MindMoodEntry(date: at(18, day: -1), kind: .momentary, valence: 0.5, associations: ["friends"]),
            MindMoodEntry(date: at(18, day: -2), kind: .momentary, valence: 0.2, associations: ["work"]),
            MindMoodEntry(date: at(18, day: -9), kind: .momentary, valence: 0.2, associations: ["family"]),
        ]
        let week = ConnectionWeek.make(
            moods: moods, events: [], calendarAllowed: false, journal: journal,
            now: at(12), calendar: calendar, category: { _ in .unknown }
        )
        #expect(week.taggedDays == 2)
        #expect(week.moodsWithPeople == 1)
        #expect(week.hasPeople)

        let quiet = ConnectionWeek.make(moods: [], events: [], calendarAllowed: false, journal: [:],
                                        now: at(12), calendar: calendar, category: { _ in .unknown })
        #expect(!quiet.hasPeople)
    }

    @Test("The evening asks yes or no about time with people, and writes the tag")
    func eveningQuestion() throws {
        let question = try #require(CheckInCatalog.evening.first { $0.id == "people" })
        #expect(question.kind == .yesNo)
        #expect(question.windows == [.evening])
        #expect(question.destination == .journalTag(SocialTag.timeWithPeople, day: .today))
        let starters = Set(JournalStore.starterTags.map(\.id))
        for tag in SocialTag.all { #expect(starters.contains(tag)) }
        // The oral tags stay.
        #expect(starters.contains(OralTag.gumsBleed))
    }

    @Test("The monthly reminder is off until asked for, then a month after the last check")
    func monthlyReminder() throws {
        let now = at(12)
        #expect(!NotificationSchedule().connectionReminders)
        var schedule = NotificationSchedule()
        schedule.connectionReminders = true
        let planned = MindQuestionnaireReminders.reminders(
            lastAssessment: nil, lastConnection: at(9, day: -5), schedule: schedule,
            prefs: NotificationPreferences(), now: now, calendar: calendar)
        let reminder = try #require(planned.first)
        #expect(planned.count == 1)
        #expect(reminder.link == .mindConnection)
        let fire = try #require(NotificationPlanner.nextFire(reminder.trigger, after: now, calendar: calendar))
        #expect(calendar.dateComponents([.month, .day, .hour], from: fire) == DateComponents(month: 11, day: 20, hour: 10))
    }

    @Test func storeKeepsConnectionChecks() {
        let store = MindStore(url: nil)
        #expect(MindConnectionCheck.lastDate(in: store) == nil)
        store.save(MindAssessment(instrument: .ucla3, date: at(9), answers: [1, 1, 0]))
        store.save(MindAssessment(instrument: .purpose, date: at(9, 1), answers: [5]))
        #expect(MindConnectionCheck.lastDate(in: store) == at(9))
        #expect(store.latest(.ucla3)?.score == 5)
    }
}
