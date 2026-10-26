//
//  MeetingStressAnalysisTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// `MeetingStressAnalysis`: a meeting's heart against the hour before it,
/// with the walking set aside, then grouped and forecast. A fixed calendar
/// keeps the days the same on every machine.
@Suite("Meeting stress analysis")
@MainActor
struct MeetingStressAnalysisTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    /// Tuesday 29 September 2026 at `hour`:`minute`, or a day before or after.
    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func meeting(_ title: String, _ hour: Int, day offset: Int = 0, with people: [String] = [], series: String? = nil, id: String? = nil) -> MindCalendarEvent {
        MindCalendarEvent(
            id: id ?? "\(title)-\(offset)-\(hour)", title: title, calendarTitle: "Work",
            start: at(hour, day: offset), end: at(hour + 1, day: offset),
            attendees: people, seriesID: series
        )
    }

    /// A heart reading every five minutes from `start` to `end`.
    func heart(_ bpm: Double, from start: Date, to end: Date) -> [HealthReading] {
        stride(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, by: 300).map { time in
            let date = Date(timeIntervalSince1970: time)
            return HealthReading(metric: "hr", value: bpm, unit: .none, start: date, end: date)
        }
    }

    /// `perMinute` steps, one sample a minute, from `start` to `end`.
    func walking(_ perMinute: Double, from start: Date, to end: Date) -> [HealthReading] {
        stride(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, by: 60).map { time in
            let date = Date(timeIntervalSince1970: time)
            return HealthReading(metric: "steps", value: perMinute, unit: .none, start: date, end: date.addingTimeInterval(60))
        }
    }

    /// One meeting at 10:00 on day `offset`, with 62 bpm the hour before and
    /// `bpm` during it, sitting unless `walks`.
    func read(_ event: MindCalendarEvent, bpm: Double, walks: Bool = false) -> MeetingStressAnalysis.Assessment {
        let before = heart(62, from: event.start.addingTimeInterval(-3600), to: event.start.addingTimeInterval(-300))
        let during = heart(bpm, from: event.start, to: event.end)
        let steps = walks ? walking(90, from: event.start, to: event.end) : []
        return MeetingStressAnalysis.assess(event, heartRate: before + during, steps: steps, workouts: [], resting: 55)
    }

    // MARK: One meeting

    @Test func aRiseWhileStillIsStressful() {
        let result = read(meeting("Board update", 10), bpm: 80)
        #expect(result.verdict == .stressful)
        #expect(result.baselineIsMeasured)
        #expect(result.baseline == 62)
        #expect(result.rise == 18)
        #expect(result.steps == 0)
        #expect(result.confidence > 0.5)
    }

    @Test func aRiseWithStepsIsMovement() {
        let result = read(meeting("Walking one to one", 10), bpm: 95, walks: true)
        #expect(result.verdict == .active)
        #expect(result.movingShare == 1)
        #expect(result.steps > 1000)
        #expect(!result.isRead)
    }

    @Test func aRiseInsideAWorkoutIsMovement() {
        let event = meeting("Standup", 10)
        let hearts = heart(62, from: at(9), to: at(9, 55)) + heart(120, from: at(10), to: at(11))
        let run = HealthReading(metric: "workout", value: 37, unit: .none, start: at(10), end: at(11))
        let result = MeetingStressAnalysis.assess(event, heartRate: hearts, steps: [], workouts: [run], resting: 55)
        #expect(result.verdict == .active)
        #expect(result.workoutMinutes == 60)
    }

    @Test func aStillRiseCountsEvenWhenPartOfTheMeetingWasWalked() {
        let event = meeting("Hard review", 10)
        let hearts = heart(62, from: at(9), to: at(9, 55)) + heart(84, from: at(10), to: at(11))
        // Walking the first quarter hour only.
        let steps = walking(100, from: at(10), to: at(10, 15))
        let result = MeetingStressAnalysis.assess(event, heartRate: hearts, steps: steps, workouts: [], resting: 55)
        #expect(result.verdict == .stressful)
        #expect((result.movingShare ?? 0) > 0)
    }

    @Test func aFlatHeartIsCalm() {
        let result = read(meeting("Design review", 10), bpm: 64)
        #expect(result.verdict == .calm)
        #expect(result.isRead)
    }

    @Test func tooFewReadingsIsUnknown() {
        let event = meeting("Design review", 10)
        let hearts = heart(62, from: at(9), to: at(9, 55)) + heart(90, from: at(10), to: at(10, 10))
        let result = MeetingStressAnalysis.assess(event, heartRate: hearts, steps: [], workouts: [], resting: 55)
        #expect(result.verdict == .unknown)
        #expect(result.confidence == 0)
    }

    @Test func withoutTheHourBeforeRestingStandsIn() {
        let event = meeting("Budget", 10)
        let result = MeetingStressAnalysis.assess(event, heartRate: heart(80, from: at(10), to: at(11)), steps: [], workouts: [], resting: 55)
        #expect(!result.baselineIsMeasured)
        #expect(result.baseline == 65)
        #expect(result.verdict == .stressful)
        #expect(result.confidence < read(event, bpm: 80).confidence)
    }

    @Test func anEarlierMeetingIsKeptOutOfTheBaseline() {
        let first = meeting("Tense call", 9)
        let second = meeting("Next call", 10)
        // The hour before the second call lies inside the first, so none of
        // it is a baseline and the second call falls back to resting.
        let hearts = heart(85, from: at(9), to: at(10)) + heart(80, from: at(10), to: at(11))
        let results = MeetingStressAnalysis.assessDay([first, second], heartRate: hearts, steps: [], workouts: [], resting: 55)
        #expect(results[1].baselineIsMeasured == false)
        #expect(results[1].verdict == .stressful)
    }

    @Test func emptyAndBrokenInputsNeverCrash() {
        let event = meeting("Anything", 10)
        let empty = MeetingStressAnalysis.assess(event, heartRate: [], steps: [], workouts: [], resting: nil)
        #expect(empty.verdict == .unknown)
        #expect(empty.readings == 0)

        let broken = [Double.nan, .infinity, -.infinity, 0, 900].map {
            HealthReading(metric: "hr", value: $0, unit: .none, start: at(10, 10), end: at(10, 10))
        }
        let brokenSteps = [HealthReading(metric: "steps", value: .nan, unit: .none, start: at(10), end: at(10, 5))]
        let result = MeetingStressAnalysis.assess(event, heartRate: broken, steps: brokenSteps, workouts: [], resting: .nan)
        #expect(result.verdict == .unknown)
        #expect(result.baseline == nil)
        #expect(result.steps == 0)

        let zeroLength = MindCalendarEvent(id: "z", title: "Blip", calendarTitle: "", start: at(10), end: at(10))
        #expect(MeetingStressAnalysis.assess(zeroLength, heartRate: heart(70, from: at(9), to: at(11)), steps: [], workouts: [], resting: 55).verdict == .unknown)

        let history = MeetingStressAnalysis.history([], calendar: calendar)
        #expect(history.overall == nil)
        #expect(history.raisers.isEmpty)
        #expect(MeetingStressAnalysis.forecasts([], history: history, now: at(8), calendar: calendar).isEmpty)
        #expect(MeetingStressAnalysis.forecast(event, history: history, calendar: calendar).level == .unknown)
    }

    // MARK: Links

    @Test func twoTenseMeetingsAreNotYetALink() {
        let tense = (1...2).map { read(meeting("Sync", 10, day: -$0, with: ["Alex"]), bpm: 82) }
        let calm = (3...8).map { read(meeting("Other", 15, day: -$0, with: ["Sam"]), bpm: 63) }
        let history = MeetingStressAnalysis.history(tense + calm, calendar: calendar)
        let alex = history.attendees[MeetingStressAnalysis.attendeeKey("Alex")]
        #expect(alex?.read == 2)
        #expect(alex?.hasEvidence == false)
        #expect(history.raisers.isEmpty)
        // Too few to forecast from Alex either.
        let next = MeetingStressAnalysis.forecast(meeting("New thing", 16, day: 1, with: ["Alex"]), history: history, calendar: calendar)
        #expect(next.basis != .attendee)
    }

    @Test func fourOfFiveWithOnePersonIsALink() {
        let alex = [82.0, 84, 80, 83, 63].enumerated().map { index, bpm in
            read(meeting("Topic \(index)", 10, day: -index - 1, with: ["Alex Martin"]), bpm: bpm)
        }
        let others = (6...12).map { read(meeting("Planning \($0)", 15, day: -$0, with: ["Sam"]), bpm: 63) }
        let history = MeetingStressAnalysis.history(alex + others, calendar: calendar)
        let raisers = history.raisers
        #expect(raisers.first?.kind == .attendee)
        #expect(raisers.first?.title == "Alex Martin")
        #expect(raisers.first?.stressful == 4)
        #expect(raisers.first?.read == 5)
        #expect(!raisers.contains { $0.title == "Sam" })

        let next = MeetingStressAnalysis.forecast(meeting("Fresh topic", 11, day: 2, with: ["Alex Martin", "Sam"]), history: history, calendar: calendar)
        #expect(next.basis == .attendee)
        #expect(next.level == .likely)
        #expect(next.reason == "4 of 5 meetings with Alex Martin ran above your usual.")
    }

    @Test func movingMeetingsDoNotCountAsRead() {
        let walks = (1...4).map { read(meeting("Walk and talk", 10, day: -$0, with: ["Kim"]), bpm: 95, walks: true) }
        let history = MeetingStressAnalysis.history(walks, calendar: calendar)
        let kim = history.attendees[MeetingStressAnalysis.attendeeKey("Kim")]
        #expect(kim?.read == 0)
        #expect(kim?.active == 4)
        #expect(history.raisers.isEmpty)
    }

    // MARK: Forecast

    @Test func theSeriesComesBeforeThePeople() {
        // The weekly review has always been calm; Alex, met elsewhere, has
        // always run tense. The review is the better guide to itself.
        let reviews = (1...4).map { read(meeting("Weekly review", 10, day: -$0 * 7, with: ["Alex"], series: "review"), bpm: 63) }
        let other = (1...4).map { read(meeting("Escalation \($0)", 15, day: -$0, with: ["Alex"]), bpm: 85) }
        let history = MeetingStressAnalysis.history(reviews + other, calendar: calendar)
        let next = MeetingStressAnalysis.forecast(meeting("Weekly review", 10, day: 7, with: ["Alex"], series: "review"), history: history, calendar: calendar)
        #expect(next.basis == .series)
        #expect(next.level == .unlikely)
        #expect(next.reason == "0 of 4 times, this meeting ran above your usual.")
    }

    @Test func theSeriesFollowsItsIDThroughARename() {
        let reviews = (1...3).map { read(meeting("Q3 review", 10, day: -$0 * 7, series: "s1"), bpm: 82) }
        let history = MeetingStressAnalysis.history(reviews, calendar: calendar)
        let next = MeetingStressAnalysis.forecast(meeting("Q4 review", 10, day: 7, series: "s1"), history: history, calendar: calendar)
        #expect(next.basis == .series)
        #expect(next.level == .likely)
    }

    @Test func thePartOfDayIsTheLastResort() {
        let afternoons = (1...5).map { read(meeting("Call \($0)", 15, day: -$0), bpm: 82) }
        let history = MeetingStressAnalysis.history(afternoons, calendar: calendar)
        let next = MeetingStressAnalysis.forecast(meeting("Brand new", 16, day: 1), history: history, calendar: calendar)
        #expect(next.basis == .partOfDay)
        #expect(next.reason == "5 of 5 afternoon meetings ran above your usual.")
        let morning = MeetingStressAnalysis.forecast(meeting("Brand new", 9, day: 1), history: history, calendar: calendar)
        #expect(morning.basis == .none)
        #expect(morning.likelihood == nil)
    }

    @Test func forecastsCoverTheComingWeekOnly() {
        let history = MeetingStressAnalysis.history([], calendar: calendar)
        let events = [
            meeting("Gone", 9, day: -1),
            meeting("Soon", 11, day: 1),
            meeting("Later", 11, day: 6),
            meeting("Too far", 11, day: 9),
        ]
        let titles = MeetingStressAnalysis.forecasts(events, history: history, now: at(8), calendar: calendar).map(\.event.title)
        #expect(titles == ["Soon", "Later"])
    }

    // MARK: Sources

    @Test func twoSourcesShowOneMeetingOnce() {
        let apple = MindCalendarEvent(id: "a", title: "Design Review", calendarTitle: "Work", start: at(10), end: at(11), attendees: ["Alex"])
        let google = MindCalendarEvent(id: "g", title: "design review", calendarTitle: "Google", start: at(10).addingTimeInterval(20), end: at(11), attendees: ["alex", "Sam"], seriesID: "x")
        let merged = MeetingCalendar.merged([[apple], [google, meeting("Other", 14)]])
        #expect(merged.count == 2)
        #expect(merged[0].id == "a")
        #expect(merged[0].attendees == ["Alex", "Sam"])
        #expect(merged[0].seriesID == "x")
    }

    @Test func keywordsSkipTheGenericWords() {
        #expect(MeetingStressAnalysis.keywords(in: "Weekly Budget sync with Finance") == ["budget", "finance"])
    }
}
