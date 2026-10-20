//
//  LongevityLoadTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// How many reads a source served, by kind.
private actor ReadLog {
    private(set) var samples: [String] = []
    private(set) var totals = 0
    private(set) var collections = 0
    private(set) var others = 0

    func sample(_ identifier: String) { samples.append(identifier) }
    func total() { totals += 1 }
    func collection() { collections += 1 }
    func other() { others += 1 }

    /// Every query the source answered.
    var queries: Int { samples.count + totals + collections + others }
}

/// Steps as a phone and a watch write them: every step sample twice, once per
/// device, while Health's own daily total counts each step once.
private struct StepsSource: HealthSampleSource {
    let log: ReadLog
    let calendar: Calendar
    let now: Date
    /// Health's total for the day `n` days ago.
    static func total(daysAgo: Int) -> Double { Double(4_000 + daysAgo * 10) }

    var isAvailable: Bool { true }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        await log.other()
        return nil
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        await log.total()
        let today = calendar.startOfDay(for: now)
        guard let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: today).day else { return nil }
        return HealthReading(metric: metric.identifier, value: Self.total(daysAgo: daysAgo), unit: metric.unit, start: from, end: to)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        await log.other()
        return nil
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        await log.sample(metric.identifier)
        return []
    }

    /// One query for every day, as HealthKit's statistics collection reads.
    func dailyTotals(_ metric: HealthMetric, from: Date, to: Date, calendar: Calendar) async throws -> [HealthReading] {
        await log.collection()
        let today = calendar.startOfDay(for: now)
        return HealthDays.starts(from: from, to: to, calendar: calendar).compactMap { day in
            guard let daysAgo = calendar.dateComponents([.day], from: day, to: today).day else { return nil }
            let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? to, to)
            return HealthReading(metric: metric.identifier, value: Self.total(daysAgo: daysAgo), unit: metric.unit, start: day, end: end)
        }
    }
}

@MainActor
struct LongevityLoadTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 15, minute: 30))!
    }

    @Test("A tab switch inside a minute keeps the dashboard's read instead of reading every metric again")
    func startKeepsAFreshRead() async {
        let log = ReadLog()
        let dashboard = HealthDashboard(source: StepsSource(log: log, calendar: calendar, now: now))

        await dashboard.start()
        let first = await log.totals + log.others
        #expect(first > 0)
        #expect(dashboard.status == .ready)

        await dashboard.start()
        await dashboard.start()
        #expect(await log.totals + log.others == first)
        #expect(dashboard.status == .ready)
    }

    @Test("Steps are read as Health's daily totals, one per day and filed under that day, never as raw samples")
    func stepsReadAsDailyTotals() async {
        let log = ReadLog()
        let source = StepsSource(log: log, calendar: calendar, now: now)

        let readings = await BodyBiomarkers.read(from: source, now: now, calendar: calendar)
        let steps = readings[.stepCount] ?? []

        #expect(!(await log.samples.contains(BodyBiomarkerSpec.stepCount.identifier)))
        // One statistics collection a summed reading (steps, exercise, active
        // energy), where a statistics query a day made 273.
        let summed = BodyBiomarkerSpec.allCases.filter(\.sumsPerDay).count
        #expect(await log.collections == summed)
        #expect(await log.totals == 0)
        #expect(await log.queries == BodyBiomarkerSpec.allCases.count)
        #expect(steps.count == BodyBiomarkers.lookback + 1)
        for reading in steps {
            #expect(calendar.isDate(reading.start, inSameDayAs: reading.end))
        }

        let marker = BodyBiomarkers.make(.stepCount, readings: steps, now: now, calendar: calendar)
        #expect(marker.value == BodyBiomarkerSpec.stepCount.format(StepsSource.total(daysAgo: 0)))
        #expect(marker.days.compactMap { $0 }.count == BodyBiomarkers.days)
        #expect(marker.days.last == StepsSource.total(daysAgo: 0))
        #expect(marker.days.first == StepsSource.total(daysAgo: BodyBiomarkers.days - 1))
    }

    @Test("The Body lens keeps its read for a minute; a pull to refresh reads again")
    func bodyLensKeepsAFreshRead() async {
        let log = ReadLog()
        let dashboard = HealthDashboard(source: StepsSource(log: log, calendar: calendar, now: now))
        let cache = BodyLensCache()

        let first = await cache.read(health: dashboard, now: now, calendar: calendar)
        #expect(first?.markers.count == BodyBiomarkerSpec.allCases.count)
        let once = await log.queries
        #expect(once > 0)

        _ = await cache.read(health: dashboard, now: now.addingTimeInterval(30), calendar: calendar)
        #expect(await log.queries == once)
        #expect(cache.fresh(for: dashboard, now: now.addingTimeInterval(30)) != nil)

        _ = await cache.read(health: dashboard, force: true, now: now.addingTimeInterval(31), calendar: calendar)
        #expect(await log.queries == once * 2)

        #expect(cache.fresh(for: dashboard, now: now.addingTimeInterval(120)) == nil)
        _ = await cache.read(health: dashboard, now: now.addingTimeInterval(120), calendar: calendar)
        #expect(await log.queries == once * 3)
    }
}
