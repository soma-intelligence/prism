//
//  MeetingDisplayTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// `MeetingDisplay`: how the meetings page names people, cleans titles,
/// groups days and words its verdicts. A fixed calendar and locale keep the
/// days and weekday names the same on every machine.
@Suite("Meeting display")
@MainActor
struct MeetingDisplayTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")

    /// Saturday 24 October 2026 at `hour`, or a day before or after.
    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func assessment(_ verdict: MeetingStressAnalysis.Verdict, rise: Double? = nil, day offset: Int = 0, hour: Int = 10, people: [String] = [], title: String = "Sync") -> MeetingStressAnalysis.Assessment {
        let event = MindCalendarEvent(
            id: "\(title)-\(offset)-\(hour)", title: title, calendarTitle: "Work",
            start: at(hour, day: offset), end: at(hour, 30, day: offset), attendees: people
        )
        return MeetingStressAnalysis.Assessment(
            event: event, verdict: verdict, confidence: 1,
            baseline: rise == nil ? nil : 70, baselineIsMeasured: true,
            stillHeartRate: rise.map { 70 + $0 }, heartRate: rise.map { 70 + $0 },
            steps: 20, movingShare: 0, workoutMinutes: 0, readings: 8
        )
    }

    // MARK: People

    @Test func anAddressReadsAsAName() {
        #expect(MeetingDisplay.personName("jeanpaul@augura.health") == "Jeanpaul")
        #expect(MeetingDisplay.personName("nicolas.martin@augura.health") == "Nicolas Martin")
        #expect(MeetingDisplay.personName("mailto:ana_costa2@gmail.com") == "Ana Costa")
        #expect(MeetingDisplay.personName("JEAN-PAUL@augura.health") == "Jean Paul")
    }

    @Test func aRealNameStaysAsWritten() {
        #expect(MeetingDisplay.personName("  Hana Sato ") == "Hana Sato")
        #expect(MeetingDisplay.personName("Philippe de Montfort") == "Philippe de Montfort")
    }

    @Test func peopleReadAsNamesWithACount() {
        let six = ["jeanpaul@augura.health", "a@x.io", "b@x.io", "c@x.io", "d@x.io", "e@x.io"]
        #expect(MeetingDisplay.people(six) == "Jeanpaul and 5 others")
        #expect(MeetingDisplay.people(["sam@x.io", "Alex"]) == "Sam and Alex")
        #expect(MeetingDisplay.people([]) == "")
    }

    @Test func aReasonNamesThePersonNotTheAddress() {
        let reason = "1 of 5 meetings with nicolas@augura.health ran above your usual."
        #expect(MeetingDisplay.namingPeople(in: reason) == "1 of 5 meetings with Nicolas ran above your usual.")
        #expect(MeetingDisplay.namingPeople(in: "Too few meetings like this one to say yet.") == "Too few meetings like this one to say yet.")
    }

    // MARK: Titles

    @Test func aBookingTitleBecomesTheOtherPerson() {
        #expect(MeetingDisplay.title("30 Minutes Meeting with Philippe Boulanger") == "Philippe Boulanger")
        #expect(MeetingDisplay.title("30 min with Alex (Jean Dupont)") == "Jean Dupont")
        #expect(MeetingDisplay.title("1 hour call with sam.lee@gmail.com") == "Sam Lee")
        #expect(MeetingDisplay.title("Meeting with Alex") == "Alex")
        #expect(MeetingDisplay.title("Invitation: 15 min with Ines") == "Ines")
    }

    @Test func aBareBookingTitleReadsAsWhoItIsWith() {
        #expect(MeetingDisplay.title("30 Minute Meeting", attendees: ["camille.roux@augura.health"]) == "Camille Roux")
        #expect(MeetingDisplay.title("30 Minute Meeting") == "Meeting")
    }

    @Test func anOrdinaryTitleIsLeftAlone() {
        #expect(MeetingDisplay.title("Augura Brain: status & next steps") == "Augura Brain: status & next steps")
        #expect(MeetingDisplay.title("Coffee with   Sam") == "Coffee with Sam")
        #expect(MeetingDisplay.title("Design review") == "Design review")
        #expect(MeetingDisplay.title("   ") == "Meeting")
    }

    // MARK: Days

    @Test func daysAreTitledByDistanceFromToday() {
        let now = at(15)
        #expect(MeetingDisplay.dayTitle(at(9), now: now, calendar: calendar, locale: locale) == "Today")
        #expect(MeetingDisplay.dayTitle(at(9, day: -1), now: now, calendar: calendar, locale: locale) == "Yesterday")
        #expect(MeetingDisplay.dayTitle(at(9, day: 1), now: now, calendar: calendar, locale: locale) == "Tomorrow")
        #expect(MeetingDisplay.dayTitle(at(9, day: -2), now: now, calendar: calendar, locale: locale) == "Thu")
        #expect(MeetingDisplay.dayTitle(at(9, day: -8), now: now, calendar: calendar, locale: locale).contains("16"))
    }

    @Test func itemsGroupUnderTheirDayInTimelineOrder() {
        let items = [at(14, day: -1), at(9, day: -1), at(11), at(8)]
        let newest = MeetingDisplay.days(items, start: { $0 }, newestFirst: true, calendar: calendar)
        #expect(newest.count == 2)
        #expect(newest[0].items == [at(8), at(11)])
        #expect(newest[1].items == [at(9, day: -1), at(14, day: -1)])
        let oldest = MeetingDisplay.days(items, start: { $0 }, newestFirst: false, calendar: calendar)
        #expect(oldest.first?.day == calendar.startOfDay(for: at(9, day: -1)))
    }

    // MARK: Verdict

    @Test func theWeekLeadsWhenItHasReadMeetings() {
        let assessments = [
            assessment(.calm, rise: 2, day: -1), assessment(.calm, rise: 4, day: -2),
            assessment(.stressful, rise: 15, day: -3), assessment(.active, rise: 20, day: -3, hour: 16),
            assessment(.stressful, rise: 18, day: -20),
        ]
        let summary = MeetingDisplay.summary(assessments, now: at(12), calendar: calendar)
        #expect(summary.span == .week)
        #expect(summary.read == 3)
        #expect(summary.stressful == 1)
        #expect(summary.meanRise == 7)
        #expect(MeetingDisplay.headline(summary) == "Some meetings ran tense this week.")
        #expect(MeetingDisplay.reason(summary) == "1 of 3 ran above the hour before.")
    }

    @Test func aQuietWeekFallsBackToTheMonth() {
        let summary = MeetingDisplay.summary([assessment(.calm, rise: 1, day: -12)], now: at(12), calendar: calendar)
        #expect(summary.span == .month)
        #expect(MeetingDisplay.headline(summary) == "Meetings ran calm lately.")
        #expect(MeetingDisplay.reason(summary) == "None ran above the hour before.")
    }

    @Test func nothingReadSaysSo() {
        let summary = MeetingDisplay.summary([assessment(.unknown)], now: at(12), calendar: calendar)
        #expect(summary.read == 0)
        #expect(summary.share == nil)
        #expect(MeetingDisplay.headline(summary) == "No meetings read yet.")
    }

    @Test func theExpandedRowExplainsItsVerdict() {
        #expect(MeetingDisplay.explanation(assessment(.stressful, rise: 14.4)) == "Sitting still, your heart ran 14 bpm above the hour before.")
        #expect(MeetingDisplay.explanation(assessment(.calm, rise: 2)) == "Your heart stayed within 8 bpm of the hour before.")
        var walk = assessment(.active, rise: 22)
        walk.workoutMinutes = 20
        #expect(MeetingDisplay.explanation(walk) == "Your heart rose while you moved, so the walking explains it. A workout covered 20 min of it.")
    }

    // MARK: Footnote

    /// The count that gates a link is per person or series: many meetings
    /// with many people link nobody, and the footnote says how close the
    /// nearest one is rather than the total.
    @Test func theFootnoteCountsMeetingsWithTheSamePerson() {
        let spread = (0..<29).map { assessment(.calm, rise: 1, day: -($0 % 20), hour: 8 + $0 % 10, people: ["p\($0)@x.io"], title: "Call \($0)") }
        var history = MeetingStressAnalysis.history(spread, calendar: calendar)
        history.series = [:]
        let note = MeetingDisplay.footnote(history)
        #expect(note.text == "No one stands out yet. Mind links a person or a series after 3 meetings together; the closest has 1.")
        #expect(note.progress.map { abs($0 - 1.0 / 3) < 0.001 } == true)
    }

    @Test func theFootnoteDropsItsBarOncePeopleCanBeJudged() {
        let alex = (0..<4).map { assessment(.calm, rise: 1, day: -$0, people: ["alex@x.io"], title: "Call \($0)") }
        let note = MeetingDisplay.footnote(MeetingStressAnalysis.history(alex, calendar: calendar))
        #expect(note.progress == nil)
        #expect(note.text.hasPrefix("No one stands out:"))
    }

    // MARK: Mornings and afternoons

    @Test func theHalvesVerdictNamesTheHigherHalf() {
        let afternoons = MindMeetingStress.Halves(meetings: 10, morning: 40, afternoon: 52)
        #expect(MeetingDisplay.lean(afternoons) == .afternoons)
        #expect(MeetingDisplay.halvesVerdict(afternoons) == "Afternoons run 30% higher")
        let even = MindMeetingStress.Halves(meetings: 10, morning: 28, afternoon: 28)
        #expect(MeetingDisplay.halvesVerdict(even) == "Mornings and afternoons run alike")
        let mornings = MindMeetingStress.Halves(meetings: 4, morning: 50, afternoon: 40)
        #expect(MeetingDisplay.halvesVerdict(mornings) == "Mornings run 25% higher")
        let lone = MindMeetingStress.Halves(meetings: 2, morning: 30, afternoon: nil)
        #expect(MeetingDisplay.lean(lone) == nil)
        #expect(MeetingDisplay.halvesVerdict(lone) == "No afternoon meetings read yet")
    }
}
