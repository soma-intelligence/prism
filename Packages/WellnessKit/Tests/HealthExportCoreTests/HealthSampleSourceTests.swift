//
//  HealthSampleSourceTests.swift
//  HealthExportCoreTests
//

import Foundation
import Testing
@testable import HealthExportCore

/// A source backed by a fixture, so the reading contract can be exercised
/// without a Health store.
private struct StubSource: HealthSampleSource {
    var isAvailable = true
    var stored: [String: [HealthReading]] = [:]
    var totals: [String: Double] = [:]
    var averages: [String: Double] = [:]

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        stored[metric.identifier]?.max { $0.end < $1.end }
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        guard metric.aggregation == .cumulative else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }
        guard let value = totals[metric.identifier] else { return nil }
        return HealthReading(metric: metric.identifier, value: value, unit: metric.unit, start: from, end: to)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        guard metric.aggregation == .discrete else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }
        guard let value = averages[metric.identifier] else { return nil }
        return HealthReading(metric: metric.identifier, value: value, unit: metric.unit, start: from, end: to)
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        let all = (stored[metric.identifier] ?? []).filter { $0.start >= from && $0.end <= to }
        return limit == 0 ? all : Array(all.prefix(limit))
    }
}

private func metric(_ identifier: String) -> HealthMetric {
    HealthMetricCatalog.metric(for: identifier)!
}

@Suite("Reading contract")
struct HealthSampleSourceTests {
    private let steps = metric("HKQuantityTypeIdentifierStepCount")
    private let restingHeartRate = metric("HKQuantityTypeIdentifierRestingHeartRate")
    private let sleep = metric("HKCategoryTypeIdentifierSleepAnalysis")
    private let mindful = metric("HKCategoryTypeIdentifierMindfulSession")

    @Test("Summary sums a cumulative metric and averages a discrete one")
    func summaryFollowsAggregation() async throws {
        var source = StubSource()
        source.totals[steps.identifier] = 8_412
        source.averages[restingHeartRate.identifier] = 54

        let now = Date()
        let earlier = now.addingTimeInterval(-3600)

        let stepped = try await source.summary(steps, from: earlier, to: now)
        #expect(stepped?.value == 8_412)
        #expect(stepped?.unit == .count)

        let heart = try await source.summary(restingHeartRate, from: earlier, to: now)
        #expect(heart?.value == 54)
        #expect(heart?.unit == .countPerMinute)
    }

    @Test("Summing a discrete metric is refused rather than silently wrong")
    func discreteCannotBeTotalled() async {
        let source = StubSource()
        await #expect(throws: HealthReadError.unsupportedQuery(restingHeartRate.identifier)) {
            _ = try await source.total(restingHeartRate, from: .distantPast, to: .distantFuture)
        }
    }

    @Test("Time asleep counts the asleep stages and ignores in-bed and awake")
    func sleepCountsOnlyAsleepStages() async throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func sample(_ code: Int, minutes: Double, after offset: Double) -> HealthReading {
            HealthReading(
                metric: sleep.identifier,
                value: Double(code),
                unit: .none,
                start: start.addingTimeInterval(offset * 60),
                end: start.addingTimeInterval((offset + minutes) * 60)
            )
        }

        var source = StubSource()
        source.stored[sleep.identifier] = [
            sample(0, minutes: 30, after: 0),    // in bed
            sample(2, minutes: 10, after: 30),   // awake
            sample(3, minutes: 90, after: 40),   // core
            sample(4, minutes: 45, after: 130),  // deep
            sample(5, minutes: 60, after: 175),  // REM
        ]

        let asleep = try await source.totalDuration(
            sleep, from: start, to: start.addingTimeInterval(24 * 3600),
            codes: HealthCategoryValue.asleep
        )
        #expect(asleep == 195 * 60)

        let everything = try await source.totalDuration(
            sleep, from: start, to: start.addingTimeInterval(24 * 3600)
        )
        #expect(everything == 235 * 60)
    }

    @Test("Mindful minutes are the sessions' length, not their coded value")
    func mindfulCountsDuration() async throws {
        let start = Date(timeIntervalSince1970: 2_000_000)
        var source = StubSource()
        source.stored[mindful.identifier] = [
            HealthReading(metric: mindful.identifier, value: 0, unit: .none,
                          start: start, end: start.addingTimeInterval(600)),
            HealthReading(metric: mindful.identifier, value: 0, unit: .none,
                          start: start.addingTimeInterval(3600),
                          end: start.addingTimeInterval(3600 + 300)),
        ]

        let total = try await source.totalDuration(
            mindful, from: start, to: start.addingTimeInterval(24 * 3600)
        )
        #expect(total == 900)
    }

    @Test("An empty store reads as nil, never as zero")
    func emptyStoreIsNil() async throws {
        let source = StubSource()
        #expect(try await source.latest(steps) == nil)
        #expect(try await source.summary(steps, from: .distantPast, to: .distantFuture) == nil)
        #expect(try await source.totalDuration(sleep, from: .distantPast, to: .distantFuture) == 0)
    }

    @Test("Provenance defaults to unknown and typed by a sensor")
    func provenanceDefaults() {
        let reading = HealthReading(metric: steps.identifier, value: 1, unit: .count, start: .now, end: .now)
        #expect(reading.device == nil)
        #expect(reading.deviceModel == nil)
        #expect(reading.sourceBundle == nil)
        #expect(reading.wasUserEntered == false)
    }

    @Test("A reading stored before provenance existed still decodes")
    func decodesLegacyReading() throws {
        let legacy = Data(#"{"metric":"m","value":2,"unit":"count","start":0,"end":60,"source":"Watch"}"#.utf8)
        let reading = try JSONDecoder().decode(HealthReading.self, from: legacy)
        #expect(reading.source == "Watch")
        #expect(reading.device == nil)
        #expect(reading.wasUserEntered == false)
    }

    @Test("Provenance survives a round trip")
    func provenanceRoundTrip() throws {
        let reading = HealthReading(
            metric: "m", value: 3, unit: .count, start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 60), source: "Oura", sourceBundle: "com.ouraring.oura",
            device: "Oura Ring", deviceModel: "Gen3 Oura", wasUserEntered: true
        )
        let back = try JSONDecoder().decode(HealthReading.self, from: JSONEncoder().encode(reading))
        #expect(back == reading)
    }
}
