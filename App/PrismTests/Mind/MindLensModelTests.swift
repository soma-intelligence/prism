//
//  MindLensModelTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Mind lens is drawn from plain values: today's stress in zones, two
/// weeks of mood, and the Health reads behind them. A day with nothing logged
/// stays empty rather than neutral, and the Journal's evening feeling stands
/// in only on a day with no entry of its own.
@Suite("Mind lens")
@MainActor
struct MindLensModelTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    var today: Date { calendar.startOfDay(for: at(12)) }

    // MARK: Zones

    @Test("Stress zones break at 34 and 67, the lines Pulse's stress page draws")
    func zones() {
        #expect(MindZone(0) == .low)
        #expect(MindZone(33.9) == .low)
        #expect(MindZone(34) == .medium)
        #expect(MindZone(66.9) == .medium)
        #expect(MindZone(67) == .high)
        #expect(MindZone(100) == .high)
    }

    @Test("The zones tile the line from 0 to 100 without a gap")
    func zoneRanges() {
        #expect(MindZone.low.range.lowerBound == 0)
        #expect(MindZone.low.range.upperBound == MindZone.medium.range.lowerBound)
        #expect(MindZone.medium.range.upperBound == MindZone.high.range.lowerBound)
        #expect(MindZone.high.range.upperBound == 100)
    }

    @Test("Each half hour of stress counts thirty minutes in its zone, and an empty day counts none")
    func zoneMinutes() {
        let samples = [10.0, 50, 55, 80].enumerated().map { index, value in
            MindStressSample(start: at(9 + index), value: value)
        }
        let model = MindLensModel(now: at(15), dayStart: today, stress: samples)
        #expect(model.zoneMinutes == [.low: 30, .medium: 60, .high: 30])
        #expect(MindLensModel(now: at(15), dayStart: today).zoneMinutes == nil)
    }

    // MARK: Mood

    @Test("Two weeks of mood, oldest first, today last, a day without anything left empty")
    func moodStrip() {
        let days = MindLensModel.moodDays([], feelings: [:], today: today, calendar: calendar)
        #expect(days.count == MindLensModel.moodDays)
        #expect(days.last?.day == today)
        #expect(days.last?.isToday == true)
        #expect(days.dropLast().allSatisfy { !$0.isToday })
        #expect(days.first?.day == calendar.date(byAdding: .day, value: -13, to: today))
        #expect(days.allSatisfy { $0.valence == nil })
    }

    @Test("A day's entries average, and their words and themes are named once, in order")
    func entriesAverage() throws {
        let entries = [
            MindMoodEntry(date: at(9), kind: .momentary, valence: 0.5, labels: ["calm", "drained"], associations: ["work"]),
            MindMoodEntry(date: at(20), kind: .daily, valence: -0.1, labels: ["calm", "made-up"], associations: ["work", "garden"]),
        ]
        let days = MindLensModel.moodDays(entries, feelings: [today: 0], today: today, calendar: calendar)
        let last = try #require(days.last)
        #expect(abs((last.valence ?? 0) - 0.2) < 1e-9)
        #expect(last.words == ["Calm", "Tired", "Made-Up"])
        #expect(last.themes == ["Work", "Garden"])
    }

    @Test("The Journal's evening feeling stands in on a day with no entry")
    func journalFallback() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let days = MindLensModel.moodDays([], feelings: [yesterday: MindMoodEntry.stops - 1], today: today, calendar: calendar)
        #expect(days[days.count - 2].valence == 1)
        #expect(days.last?.valence == nil)
    }

    @Test("Minutes read as hours and minutes, the way every duration in the app reads")
    func duration() {
        let english = Locale(identifier: "en_US")
        #expect(MindLensFormat.duration(336, locale: english) == "5h 36m")
        #expect(MindLensFormat.duration(59.6, locale: english) == "1h")
        #expect(MindLensFormat.duration(0, locale: english) == "0m")
    }

    // MARK: Reading

    @Test("Every type the Mind tab reads is one the Health catalog knows")
    func metricsAreInTheCatalog() {
        for identifier in MindInputs.Metric.all + MindJourneyLoad.Metric.all {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    @Test("One read gathers sixty days of each series and nothing older")
    func read() async {
        typealias Metric = MindInputs.Metric
        let readings: [HealthReading] = [
            .test(Metric.heartRateVariability, 48, at: at(7, day: -10)),
            .test(Metric.heartRateVariability, 40, at: at(7, day: -70)),
            .test(Metric.restingHeartRate, 55, at: at(7, day: -1)),
            .test(Metric.mindful, 1, from: at(8), to: at(8, 10)),
            .test(Metric.sleep, 3, from: at(23, day: -1), to: at(7)),
            .test(Metric.workout, 37, from: at(18, day: -2), to: at(19, day: -2)),
        ]
        let inputs = await MindInputs.read(from: ScriptedHealthSource(readings), now: at(15), calendar: calendar)
        #expect(inputs.heartRateVariability.map(\.value) == [48])
        #expect(inputs.restingHeartRate.map(\.value) == [55])
        #expect(inputs.mindful.count == 1)
        #expect(inputs.sleep.count == 1)
        #expect(inputs.workouts.count == 1)
        #expect(!inputs.isEmpty)
    }

    @Test("A store that refuses every read leaves the tab empty")
    func refusedStore() async {
        let inputs = await MindInputs.read(from: ScriptedHealthSource(fails: true), now: at(15), calendar: calendar)
        #expect(inputs.isEmpty)
    }
}
