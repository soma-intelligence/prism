//
//  MetricPageWordsTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaUI
@testable import Prism

/// What a metric's page says: the caption over the number, the one line under
/// it, the facts, the chart's words and the sources.
@Suite("Metric page words")
struct MetricPageWordsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func plain(_ value: Double) -> String { VaultFormat.number(value) }

    // MARK: - Caption

    @Test("The caption says when the number is from, in the metric's own words")
    func caption() {
        let now = date(2026, 10, 19, 15)
        let today = date(2026, 10, 19, 0)
        #expect(MetricPageWords.caption(for: today, kind: .total, now: now, calendar: calendar) == "Today so far")
        #expect(MetricPageWords.caption(for: today, kind: .night, now: now, calendar: calendar) == "Last night")
        #expect(MetricPageWords.caption(for: today, kind: .reading(manyADay: true), now: now, calendar: calendar) == "Today's average")
        #expect(MetricPageWords.caption(for: today, kind: .reading(manyADay: false), now: now, calendar: calendar) == "Today")
        #expect(MetricPageWords.caption(for: date(2026, 10, 18, 0), kind: .total, now: now, calendar: calendar) == "Yesterday")
        #expect(MetricPageWords.caption(for: date(2026, 10, 18, 0), kind: .night, now: now, calendar: calendar) == "The night before")
        let older = MetricPageWords.caption(for: date(2026, 10, 12, 0), kind: .score, now: now, calendar: calendar)
        #expect(older?.contains("12") == true)
        #expect(MetricPageWords.caption(for: nil, kind: .score, now: now, calendar: calendar) == nil)
    }

    // MARK: - Meaning

    private func meaning(
        _ value: Double?,
        band: ClosedRange<Double>? = 50...70,
        reference: Bool = false,
        known: Int = 30,
        open: Bool = false,
        rising: Bool? = nil,
        unit: String? = nil
    ) -> MetricPageWords.Meaning? {
        MetricPageWords.meaning(
            value: value, band: band, isReference: reference, known: known,
            todayOpen: open, risingIsGood: rising, format: plain, unit: unit
        )
    }

    @Test("Inside, above and below the band, against the person or the typical range")
    func meaningAgainstBand() {
        #expect(meaning(60) == .init(text: "Within your usual", tone: .good))
        #expect(meaning(60, reference: true) == .init(text: "In the typical range", tone: .good))
        #expect(meaning(80)?.text == "Above your usual")
        #expect(meaning(40, reference: true)?.text == "Below the typical range")
    }

    @Test("Out of the band is worth a look, unless that way is good news")
    func meaningTone() {
        #expect(meaning(80, rising: true)?.tone == .good)
        #expect(meaning(80, rising: false)?.tone == .watch)
        #expect(meaning(80, rising: nil)?.tone == .watch)
        #expect(meaning(40, rising: false)?.tone == .good)
        #expect(meaning(40, rising: true)?.tone == .watch)
    }

    @Test("A total on a day still adding up says how far it is from a usual day")
    func meaningOpenDay() {
        #expect(meaning(6_557, band: 7_088...9_379, open: true, rising: true, unit: "steps")?.text == "531 steps to a usual day")
        #expect(meaning(8_000, band: 7_088...9_379, open: true, rising: true)?.text == "Already a usual day")
        #expect(meaning(9_900, band: 7_088...9_379, open: true, rising: true) == .init(text: "Already above a usual day", tone: .good))
    }

    @Test("Without a band the line says what the page waits for")
    func meaningWaiting() {
        #expect(meaning(nil, band: nil, known: 0)?.text == "Waiting for a first reading")
        #expect(meaning(60, band: nil, known: 2)?.text == "Still learning your usual")
        #expect(meaning(60, band: nil, known: 10) == nil)
    }

    @Test("No diagnosis words, no dashes, no full stops in a meaning")
    func meaningWords() {
        let lines = [meaning(60), meaning(80), meaning(40, reference: true), meaning(1, band: 5...9, open: true),
                     meaning(nil, band: nil, known: 0), meaning(1, band: nil, known: 1)].compactMap { $0?.text }
        for line in lines {
            #expect(!line.contains("."))
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"))
            for word in ["normal", "abnormal", "risk", "disease", "diagnos"] {
                #expect(!line.lowercased().contains(word), "\(line)")
            }
        }
    }

    // MARK: - Facts

    @Test("The usual as a fact, shortened past a thousand")
    func usualFact() {
        let steps = MetricPageWords.usualFact(band: 7_088...9_379, isReference: false, format: plain)
        #expect(steps.label == "Your usual")
        #expect(steps.value == "7.1K to 9.4K")
        let oxygen = MetricPageWords.usualFact(band: 95...100, isReference: true, format: plain)
        #expect(oxygen == SomaFact("Typical range", value: "95 to 100"))
        #expect(MetricPageWords.usualFact(band: nil, isReference: false, format: plain).value == nil)
    }

    @Test("The trend compares the last thirty finished days with the thirty before")
    func trendFact() {
        let before = [Double?](repeating: 100, count: 30)
        let up = MetricPageWords.trendFact(days: before + Array(repeating: 110, count: 30), openDayTail: 0, risingIsGood: true, accumulates: false, format: plain)
        #expect(up == SomaFact("30 day trend", value: "Up 10%", detail: "From 100", tone: .good))
        let down = MetricPageWords.trendFact(days: before + Array(repeating: 90, count: 30), openDayTail: 0, risingIsGood: true, accumulates: false, format: plain)
        #expect(down?.value == "Down 10%")
        #expect(down?.tone == .watch)
        let steady = MetricPageWords.trendFact(days: before + Array(repeating: 101, count: 30), openDayTail: 0, risingIsGood: true, accumulates: false, format: plain)
        #expect(steady?.value == "Steady")
        let neutral = MetricPageWords.trendFact(days: before + Array(repeating: 110, count: 30), openDayTail: 0, risingIsGood: nil, accumulates: false, format: plain)
        #expect(neutral?.tone == .neutral)
        // Under a week on either side is too little to call.
        #expect(MetricPageWords.trendFact(days: [100, 100, 110], openDayTail: 0, risingIsGood: true, accumulates: false, format: plain) == nil)
    }

    @Test("Today's open total is left out of the trend")
    func trendFactOpenDay() {
        let days: [Double?] = Array(repeating: 100, count: 60) + [5]
        let fact = MetricPageWords.trendFact(days: days, openDayTail: 1, risingIsGood: true, accumulates: true, format: plain)
        #expect(fact?.value == "Steady")
    }

    @Test("Days in the band over the last thirty finished days")
    func daysInBand() {
        let days: [Double?] = Array(repeating: 60, count: 20) + Array(repeating: 90, count: 10) + [nil]
        let band = MetricDetailMath.Band(lower: Array(repeating: 50, count: 31), upper: Array(repeating: 70, count: 31), isReference: false)
        #expect(MetricPageWords.daysInBandFact(days: days, band: band, openDayTail: 1) == SomaFact("Usual days", value: "20 of 30"))
        #expect(MetricPageWords.daysInBandFact(days: days, band: nil, openDayTail: 0) == nil)
    }

    // MARK: - Ranges and the chart's words

    @Test("A day is offered only for a metric read through the day")
    func ranges() {
        #expect(MetricPageWords.ranges(dayIsUseful: true) == [.day, .week, .month, .year])
        #expect(MetricPageWords.ranges(dayIsUseful: false) == [.week, .month, .year])
        let offered = MetricPageWords.ranges(dayIsUseful: false)
        #expect(MetricPageWords.opening(.sixMonths, offered: offered) == .year)
        #expect(MetricPageWords.opening(.threeMonths, offered: offered) == .month)
        #expect(MetricPageWords.opening(.day, offered: offered) == .month)
    }

    @Test("A month labels every seventh day counted back from today")
    func monthAxis() {
        let labelled = (0..<31).filter { MetricPageWords.axisLabel(.month, index: $0, count: 31, start: date(2026, 10, 19), calendar: calendar) != nil }
        #expect(labelled == [2, 9, 16, 23, 30])
    }

    @Test("A day labels every sixth hour")
    func dayAxis() {
        let labels = (0..<24).compactMap { hour in
            MetricPageWords.axisLabel(.day, index: hour, count: 24, start: date(2026, 10, 19, hour), calendar: calendar)
        }
        #expect(labels.count == 4)
    }

    @Test("The summary's dates stop at today, even when a year's span runs to the month's end")
    func summaryStopsToday() {
        let now = date(2026, 10, 19, 15)
        let span = DateInterval(start: date(2025, 11, 1, 0), end: date(2026, 11, 1, 0))
        let label = MetricPageWords.summaryLabel(.year, kind: .total, span: span, now: now, calendar: calendar)
        #expect(label.hasPrefix("Daily average, "))
        #expect(label.contains("19"))
        #expect(!label.contains("31"))
        #expect(MetricPageWords.summaryLabel(.day, kind: .total, span: span, now: now, calendar: calendar) == "Total today")
    }

    // MARK: - Sources and names

    @Test("Sources carry their share, a glyph for a known device and a word on quality")
    func sources() {
        let watch = ReadingQuality(level: .sensor, reason: "Wrist sensor")
        let phone = ReadingQuality(level: .estimated, reason: "Phone motion")
        let hand = ReadingQuality(level: .manual, reason: "Entered by hand")
        let listed = MetricPageWords.sources([
            .init(name: "Apple Watch", device: "Apple Watch", count: 6, quality: watch),
            .init(name: "iPhone", device: nil, count: 3, quality: phone),
            .init(name: "Health", device: nil, count: 1, quality: hand),
        ])
        #expect(listed.map(\.share) == [0.6, 0.3, 0.1])
        #expect(listed.map(\.symbol) == ["applewatch", "iphone", "hand.point.up.left"])
        #expect(listed.map(\.quality) == ["Measured", "Estimated", "Entered by hand"])
        #expect(MetricPageWords.sources([]).isEmpty)
    }

    @Test("A source the grade does not know draws its initial")
    func unknownSource() {
        let unknown = ReadingQuality(level: .unknown, reason: "Source not recognised")
        let listed = MetricPageWords.sources([.init(name: "Lab notes", device: nil, count: 2, quality: unknown)])
        #expect(listed.first?.symbol == nil)
        #expect(listed.first?.quality == nil)
    }

    @Test("Names read in sentence case, with Soma's short name where it has one")
    func names() {
        #expect(MetricPageWords.title(identifier: "HKQuantityTypeIdentifierStepCount", fallback: "Step Count") == "Steps")
        #expect(MetricPageWords.title(identifier: "HKQuantityTypeIdentifierHeartRate", fallback: "Heart Rate") == "Heart rate")
        #expect(MetricPageWords.sentenceCase("VO2 Max Level") == "VO2 max level")
        #expect(MetricPageWords.sentenceCase("Heart Rate Variability SDNN") == "Heart rate variability SDNN")
        #expect(MetricPageWords.unit(identifier: "HKQuantityTypeIdentifierStepCount", fallback: nil) == "steps")
        #expect(MetricPageWords.unit(identifier: "HKQuantityTypeIdentifierHeartRate", fallback: "bpm") == "bpm")
    }

    @Test("The info sheet keeps the long words, in wellness terms")
    func about() {
        let sections = MetricAbout.sections(
            identifier: "HKQuantityTypeIdentifierStepCount", title: "Steps", band: 7_000...9_000,
            isReference: false, accumulates: true, hasSources: true, unit: "steps", format: plain
        )
        #expect(sections.map(\.heading) == ["What it is", "Your usual", "Sources", "Unit", "Good to know"])
        #expect(sections[1].body.contains("until midnight"))
        let reference = MetricAbout.sections(
            identifier: "HKQuantityTypeIdentifierOxygenSaturation", title: "Blood oxygen", band: 95...100,
            isReference: true, accumulates: false, hasSources: false, unit: "%", format: plain
        )
        #expect(reference[1].heading == "The band")
        #expect(reference[1].body.contains("95 to 100 %"))
        for section in sections + reference {
            #expect(!section.body.lowercased().contains("diagnos"))
        }
    }

    @Test("The chart's key names the band and the average in a few words")
    func chartKey() {
        #expect(MetricPageWords.usualKey(56...58, isReference: false, format: plain) == "Usual 56 to 58")
        #expect(MetricPageWords.usualKey(7_100...9_400, isReference: false, format: plain) == "Usual 7.1K to 9.4K")
        #expect(MetricPageWords.usualKey(95...100, isReference: true, format: plain) == "Typical 95 to 100")
        #expect(MetricPageWords.averageKey(58, kind: .reading(manyADay: false), format: plain, unit: "bpm") == "Average 58 bpm")
        #expect(MetricPageWords.averageKey(8_288, kind: .total, format: plain, unit: "steps") == "Daily average 8,288 steps")
        #expect(MetricPageWords.averageKey(92, kind: .score, format: plain, unit: nil) == "Average 92")
    }

    @Test("The quiet line under the chart folds the trend and the days in the band, or where the body is heading")
    func chartNote() {
        let trend = SomaFact("30 day trend", value: "Up 5%", detail: "From 55", tone: .watch)
        let steady = SomaFact("30 day trend", value: "Steady", detail: "Around 58")
        let days = SomaFact("Usual days", value: "18 of 30")
        let range = SomaFact("Days in range", value: "30 of 30")
        let heading = SomaFact("In 30 days", value: "75.9 kg", detail: "\u{00B1} 0.6")
        #expect(MetricPageWords.note(trend: trend, projection: nil, inBand: days) == "Up 5% on the 30 days before · 18 of 30 days in your usual")
        #expect(MetricPageWords.note(trend: steady, projection: nil, inBand: range) == "Steady over 30 days · 30 of 30 days in the typical range")
        #expect(MetricPageWords.note(trend: nil, projection: heading, inBand: days) == "About 75.9 kg in 30 days")
        #expect(MetricPageWords.note(trend: nil, projection: nil, inBand: nil) == nil)
    }
}
