//
//  EnergyLedgerEquilibriumTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Pins the battery's SCALE to measured population data instead of taste.
//
//  Anchors, from Garmin Connect's published 2024 aggregate (the largest
//  public sample of a Body-Battery-shaped metric): the average morning
//  reads 71, the average evening low reads 22, the average day therefore
//  drains 49 points, and the displayed value never falls below 5. A
//  typical night lifts the bank 40-60 points, the very best nights 60-70.
//
//  These tests exist because the ledger has drifted off that scale twice.
//  First a linear quality map settled the fixed point at ~0 and the clamp
//  kept it there. Then the correction overshot: `chargeQuality x
//  sleepClosureFraction` let a typical night close 72% of the headroom
//  against a drain inflated to match, which read plausibly in aggregate
//  but collapsed through the floor on any day that was not easy. The v4
//  model pins BOTH ends at once: `nightClosureMax` caps what a night can
//  return, and `dailyStrainDrain` saturates what a day can cost.
//

import XCTest
@testable import HealthScoring

final class EnergyLedgerEquilibriumTests: XCTestCase {

    /// The headline anchor. An ordinary repeated day must settle where the
    /// population actually sits: morning 71, evening 22, drain 49. This is
    /// the test that says the scale is right; the others say it degrades
    /// sensibly on either side of it.
    func testTypicalDaySettlesOnTheMeasuredAnchor() throws {
        let days = 30
        let ledger = RealHealthMath.energyLedger(
            sleepScores: Array(repeating: 75.0, count: days),
            strains: Array(repeating: 40.0, count: days),
            sleepHours: Array(repeating: 7.5, count: days))
        let morning = try XCTUnwrap(ledger.morning.last.flatMap { $0 })
        let evening = try XCTUnwrap(ledger.end.last.flatMap { $0 })

        XCTAssertEqual(morning, 71, accuracy: 4,
                       "Garmin's population morning average is 71.")
        XCTAssertEqual(evening, 22, accuracy: 4,
                       "Garmin's population evening low is 22.")
        XCTAssertEqual(morning - evening, 49, accuracy: 5,
                       "The average day drains 49 points.")
    }

    /// A night returns 40-60 points typically and 60-70 at its very best.
    /// Guards the other side of `nightClosureMax`: capping the closure must
    /// not make a great night feel worthless.
    func testNightRechargeSitsInTheMeasuredBand() {
        let typical = VitalitySections.sleepCharge(previousReserve: 22, sleepScore: 75,
                                                   lateWorkoutPenalty: 0, sleepHours: 7.5) - 22
        XCTAssertGreaterThan(typical, 40)
        XCTAssertLessThan(typical, 60)

        let best = VitalitySections.sleepCharge(previousReserve: VitalitySections.batteryFloor,
                                                sleepScore: 95, lateWorkoutPenalty: 0,
                                                sleepHours: 8.5) - VitalitySections.batteryFloor
        XCTAssertGreaterThan(best, 58)
        XCTAssertLessThan(best, 72, "Even a perfect night cannot refill the bank outright.")
    }

    /// A good long night from a modest evening must wake NEAR the top of
    /// the range without reaching it: 100 stays asymptotic.
    func testGoodLongNightWakesHigh() {
        let ledger = RealHealthMath.energyLedger(
            sleepScores: [75, 90],
            strains: [40, 0],
            sleepHours: [7.5, 8.0])
        let morning = ledger.morning.last.flatMap { $0 } ?? 0
        XCTAssertGreaterThan(morning, 75)
        XCTAssertLessThan(morning, 92, "100 stays asymptotic, not a daily ceiling.")
    }

    /// A hard training day must cost real points without erasing the
    /// scale. This is the case the old linear strain term broke: at
    /// `0.45 x strain` a strain-80 day cost 36 on top of a ~30-point
    /// homeostatic burn, more than any night could return, so the fixed
    /// point sat below the floor and every evening read the same.
    func testHardTrainingDaysStayReadable() throws {
        let days = 21
        let ledger = RealHealthMath.energyLedger(
            sleepScores: Array(repeating: 75.0, count: days),
            strains: Array(repeating: 80.0, count: days),
            sleepHours: Array(repeating: 7.0, count: days))
        let morning = try XCTUnwrap(ledger.morning.last.flatMap { $0 })
        let evening = try XCTUnwrap(ledger.end.last.flatMap { $0 })
        XCTAssertGreaterThan(morning, 55,
                             "Hard training must not make every morning unusable.")
        XCTAssertLessThan(morning, 71,
                          "It must still read lower than an ordinary week.")
        XCTAssertLessThan(evening, 22)
    }

    /// The floor is 5, not 0. Sustained overload still bottoms the bank
    /// out, but the bottom is a readable value rather than an absorbing
    /// state that makes every catastrophic evening identical.
    func testSustainedOverloadBottomsOutAtTheFloor() {
        let days = 10
        let ledger = RealHealthMath.energyLedger(
            sleepScores: Array(repeating: 25.0, count: days),
            strains: Array(repeating: 100.0, count: days),
            sleepHours: Array(repeating: 4.0, count: days))
        XCTAssertEqual(ledger.end.last.flatMap { $0 } ?? -1,
                       VitalitySections.batteryFloor, accuracy: 0.001,
                       "Sustained overload empties the bank to the floor, never below.")
    }

    /// Recovery from the floor: one decent night must restore a morning
    /// you can actually run a day on.
    func testDecentNightRechargesFromEmpty() {
        let ledger = RealHealthMath.energyLedger(
            sleepScores: [25, 25, 25, 80],
            strains: [100, 100, 100, 30],
            sleepHours: [4, 4, 4, 7.5])
        let morning = ledger.morning.last.flatMap { $0 }
        XCTAssertGreaterThan(morning ?? 0, 55,
                             "A decent night from empty must restore a usable morning level.")
    }

    /// No displayed battery value, anywhere in the ledger, may sit below
    /// the floor or above 100.
    func testLedgerNeverLeavesTheDisplayableRange() {
        let ledger = RealHealthMath.energyLedger(
            sleepScores: [nil, 10, 95, 40, nil, 88, 60],
            strains: [100, 90, 0, 55, 70, 5, 100],
            sleepHours: [nil, 3.5, 9.5, 6, nil, 8, 5])
        for value in (ledger.morning + ledger.end).compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(value, VitalitySections.batteryFloor)
            XCTAssertLessThanOrEqual(value, 100)
        }
    }
}
