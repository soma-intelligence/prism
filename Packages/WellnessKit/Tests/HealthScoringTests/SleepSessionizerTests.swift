//
//  SleepSessionizerTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Pins down the night-vs-nap classifier. All dates are built in UTC
//  and the UTC calendar is passed in, so the wake-window check is
//  deterministic regardless of the machine's timezone. `base` is
//  midnight of the wake day; hours can be negative (the evening before)
//  or past 24 (later the same day).
//

import XCTest
@testable import HealthScoring

final class SleepSessionizerTests: XCTestCase {

    private let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private lazy var base: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 15
        comps.hour = 0; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return cal.date(from: comps)!
    }()

    private func at(_ hour: Double) -> Date {
        base.addingTimeInterval(hour * 3600)
    }

    private func sample(_ stage: String, _ from: Double, _ to: Double) -> SleepSampleLite {
        SleepSampleLite(stage: stage, start: at(from), end: at(to))
    }

    private func src(_ stage: String, _ from: Double, _ to: Double,
                     _ source: String) -> SleepSampleLite {
        SleepSampleLite(stage: stage, start: at(from), end: at(to), source: source)
    }

    private func run(_ samples: [SleepSampleLite], now: Double) -> [RealSleepSession] {
        SleepSessionizer.sessions(from: samples, now: at(now), calendar: cal)
    }

    // A normal night (23:00 -> 07:00) becomes exactly one .night.
    func testNightOnly() {
        let samples = [
            sample("core", -1.0, 1.0),
            sample("deep", 1.0, 3.0),
            sample("rem", 3.0, 5.0),
            sample("core", 5.0, 7.0),
        ]
        let sessions = run(samples, now: 8.0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, .night)
        XCTAssertEqual(sessions.first?.asleepSeconds, 8 * 3600)
    }

    // Awake segments do not count toward asleep time.
    func testAwakeExcludedFromAsleep() {
        let samples = [
            sample("awake", -1.0, -0.5),   // 30 min awake in bed
            sample("core", -0.5, 6.5),     // 7 h asleep
        ]
        let sessions = run(samples, now: 8.0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.asleepSeconds, 7 * 3600)
    }

    // Night plus a 36-minute afternoon nap: two sessions, one of each.
    func testNightPlusNap() {
        let samples = [
            sample("core", -1.0, 7.0),
            sample("core", 14.0, 14.6),    // 36 min nap
        ]
        let sessions = run(samples, now: 18.0)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.filter { $0.kind == .night }.count, 1)
        XCTAssertEqual(sessions.filter { $0.kind == .nap }.count, 1)
        XCTAssertEqual(sessions.first { $0.kind == .nap }?.source, .healthKit)
    }

    // A 5-minute micro-arousal is dropped, not surfaced as a nap.
    func testMicroArousalDropped() {
        let samples = [
            sample("core", -1.0, 7.0),
            sample("core", 15.0, 15.0 + 5.0 / 60.0),   // 5 min
        ]
        let sessions = run(samples, now: 18.0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, .night)
    }

    // Two distinct daytime naps both surface.
    func testTwoNaps() {
        let samples = [
            sample("core", -1.0, 7.0),
            sample("core", 13.0, 13.5),    // 30 min
            sample("core", 16.0, 16.75),   // 45 min
        ]
        let sessions = run(samples, now: 18.0)
        XCTAssertEqual(sessions.filter { $0.kind == .nap }.count, 2)
        XCTAssertEqual(sessions.filter { $0.kind == .night }.count, 1)
    }

    // A 20-minute gap keeps a fragmented night as ONE session.
    func testShortGapMergesNight() {
        let samples = [
            sample("core", -2.0, -1.5),    // 22:00 - 22:30
            sample("core", -1.17, 6.0),    // 22:50 - 06:00 (20 min gap)
        ]
        let sessions = run(samples, now: 8.0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, .night)
    }

    // A gap over an hour splits: the morning-ending cluster is the
    // night, the short evening cluster is a nap.
    func testLongGapSplits() {
        let samples = [
            sample("core", -2.0, -1.5),    // 22:00 - 22:30, ends hour 22
            sample("core", 1.0, 6.0),      // 01:00 - 06:00, ends in window
        ]
        let sessions = run(samples, now: 8.0)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first { $0.kind == .night }?.end, at(6.0))
    }

    // Night-shift: a long daytime sleep with no wake-window end is
    // still promoted to the night via the fallback floor.
    func testLongDaytimeSleepBecomesNight() {
        let samples = [
            sample("core", 13.0, 16.0),    // 3 h, ends hour 16
        ]
        let sessions = run(samples, now: 18.0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, .night)
    }

    // A lone short daytime sleep stays a nap, never "the night".
    func testShortDaytimeSleepStaysNap() {
        let samples = [
            sample("core", 13.0, 13.0 + 40.0 / 60.0),   // 40 min, ends hour 13
        ]
        let sessions = run(samples, now: 18.0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, .nap)
    }

    // Two nights land in the 36h read when checking in the morning. The
    // MOST RECENT night is the primary sleep, even when the night before
    // it was LONGER. Before the recency anchor the longer older night
    // stole "the night" and last night was demoted to a nap.
    func testMostRecentNightWinsOverLongerPriorNight() {
        let samples = [
            sample("core", -27.0, -19.0),   // night before last: 8 h, ends 05:00
            sample("core", -1.0, 6.0),      // last night: 7 h, ends 06:00 today
        ]
        let sessions = run(samples, now: 9.0)
        XCTAssertEqual(sessions.filter { $0.kind == .night }.count, 1)
        XCTAssertEqual(sessions.first { $0.kind == .night }?.end, at(6.0))
        // The older, longer night is a prior cycle: it must NOT resurface
        // as today's nap (it would show in the sheet and charge energy).
        XCTAssertTrue(sessions.allSatisfy { $0.kind != .nap })
    }

    // A genuine daytime nap is never a wake-window ender, so the
    // prior-night drop leaves it untouched alongside the recent night.
    func testRecentNightKeepsDaytimeNapWithPriorNightPresent() {
        let samples = [
            sample("core", -27.0, -19.0),   // older, longer night (dropped)
            sample("core", -1.0, 6.0),      // last night (the night)
            sample("core", 13.0, 13.75),    // 45 min afternoon nap today
        ]
        let sessions = run(samples, now: 15.0)
        XCTAssertEqual(sessions.first { $0.kind == .night }?.end, at(6.0))
        XCTAssertEqual(sessions.filter { $0.kind == .nap }.count, 1)
        XCTAssertEqual(sessions.first { $0.kind == .nap }?.end, at(13.75))
    }

    // Two sources writing the same night must not stack: only the source
    // covering the most time is kept (Apple Health's per-source view), so
    // durations and the hypnogram match one tracker, not their sum.
    func testDominantSourceWinsOverOverlappingSecondSource() {
        let samples = [
            src("deep", -1.0, 2.0, "watch"),   // watch: detailed stages,
            src("rem", 2.0, 4.0, "watch"),     // 8 h total coverage
            src("core", 4.0, 7.0, "watch"),
            src("core", -1.0, 6.0, "app"),     // app: 7 h, one overlapping block
        ]
        let sessions = run(samples, now: 8.0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, .night)
        // 8 h from the watch, not 15 h (8 + 7) from stacking both.
        XCTAssertEqual(sessions.first?.asleepSeconds, 8 * 3600)
        // The watch's real stage sequence survived, not the app's block.
        XCTAssertTrue(sessions.first?.segments.contains { $0.stage == "deep" } ?? false)
        XCTAssertTrue(sessions.first?.segments.contains { $0.stage == "rem" } ?? false)
    }

    // Overlapping samples from one source are clipped, never summed.
    func testOverlapWithinSourceClipped() {
        let samples = [
            sample("core", -1.0, 5.0),   // 6 h
            sample("deep", 3.0, 6.0),    // overlaps the last 2 h, adds 1 h
        ]
        let sessions = run(samples, now: 8.0)
        // 7 h of clock time covered (-1 -> 6), not 9 h (6 + 3) summed.
        XCTAssertEqual(sessions.first?.asleepSeconds, 7 * 3600)
    }

    // No samples in, nothing out.
    func testEmpty() {
        XCTAssertTrue(run([], now: 8.0).isEmpty)
    }

    // The shared dedup pass the daily breakdown consumes: a night written
    // by two trackers yields ONE cluster with single-counted hours. This
    // is the Sleep Bank fix (a double-counted night read as need + 5 h
    // and pinned the bank at its +5 h cap overnight).
    func testDedupedClustersSingleCountTwoTrackerNight() {
        let samples = [
            src("core", -1.0, 3.0, "watch"),   // watch: 8 h coverage
            src("core", 3.0, 7.0, "watch"),
            src("core", -1.0, 7.0, "phone"),   // phone: the same 8 h block
        ]
        let clusters = SleepSessionizer.dedupedClusters(from: samples)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.asleepSeconds, 8 * 3600)
    }

    // A night and a separate nap stay two clusters, each single-source.
    func testDedupedClustersKeepNightAndNapSeparate() {
        let samples = [
            src("core", -1.0, 7.0, "watch"),
            src("core", 14.0, 15.0, "phone"),  // afternoon nap, other source
        ]
        let clusters = SleepSessionizer.dedupedClusters(from: samples)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.first?.asleepSeconds, 8 * 3600)
        XCTAssertEqual(clusters.last?.asleepSeconds, 3600)
    }

    // A single corrupt sample with an impossible multi-day span (a bad
    // HealthKit end date, or a mislogged manual block) must never become
    // the night. Left in, it dominated its source, clipped into one giant
    // segment and produced a 31 h "time asleep" that broke the sleep
    // score, the energy charge and the Sleep Bank. It is dropped before
    // clustering, so the real night recorded alongside it survives with
    // its true duration.
    func testCorruptOverlongSampleDropped() {
        let samples = [
            src("core", -1.0, 7.0, "watch"),      // real night: 8 h
            src("core", -25.0, 6.0, "badapp"),    // corrupt: 31 h single block
        ]
        let sessions = run(samples, now: 8.0)
        let night = sessions.first { $0.kind == .night }
        XCTAssertNotNil(night)
        XCTAssertEqual(night?.asleepSeconds, 8 * 3600)   // not 31 h
    }

    // The corrupt-sample guard bounds a physically impossible span; it
    // must NOT touch a genuinely long night (e.g. illness recovery), so a
    // 13 h night is kept in full.
    func testLongButPlausibleNightKept() {
        let samples = [
            sample("core", -4.0, 9.0),   // 13 h, ends 09:00 (in wake window)
        ]
        let sessions = run(samples, now: 10.0)
        XCTAssertEqual(sessions.first?.kind, .night)
        XCTAssertEqual(sessions.first?.asleepSeconds, 13 * 3600)
    }

    // Even with NO other data, a lone corrupt block yields no session at
    // all rather than an impossible night (callers then fall back to the
    // capped representative night).
    func testLoneCorruptSampleYieldsNoSession() {
        let clusters = SleepSessionizer.dedupedClusters(from: [
            sample("core", -25.0, 6.0),   // 31 h, the only sample
        ])
        XCTAssertTrue(clusters.isEmpty)
    }
}
