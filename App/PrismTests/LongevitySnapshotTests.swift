//
//  LongevitySnapshotTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

/// Who the numbers belong to in a test, switched by hand.
@MainActor
private final class Owner {
    var id = "a"
}

@Suite("Longevity snapshot: the numbers kept for the next opening")
@MainActor
struct LongevitySnapshotTests {
    let now = Date(timeIntervalSince1970: 1_790_700_000)
    /// Fixtures built once: the previews they start from read the clock.
    let muscles = MuscleFreshness.preview
    let environment: EnvironmentLensSnapshot

    init() {
        var report = EnvironmentReport.preview
        report.outside = EnvironmentConditions(temperature: 14, humidity: 70, low: 12, high: 20, hourly: [now: 13.5])
        environment = EnvironmentLensSnapshot(
            report: report, outdoorNight: 11.2, noise: 34,
            place: EnvironmentSun.Place(latitude: 37.44, longitude: -122.14, name: "Palo Alto"),
            isHere: true,
            sleepPlaces: [EnvironmentSleepPlace(id: "home", name: "Home", latitude: 37.4, longitude: -122.1,
                                                nights: 12, score: 81, isLastNight: true)]
        )
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "longevity-\(UUID().uuidString)")
    }

    private func body(steps: Double) -> BodyLensSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let readings = (0..<30).map { day in
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            return HealthReading(metric: BodyBiomarkerSpec.stepCount.identifier, value: steps + Double(day * 10),
                                 unit: .count, start: date, end: date)
        }
        var snapshot = BodyLensSnapshot.empty(now: now)
        snapshot.page = BodyOverview.preview
        snapshot.sex = .female
        snapshot.markers[.stepCount] = BodyBiomarkers.make(.stepCount, readings: readings, now: now, calendar: calendar)
        snapshot.muscles = muscles
        return snapshot
    }

    // MARK: Encode and decode

    @Test("Every lens survives a relaunch: written, then read back by a new store")
    func roundTrip() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "longevity-snapshot.json")
        let owner = Owner()

        let store = LongevitySnapshotStore(url: url, owner: { owner.id })
        let body = body(steps: 8_000)
        store.save(body: body, at: now)
        store.save(mind: .preview, at: now)
        store.save(environment: environment, at: now)
        await store.settle()
        #expect(FileManager.default.fileExists(atPath: url.path()))

        let relaunched = LongevitySnapshotStore(url: url, owner: { owner.id })
        #expect(relaunched.body == LongevityKept(value: body, savedAt: now))
        #expect(relaunched.mind == LongevityKept(value: MindLensModel.preview, savedAt: now))
        #expect(relaunched.environment == LongevityKept(value: environment, savedAt: now))
        #expect(relaunched.body?.value.markers[.stepCount]?.value == body.markers[.stepCount]?.value)
    }

    @Test("A lens written again replaces only itself")
    func partialWrite() async {
        let store = LongevitySnapshotStore(url: nil, owner: { "a" })
        store.save(body: body(steps: 8_000), at: now)
        store.save(mind: .preview, at: now)
        store.save(body: body(steps: 9_000), at: now.addingTimeInterval(60))
        #expect(store.mind?.value == .preview)
        #expect(store.body?.savedAt == now.addingTimeInterval(60))
        #expect(store.body?.value == body(steps: 9_000))
    }

    // MARK: Invalidation

    @Test("Someone else signing in finds nothing, and the file is gone")
    func otherOwnerOnRelaunch() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "longevity-snapshot.json")

        let store = LongevitySnapshotStore(url: url, owner: { "a" })
        store.save(body: body(steps: 8_000), at: now)
        await store.settle()

        let other = LongevitySnapshotStore(url: url, owner: { "b" })
        #expect(other.body == nil)
        #expect(other.mind == nil)
        await other.settle()
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test("An account change while the app runs drops the kept numbers at once")
    func otherOwnerInProcess() async {
        let owner = Owner()
        let store = LongevitySnapshotStore(url: nil, owner: { owner.id })
        store.save(body: body(steps: 8_000), at: now)
        #expect(store.body != nil)
        owner.id = "b"
        #expect(store.body == nil)
        owner.id = "a"
        #expect(store.body == nil, "Gone for good, not hidden")
    }

    @Test("Clearing, as Delete my data and signing out do, removes every lens and the file")
    func clearOnDelete() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "longevity-snapshot.json")

        let store = LongevitySnapshotStore(url: url, owner: { "a" })
        store.save(body: body(steps: 8_000), at: now)
        store.save(environment: environment, at: now)
        await store.settle()
        store.clear()
        await store.settle()
        #expect(store.body == nil)
        #expect(store.environment == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
        #expect(LongevitySnapshotStore(url: url, owner: { "a" }).body == nil)
    }

    @Test("Deleting what Mind keeps drops the Mind lens, mood strip and all, and leaves Body")
    func clearMind() {
        let store = LongevitySnapshotStore(url: nil, owner: { "a" })
        store.save(body: body(steps: 8_000), at: now)
        store.save(mind: .preview, at: now)
        store.clearMind()
        #expect(store.mind == nil)
        #expect(store.body != nil)
    }

    @Test("A file from another version reads as nothing and is removed")
    func versionMismatch() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "longevity-snapshot.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var old = LongevitySnapshot(owner: "a")
        old.version = LongevitySnapshot.currentVersion + 1
        old.mind = LongevityKept(value: .preview, savedAt: now)
        let data = try JSONEncoder().encode(old)
        #expect(LongevitySnapshot.read(data, owner: "a") == .otherVersion)
        try data.write(to: url)

        let store = LongevitySnapshotStore(url: url, owner: { "a" })
        #expect(store.mind == nil)
        await store.settle()
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test("A file that cannot be read falls back to empty")
    func unreadable() throws {
        #expect(LongevitySnapshot.read(Data("not json".utf8), owner: "a") == .unreadable)
        let shape = Data(#"{"version":1,"owner":"a","body":{"savedAt":3}}"#.utf8)
        #expect(LongevitySnapshot.read(shape, owner: "a") == .unreadable)
        #expect(LongevitySnapshot.read(try JSONEncoder().encode(LongevitySnapshot(owner: "a")), owner: "b") == .otherOwner)
    }

    @Test("The owner is a hash of the account id, never the id itself; this device when nobody is signed in")
    func ownerKey() {
        #expect(LongevitySnapshotStore.owner(of: nil) == "device")
        let id = "6f1c2a9e-0b7d-4c55-9a51-3d0f2b7e8c11"
        let key = LongevitySnapshotStore.owner(of: id)
        #expect(key.count == 64)
        #expect(!key.contains(id))
        #expect(key == LongevitySnapshotStore.owner(of: id.uppercased()))
        #expect(key != LongevitySnapshotStore.owner(of: "someone-else"))
    }

    // MARK: Cached, then fresh

    @Test("The kept numbers show until the fresh read lands, then the fresh ones")
    func keptThenFresh() {
        let kept = LongevityKept(value: body(steps: 8_000), savedAt: now.addingTimeInterval(-600))
        var shown = LongevityShown(kept: kept, fresh: nil)
        #expect(shown.value == kept.value)
        #expect(shown.isKept)

        shown.fresh = body(steps: 9_000)
        #expect(shown.value == body(steps: 9_000))
        #expect(!shown.isKept)
    }

    @Test("Nothing kept on a first launch: nothing to show until the read lands")
    func firstLaunch() {
        let shown = LongevityShown<BodyLensSnapshot>(kept: nil, fresh: nil)
        #expect(shown.value == nil)
        #expect(!shown.isKept)
        #expect(shown.updated(now: now) == nil)
    }

    @Test("Kept numbers say when they were read only once they are 12 hours old, and not after the fresh read")
    func updatedNote() {
        let young = LongevityShown(kept: LongevityKept(value: 1, savedAt: now.addingTimeInterval(-11 * 3_600)), fresh: nil)
        #expect(young.updated(now: now) == nil)

        let savedAt = now.addingTimeInterval(-13 * 3_600)
        var old = LongevityShown(kept: LongevityKept(value: 1, savedAt: savedAt), fresh: nil)
        #expect(old.updated(now: now) == savedAt)

        old.fresh = 2
        #expect(old.updated(now: now) == nil)
    }

    @Test("A fresh read kept, then a relaunch: the next opening starts from it, dated now")
    func freshBecomesKept() async {
        let store = LongevitySnapshotStore(url: nil, owner: { "a" })
        store.save(body: body(steps: 8_000), at: now.addingTimeInterval(-20 * 3_600))
        var shown = LongevityShown(kept: store.body, fresh: nil)
        #expect(shown.updated(now: now) != nil)

        let fresh = body(steps: 9_000)
        shown.fresh = fresh
        store.save(body: fresh, at: now)

        let next = LongevityShown(kept: store.body, fresh: nil)
        #expect(next.value == fresh)
        #expect(next.updated(now: now) == nil)
    }

    // MARK: The stress line's morph

    @Test("Today's stress sits on a fixed grid of half hours, gaps carrying a neighbour's height")
    func stressSlots() {
        let dayStart = now
        let samples = [0, 1, 2, 6].map { slot in
            MindStressSample(start: dayStart.addingTimeInterval(Double(slot) * 1_800), value: Double(slot * 10))
        }
        let slots = MindStressSlots(samples, dayStart: dayStart)
        #expect(slots.heights.count == MindStressSlots.count)
        #expect(slots.present.filter { $0 }.count == 4)
        #expect(slots.runs == [[0, 1, 2], [6]])
        #expect(slots.heights[2] == 0.2)
        #expect(slots.heights[3] == 0.2, "The nearest reading before the gap")
        #expect(slots.heights[49] == 0.6)
        #expect(MindStressSlots([], dayStart: dayStart).heights.allSatisfy { $0 == 0 })
    }
}
