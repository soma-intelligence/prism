//
//  VitalitySectionsTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Each isolated section is a pure function, so every constant decision
//  is pinned by a test. See docs/calculations/02-energy.md.
//

import XCTest
@testable import HealthScoring

final class VitalitySectionsTests: XCTestCase {

    // MARK: Homeostatic drain (Borbely Process S)

    func testHomeostaticDrainSaturates() {
        // ~16 h awake -> about 29 points (50 * (1 - e^-16/18.2)).
        let d = VitalitySections.homeostaticDrain(awakeHours: 16)
        XCTAssertEqual(d, 29, accuracy: 2)
    }

    func testHomeostaticDrainZeroAtWake() {
        XCTAssertEqual(VitalitySections.homeostaticDrain(awakeHours: 0), 0, accuracy: 0.001)
    }

    // MARK: Circadian (Process C) in [-1, 1]

    func testCircadianBounded() {
        for h in stride(from: 0.0, through: 24.0, by: 0.5) {
            let v = VitalitySections.circadianModulation(clockHour: h)
            XCTAssertGreaterThanOrEqual(v, -1.0001)
            XCTAssertLessThanOrEqual(v, 1.0001)
        }
    }

    func testCircadianMorningPeakAboveNight() {
        let morning = VitalitySections.circadianModulation(clockHour: 10)
        let night = VitalitySections.circadianModulation(clockHour: 3)
        XCTAssertGreaterThan(morning, night)
    }

    // MARK: Sleep charge

    func testPerfectNightChargesInsideTheGarminBand() {
        // From a typical low reserve (30), a perfect night lands inside the
        // Garmin 40-60 anchor.
        //
        // STALE UNTIL 2026-08-23, and only because nothing ran this file. It
        // asserted 50 +/- 3, which was right before `nightClosureMax` (0.87)
        // existed. Commit 23840a2a introduced that constant and updated three
        // other test files; this one it missed, and no runtime harness covered
        // `VitalitySections`, so the failure sat here unseen. The product anchor
        // it defends still holds, so the anchor is what is asserted now, with
        // the exact value pinned beside it.
        let after = VitalitySections.sleepCharge(previousReserve: 30,
                                                 sleepScore: 100,
                                                 lateWorkoutPenalty: 0)
        XCTAssertGreaterThan(after - 30, 40)
        XCTAssertLessThan(after - 30, 60)
        XCTAssertEqual(after - 30, 43.85, accuracy: 0.1)
    }

    func testPoorNightChargesNoticeablyLessThanPerfect() {
        // Concave restoration: a poor night still dissipates real sleep
        // pressure (sqrt map), but must stay well under the perfect
        // night's ~+50 gain.
        let after = VitalitySections.sleepCharge(previousReserve: 30,
                                                 sleepScore: 20,
                                                 lateWorkoutPenalty: 0)
        XCTAssertLessThan(after - 30, 27)
        XCTAssertGreaterThan(after - 30, 10)
    }

    func testChargeQualityConcaveAnchors() {
        // Anchors of the sqrt restoration map: perfect night unchanged,
        // zero stays zero, and a typical score (75) restores MORE than
        // its linear share (the fix for the battery pinning at 0).
        XCTAssertEqual(VitalitySections.chargeQuality(sleepScore: 100), 1.0, accuracy: 0.001)
        XCTAssertEqual(VitalitySections.chargeQuality(sleepScore: 0), 0.0, accuracy: 0.001)
        XCTAssertEqual(VitalitySections.chargeQuality(sleepScore: 75), 0.866, accuracy: 0.01)
        XCTAssertGreaterThan(VitalitySections.chargeQuality(sleepScore: 75), 0.75)
        // Monotonic: better sleep never charges less.
        XCTAssertLessThan(VitalitySections.chargeQuality(sleepScore: 40),
                          VitalitySections.chargeQuality(sleepScore: 80))
    }

    func testLateWorkoutSuppressesCharge() {
        let clean = VitalitySections.sleepCharge(previousReserve: 30,
                                                 sleepScore: 100,
                                                 lateWorkoutPenalty: 0)
        let late = VitalitySections.sleepCharge(previousReserve: 30,
                                                sleepScore: 100,
                                                lateWorkoutPenalty: 12)
        XCTAssertEqual(clean - late, 12, accuracy: 0.5)
    }

    func testChargeNeverExceedsHundred() {
        let after = VitalitySections.sleepCharge(previousReserve: 95,
                                                 sleepScore: 100,
                                                 lateWorkoutPenalty: 0)
        XCTAssertLessThanOrEqual(after, 100)
    }

    // MARK: Duration-aware closure (Process S dissipation)

    func testClosureFractionFollowsProcessS() {
        // 8 h closes ~85% of the gap, 6 h ~76%, 4 h ~61% (tau 4.2 h);
        // unknown duration falls back to the legacy 0.72 anchor.
        XCTAssertEqual(VitalitySections.sleepClosureFraction(sleepHours: 8), 0.85, accuracy: 0.01)
        XCTAssertEqual(VitalitySections.sleepClosureFraction(sleepHours: 6), 0.76, accuracy: 0.01)
        XCTAssertEqual(VitalitySections.sleepClosureFraction(sleepHours: 4), 0.61, accuracy: 0.01)
        XCTAssertEqual(VitalitySections.sleepClosureFraction(sleepHours: nil), 0.72, accuracy: 0.001)
    }

    func testPerfectEightHourNightWakesHighButNotFull() {
        // From a modest evening (30), a perfect 8 h night wakes high, and
        // deliberately NOT near 100.
        //
        // STALE UNTIL 2026-08-23, same cause as the test above: it asserted
        // 89.6, which is `30 + 70 * (1 - e^(-8/4.2))` with no `nightClosureMax`.
        // The 0.87 factor that commit 23840a2a added says a night restores
        // TOWARD a ceiling it never quite reaches, so the same night now lands
        // at 81.8 and the asymptote from a reserve of 30 is 90.9. That is the
        // documented intent of the constant, not a regression, and the file's
        // own header states both anchors it was fitted on.
        let after = VitalitySections.sleepCharge(previousReserve: 30,
                                                 sleepScore: 100,
                                                 lateWorkoutPenalty: 0,
                                                 sleepHours: 8)
        XCTAssertEqual(after, 81.8, accuracy: 0.5)
        XCTAssertLessThan(after, 30 + 70 * VitalitySections.nightClosureMax)
    }

    // MARK: Nap charge

    /// THE ANCHOR. A nap minute is worth exactly `napRestorationFactor` of a
    /// perfect night minute at the same battery level. Asserting it against the
    /// NIGHT rather than against a hard-coded number is the point: the two
    /// cannot drift apart, and the only thing that separates them is the one
    /// constant that says a nap is not a night.
    func testANapMinuteIsAStatedFractionOfANightMinute() {
        let nightGain = VitalitySections.sleepCharge(previousReserve: 50,
                                                     sleepScore: 100,
                                                     lateWorkoutPenalty: 0,
                                                     sleepHours: 1) - 50
        let napGain = VitalitySections.napCharge(level: 50, hoursBefore: 0,
                                                 hoursAfter: 1, alreadyCharged: 0)
        XCTAssertEqual(napGain, nightGain * VitalitySections.napRestorationFactor,
                       accuracy: 0.01)
    }

    /// THE DEFECT THIS REPLACED. The nap used to close the headroom on a
    /// straight line, `napSeconds / sleepNeed` at 0.45, so an hour's nap from a
    /// half-empty battery returned 2.81 points. Sleep pressure dissipates
    /// exponentially and FRONT LOADED, which this file documents for the night
    /// and a nap is entirely front loaded sleep, so the straight line
    /// under-credited it exactly where the model says sleep works best.
    func testAnHourNapReturnsMoreThanTheOldLinearRampGave() {
        let legacyLinear = (100 - 50.0) * 0.45 * 3600 / (8 * 3600)
        XCTAssertEqual(legacyLinear, 2.81, accuracy: 0.01)
        let now = VitalitySections.napCharge(level: 50, hoursBefore: 0,
                                             hoursAfter: 1, alreadyCharged: 0)
        XCTAssertGreaterThan(now, legacyLinear * 2)
    }

    /// The second half hour is worth less than the first: that is what the
    /// exponential law means, and it is why the charge is incremental.
    func testTheSecondHalfHourOfANapIsWorthLessThanTheFirst() {
        let first = VitalitySections.napCharge(level: 50, hoursBefore: 0,
                                               hoursAfter: 0.5, alreadyCharged: 0)
        let second = VitalitySections.napCharge(level: 50, hoursBefore: 0.5,
                                                hoursAfter: 1, alreadyCharged: first)
        XCTAssertGreaterThan(first, second)
        XCTAssertEqual(first + second,
                       VitalitySections.napCharge(level: 50, hoursBefore: 0,
                                                  hoursAfter: 1, alreadyCharged: 0),
                       accuracy: 0.01)
    }

    /// A full battery cannot be refilled, and the day's credit is bounded
    /// because a nap borrows from the night that follows.
    func testNapChargeRespectsHeadroomAndTheDailyCap() {
        XCTAssertEqual(VitalitySections.napCharge(level: 100, hoursBefore: 0,
                                                  hoursAfter: 2, alreadyCharged: 0),
                       0, accuracy: 0.0001)
        XCTAssertEqual(VitalitySections.napCharge(level: 20, hoursBefore: 0,
                                                  hoursAfter: 3,
                                                  alreadyCharged: VitalitySections.napChargeCap),
                       0, accuracy: 0.0001)
        // A very long nap from a very low battery is clipped to the cap.
        XCTAssertLessThanOrEqual(
            VitalitySections.napCharge(level: 5, hoursBefore: 0, hoursAfter: 6,
                                       alreadyCharged: 0),
            VitalitySections.napChargeCap + 0.0001)
    }

    /// A ninety minute nap, the full cycle, is worth about ten points from a
    /// half-empty battery. It was 4.2, which is why it read as doing nothing.
    func testAFullCycleNapIsVisibleOnTheGauge() {
        XCTAssertEqual(VitalitySections.napCharge(level: 50, hoursBefore: 0,
                                                  hoursAfter: 1.5, alreadyCharged: 0),
                       9.8, accuracy: 0.3)
    }

    func testLongerNightChargesMoreAtEqualScore() {
        let short = VitalitySections.sleepCharge(previousReserve: 30,
                                                 sleepScore: 80,
                                                 lateWorkoutPenalty: 0,
                                                 sleepHours: 5.5)
        let long = VitalitySections.sleepCharge(previousReserve: 30,
                                                sleepScore: 80,
                                                lateWorkoutPenalty: 0,
                                                sleepHours: 8.5)
        XCTAssertGreaterThan(long, short + 5)
    }

    // MARK: Exercise drain

    func testWorkoutDrainScalesWithLoad() {
        let easy = VitalitySections.exerciseDrainPoints(trimp: 50, vo2max: 40)
        let hard = VitalitySections.exerciseDrainPoints(trimp: 300, vo2max: 40)
        XCTAssertGreaterThan(hard, easy)
        XCTAssertLessThanOrEqual(hard, 45)
    }

    func testFitterUserDrainsLessForSameWorkout() {
        let unfit = VitalitySections.exerciseDrainPoints(trimp: 300, vo2max: 35)
        let fit = VitalitySections.exerciseDrainPoints(trimp: 300, vo2max: 55)
        XCTAssertGreaterThan(unfit, fit)
    }

    func testEpocTailDecaysToThirteenPercentAtThreeHours() {
        let f0 = VitalitySections.epocFactor(hoursSinceEnd: 0)
        let f3 = VitalitySections.epocFactor(hoursSinceEnd: 3)
        XCTAssertEqual(f0, 1.0, accuracy: 0.001)
        XCTAssertEqual(f3, 0.13, accuracy: 0.02)
    }

    func testExerciseDrainAtTimeSumsWorkoutsWithTail() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int) -> Date {
            cal.date(byAdding: .minute, value: h * 60 + m, to: base)!
        }
        let w = VitalityWorkout(start: at(8, 0), end: at(9, 0), trimp: 300)
        // During the workout: ~full drain. One hour after: decayed.
        let during = VitalitySections.exerciseDrain(at: at(8, 30), workouts: [w], vo2max: 40)
        let after = VitalitySections.exerciseDrain(at: at(10, 0), workouts: [w], vo2max: 40)
        XCTAssertGreaterThan(during, after)
        XCTAssertGreaterThan(after, 0)
    }

    // MARK: Stress drain (non-exercise)

    func testStressDrainIgnoresNeutralStress() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let samples = (0..<6).map {
            VitalitySample(date: cal.date(byAdding: .hour, value: $0, to: base)!, value: 25)
        }
        let d = VitalitySections.stressDrain(stressSamples: samples,
                                             workouts: [],
                                             neutralThreshold: 30)
        XCTAssertEqual(d, 0, accuracy: 0.001)
    }

    func testHighStressDrains() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let samples = (0..<6).map {
            VitalitySample(date: cal.date(byAdding: .hour, value: $0, to: base)!, value: 80)
        }
        let d = VitalitySections.stressDrain(stressSamples: samples,
                                             workouts: [],
                                             neutralThreshold: 30)
        XCTAssertGreaterThan(d, 0)
    }

    func testWorkoutWindowExcludedFromStressDrain() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        func at(_ h: Int) -> Date { cal.date(byAdding: .hour, value: h, to: base)! }
        let samples = (0..<6).map { VitalitySample(date: at($0), value: 80) }
        let noWorkout = VitalitySections.stressDrain(stressSamples: samples,
                                                     workouts: [],
                                                     neutralThreshold: 30)
        let withWorkout = VitalitySections.stressDrain(
            stressSamples: samples,
            workouts: [VitalityWorkout(start: at(1), end: at(3), trimp: 200)],
            neutralThreshold: 30)
        // Samples inside the workout window are credited to exerciseDrain,
        // so the stress drain is strictly smaller.
        XCTAssertLessThan(withWorkout, noWorkout)
    }
}
