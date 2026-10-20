//
//  VaultRedesignTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
import HealthExportCore
@testable import Prism

/// The Vault's words, its record list and its score rows.
@Suite("Vault words")
struct VaultRedesignTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func reading(_ start: Date, minutes: Double = 0, source: String? = "Apple Watch",
                         device: String? = "Apple Watch", byHand: Bool = false) -> HealthReading {
        HealthReading(metric: "HKQuantityTypeIdentifierHeartRate", value: 72, unit: .countPerMinute,
                      start: start, end: start.addingTimeInterval(minutes * 60),
                      source: source, device: device, wasUserEntered: byHand)
    }

    // MARK: - Words

    @Test("A day reads as today, yesterday, a weekday within the week, then a date")
    func days() {
        let now = date(20, 18)
        #expect(VaultWords.day(date(20, 9), now: now, calendar: calendar) == "Today")
        #expect(VaultWords.day(date(19, 9), now: now, calendar: calendar) == "Yesterday")
        #expect(VaultWords.day(date(16, 9), now: now, calendar: calendar) == "Friday")
        let older = VaultWords.day(date(2, 9), now: now, calendar: calendar)
        #expect(older.contains("Oct") && older.contains("2") && !older.contains("2026"))
        #expect(VaultWords.day(date(2, 9, year: 2025), now: now, calendar: calendar).contains("2025"))
    }

    @Test("A record is a time, or a span once it lasts a minute")
    func recordTimes() {
        #expect(!VaultWords.time(start: date(20, 10), end: date(20, 10), calendar: calendar).contains(" to "))
        #expect(VaultWords.time(start: date(19, 23), end: date(20, 6, 48), calendar: calendar).contains(" to "))
    }

    @Test("Counts are singular at one")
    func counts() {
        #expect(VaultWords.measures(1) == "1 measure")
        #expect(VaultWords.measures(12) == "12 measures")
        #expect(VaultWords.readings(1) == "1 reading")
    }

    @Test("Every count of measures reads the Vault's categories; Health's tile counts readings")
    func measureCounts() {
        let listed = BodyCatalog.categories.reduce(0) { $0 + $1.types.count }
        #expect(BodyCatalog.measureCount == listed)
        // The Health catalog holds more entries than the categories browse,
        // so a count of measures never names the catalog's size.
        #expect(BodyCatalog.measureCount < HealthMetricCatalog.all.count)
        #expect(VaultWords.searchPrompt(BodyCatalog.measureCount) == "Search \(listed) measures")
        #expect(VaultWords.holds(measures: BodyCatalog.measureCount, scores: 10).hasPrefix("\(listed) measures"))
        #expect(VaultWords.withData(1) == "1 measure with data")
        #expect(VaultWords.withData(6) == "6 measures with data")
    }

    @Test("Categories carry a line glyph and a sentence case name")
    func categoryNames() throws {
        let heart = try #require(BodyCatalog.categories.first { $0.title == "Heart" })
        #expect(heart.lineSymbol == "heart")
        let body = try #require(BodyCatalog.categories.first { $0.title == "Body Measurements" })
        #expect(body.displayTitle == "Body measurements")
        #expect(body.lineSymbol == "figure.arms.open")
        #expect(BodyCatalog.categories.allSatisfy { !$0.lineSymbol.hasSuffix(".fill") })
    }

    // MARK: - Records

    @Test("Records split by day, each knowing its place on the day's card")
    func recordLines() {
        let records = [reading(date(20, 12)), reading(date(20, 11)), reading(date(20, 10)), reading(date(19, 20))]
        let lines = VaultRecordLines.make(records, calendar: calendar)
        #expect(lines.count == 6)
        #expect(lines[0].kind == .day(calendar.startOfDay(for: date(20, 0))))
        #expect(lines[1].kind == .record(records[0], .first))
        #expect(lines[2].kind == .record(records[1], .middle))
        #expect(lines[3].kind == .record(records[2], .last))
        #expect(lines[4].kind == .day(calendar.startOfDay(for: date(19, 0))))
        #expect(lines[5].kind == .record(records[3], .only))
        #expect(Set(lines.map(\.id)).count == lines.count)
        #expect(VaultRecordLines.make([], calendar: calendar).isEmpty)
    }

    @Test("A record's glyph names what wrote it")
    func recordGlyph() {
        #expect(VaultRecordRow.symbol(reading(date(20, 10))) == "applewatch")
        #expect(VaultRecordRow.symbol(reading(date(20, 10), source: "Health", device: "iPhone")) == "iphone")
        #expect(VaultRecordRow.symbol(reading(date(20, 10), byHand: true)) == "hand.point.up.left")
    }

    @Test("A record's sheet gives one time for an instant, three lines for a span, and leaves out empty fields")
    func recordFields() {
        let instant = VaultRecordSheet.when(reading(date(20, 10)), calendar: calendar)
        #expect(instant.map(\.title) == ["Taken"])
        let span = VaultRecordSheet.when(reading(date(20, 10), minutes: 30), calendar: calendar)
        #expect(span.map(\.title) == ["Began", "Ended", "Lasted"])
        let fields = VaultRecordSheet.source(reading(date(20, 10), device: nil))
        #expect(fields.map(\.title) == ["App", "Entered by hand"])
        #expect(VaultRecordSheet.caption(reading(date(20, 10)), now: date(20, 18), calendar: calendar).hasPrefix("Today at "))
    }

    // MARK: - Scores

    @Test("A score's row shows its latest value, when that was, and its week")
    func scoreSummary() {
        let now = date(20, 18)
        let days: [Double?] = [80, 81, 82, 83, 84, 85, 86, 87.4, nil]
        let summary = VaultScoreSummary.make(.sleepScore, days: days, now: now, calendar: calendar)
        #expect(summary.value == "87")
        #expect(summary.caption == "Yesterday")
        #expect(summary.week.count == 7)
        let empty = VaultScoreSummary.make(.recovery, days: [nil, nil], now: now, calendar: calendar)
        #expect(empty.value == nil && empty.caption == nil)
    }

    @Test("Night parts read as durations and clock times")
    func scoreFormats() {
        #expect(VaultScoreSummary.format(.deepHours, 1.2, calendar: calendar).contains("1h"))
        #expect(VaultScoreSummary.format(.bedtime, 22.5, calendar: calendar) == "22:30")
        #expect(VaultScoreSummary.format(.wakeTime, 30.25, calendar: calendar) == "6:15")
        #expect(VaultScoreSummary.format(.strain, 12.6, calendar: calendar) == "13")
    }

    @Test("Each score wears an aspect; only the 0 to 100 ones count as scores")
    func scoreAspects() {
        #expect(ScoreMetric.sleepScore.aspect == .sleep)
        #expect(ScoreMetric.stress.aspect == .mind)
        #expect(ScoreMetric.strain.aspect == .activity)
        #expect(ScoreMetric.allCases.filter(\.isScore) == [.sleepScore, .recovery, .strain, .stress, .energy])
    }
}
