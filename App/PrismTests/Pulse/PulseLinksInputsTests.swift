//
//  PulseLinksInputsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Trends page's links read every series keyed by its day: the score
/// engine's, Health's and the Journal's tags. What is checked is that each
/// value lands on its own day, that a night with no sleep or a day the phone
/// sat on a desk is left out rather than counted low, and that the Journal's
/// first day is the first one that holds anything.
@Suite("Pulse links inputs")
@MainActor
struct PulseLinksInputsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    func midnight(_ day: Int) -> Date { calendar.startOfDay(for: at(12, day: day)) }

    var now: Date { at(15) }

    func series(health: PulseLinksInputs.Health = .init(), scores: SomaScores? = nil,
                journal: [Date: JournalDay] = [:]) -> LinkSeries {
        PulseLinksInputs.series(health: health, scores: scores, journal: journal, now: now, calendar: calendar)
    }

    @Test("Every type the links read is one the Health catalog knows")
    func metricsAreInTheCatalog() {
        for identifier in PulseLinksInputs.metrics {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    @Test("The score engine's series land on their days, ending today, and a night without sleep is left out")
    func scoreSeries() {
        var scores = SomaScores.fixture
        scores.detail.sleepHours = [7.2, 0, 7.5]
        scores.detail.sleep = [80, nil, 85]
        scores.detail.bedHour = [23.5, 24.25, nil]
        scores.detail.recovery = [nil, nil, 64]
        scores.detail.energyMorning = [70, nil, nil]
        scores.detail.strain = [nil, 12, nil]

        let links = series(scores: scores)
        #expect(links.sleepHours == [midnight(-2): 7.2, midnight(0): 7.5])
        #expect(links.sleepScore == [midnight(-2): 80, midnight(0): 85])
        #expect(links.sleepOnset == [midnight(-2): 23.5, midnight(-1): 24.25])
        #expect(links.recovery == [midnight(0): 64])
        #expect(links.energy == [midnight(-2): 70])
        #expect(links.strain == [midnight(-1): 12])
        #expect(series().sleepScore.isEmpty)
    }

    @Test("Steps under five hundred are a phone left on a desk, not a quiet day")
    func wornSteps() {
        let health = PulseLinksInputs.Health(steps: [midnight(0): 8_000, midnight(-1): 300, midnight(-2): 500],
                                             daylight: [midnight(-1): 42])
        let links = series(health: health)
        #expect(links.steps == [midnight(0): 8_000, midnight(-2): 500])
        #expect(links.daylight == [midnight(-1): 42])
    }

    @Test("Resting heart rate is the day's mean, and a morning's HRV the median before noon, on that morning")
    func heart() {
        let health = PulseLinksInputs.Health(
            hrv: [
                .test(PulseLinksInputs.Metric.hrv, 48, at: at(7)),
                .test(PulseLinksInputs.Metric.hrv, 52, at: at(9)),
                .test(PulseLinksInputs.Metric.hrv, 90, at: at(14)),
            ],
            resting: [
                .test(PulseLinksInputs.Metric.restingHeartRate, 50, at: at(6, day: -1)),
                .test(PulseLinksInputs.Metric.restingHeartRate, 54, at: at(20, day: -1)),
            ]
        )
        let links = series(health: health)
        #expect(links.restingHeart == [midnight(-1): 52])
        #expect(links.morningHRV == [midnight(0): 50])
    }

    @Test("Tags gather by day, and the Journal begins on its first day that holds anything")
    func journal() {
        let journal: [Date: JournalDay] = [
            at(20, day: -1): JournalDay(tags: ["alcohol", "late-meal"]),
            at(20, day: -3): JournalDay(tags: ["alcohol"]),
            at(20, day: -5): JournalDay(feeling: 3),
            at(20, day: -9): JournalDay(),
        ]
        let links = series(journal: journal)
        #expect(links.tagDays["alcohol"] == [midnight(-1), midnight(-3)])
        #expect(links.tagDays["late-meal"] == [midnight(-1)])
        #expect(links.firstJournalDay == at(20, day: -5))
    }
}
