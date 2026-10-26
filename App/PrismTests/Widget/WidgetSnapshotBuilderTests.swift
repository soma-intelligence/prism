//
//  WidgetSnapshotBuilderTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthScoring
import SomaWidgetKit
@testable import Prism

/// 2026-10-03T12:00:00Z, the widget fixture's own noon.
private let fixedNow = Date(timeIntervalSince1970: 1_791_028_800)

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)")
}

@Suite("Widget snapshot builder")
@MainActor
struct WidgetSnapshotBuilderTests {
    @Test func buildsScoresAndSeries() {
        var s = SomaScores.fixture
        s.recovery = 82
        s.recoverySeries = Array(repeating: 70, count: 23) + [71, 72, 73, 74, 75, 76, 82]
        let snap = WidgetSnapshotBuilder.build(
            .init(scores: s, restingHR: 52, hrv: 64, activeKcal: 600, basalKcal: 1700,
                  tally: .empty(day: "2026-10-03"), eatenKcal: 1980),
            now: fixedNow
        )
        #expect(snap.recovery.value == 82)
        #expect(snap.recovery.series7 == [71, 72, 73, 74, 75, 76, 82])
        #expect(snap.burnedKcal == 2300)
        #expect(snap.eatenKcal == 1980)
        #expect(snap.restingHR.value == 52)
        #expect(snap.hrv.value == 64)
        #expect(snap.generatedAt == fixedNow)
        #expect(snap.hasData)
    }

    @Test func noScoresNoData() {
        let snap = WidgetSnapshotBuilder.build(
            .init(scores: nil, restingHR: nil, hrv: nil, activeKcal: nil, basalKcal: nil,
                  tally: .empty(day: "2026-10-03"), eatenKcal: nil),
            now: fixedNow
        )
        #expect(!snap.hasData)
        #expect(snap.recovery.value == nil)
        #expect(snap.burnedKcal == nil)
        #expect(snap.hypnogram == nil)
    }

    @Test func burnedIsActiveAloneWithoutBasal() {
        let snap = WidgetSnapshotBuilder.build(
            .init(scores: nil, restingHR: nil, hrv: nil, activeKcal: 420, basalKcal: nil,
                  tally: .empty(day: "2026-10-03"), eatenKcal: nil),
            now: fixedNow
        )
        #expect(snap.burnedKcal == 420)
    }

    @Test func vitalsTracesStagesAndEnergy() {
        var s = SomaScores.fixture
        s.stress = 39
        s.stressSeries = [50, 45, 41, 50, 38, 36, 42, 39]
        s.energy = 70
        s.energyCurve = [.init(date: fixedNow.addingTimeInterval(-3600), level: 72), .init(date: fixedNow, level: 70)]
        s.detail.restingBaseline = [60, 58, 54, 53, 53, 52, 52, 51, 52]
        s.detail.hrvBaseline = [50, 58, 61, 60, 63, 66, 62, 64]
        s.detail.sleepHours = [8, 6.8, 7.4, 7.0, 7.6, nil, 7.3, 7.2]
        let bed = fixedNow.addingTimeInterval(-15 * 3600)
        let wake = fixedNow.addingTimeInterval(-7 * 3600)
        s.detail.lastNight = ScoringNightWindow(start: bed, end: wake)
        s.detail.lastNightStages = [
            ScoringStageRun(stage: "awake", start: bed, end: bed.addingTimeInterval(600)),
            ScoringStageRun(stage: "deep", start: bed.addingTimeInterval(600), end: bed.addingTimeInterval(3600)),
            ScoringStageRun(stage: "unknown", start: bed.addingTimeInterval(3600), end: bed.addingTimeInterval(4000)),
            ScoringStageRun(stage: "rem", start: bed.addingTimeInterval(4000), end: wake),
        ]
        let snap = WidgetSnapshotBuilder.build(
            .init(scores: s, restingHR: nil, hrv: nil, activeKcal: nil, basalKcal: nil,
                  tally: .empty(day: "2026-10-03"), eatenKcal: nil),
            now: fixedNow
        )
        #expect(snap.stress.series7 == [45, 41, 50, 38, 36, 42, 39])
        #expect(snap.energyNow == 70)
        #expect(snap.energyCurve.map(\.level) == [72, 70])
        #expect(snap.restingHR.series7 == [54, 53, 53, 52, 52, 51, 52])
        #expect(snap.restingHR.value == nil)
        #expect(snap.hrv.series7 == [58, 61, 60, 63, 66, 62, 64])
        #expect(snap.sleepHours.series7 == [6.8, 7.4, 7.0, 7.6, nil, 7.3, 7.2])
        #expect(snap.sleepHours.value == 7.2)
        #expect(snap.sleepBand == bed...wake)
        #expect(snap.hypnogram?.map(\.kind) == [.awake, .deep, .rem])
        #expect(snap.hasData)
    }

    @Test func reloadsOnlyChangedKinds() {
        var reloaded: [WidgetKind] = []
        let pub = WidgetPublisher(store: SnapshotStore(directory: tempDir()), reload: { reloaded.append($0) })
        pub.publish(.placeholder)
        reloaded.removeAll()
        var next = SomaWidgetSnapshot.placeholder
        next.tally.waterMl += 250
        next.generatedAt += 60
        pub.publish(next)
        #expect(reloaded == [.log])
    }

    @Test func firstPublishReloadsEverything() {
        var reloaded: [WidgetKind] = []
        let pub = WidgetPublisher(store: SnapshotStore(directory: tempDir()), reload: { reloaded.append($0) })
        pub.publish(.placeholder)
        #expect(Set(reloaded) == Set(WidgetKind.allCases))
    }

    @Test func ageAloneReloadsNothing() {
        var reloaded: [WidgetKind] = []
        let dir = tempDir()
        let pub = WidgetPublisher(store: SnapshotStore(directory: dir), reload: { reloaded.append($0) })
        pub.publish(.placeholder)
        reloaded.removeAll()
        var next = SomaWidgetSnapshot.placeholder
        next.generatedAt += 3600
        pub.publish(next)
        #expect(reloaded.isEmpty)
        #expect(SnapshotStore(directory: dir).read()?.generatedAt == next.generatedAt)
    }

    @Test func slicesMapToTheirKinds() {
        var reloaded: [WidgetKind] = []
        let pub = WidgetPublisher(store: SnapshotStore(directory: tempDir()), reload: { reloaded.append($0) })
        pub.publish(.placeholder)
        reloaded.removeAll()
        var next = SomaWidgetSnapshot.placeholder
        next.recovery.value = 60
        next.hrv.value = 40
        next.stress.value = 20
        next.eatenKcal = 100
        pub.publish(next)
        #expect(Set(reloaded) == [.scores, .vitals, .strain, .fuel])
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// What a pass that read no Health builds: today's Track log alone.
    private func trackOnly(at now: Date, day: String, eaten: Double? = 500) -> SomaWidgetSnapshot {
        WidgetSnapshotBuilder.build(
            .init(scores: nil, restingHR: nil, hrv: nil, activeKcal: nil, basalKcal: nil,
                  tally: .init(day: day, waterMl: 750), eatenKcal: eaten),
            now: now
        )
    }

    @Test func unreadHealthSlicesCarryOver() {
        let old = SomaWidgetSnapshot.placeholder
        let new = trackOnly(at: fixedNow.addingTimeInterval(3600), day: "2026-10-03")
        let carried = WidgetPublisher.carryingUnread(new, from: old, read: .none, calendar: utc)
        #expect(carried.sleep == old.sleep)
        #expect(carried.recovery == old.recovery)
        #expect(carried.strain == old.strain)
        #expect(carried.stress == old.stress)
        #expect(carried.energyNow == old.energyNow)
        #expect(carried.energyCurve == old.energyCurve)
        #expect(carried.sleepBand == old.sleepBand)
        #expect(carried.sleepHours == old.sleepHours)
        #expect(carried.hypnogram == old.hypnogram)
        #expect(carried.restingHR == old.restingHR)
        #expect(carried.hrv == old.hrv)
        #expect(carried.burnedKcal == old.burnedKcal)
        // The Track log is always read: its slices are the new ones.
        #expect(carried.eatenKcal == 500)
        #expect(carried.tally.waterMl == 750)
        #expect(carried.generatedAt == new.generatedAt)
        #expect(carried.hasData)
    }

    @Test func freshHealthSlicesReplace() {
        var old = SomaWidgetSnapshot.placeholder
        old.generatedAt = fixedNow.addingTimeInterval(-86_400)
        old.tally.day = "2026-10-02"
        var scores = SomaScores.fixture
        scores.recovery = 60
        let read = WidgetSnapshotBuilder.build(
            .init(scores: scores, restingHR: nil, hrv: nil, activeKcal: 300, basalKcal: nil,
                  tally: .empty(day: "2026-10-03"), eatenKcal: nil),
            now: fixedNow
        )
        let carried = WidgetPublisher.carryingUnread(read, from: old, read: .all, calendar: utc)
        #expect(carried.recovery.value == 60)
        #expect(carried.sleep.value == nil)
        #expect(carried.energyCurve.isEmpty)
        #expect(carried.burnedKcal == 300)

        let nothing = trackOnly(at: fixedNow, day: "2026-10-03", eaten: nil)
        let blank = WidgetPublisher.carryingUnread(nothing, from: old, read: .all, calendar: utc)
        #expect(blank.recovery.value == nil)
        #expect(blank.restingHR.value == nil)
        #expect(!blank.hasData)
    }

    @Test func unreadPassAfterMidnightKeepsData() {
        let old = SomaWidgetSnapshot.placeholder
        // 00:30 the next day, Health not read in this process yet.
        let new = trackOnly(at: fixedNow.addingTimeInterval(12.5 * 3600), day: "2026-10-04", eaten: nil)
        let carried = WidgetPublisher.carryingUnread(new, from: old, read: .none, calendar: utc)
        #expect(carried.hasData)
        #expect(carried.recovery == old.recovery)
        // Burned is a day's total: yesterday's does not carry into today.
        #expect(carried.burnedKcal == nil)
        #expect(WidgetPublisher.changedKinds(from: old, to: carried, calendar: utc).contains(.log))
    }

    @Test func staleOrOtherDayPreviousReloadsEverything() {
        var reloaded: [WidgetKind] = []
        let pub = WidgetPublisher(store: SnapshotStore(directory: tempDir()), reload: { reloaded.append($0) })
        pub.publish(.placeholder)
        reloaded.removeAll()
        var next = SomaWidgetSnapshot.placeholder
        next.generatedAt += 13 * 3600
        pub.publish(next)
        #expect(Set(reloaded) == Set(WidgetKind.allCases))

        // 20:00 to 01:00: fresh, but another day.
        var old = SomaWidgetSnapshot.placeholder
        old.generatedAt += 8 * 3600
        var otherDay = old
        otherDay.generatedAt += 5 * 3600
        #expect(WidgetPublisher.changedKinds(from: old, to: otherDay, calendar: utc) == Set(WidgetKind.allCases))
        var sameDay = old
        sameDay.generatedAt += 3600
        #expect(WidgetPublisher.changedKinds(from: old, to: sameDay, calendar: utc).isEmpty)
    }

    @Test func vitalsCarryOverWithinTheDay() {
        let old = SomaWidgetSnapshot(
            generatedAt: fixedNow,
            restingHR: .init(value: 54), hrv: .init(value: 61)
        )
        let new = SomaWidgetSnapshot(
            generatedAt: fixedNow.addingTimeInterval(3600),
            restingHR: .init(value: nil, series7: [50]), hrv: .init(value: 70)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let carried = WidgetPublisher.carryingVitals(new, from: old, calendar: calendar)
        #expect(carried.restingHR.value == 54)
        #expect(carried.restingHR.series7 == [50])
        #expect(carried.hrv.value == 70)
        #expect(carried.hasData)

        let nextDay = SomaWidgetSnapshot(generatedAt: fixedNow.addingTimeInterval(86_400))
        #expect(WidgetPublisher.carryingVitals(nextDay, from: old, calendar: calendar).restingHR.value == nil)
    }
}
