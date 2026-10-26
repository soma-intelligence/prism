//
//  OralHealthTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Mouth and teeth: days brushed twice out of thirty, brushing time against
/// two minutes, the Journal's floss, mouthwash and gums when Health holds no
/// brushing, the next dental visit six months after the last, the weekly
/// cap on the gums question, and the Body's Glucose tile that only shows
/// for a monitor's trace.
@Suite("Mouth and teeth")
@MainActor
struct OralHealthTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// Saturday 24 October 2026, 21:00 in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 21))!
    }

    private func at(_ hour: Int, daysAgo days: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    private func brushing(_ hour: Int, daysAgo days: Int, seconds: Double = 120) -> HealthReading {
        let start = at(hour, daysAgo: days)
        return HealthReading(metric: OralSummary.brushingID, value: 0, unit: .none,
                             start: start, end: start.addingTimeInterval(seconds), source: "Oral-B")
    }

    private func journalDay(_ days: Int, yes: Set<String> = [], no: Set<String> = []) -> (date: Date, day: JournalDay) {
        (calendar.startOfDay(for: at(0, daysAgo: days)), JournalDay(tags: yes, declined: no))
    }

    private func summary(
        brushing: [HealthReading] = [],
        journal: [(date: Date, day: JournalDay)] = [],
        lastVisit: Date? = nil,
        bookedVisit: Date? = nil
    ) -> OralSummary {
        OralSummary.make(brushing: brushing, journalDays: journal, lastVisit: lastVisit, bookedVisit: bookedVisit,
                         now: now, calendar: calendar)
    }

    // MARK: Brushing

    @Test("Days brushed twice count the days of the last thirty with two brushings or more")
    func twiceDailyCount() {
        let found = summary(brushing: [
            brushing(7, daysAgo: 0), brushing(20, daysAgo: 0),
            brushing(8, daysAgo: 1),
            brushing(7, daysAgo: 2), brushing(13, daysAgo: 2), brushing(22, daysAgo: 2),
            brushing(7, daysAgo: 5), brushing(23, daysAgo: 5),
            // Outside the thirty days: not counted.
            brushing(7, daysAgo: 40), brushing(21, daysAgo: 40),
        ])
        #expect(found.hasBrushing)
        #expect(found.brushedTwiceDays == 3)
        #expect(found.brushedDays == 4)
        #expect(found.perDay.count == OralSummary.windowDays)
        #expect(found.perDay.last == 2)
        #expect(found.perDay[OralSummary.windowDays - 2] == 1)
        // A day of the thirty with no brushing is a zero once Health has any.
        #expect(found.perDay[OralSummary.windowDays - 4] == 0)
        #expect(found.lastBrushing == at(20, daysAgo: 0))
    }

    @Test("A brushing under two minutes on average is flagged, a zero length one is counted but not timed")
    func shortBrushFlagged() throws {
        let short = summary(brushing: [brushing(7, daysAgo: 0, seconds: 90), brushing(21, daysAgo: 1, seconds: 100)])
        #expect(abs(try #require(short.averageSeconds) - 95) < 1e-9)
        #expect(short.isShortBrush)

        let long = summary(brushing: [brushing(7, daysAgo: 0, seconds: 130), brushing(21, daysAgo: 0, seconds: 0)])
        #expect(abs(try #require(long.averageSeconds) - 130) < 1e-9)
        #expect(!long.isShortBrush)
        #expect(long.brushedTwiceDays == 1)
    }

    @Test("Without brushing in Health the page reads the Journal, and brushing stays a dash")
    func noBrushDataUsesJournal() {
        let found = summary(journal: [
            journalDay(0, yes: [OralTag.floss], no: [OralTag.mouthwash]),
            journalDay(3, yes: [OralTag.floss]),
            journalDay(9, yes: [OralTag.floss, OralTag.gumsBleed]),
            // Older than thirty days: not counted.
            journalDay(45, yes: [OralTag.floss, OralTag.mouthwash]),
        ])
        #expect(!found.hasBrushing)
        #expect(found.brushedTwiceDays == nil)
        #expect(found.brushedDays == nil)
        #expect(found.averageSeconds == nil)
        #expect(found.perDay.allSatisfy { $0 == nil })
        #expect(found.flossDays == 3)
        #expect(found.mouthwashDays == 0)
        #expect(found.gumBleedDays == 1)
        #expect(!found.isEmpty)
    }

    @Test("Nothing anywhere: every number is missing, nothing reads as zero")
    func emptyState() {
        let found = summary()
        #expect(found.isEmpty)
        #expect(found.brushedTwiceDays == nil)
        #expect(found.flossDays == nil)
        #expect(found.mouthwashDays == nil)
        #expect(found.gumBleedDays == nil)
        #expect(found.nextVisit == nil)
        #expect(!found.isVisitDue)
        #expect(!found.isShortBrush)
    }

    // MARK: Visits

    @Test("The next visit falls six months after the last one, and a booked visit wins")
    func visitDueAfter6Months() {
        let last = calendar.date(byAdding: .month, value: -7, to: now)!
        let due = summary(lastVisit: last)
        #expect(due.nextVisit == calendar.date(byAdding: .month, value: 6, to: last))
        #expect(due.isVisitDue)

        let recent = summary(lastVisit: calendar.date(byAdding: .month, value: -2, to: now)!)
        #expect(!recent.isVisitDue)

        let booked = calendar.date(byAdding: .day, value: 10, to: now)!
        let withBooking = summary(lastVisit: last, bookedVisit: booked)
        #expect(withBooking.nextVisit == booked)
        #expect(!withBooking.isVisitDue)
        #expect(!withBooking.isEmpty)
    }

    @Test("The screening catalog counts a dental checkup every six months, like this page")
    func dentalCatalogEverySixMonths() {
        let dental = SomaTools.ScreeningCatalog.item(id: "dental")
        #expect(dental?.intervalMonths == OralSummary.visitMonths)
        #expect(dental?.intervalMonths == 6)
    }

    @Test("The next dental appointment in the medical record is the booked visit")
    func bookedVisitFromRecord() {
        var record = MedicalRecord()
        let booked = calendar.date(byAdding: .day, value: 12, to: now)!
        record.appointments = [Appointment(date: booked, with: "Dr Smile", reason: .dental)]
        let withBooking = summary(lastVisit: nil, bookedVisit: record.nextDentalVisit(now: now))
        #expect(withBooking.nextVisit == booked)
    }

    // MARK: The gums question

    private func eveningRun(lastSettled: [String: Date]) -> [String] {
        var context = CheckInContext(offeredTags: Set(JournalStore.starterTags.map(\.id)), mindAvailable: true)
        context.lastSettled = lastSettled
        return CheckInEngine.questions(now: now, calendar: calendar, record: CheckInDayRecord(),
                                       signals: .none, context: context).map(\.id)
    }

    @Test("The gums question is a yes or no in the evening, asked once a week at most")
    func gumQuestionWeeklyCap() throws {
        let question = try #require(CheckInCatalog.all.first { $0.id == "gums" })
        #expect(question.kind == .yesNo)
        #expect(question.windows == [.evening])
        #expect(question.everyDays == 7)
        #expect(question.destination == .journalTag(OralTag.gumsBleed, day: .today))

        #expect(eveningRun(lastSettled: [:]).contains("gums"))
        #expect(!eveningRun(lastSettled: ["gums": at(20, daysAgo: 3)]).contains("gums"))
        #expect(!eveningRun(lastSettled: ["gums": at(20, daysAgo: 6)]).contains("gums"))
        #expect(eveningRun(lastSettled: ["gums": at(20, daysAgo: 7)]).contains("gums"))
        // A daily question ignores when it was last settled.
        #expect(eveningRun(lastSettled: ["day": at(20, daysAgo: 1)]).contains("day"))
    }

    @Test("When a weekly question was last settled comes from the check-in record and the Journal")
    func lastSettledSources() {
        let store = CheckInStore(url: nil, calendar: calendar)
        let question = CheckInCatalog.all.first { $0.id == "gums" }!
        store.update(on: at(20, daysAgo: 4)) { $0.answer(question, with: .no) }
        store.update(on: at(20, daysAgo: 2)) { $0.skip(CheckInCatalog.all.first { $0.id == "day" }!) }
        #expect(store.lastSettled("gums").map(calendar.startOfDay) == calendar.startOfDay(for: at(0, daysAgo: 4)))
        #expect(store.lastSettled("sauna") == nil)

        let journal = JournalStore(url: nil, calendar: calendar)
        journal.answer(OralTag.gumsBleed, false, on: at(9, daysAgo: 1))
        journal.answer(OralTag.gumsBleed, true, on: at(9, daysAgo: 8))
        #expect(journal.lastAnswered(OralTag.gumsBleed) == calendar.startOfDay(for: at(0, daysAgo: 1)))
        #expect(journal.lastAnswered(OralTag.floss) == nil)
    }

    // MARK: Journal tags

    @Test("Floss, mouthwash and gums are starter tags, and an older Journal gains them on load")
    func starterTagsMerged() throws {
        let ids = JournalStore.starterTags.map(\.id)
        #expect(ids.contains(OralTag.floss))
        #expect(ids.contains(OralTag.mouthwash))
        #expect(ids.contains(OralTag.gumsBleed))
        // The last two are still the ones switched off.
        #expect(JournalStore.starterTags.suffix(2).allSatisfy { !$0.isOffered })

        let url = FileManager.default.temporaryDirectory.appending(path: "oral-journal-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = """
        {"tags":[{"id":"alcohol","title":"Alcohol","isOffered":false}],"days":{},
         "questions":{"asksFeeling":true,"feelingHour":21,"asksEnergy":false,"asksStress":false}}
        """
        try Data(old.utf8).write(to: url)
        let journal = JournalStore(url: url, calendar: calendar)
        #expect(journal.tags.first?.id == "alcohol")
        #expect(journal.tags.first?.isOffered == false)
        #expect(journal.offeredTags.map(\.id).contains(OralTag.floss))
        #expect(journal.offeredTags.map(\.id).contains(OralTag.gumsBleed))
        #expect(Set(journal.tags.map(\.id)) == Set(ids))
    }

    // MARK: The Body's Glucose tile

    private func trace(days: Int, value: (Int) -> Double) -> [HealthReading] {
        let start = calendar.date(byAdding: .day, value: -days, to: now)!
        return (0..<(days * 288)).map { index in
            let date = start.addingTimeInterval(Double(index) * 300)
            return HealthReading(metric: LabMetric.glucose, value: value(index), unit: .milligramPerDecilitre,
                                 start: date, end: date, source: "Dexcom")
        }
    }

    @Test("The Glucose tile shows only for a monitor's trace, with a week of daily time in range")
    func glucoseTileOnlyForCGM() throws {
        // Every tenth reading over 180: 90 % in range each day.
        let tile = try #require(GlucoseTile.make(samples: trace(days: 14) { $0 % 10 == 0 ? 200 : 110 },
                                                 now: now, calendar: calendar))
        #expect(abs(try #require(tile.timeInRange) - 0.9) < 0.01)
        #expect(tile.days.count == 7)
        #expect(tile.days.compactMap { $0 }.allSatisfy { abs($0 - 90) < 2 })

        let sticks = (0..<14).flatMap { day in [7, 13, 19].map { hour in
            HealthReading(metric: LabMetric.glucose, value: 100, unit: .milligramPerDecilitre,
                          start: at(hour, daysAgo: day), end: at(hour, daysAgo: day))
        } }
        #expect(GlucoseTile.make(samples: sticks, now: now, calendar: calendar) == nil)
        #expect(GlucoseTile.make(samples: [], now: now, calendar: calendar) == nil)
    }
}
