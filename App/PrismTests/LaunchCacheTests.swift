//
//  LaunchCacheTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import HealthScoring
@testable import Prism

/// The snapshot that lets a launch open on the last known numbers: it must
/// round-trip exactly, refuse anything it cannot trust without crashing, and
/// hand over to the first read of the new launch.
@Suite("Launch cache")
@MainActor
struct LaunchCacheTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 24 October 2026 at 09:00.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9))! }

    /// A store in a folder of its own, removed when the test ends.
    private func withStore<T>(_ body: (HealthSnapshotStore) async throws -> T) async rethrows -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        return try await body(HealthSnapshotStore(url: folder.appendingPathComponent("health-snapshot.json")))
    }

    private func scores() async -> SomaScores {
        let inputs = await SomaScoresReader.read(from: FixtureHealthSource(now: now, calendar: calendar), now: now, calendar: calendar)
        return SomaScores.compute(inputs)
    }

    private func today(scores: SomaScores) async -> PulseToday {
        let inputs = await PulseInputs.read(from: FixtureHealthSource(now: now, calendar: calendar), now: now, calendar: calendar)
        return PulseToday.make(from: inputs, scores: scores, calendar: calendar)
    }

    // MARK: - The file

    @Test("A year of fixture scores and the Today page come back equal")
    func roundTrip() async throws {
        let scores = await scores()
        var page = await today(scores: scores)
        try await withStore { store in
            let reading = HealthReading(metric: "HKQuantityTypeIdentifierStepCount", value: 4_210, unit: .count,
                                        start: now.addingTimeInterval(-3_600), end: now)
            try store.save(HealthSnapshot(savedAt: now, scores: scores, today: page,
                                          readings: [reading.metric: reading], durations: ["sleep": 27_000]))
            let loaded = try #require(store.load(now: now.addingTimeInterval(600), calendar: calendar))
            #expect(loaded.scores == scores)
            // The day's events carry navigation, not data: they are left out.
            page.events = []
            #expect(loaded.today == page)
            #expect(loaded.readings[reading.metric] == reading)
            #expect(loaded.durations["sleep"] == 27_000)
        }
    }

    @Test("No file reads as no snapshot")
    func missingFile() async {
        await withStore { store in
            #expect(store.load(now: now, calendar: calendar) == nil)
        }
    }

    @Test("A corrupt, empty or truncated file reads as no snapshot, never a crash")
    func corruptFile() async throws {
        try await withStore { store in
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for bytes in [Data(), Data("{".utf8), Data("not json".utf8), Data(repeating: 0xFF, count: 512),
                          Data(#"{"version":1,"savedAt":"yesterday"}"#.utf8)] {
                try bytes.write(to: store.url)
                #expect(store.load(now: now, calendar: calendar) == nil)
            }
            // Half of a real file, as a crash mid-write would have left it
            // without the atomic write.
            try store.save(HealthSnapshot(savedAt: now, scores: await scores()))
            let whole = try Data(contentsOf: store.url)
            try whole.prefix(whole.count / 2).write(to: store.url)
            #expect(store.load(now: now, calendar: calendar) == nil)
        }
    }

    @Test("A snapshot of another shape is dropped")
    func otherVersion() async throws {
        try await withStore { store in
            var snapshot = HealthSnapshot(savedAt: now)
            snapshot.version = HealthSnapshot.version + 1
            try store.save(snapshot)
            #expect(store.load(now: now, calendar: calendar) == nil)
        }
    }

    @Test("Past a week, or dated in the future, the snapshot is not shown")
    func tooOldOrFuture() async throws {
        try await withStore { store in
            try store.save(HealthSnapshot(savedAt: now.addingTimeInterval(-8 * 86_400)))
            #expect(store.load(now: now, calendar: calendar) == nil)
            try store.save(HealthSnapshot(savedAt: now.addingTimeInterval(3_600)))
            #expect(store.load(now: now, calendar: calendar) == nil)
        }
    }

    @Test("On another day the scores stay, the day's own numbers go")
    func anotherDay() async throws {
        let scores = await scores()
        let page = await today(scores: scores)
        try await withStore { store in
            let reading = HealthReading(metric: "steps", value: 9_000, unit: .count, start: now, end: now)
            try store.save(HealthSnapshot(savedAt: now, scores: scores, today: page,
                                          readings: ["steps": reading], durations: ["sleep": 1]))
            let tomorrow = try #require(store.load(now: now.addingTimeInterval(86_400), calendar: calendar))
            #expect(tomorrow.scores == scores)
            #expect(tomorrow.today == nil)
            #expect(tomorrow.readings.isEmpty)
            #expect(tomorrow.durations.isEmpty)
        }
    }

    @Test("Clearing removes the file")
    func clear() async throws {
        try await withStore { store in
            try store.save(HealthSnapshot(savedAt: now))
            store.clear()
            #expect(!FileManager.default.fileExists(atPath: store.url.path))
            store.clear()
        }
    }

    // MARK: - The dashboard

    @Test("A launch opens on the snapshot, ready, and says it is updating")
    func launchOpensOnTheSnapshot() async throws {
        let scores = await scores()
        try await withStore { store in
            try store.save(HealthSnapshot(savedAt: Date().addingTimeInterval(-600), scores: scores))
            let dashboard = HealthDashboard(source: EmptyHealthSource(), snapshots: store)
            #expect(dashboard.scores == scores)
            #expect(dashboard.status == .ready)
            #expect(dashboard.isShowingCache)
        }
    }

    @Test("The first read replaces the snapshot, settles the indicator and writes the file again")
    func firstReadTakesOver() async throws {
        let scores = await scores()
        try await withStore { store in
            let written = Date().addingTimeInterval(-600)
            try store.save(HealthSnapshot(savedAt: written, scores: scores))
            let dashboard = HealthDashboard(source: FixtureHealthSource(), snapshots: store)

            await dashboard.loadToday(force: true)

            #expect(!dashboard.isShowingCache)
            #expect(dashboard.today != nil)
            // The writes run off the main actor, the scores' first and the
            // page's after it; give the last a moment to land.
            var saved = store.load()
            for _ in 0..<100 where saved?.today == nil {
                try await Task.sleep(for: .milliseconds(20))
                saved = store.load()
            }
            #expect((saved?.savedAt ?? .distantPast) > written)
            #expect(saved?.today != nil)
        }
    }

    @Test("Without a store, nothing is read and nothing is written")
    func noStoreNoFile() async throws {
        try await withStore { store in
            let dashboard = HealthDashboard(source: FixtureHealthSource())
            await dashboard.loadToday(force: true)
            #expect(!dashboard.isShowingCache)
            #expect(!FileManager.default.fileExists(atPath: store.url.path))
        }
    }
}
