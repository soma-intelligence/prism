//
//  ScoreMetricTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// A score's detail page opens on one of Soma's own series rather than a
/// HealthKit type. Each metric has to read its own series out of the scores,
/// be shown as exactly one kind of value, and draw the band its profile names.
@Suite("Score metrics")
@MainActor
struct ScoreMetricTests {
    @Test("Each one is filed under its own key in the profile table")
    func identifiers() {
        let identifiers = ScoreMetric.allCases.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0.hasPrefix("soma.score.") })
        #expect(Set(ScoreMetric.allCases.map(\.title)).count == ScoreMetric.allCases.count)
    }

    @Test("Each one reads as a score, a duration or a clock time, never two of them", arguments: ScoreMetric.allCases)
    func oneReading(_ metric: ScoreMetric) {
        let kinds = [metric.unit != nil, metric.isDuration, metric.isClock].filter { $0 }
        #expect(kinds.count == 1)
    }

    @Test("A score out of 100 is capped at 100 on its chart, and nothing else is", arguments: ScoreMetric.allCases)
    func ceiling(_ metric: ScoreMetric) {
        let capped = MetricProfile.of(metric.identifier).ceiling == 100
        #expect(capped == (metric.unit == "of 100"))
    }

    @Test("Each one reads its own series from the scores")
    func days() {
        var scores = SomaScores.fixture
        scores.detail.sleep = [1]
        scores.detail.recovery = [2]
        scores.detail.strain = [3]
        scores.detail.stress = [4]
        scores.detail.energyMorning = [50]
        scores.detail.energyEnd = [5]
        scores.detail.remHours = [6]
        scores.detail.deepHours = [7]
        scores.detail.sleepDebtHours = [8]
        scores.detail.bedHour = [9]
        scores.detail.wakeHour = [10]

        let read = Dictionary(uniqueKeysWithValues: ScoreMetric.allCases.map { ($0, $0.days(scores)) })
        let expected: [ScoreMetric: [Double?]] = [
            .sleepScore: [1], .recovery: [2], .strain: [3], .stress: [4], .energy: [5],
            .remHours: [6], .deepHours: [7], .sleepDebt: [8], .bedtime: [9], .wakeTime: [10],
        ]
        #expect(read == expected)
    }

    @Test("Strain's band is the day's personal target, and only strain's")
    func strainBand() {
        var scores = SomaScores.fixture
        scores.strainTarget = 40...60

        #expect(ScoreMetric.strain.profile(scores).referenceBand == 40...60)
        #expect(ScoreMetric.strain.profile(nil).referenceBand == nil)
        #expect(ScoreMetric.strain.profile(SomaScores.fixture).referenceBand == nil)
        #expect(ScoreMetric.recovery.profile(scores).referenceBand == 67...100)
        #expect(ScoreMetric.stress.profile(scores) == MetricProfile.of(ScoreMetric.stress.identifier))
    }
}
