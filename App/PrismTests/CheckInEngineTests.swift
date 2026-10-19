//
//  CheckInEngineTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// "Soma asks" picks its questions from the clock, the day's record, the
/// readings and what is already logged. Each failure mode has a test
/// here: Later counted as done, a morning sheet in the afternoon, eleven
/// answers at once, questions at the wrong time of day, and questions that
/// never ended.
@Suite("Soma asks: engine")
@MainActor
struct CheckInEngineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    /// Every tag offered, nothing logged, Mind on.
    var open: CheckInContext {
        CheckInContext(offeredTags: Set(JournalStore.starterTags.map(\.id)), mindAvailable: true)
    }

    func run(_ date: Date, record: CheckInDayRecord = CheckInDayRecord(), signals: CheckInSignals = .none, context: CheckInContext? = nil) -> [CheckInQuestion] {
        CheckInEngine.questions(now: date, calendar: calendar, record: record, signals: signals, context: context ?? open)
    }

    // MARK: Windows

    @Test("Morning is 05:00 to 12:00, evening 18:00 to midnight, nothing between")
    func windows() {
        #expect(CheckInWindow.at(at(4, 59), calendar: calendar) == nil)
        #expect(CheckInWindow.at(at(5), calendar: calendar) == .morning)
        #expect(CheckInWindow.at(at(11, 59), calendar: calendar) == .morning)
        #expect(CheckInWindow.at(at(12), calendar: calendar) == nil)
        #expect(CheckInWindow.at(at(15), calendar: calendar) == nil)
        #expect(CheckInWindow.at(at(17, 59), calendar: calendar) == nil)
        #expect(CheckInWindow.at(at(18), calendar: calendar) == .evening)
        #expect(CheckInWindow.at(at(23, 59), calendar: calendar) == .evening)
        #expect(CheckInWindow.at(at(0, 30), calendar: calendar) == nil)
    }

    @Test("Nothing is asked in the afternoon, at night, or by itself there")
    func nothingOutsideWindows() {
        #expect(run(at(14)).isEmpty)
        #expect(run(at(2)).isEmpty)
        #expect(!CheckInEngine.shouldPresentAutomatically(now: at(14), calendar: calendar, record: CheckInDayRecord()))
    }

    @Test("The morning asks about last night, the evening about the day")
    func rightTimeOfDay() {
        let morning = run(at(8))
        let evening = run(at(20))
        #expect(morning.allSatisfy { $0.windows.contains(.morning) })
        #expect(evening.allSatisfy { $0.windows.contains(.evening) })
        #expect(morning.map(\.id).contains("alcohol"))
        #expect(!evening.map(\.id).contains("alcohol"))
        #expect(evening.first?.id == "day")
    }

    @Test("A run holds at most five questions")
    func atMostFive() {
        let evening = run(at(20))
        #expect(evening.count == CheckInEngine.sessionLimit)
        #expect(CheckInCatalog.evening.count > CheckInEngine.sessionLimit)
    }

    @Test("Every question is phrased as a question")
    func phrasedAsQuestions() {
        for question in CheckInCatalog.all {
            #expect(question.text.hasSuffix("?"), "\(question.id) reads \(question.text)")
        }
    }

    // MARK: Data driven

    @Test("A short night leads the morning, in minutes to the nearest five")
    func shortNight() {
        let signals = CheckInSignals(lastNightSleepMinutes: 380, usualSleepMinutes: 432)
        let morning = run(at(7), signals: signals)
        #expect(morning.first?.text == "Slept 50 min less than usual. Feeling it?")
        #expect(morning.first?.isDataDriven == true)
        #expect(morning.count == CheckInEngine.sessionLimit)
    }

    @Test("A night near the usual asks nothing; one with no usual asks nothing")
    func ordinaryNight() {
        #expect(CheckInCatalog.dataDriven(CheckInSignals(lastNightSleepMinutes: 420, usualSleepMinutes: 440)).isEmpty)
        #expect(CheckInCatalog.dataDriven(CheckInSignals(lastNightSleepMinutes: 300, usualSleepMinutes: nil)).isEmpty)
    }

    @Test("A raised resting rate is asked morning and evening, the stronger signal first")
    func restingRise() {
        let signals = CheckInSignals(
            lastNightSleepMinutes: 390, usualSleepMinutes: 425,
            restingHeartRate: 62.4, usualRestingHeartRate: 54
        )
        let asked = CheckInCatalog.dataDriven(signals)
        #expect(asked.map(\.id) == ["data.resting-up", "data.sleep-short"])
        #expect(asked.first?.text == "Resting HR up 8 bpm. Coming down with something?")
        #expect(run(at(20), signals: signals).first?.id == "data.resting-up")
        #expect(!run(at(20), signals: signals).map(\.id).contains("data.sleep-short"))
    }

    @Test("Spans read as minutes under the hour and hours with minutes over it")
    func spans() {
        #expect(CheckInCatalog.span(48) == "50 min")
        #expect(CheckInCatalog.span(70) == "1 h 10")
        #expect(CheckInCatalog.span(119) == "2 h")
    }

    // MARK: The day's record

    @Test("An answered question is not asked again that day, nor a skipped one")
    func noRepeats() {
        var record = CheckInDayRecord()
        let first = run(at(8))
        record.answer(first[0], with: .number(7))
        record.skip(first[1])
        let again = run(at(10), record: record)
        #expect(!again.contains(first[0]))
        #expect(!again.contains(first[1]))
        #expect(!again.isEmpty)
        // The next morning starts from a fresh record.
        #expect(run(at(8, day: 1)).contains(first[0]))
    }

    @Test("Later snoozes two hours and does not count as done")
    func laterIsNotDone() {
        var record = CheckInDayRecord()
        record.markPresented(.morning)
        record.snooze(.morning, at: at(7))
        #expect(!record.finished.contains(.morning))
        #expect(!run(at(7, 30), record: record).isEmpty)
        #expect(!CheckInEngine.shouldPresentAutomatically(now: at(8, 59), calendar: calendar, record: record))
        #expect(CheckInEngine.shouldPresentAutomatically(now: at(9, 1), calendar: calendar, record: record))
    }

    @Test("Once per window by itself, and the evening is its own window")
    func oncePerWindow() {
        var record = CheckInDayRecord()
        #expect(CheckInEngine.shouldPresentAutomatically(now: at(8), calendar: calendar, record: record))
        record.markPresented(.morning)
        #expect(!CheckInEngine.shouldPresentAutomatically(now: at(9), calendar: calendar, record: record))
        #expect(CheckInEngine.shouldPresentAutomatically(now: at(19), calendar: calendar, record: record))
    }

    @Test("A finished window asks nothing more: the questions end")
    func questionsEnd() {
        var record = CheckInDayRecord()
        for question in run(at(8)) { record.answer(question, with: .yes) }
        record.finish(.morning)
        #expect(run(at(9), record: record).isEmpty)
        #expect(!CheckInEngine.shouldPresentAutomatically(now: at(9), calendar: calendar, record: record))
        #expect(!run(at(19), record: record).isEmpty)
    }

    @Test("The Later reminder comes only while the window is still open")
    func laterReminder() {
        #expect(CheckInEngine.reminderDate(after: at(7), calendar: calendar) == at(9))
        #expect(CheckInEngine.reminderDate(after: at(10, 30), calendar: calendar) == nil)
        #expect(CheckInEngine.reminderDate(after: at(22, 30), calendar: calendar) == nil)
        #expect(CheckInEngine.reminderDate(after: at(14), calendar: calendar) == nil)
    }

    // MARK: What is already known

    @Test("A tag switched off, or already tapped, is not asked about")
    func journalContext() {
        var context = open
        context.offeredTags.remove("screens-in-bed")
        context.tagsYesterday = ["alcohol"]
        let ids = run(at(8), context: context).map(\.id)
        #expect(!ids.contains("screens-in-bed"))
        #expect(!ids.contains("alcohol"))
        #expect(ids.contains("late-meal"))
    }

    @Test("A check-in filled in elsewhere, a wake rating or a feeling already set is not asked again")
    func loggedElsewhere() {
        var context = open
        context.homeCheckInElsewhere = true
        context.hasFeeling = true
        context.hasWakeRating = true
        let evening = run(at(20), context: context).map(\.id)
        #expect(!evening.contains("energy"))
        #expect(!evening.contains("stress"))
        #expect(!evening.contains("sore"))
        #expect(!evening.contains("day"))
        #expect(!run(at(8), context: context).map(\.id).contains("wake"))
    }

    @Test("Mind's questions wait for Mind to be on")
    func mindGate() {
        var context = open
        context.mindAvailable = false
        #expect(!run(at(8), context: context).map(\.id).contains("rested"))
        #expect(run(at(8)).map(\.id).contains("rested"))
    }

    // MARK: Scales

    @Test("Five steps land on the Journal's seven stops and Mind's five, ends at the ends")
    func scales() {
        #expect((1...5).map(CheckInEngine.feelingStop(fromStep:)) == [0, 2, 3, 4, 6])
        #expect((1...5).map(CheckInEngine.mindStep(fromStep:)) == [0, 1, 2, 3, 4])
    }
}

/// The answers land in the stores the rest of the app reads.
@Suite("Soma asks: writing")
@MainActor
struct CheckInWriterTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 8))! }
    var evening: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21))! }

    func question(_ id: String) -> CheckInQuestion {
        CheckInCatalog.all.first { $0.id == id }!
    }

    @Test("A morning yes tags yesterday, a no clears it")
    func tagsYesterday() {
        let journal = JournalStore(url: nil, calendar: calendar)
        let writer = CheckInWriter(journal: journal, home: HomeLog(url: nil, calendar: calendar), mind: MindStore(url: nil), track: TrackLogStore(url: nil, calendar: calendar), calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: morning)!
        writer.write(question("alcohol"), .yes, answers: [:], now: morning)
        #expect(journal.day(yesterday).tags.contains("alcohol"))
        #expect(!journal.day(morning).tags.contains("alcohol"))
        writer.write(question("alcohol"), .no, answers: [:], now: morning)
        #expect(!journal.day(yesterday).tags.contains("alcohol"))
    }

    @Test("The evening check-in is built from the answers, the rest kept at the middle")
    func homeCheckIn() {
        let home = HomeLog(url: nil, calendar: calendar)
        let writer = CheckInWriter(journal: nil, home: home, mind: MindStore(url: nil), track: TrackLogStore(url: nil, calendar: calendar), calendar: calendar)
        writer.write(question("energy"), .scale(2), answers: ["energy": .scale(2)], now: evening)
        #expect(home.checkIn(on: evening)?.energy == 2)
        #expect(home.checkIn(on: evening)?.stress == 3)
        writer.write(question("sore"), .yes, answers: ["energy": .scale(2), "sore": .yes], now: evening)
        #expect(home.checkIn(on: evening)?.body == .sore)
        #expect(home.checkIns.count == 1)
    }

    @Test("Wake rating and the day's feeling land in Track and the Journal")
    func trackAndFeeling() {
        let journal = JournalStore(url: nil, calendar: calendar)
        let track = TrackLogStore(url: nil, calendar: calendar)
        let writer = CheckInWriter(journal: journal, home: HomeLog(url: nil, calendar: calendar), mind: MindStore(url: nil), track: track, calendar: calendar)
        writer.write(question("wake"), .scale(4), answers: [:], now: morning)
        writer.write(question("day"), .scale(5), answers: [:], now: evening)
        #expect(track.wakeRating(on: morning) == 8)
        #expect(journal.day(evening).feeling == 6)
    }

    @Test("Mind gets one check-in a run, and only once Mind is on")
    func mindOnce() {
        let mind = MindStore(url: nil)
        let writer = CheckInWriter(journal: nil, home: HomeLog(url: nil, calendar: calendar), mind: mind, track: TrackLogStore(url: nil, calendar: calendar), calendar: calendar)
        let body = CheckInCatalog.dataDriven(CheckInSignals(lastNightSleepMinutes: 360, usualSleepMinutes: 430)).first!
        let answered: [(question: CheckInQuestion, answer: CheckInAnswer)] = [(question("rested"), .scale(2)), (body, .yes)]
        writer.writeMind(answered, now: morning)
        #expect(mind.checkIns.isEmpty)

        mind.setConsent(MindConsent(givenAt: morning))
        writer.writeMind(answered, now: morning)
        #expect(mind.checkIns.count == 1)
        #expect(mind.checkIns.first?.energy == 1)
        #expect(mind.checkIns.first?.question == body.text)
        #expect(mind.checkIns.first?.answer == .yes)
    }

    @Test("Morning and evening reminders and Later open the run; other notifications do not")
    func notificationIdentifiers() {
        #expect(CheckInPresenter.opens(ReminderPlan.Identifier.morning))
        #expect(CheckInPresenter.opens(ReminderPlan.Identifier.evening))
        #expect(CheckInPresenter.opens(CheckInReminder.identifier))
        #expect(!CheckInPresenter.opens(ReminderPlan.Identifier.lastMeal))
    }
}
