//
//  StressEngineTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Centered personal-distribution stress model. Typical day ~35, exercise
//  excluded, no signal -> nil. See docs/calculations/01-stress.md.
//

import XCTest
@testable import HealthScoring

final class StressEngineTests: XCTestCase {

    // MARK: robustSpread

    func testRobustSpreadOfFlatSeriesHitsFloor() {
        let s = StressEngine.robustSpread([50, 50, 50, 50], floor: 2)
        XCTAssertEqual(s, 2, accuracy: 0.001)
    }

    func testRobustSpreadScalesWithMAD() {
        // values 10,20,30,40,50 -> median 30, abs dev 20,10,0,10,20 -> MAD 10
        // 1.4826 * 10 = 14.826
        let s = StressEngine.robustSpread([10, 20, 30, 40, 50], floor: 0)
        XCTAssertEqual(s, 14.826, accuracy: 0.01)
    }

    func testRobustSpreadTooFewValuesReturnsFloor() {
        XCTAssertEqual(StressEngine.robustSpread([42], floor: 3), 3, accuracy: 0.001)
        XCTAssertEqual(StressEngine.robustSpread([], floor: 3), 3, accuracy: 0.001)
    }

    // MARK: centered anchors

    func testTypicalDayReadsAroundThirtyFive() {
        // hrv exactly at baseline, rhr exactly at baseline -> z = 0.
        let s = StressEngine.dailyValue(hrv: 55, hrvBaseline: 55, hrvSpread: 0.2,
                                        restingHR: 55, restingHRBaseline: 55, rhrSpread: 4)
        XCTAssertNotNil(s)
        XCTAssertEqual(s!, 35, accuracy: 5)
    }

    func testRestedDayReadsLow() {
        // hrv well above baseline + rhr below baseline -> calm.
        let s = StressEngine.dailyValue(hrv: 80, hrvBaseline: 55, hrvSpread: 0.2,
                                        restingHR: 49, restingHRBaseline: 55, rhrSpread: 4)!
        XCTAssertLessThan(s, 22)
    }

    func testTenseDayReadsHigh() {
        // hrv well below baseline + rhr above baseline -> tension.
        let s = StressEngine.dailyValue(hrv: 38, hrvBaseline: 55, hrvSpread: 0.2,
                                        restingHR: 64, restingHRBaseline: 55, rhrSpread: 4)!
        XCTAssertGreaterThan(s, 70)
    }

    func testMonotonicInHrvDeficit() {
        let mild = StressEngine.dailyValue(hrv: 52, hrvBaseline: 55, hrvSpread: 0.2,
                                           restingHR: 55, restingHRBaseline: 55, rhrSpread: 4)!
        let severe = StressEngine.dailyValue(hrv: 40, hrvBaseline: 55, hrvSpread: 0.2,
                                             restingHR: 55, restingHRBaseline: 55, rhrSpread: 4)!
        XCTAssertGreaterThan(severe, mild)
    }

    // MARK: missing-signal handling

    func testNoSignalReturnsNil() {
        let s = StressEngine.dailyValue(hrv: nil, hrvBaseline: nil, hrvSpread: nil,
                                        restingHR: nil, restingHRBaseline: nil, rhrSpread: nil)
        XCTAssertNil(s)
    }

    func testRhrOnlyStillProducesValue() {
        // Minimal tier: only resting HR present, weight renormalizes to RHR.
        let s = StressEngine.dailyValue(hrv: nil, hrvBaseline: nil, hrvSpread: nil,
                                        restingHR: 64, restingHRBaseline: 55, rhrSpread: 4)
        XCTAssertNotNil(s)
        XCTAssertGreaterThan(s!, 35) // elevated RHR -> above typical
    }

    // MARK: bands

    func testBandMapping() {
        XCTAssertEqual(StressEngine.band(for: 10), .rest)
        XCTAssertEqual(StressEngine.band(for: 40), .low)
        XCTAssertEqual(StressEngine.band(for: 60), .medium)
        XCTAssertEqual(StressEngine.band(for: 90), .high)
    }
}
