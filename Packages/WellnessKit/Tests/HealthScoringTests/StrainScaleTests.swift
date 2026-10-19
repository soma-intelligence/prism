//
//  StrainScaleTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Pins the strain scale fix ("le strain est trop genereux"): the CTL
//  tau is self-normalizing (a day at the chronic load reads ~20%), but
//  the 420 ceiling it inherited from the legacy fallback pinned tau for
//  every regular watch wearer (CTL > ~93) and inflated ordinary days to
//  45-60%. Also pins the honest TRIMP estimators (exercise minutes at
//  zone-2 weight, HR floor above quiet wakefulness) and the band/actual
//  tau coherence in strainTarget.
//

import XCTest
@testable import HealthScoring

final class StrainScaleTests: XCTestCase {

    // MARK: CTL tau self-normalization

    /// A day at exactly the chronic load reads ~20%, the documented
    /// design point, even for a heavy chronic load (tau unclamped).
    func testDayAtChronicLoadReadsTwentyPercent() {
        let strain = RealHealthMath.strainPercent(trimp: 300, trimp90Max: 500,
                                                  chronicDailyTrimp: 300)
        XCTAssertEqual(Double(strain), 20, accuracy: 3)
    }

    /// Regression: with the old shared 420 ceiling, chronic 300 pinned
    /// tau at 420 and an ordinary 318-TRIMP day (700 active kcal, no
    /// workout) read 53%. It must stay near the ~20% design point.
    func testOrdinaryDayNoLongerInflatedByTauCeiling() {
        let strain = RealHealthMath.strainPercent(trimp: 318, trimp90Max: 500,
                                                  chronicDailyTrimp: 300)
        XCTAssertLessThan(strain, 30)
    }

    /// Harder days still climb: double the chronic load reads clearly
    /// above the at-chronic point, monotonic in TRIMP.
    func testStrainStillDiscriminatesHardDays() {
        let ordinary = RealHealthMath.strainPercent(trimp: 300, trimp90Max: 0,
                                                    chronicDailyTrimp: 300)
        let hard = RealHealthMath.strainPercent(trimp: 900, trimp90Max: 0,
                                                chronicDailyTrimp: 300)
        XCTAssertGreaterThan(hard, ordinary + 15)
    }

    /// The legacy trimp90Max fallback is byte-for-byte unchanged (the
    /// causal-stability contract for thin histories and old caches).
    func testLegacyFallbackUnchanged() {
        // tau = clamp(0.85 x 110, 200...420) = 200 -> 1 - e^(-110/200) = 42%.
        let strain = RealHealthMath.strainPercent(trimp: 110, trimp90Max: 110)
        XCTAssertEqual(strain, 42)
    }

    // MARK: Target band / actual strain coherence

    /// The target band converts through the SAME CTL tau as the actual
    /// strain, so a day AT the chronic load lands inside the band at
    /// full recovery (before the fix the band used the legacy tau).
    func testTargetBandContainsChronicDayAtFullRecovery() {
        let chronic = 300.0
        let band = RealHealthMath.strainTarget(recovery: 100,
                                               chronicDailyTrimp: chronic,
                                               trimp90Max: 500)
        let atChronic = RealHealthMath.strainPercent(trimp: chronic, trimp90Max: 500,
                                                     chronicDailyTrimp: chronic)
        XCTAssertTrue(band.contains(atChronic),
                      "Band \(band) must contain the at-chronic-load strain \(atChronic).")
    }

    // MARK: Honest TRIMP estimators

    /// Exercise ring minutes earn Edwards zone-2 weight (brisk-walk
    /// intensity), not zone-4: 60 minutes -> 120 TRIMP.
    func testExerciseMinutesEarnZoneTwoWeight() {
        let trimp = RealHealthMath.estimatedTRIMP(exerciseMinutes: 60, steps: nil)
        XCTAssertEqual(trimp ?? 0, 120, accuracy: 0.001)
    }

    /// A plain desk day (mean HR barely above rest) keeps a SMALL HR
    /// floor instead of the former 100-150 TRIMP for just being awake.
    func testDeskDayHRFloorIsSmall() {
        let trimp = RealHealthMath.heartRateReserveTRIMP(
            dayHR: 75, restHR: 55, maxHR: 185, awakeHours: 16)
        XCTAssertNotNil(trimp)
        XCTAssertLessThan(trimp ?? 999, 60)
        XCTAssertGreaterThan(trimp ?? 0, 0)
    }

    /// An elevated-HR day still clears the floor by a wide margin, so
    /// wearable-only days keep their discrimination.
    func testElevatedHRDayScoresWellAboveDeskDay() {
        let desk = RealHealthMath.heartRateReserveTRIMP(
            dayHR: 75, restHR: 55, maxHR: 185, awakeHours: 16) ?? 0
        let active = RealHealthMath.heartRateReserveTRIMP(
            dayHR: 85, restHR: 55, maxHR: 185, awakeHours: 16) ?? 0
        XCTAssertGreaterThan(active, desk * 2)
    }

    /// Mean HR at (or a hair above) rest is quiet wakefulness, not
    /// training load: no HR TRIMP at all.
    func testRestingMeanHRYieldsNoLoad() {
        let trimp = RealHealthMath.heartRateReserveTRIMP(
            dayHR: 57, restHR: 55, maxHR: 185, awakeHours: 16)
        XCTAssertNil(trimp)
    }
}
