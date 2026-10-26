//
//  InsightMetricTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The sixteen metrics the interpretation engine reads. A record is matched to
/// its metric by HealthKit identifier, and the engine judges it by the policy
/// the profile table holds for it; a metric that fell back to the empty policy
/// would call the smallest change out of range.
@Suite("Insight metrics")
@MainActor
struct InsightMetricTests {
    @Test("A record finds its metric by identifier, and only an interpreted one does")
    func lookup() {
        for metric in InsightMetric.allCases {
            #expect(InsightMetric.metric(for: metric.identifier) == metric)
        }
        #expect(Set(InsightMetric.allCases.map(\.identifier)).count == InsightMetric.allCases.count)
        #expect(InsightMetric.metric(for: MetricProfile.diastolic) == nil)
        #expect(InsightMetric.metric(for: "HKQuantityTypeIdentifierHeartRate") == nil)
        #expect(InsightMetric.metric(for: "") == nil)
    }

    @Test("Each one has a title of its own")
    func titles() {
        let titles = InsightMetric.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
    }

    @Test("Each one is judged by a real policy: a floor on its band, a step that counts, a weight", arguments: InsightMetric.allCases)
    func policy(_ metric: InsightMetric) {
        let policy = metric.policy
        #expect(policy == MetricProfile.of(metric).policy)
        #expect(policy.minimumSpread > 0)
        #expect(policy.trendStep > 0)
        #expect(policy.weight > 0 && policy.weight <= 1)
        #expect(policy.minimumShare >= 0 && policy.minimumShare < 1)
    }

    @Test("Only a total that grows until midnight leaves today out", arguments: InsightMetric.allCases)
    func partialToday(_ metric: InsightMetric) {
        #expect(metric.policy.partialToday == MetricProfile.of(metric).accumulates)
        #expect(metric.policy.partialToday == (metric == .steps))
    }
}
