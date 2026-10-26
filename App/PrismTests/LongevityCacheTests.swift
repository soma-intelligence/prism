//
//  LongevityCacheTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Longevity lenses open on the last known values: the file must round
/// trip, refuse what it cannot trust without crashing, keep what a lens shows
/// until its whole read is in, and the launch preload must fill it.
@Suite("Longevity cache")
@MainActor
struct LongevityCacheTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 24 October 2026 at 09:00.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9))! }

    /// A store in a folder of its own, removed when the test ends.
    private func withStore<T>(_ body: (LongevitySnapshotStore) async throws -> T) async rethrows -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LongevityCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await body(LongevitySnapshotStore(url: folder.appendingPathComponent("longevity-snapshot.json")))
    }

    /// Every lens read from the fixture year.
    private func snapshot() async -> LongevitySnapshot {
        let health = HealthDashboard(source: FixtureHealthSource(now: now, calendar: calendar), calendar: calendar)
        let body = await LongevityLoad.body(health, now: now, calendar: calendar)
        let parts = await LongevityLoad.mind(health, now: now, calendar: calendar)
        let environment = await LongevityLoad.environment(health, now: now, calendar: calendar)
        return LongevitySnapshot(
            savedAt: now,
            body: body,
            mind: parts.model(scores: health.scores, journal: nil, calendar: calendar),
            environment: environment,
            outside: EnvironmentConditions(temperature: 14.5, uv: 3, highDays: [12, nil, 15])
        )
    }

    // MARK: - The file

    @Test("Every lens read from the fixture comes back equal")
    func roundTrip() async throws {
        let snapshot = await snapshot()
        #expect(snapshot.body?.markers[.vo2Max]?.value != nil)
        #expect(snapshot.mind?.hrv != nil)
        #expect(snapshot.environment != nil)
        try await withStore { store in
            try store.save(snapshot)
            let loaded = try #require(store.load(now: now.addingTimeInterval(600), calendar: calendar))
            #expect(loaded == snapshot)
        }
    }

    @Test("No file, or a corrupt, empty or truncated one, reads as no snapshot, never a crash")
    func corruptFile() async throws {
        let snapshot = await snapshot()
        try await withStore { store in
            #expect(store.load(now: now, calendar: calendar) == nil)
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for bytes in [Data(), Data("{".utf8), Data("not json".utf8), Data(repeating: 0xFF, count: 512),
                          Data(#"{"version":1,"savedAt":"yesterday"}"#.utf8)] {
                try bytes.write(to: store.url)
                #expect(store.load(now: now, calendar: calendar) == nil)
            }
            try store.save(snapshot)
            let whole = try Data(contentsOf: store.url)
            try whole.prefix(whole.count / 2).write(to: store.url)
            #expect(store.load(now: now, calendar: calendar) == nil)
            // A cache over a corrupt file opens empty.
            #expect(LongevityCache(store: store, now: now, calendar: calendar).body == nil)
        }
    }

    @Test("Past a week, dated in the future, or of another shape, the snapshot is not shown")
    func tooOldFutureOrOtherVersion() async throws {
        try await withStore { store in
            try store.save(LongevitySnapshot(savedAt: now.addingTimeInterval(-8 * 86_400)))
            #expect(store.load(now: now, calendar: calendar) == nil)
            try store.save(LongevitySnapshot(savedAt: now.addingTimeInterval(3_600)))
            #expect(store.load(now: now, calendar: calendar) == nil)
            var other = LongevitySnapshot(savedAt: now)
            other.version = LongevitySnapshot.version + 1
            try store.save(other)
            #expect(store.load(now: now, calendar: calendar) == nil)
        }
    }

    @Test("On another day the long readings stay, today's go")
    func anotherDay() async throws {
        let snapshot = await snapshot()
        try await withStore { store in
            try store.save(snapshot)
            let tomorrow = try #require(store.load(now: now.addingTimeInterval(86_400), calendar: calendar))
            #expect(tomorrow.mind == nil)
            #expect(tomorrow.environment == nil)
            #expect(tomorrow.outside == nil)
            #expect(tomorrow.body?.markers[.stepCount]?.value == nil)
            #expect(tomorrow.body?.markers[.vo2Max] == snapshot.body?.markers[.vo2Max])
            #expect(tomorrow.body?.overview == snapshot.body?.overview)
        }
    }

    @Test("Clearing forgets every lens and removes the file")
    func clear() async throws {
        let snapshot = await snapshot()
        try await withStore { store in
            try store.save(snapshot)
            let cache = LongevityCache(store: store, now: now, calendar: calendar)
            #expect(cache.body != nil)
            cache.clear()
            #expect(cache.body == nil && cache.mind == nil && cache.environment == nil && cache.outside == nil)
            #expect(!FileManager.default.fileExists(atPath: store.url.path))
        }
    }

    // MARK: - The lenses

    @Test("A lens draws the cached values at once and keeps them until its whole read is in")
    func drawsFromCacheBeforeTheRead() async throws {
        var cached = LongevityBodyState.empty(now: Date(), calendar: .current)
        cached.overview.fitnessAge = BodyFitnessAge.Stat(value: "99")
        try await withStore { store in
            try store.save(LongevitySnapshot(savedAt: Date(), body: cached))
            let cache = LongevityCache(store: store)
            // Before anything is read, the lens has its values.
            #expect(cache.body == cached)

            let gate = Gate()
            let health = HealthDashboard(source: GatedSource(base: FixtureHealthSource(), gate: gate))
            let read = Task { await cache.loadBody(health) }
            for _ in 0..<50 { await Task.yield() }
            // The read is under way and nothing of it shows: no tile is
            // swapped before the others.
            #expect(cache.body == cached)

            await gate.open()
            await read.value
            let fresh = try #require(cache.body)
            #expect(fresh != cached)
            #expect(fresh.overview.fitnessAge.value != "99")
            #expect(BodyBiomarkerSpec.allCases.allSatisfy { fresh.markers[$0] != nil })
            #expect(fresh.markers[.vo2Max]?.value != nil)
            #expect(cache.isFresh(.body))
        }
    }

    @Test("The preload fills every lens, so the first visit opens full")
    func preloadFillsTheCache() async throws {
        let cache = LongevityCache()
        #expect(cache.body == nil && cache.mind == nil && cache.environment == nil)
        let health = HealthDashboard(source: FixtureHealthSource())
        await cache.preload(health, journal: nil)
        let body = try #require(cache.body)
        #expect(body.markers[.restingHeartRate]?.value != nil)
        #expect(body.overview.vo2Max != nil)
        #expect(body.overview.fitnessAge != nil)
        #expect(cache.mindParts != nil)
        #expect(cache.mind?.hrv != nil)
        #expect(cache.environment != nil)
        #expect(Set(LongevityCache.Lens.allCases).allSatisfy { cache.isFresh($0) })
    }

    @Test("The preload writes the file a cold launch opens on")
    func preloadWritesTheFile() async throws {
        try await withStore { store in
            let cache = LongevityCache(store: store)
            await cache.preload(HealthDashboard(source: FixtureHealthSource()), journal: nil)
            var saved = store.load()
            for _ in 0..<100 where saved?.environment == nil {
                try await Task.sleep(for: .milliseconds(20))
                saved = store.load()
            }
            #expect(saved?.body == cache.body)
            #expect(saved?.mind == cache.mind)
            #expect(saved?.environment == cache.environment)
            // A second launch draws the same lens before reading anything.
            #expect(LongevityCache(store: store).body == cache.body)
        }
    }

    // MARK: - Fitness age

    @Test("Fitness age is the age whose average VO2 max is yours")
    func fitnessAge() {
        #expect(FitnessAge.estimate(vo2Max: 40, sex: .male) == 45)
        #expect(FitnessAge.estimate(vo2Max: 34, sex: .female) == 45)
        #expect(FitnessAge.estimate(vo2Max: 37, sex: nil) == 45)
        #expect(FitnessAge.estimate(vo2Max: 42, sex: .male) == 40)
        // Fitter is younger, and the line holds its ends.
        #expect(FitnessAge.estimate(vo2Max: 75, sex: .male) == FitnessAge.youngest)
        #expect(FitnessAge.estimate(vo2Max: 10, sex: .female) == FitnessAge.oldest)
        // Without a VO2 max there is nothing to say: a dash, never a zero.
        #expect(FitnessAge.estimate(vo2Max: nil, sex: .male) == nil)
        #expect(FitnessAge.estimate(vo2Max: .nan, sex: .male) == nil)
    }

    @Test("The Body overview shows a fitness age from a VO2 max alone, with no date of birth")
    func overviewFitnessAge() {
        let reading = HealthReading(metric: BodyMetric.vo2Max, value: 40, unit: .none,
                                    start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(-86_400))
        let page = BodyOverview.make(from: BodyOverviewInputs(now: now, vo2Max: [reading], age: nil, sex: .male), calendar: calendar)
        #expect(page.fitnessAge.value == "45")
        #expect(BodyOverview.make(from: BodyOverviewInputs(now: now), calendar: calendar).fitnessAge.value == nil)
    }
}

/// Holds every sample read until it is opened.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}

/// A source whose reads wait at the gate, for a read that is still running.
private struct GatedSource: HealthSampleSource {
    let base: FixtureHealthSource
    let gate: Gate

    var isAvailable: Bool { true }

    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        await gate.wait()
        return try await base.latest(metric)
    }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        await gate.wait()
        return try await base.total(metric, from: from, to: to)
    }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        await gate.wait()
        return try await base.average(metric, from: from, to: to)
    }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] {
        await gate.wait()
        return try await base.samples(metric, from: from, to: to, limit: limit)
    }
}
