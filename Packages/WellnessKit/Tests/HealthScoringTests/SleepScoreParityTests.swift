//
//  SleepScoreParityTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  One night must produce ONE score.
//
//  `RealHealthMath.sleepScore` takes nine inputs. The live Sleep dial passed
//  all nine, decomposing the hypnogram for efficiency, continuity and the HR
//  dip. `sleepScoreSeries`, which is what the energy ledger charges from,
//  passed four: hours, need, REM, deep. Zero-and-renormalize then rescaled the
//  surviving 65 weight back to 100, so the same night carried two different
//  numbers depending on who asked.
//
//  Renormalizing is right for a night whose data does not exist. It is not
//  right for one whose data exists and was never passed, and the effect was
//  not a harmless offset: without the efficiency, continuity and HR-dip terms
//  the score is COMPRESSED toward the middle. It flattered fragmented nights
//  and shortchanged genuinely good ones.
//

import XCTest
@testable import HealthScoring

final class SleepScoreParityTests: XCTestCase {

    private let need = 8 * 3600

    private func hypnogram() -> [(stage: String, seconds: Int)] {
        [("core", 70 * 60), ("deep", 40 * 60), ("awake", 6 * 60), ("core", 55 * 60),
         ("rem", 45 * 60), ("deep", 25 * 60), ("awake", 9 * 60), ("core", 60 * 60),
         ("rem", 45 * 60), ("awake", 10 * 60), ("core", 55 * 60)]
    }

    /// The invariant the shared function exists to hold: the hypnogram entry
    /// point and the nine-input call must agree exactly, so the Sleep page and
    /// the history series cannot drift apart again.
    func test_hypnogramPathMatchesTheNineInputPath() throws {
        let night = hypnogram()
        let asleep = night.filter { $0.stage != "awake" }.reduce(0) { $0 + $1.seconds }
        let inBed = night.reduce(0) { $0 + $1.seconds }
        let deep = night.filter { $0.stage == "deep" }.reduce(0) { $0 + $1.seconds }
        let rem = night.filter { $0.stage == "rem" }.reduce(0) { $0 + $1.seconds }
        let wakes = night.filter { $0.stage == "awake" }.count

        let shared = try XCTUnwrap(RealHealthMath.sleepScore(
            hypnogram: night, needSeconds: need,
            nightHR: 52, dayRHR: 58, ageYears: 26))
        let spelledOut = try XCTUnwrap(RealHealthMath.sleepScore(
            asleepSeconds: asleep, needSeconds: need, inBedSeconds: inBed,
            remSeconds: rem, deepSeconds: deep, awakeningCount: wakes,
            nightHR: 52, dayRHR: 58, ageYears: 26))
        XCTAssertEqual(shared, spelledOut)
    }

    /// Missing data must never read as perfect data. A hypnogram with no awake
    /// segment never measured wake, so `inBed == asleep` would fabricate 100%
    /// efficiency and zero awakenings. Both terms must be DROPPED instead.
    func test_absentWakeMeasurementDropsTermsRatherThanScoringThemPerfect() throws {
        let noWake: [(stage: String, seconds: Int)] = [
            ("core", 6 * 3600), ("deep", 3600), ("rem", 3600)
        ]
        let fromHypnogram = try XCTUnwrap(RealHealthMath.sleepScore(
            hypnogram: noWake, needSeconds: need, ageYears: 26))
        let withoutThoseTerms = try XCTUnwrap(RealHealthMath.sleepScore(
            asleepSeconds: 8 * 3600, needSeconds: need,
            remSeconds: 3600, deepSeconds: 3600, ageYears: 26))
        XCTAssertEqual(fromHypnogram, withoutThoseTerms)
    }

    func test_allAwakeNightIsNilNotZeroDivided() {
        XCTAssertNil(RealHealthMath.sleepScore(hypnogram: [("awake", 3600)],
                                               needSeconds: need))
    }

    /// The point of the fix, and the reason it is not a uniform lowering: the
    /// four-input score cannot see fragmentation, so it rated a broken night
    /// far too kindly. The full score must separate the two nights much more
    /// sharply than the old one did.
    func test_fragmentationIsVisibleAgain() throws {
        var fragmented: [(stage: String, seconds: Int)] = []
        for _ in 0..<9 {
            fragmented.append(("core", 20 * 60))
            fragmented.append(("awake", 8 * 60))
        }
        fragmented.append(("deep", 30 * 60))
        fragmented.append(("rem", 40 * 60))

        let asleep = fragmented.filter { $0.stage != "awake" }.reduce(0) { $0 + $1.seconds }
        let deep = fragmented.filter { $0.stage == "deep" }.reduce(0) { $0 + $1.seconds }
        let rem = fragmented.filter { $0.stage == "rem" }.reduce(0) { $0 + $1.seconds }

        let blindToFragmentation = try XCTUnwrap(RealHealthMath.sleepScore(
            asleepSeconds: asleep, needSeconds: need,
            remSeconds: rem, deepSeconds: deep, ageYears: 26))
        let full = try XCTUnwrap(RealHealthMath.sleepScore(
            hypnogram: fragmented, needSeconds: need,
            nightHR: 57, dayRHR: 58, ageYears: 26))

        XCTAssertLessThan(full, blindToFragmentation - 5,
                          "Nine awakenings and 78% efficiency must cost real points.")
    }

    /// The other direction, which is why this is a correction and not a
    /// penalty: a genuinely restorative night was being SHORTCHANGED, because
    /// the terms that reward it (high efficiency, an unbroken night, a deep
    /// overnight HR dip) were the very ones being dropped.
    func test_aGenuinelyGoodNightScoresHigherThanBefore() throws {
        let good: [(stage: String, seconds: Int)] = [
            ("core", 100 * 60), ("deep", 55 * 60), ("rem", 70 * 60), ("awake", 4 * 60),
            ("core", 90 * 60), ("deep", 30 * 60), ("rem", 50 * 60)
        ]
        let asleep = good.filter { $0.stage != "awake" }.reduce(0) { $0 + $1.seconds }
        let deep = good.filter { $0.stage == "deep" }.reduce(0) { $0 + $1.seconds }
        let rem = good.filter { $0.stage == "rem" }.reduce(0) { $0 + $1.seconds }

        let old = try XCTUnwrap(RealHealthMath.sleepScore(
            asleepSeconds: asleep, needSeconds: need,
            remSeconds: rem, deepSeconds: deep, ageYears: 26))
        let full = try XCTUnwrap(RealHealthMath.sleepScore(
            hypnogram: good, needSeconds: need,
            nightHR: 48, dayRHR: 58, ageYears: 26))

        XCTAssertGreaterThan(full, old,
                             "The dropped terms were the ones that reward a good night.")
    }
}
