//
//  RhythmMobilityTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Heart rhythm, walking steadiness and falls: Apple's steadiness bands, the
/// fall count over a year, the weekly AFib burden, the help line after a
/// fall, and the Body tiles that stay hidden when nothing was recorded.
@Suite("Heart rhythm, steadiness and falls")
struct RhythmMobilityTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday 21 October 2026, 10:00 in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10))!
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    private func reading(_ identifier: String, _ value: Double, daysAgo days: Int, unit: HealthUnit = .percent) -> HealthReading {
        let start = daysAgo(days)
        return HealthReading(metric: identifier, value: value, unit: unit, start: start, end: start)
    }

    private func steadiness(_ value: Double, daysAgo days: Int) -> HealthReading {
        reading(RhythmMobilityReadings.steadinessID, value, daysAgo: days)
    }

    private func fall(_ count: Double = 1, daysAgo days: Int) -> HealthReading {
        reading(RhythmMobilityReadings.fallsID, count, daysAgo: days, unit: .count)
    }

    // MARK: Steadiness

    @Test("Apple's steadiness bands: OK from 40 %, low from 20 %, very low under it")
    func steadinessLevels() {
        #expect(SteadinessLevel.of(0.72) == .ok)
        #expect(SteadinessLevel.of(0.40) == .ok)
        #expect(SteadinessLevel.of(0.399) == .low)
        #expect(SteadinessLevel.of(0.20) == .low)
        #expect(SteadinessLevel.of(0.199) == .veryLow)
        #expect(SteadinessLevel.of(nil) == .unknown)

        let summary = MobilitySummary.make(
            steadiness: [steadiness(0.62, daysAgo: 30), steadiness(0.31, daysAgo: 2)],
            falls: [], events: [], now: now, calendar: calendar
        )
        #expect(summary.level == .low)
        #expect(summary.steadiness == 0.31)
        #expect(summary.history.map(\.value) == [0.62, 0.31])

        let none = MobilitySummary.make(steadiness: [], falls: [], events: [], now: now, calendar: calendar)
        #expect(none.level == .unknown)
        #expect(none.steadiness == nil)
    }

    @Test("Steadiness events read Apple's codes, newest first")
    func steadinessEvents() {
        let id = RhythmMobilityReadings.steadinessEventID
        let summary = MobilitySummary.make(
            steadiness: [],
            falls: [],
            events: [reading(id, 1, daysAgo: 60, unit: .none), reading(id, 4, daysAgo: 5, unit: .none)],
            now: now, calendar: calendar
        )
        #expect(summary.events.map(\.kind) == [.repeatVeryLow, .initialLow])
        #expect(summary.hasData)
    }

    // MARK: Falls

    @Test("Falls count over the last twelve months, each sample's own count")
    func fallCountYear() {
        let summary = MobilitySummary.make(
            steadiness: [],
            falls: [fall(daysAgo: 10), fall(2, daysAgo: 100), fall(daysAgo: 400)],
            events: [], now: now, calendar: calendar
        )
        #expect(summary.fallsLast12Months == 3)
        #expect(summary.falls.count == 2)
        #expect(summary.lastFall == daysAgo(10))
    }

    @Test("A recent fall puts the help line first; an old one does not")
    func fallWithEventShowsHelpLine() throws {
        let recent = MobilitySummary.make(
            steadiness: [steadiness(0.18, daysAgo: 3)],
            falls: [fall(daysAgo: 4)],
            events: [reading(RhythmMobilityReadings.steadinessEventID, 2, daysAgo: 6, unit: .none)],
            now: now, calendar: calendar
        )
        let line = try #require(recent.helpLine)
        #expect(line.contains("emergency"))
        #expect(line.contains("doctor"))

        let old = MobilitySummary.make(steadiness: [], falls: [fall(daysAgo: 90)], events: [], now: now, calendar: calendar)
        #expect(old.helpLine == nil)
        #expect(old.fallsLast12Months == 1)

        let none = MobilitySummary.make(steadiness: [steadiness(0.15, daysAgo: 1)], falls: [], events: [], now: now, calendar: calendar)
        #expect(none.helpLine == nil)
    }

    // MARK: AFib burden

    @Test("AFib burden groups by week, oldest first, with the change on the week before")
    func afibBurdenWeekly() {
        let id = RhythmMobilityReadings.burdenID
        let summary = HeartRhythmSummary.make(
            burden: [
                reading(id, 0.02, daysAgo: 21),
                reading(id, 0.05, daysAgo: 14),
                reading(id, 0.08, daysAgo: 7),
                reading(id, 0.06, daysAgo: 1),
                reading(id, 0.02, daysAgo: 2),
                reading(id, 0.30, daysAgo: 400),
            ],
            irregular: [], high: [], low: [], now: now, calendar: calendar
        )
        #expect(summary.weeks.count == 4)
        #expect(summary.weeks.map(\.start) == summary.weeks.map(\.start).sorted())
        #expect(abs((summary.latestBurden ?? 0) - 0.04) < 0.000_1)
        #expect(abs((summary.change ?? 0) - -0.04) < 0.000_1)
        #expect(HeartRhythmSummary.burdenText(0.015) == "2% or less")
        #expect(HeartRhythmSummary.burdenText(0.064) == "6%")
        #expect(HeartRhythmSummary.burdenText(nil) == "-")
    }

    @Test("Rhythm notifications list newest first, by kind")
    func rhythmEvents() {
        let summary = HeartRhythmSummary.make(
            burden: [],
            irregular: [reading(RhythmMobilityReadings.irregularID, 0, daysAgo: 40, unit: .none)],
            high: [reading(RhythmMobilityReadings.highID, 0, daysAgo: 3, unit: .none)],
            low: [reading(RhythmMobilityReadings.lowID, 0, daysAgo: 12, unit: .none)],
            now: now, calendar: calendar
        )
        #expect(summary.events.map(\.kind) == [.high, .low, .irregular])
        #expect(summary.latestBurden == nil)
        #expect(summary.hasData)
        #expect(summary.hasIrregular)
    }

    // MARK: Tiles

    @Test("Nothing recorded hides both tiles; a phone alone shows Mobility")
    func noWatchHidesTiles() {
        let empty = RhythmMobilityReadings()
        #expect(!empty.rhythm(now: now, calendar: calendar).hasData)
        #expect(!empty.mobility(now: now, calendar: calendar).hasData)
        #expect(RhythmMobilityTile.shown(empty, now: now, calendar: calendar).isEmpty)

        var phone = RhythmMobilityReadings()
        phone.steadiness = [steadiness(0.55, daysAgo: 6)]
        #expect(RhythmMobilityTile.shown(phone, now: now, calendar: calendar) == [.mobility])

        var both = phone
        both.burden = [reading(RhythmMobilityReadings.burdenID, 0.03, daysAgo: 3)]
        #expect(RhythmMobilityTile.shown(both, now: now, calendar: calendar) == [.heartRhythm, .mobility])

        // A reading older than a year is not enough to show a tile.
        var stale = RhythmMobilityReadings()
        stale.falls = [fall(daysAgo: 500)]
        #expect(RhythmMobilityTile.shown(stale, now: now, calendar: calendar).isEmpty)
    }

    @Test("The reader asks for every type it reads, and each is in the one Health sheet")
    func readerTypesAreInTheCatalog() {
        for identifier in RhythmMobilityReadings.identifiers {
            let metric = HealthMetricCatalog.metric(for: identifier)
            #expect(metric != nil, "\(identifier) missing from the catalog")
            #expect(HealthMetricCatalog.readable.contains { $0.identifier == identifier })
        }
    }
}
