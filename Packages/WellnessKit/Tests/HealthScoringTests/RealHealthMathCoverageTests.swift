//
//  RealHealthMathCoverageTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Pins the RealHealthMath primitives that had no direct test: gap
//  interpolation, the trailing spreads, the Edwards and chronic TRIMP
//  loads, today's TRIMP by strain source, the circadian modulation curve,
//  and every branch of the recovery breakdown (log-space HRV, the RHR
//  ratio, thin-baseline confidence, per-term caps, jet-lag damping, the
//  rest credit and the soft knee).
//

import XCTest
@testable import HealthScoring

final class RealHealthMathCoverageTests: XCTestCase {

    private let alpha = 1 - exp(-1.0 / 42.0)

    // MARK: interpolated

    func testInterpolatedEmptySeriesIsEmpty() {
        XCTAssertEqual(RealHealthMath.interpolated([]), [])
    }

    func testInterpolatedAllNilSeriesIsZeros() {
        XCTAssertEqual(RealHealthMath.interpolated([nil, nil, nil]), [0, 0, 0])
    }

    func testInterpolatedFillsLeadingInnerAndTrailingGaps() {
        let result = RealHealthMath.interpolated([nil, 2, nil, nil, 8, nil])
        let expected: [Double] = [2, 2, 4, 6, 8, 8]
        XCTAssertEqual(result.count, expected.count)
        for (value, want) in zip(result, expected) {
            XCTAssertEqual(value, want, accuracy: 1e-12)
        }
    }

    func testInterpolatedKeepsAdjacentKnownValues() {
        XCTAssertEqual(RealHealthMath.interpolated([1, 3, 5]), [1, 3, 5])
        XCTAssertEqual(RealHealthMath.interpolated([7]), [7])
    }

    // MARK: tailStdDev

    func testTailStdDevNeedsMoreThanThreeReadings() {
        XCTAssertNil(RealHealthMath.tailStdDev(nil, days: 10))
        XCTAssertNil(RealHealthMath.tailStdDev([1, 2, 3], days: 10))
        XCTAssertNil(RealHealthMath.tailStdDev([1, 2, nil, 3, nil], days: 10))
    }

    func testTailStdDevIsTheSampleDeviationOfTheTail() {
        // Sum of squared deviations around 5 is 32, over n - 1 = 7.
        let series: [Double?] = [100, 2, 4, 4, nil, 4, 5, 5, 7, 9]
        let sd = RealHealthMath.tailStdDev(series, days: 9)
        XCTAssertEqual(sd ?? -1, (32.0 / 7.0).squareRoot(), accuracy: 1e-12)
    }

    // MARK: trailingRobustSpreadSeries

    func testRobustSpreadSeriesRejectsMissingSeriesAndEmptyWindow() {
        XCTAssertEqual(RealHealthMath.trailingRobustSpreadSeries(nil, days: 3, floor: 1).count, 0)
        XCTAssertEqual(RealHealthMath.trailingRobustSpreadSeries([1, 2], days: 0, floor: 1).count, 0)
    }

    func testRobustSpreadSeriesFloorsThinWindowsAndScalesTheMAD() {
        let series: [Double?] = [1, nil, 3, 5]
        let spread = RealHealthMath.trailingRobustSpreadSeries(series, days: 2, floor: 0.1)
        XCTAssertEqual(spread.count, 4)
        // One reading per window until index 3, which holds [3, 5]: MAD 1.
        XCTAssertEqual(spread[0] ?? -1, 0.1, accuracy: 1e-12)
        XCTAssertEqual(spread[1] ?? -1, 0.1, accuracy: 1e-12)
        XCTAssertEqual(spread[2] ?? -1, 0.1, accuracy: 1e-12)
        XCTAssertEqual(spread[3] ?? -1, 1.4826, accuracy: 1e-12)
    }

    func testRobustSpreadSeriesAppliesTheTransformBeforeTheSpread() {
        let doubled = RealHealthMath.trailingRobustSpreadSeries([3, 5], days: 2, floor: 0.1,
                                                                transform: { $0 * 2 })
        XCTAssertEqual(doubled[1] ?? -1, 2 * 1.4826, accuracy: 1e-12)
    }

    // MARK: Edwards TRIMP

    func testEdwardsTRIMPWeightsZoneMinutesAndIgnoresExtraZones() {
        XCTAssertEqual(RealHealthMath.edwardsTRIMP(zoneSeconds: []), 0)
        XCTAssertEqual(RealHealthMath.edwardsTRIMP(zoneSeconds: [120]), 2, accuracy: 1e-12)
        XCTAssertEqual(RealHealthMath.edwardsTRIMP(zoneSeconds: [60, 60, 60, 60, 60, 600]),
                       15, accuracy: 1e-12)
    }

    // MARK: estimatedTRIMP

    func testEstimatedTRIMPIsNilWithoutAnySignal() {
        XCTAssertNil(RealHealthMath.estimatedTRIMP(exerciseMinutes: nil, steps: nil))
    }

    func testEstimatedTRIMPTakesTheStrongestSingleSignal() {
        XCTAssertEqual(RealHealthMath.estimatedTRIMP(exerciseMinutes: nil, steps: nil,
                                                     activeKcal: 220) ?? -1, 100, accuracy: 1e-9)
        XCTAssertEqual(RealHealthMath.estimatedTRIMP(exerciseMinutes: 15, steps: nil) ?? -1,
                       30, accuracy: 1e-9)
        XCTAssertEqual(RealHealthMath.estimatedTRIMP(exerciseMinutes: nil, steps: 1200) ?? -1,
                       10, accuracy: 1e-9)
        XCTAssertEqual(RealHealthMath.estimatedTRIMP(exerciseMinutes: 15, steps: 1200,
                                                     activeKcal: 220) ?? -1, 100, accuracy: 1e-9)
    }

    func testEstimatedTRIMPFallsBackOnHeartRateAlone() {
        let hr = RealHealthMath.heartRateReserveTRIMP(dayHR: 80, restHR: 55, maxHR: 190,
                                                      awakeHours: 16)
        XCTAssertNotNil(hr)
        XCTAssertEqual(RealHealthMath.estimatedTRIMP(exerciseMinutes: nil, steps: nil,
                                                     dayHR: 80, restHR: 55) ?? -1,
                       hr ?? -2, accuracy: 1e-9)
    }

    // MARK: chronic load

    func testChronicDailyTRIMPNeedsFiveRealDays() {
        XCTAssertNil(RealHealthMath.chronicDailyTRIMP([]))
        XCTAssertNil(RealHealthMath.chronicDailyTRIMP([10, 10, 10, 10]))
        XCTAssertNil(RealHealthMath.chronicDailyTRIMP([10, nil, 10, nil, 10, 10]))
    }

    func testChronicDailyTRIMPIsTheEWMAWithRestDaysAtZero() {
        let q = 1 - alpha
        let steady = RealHealthMath.chronicDailyTRIMP([nil, 10, 10, 10, 10, 10])
        XCTAssertEqual(steady ?? -1, 10 * (1 - pow(q, 5)), accuracy: 1e-12)
        // A trailing rest day decays the load instead of being skipped.
        let rested = RealHealthMath.chronicDailyTRIMP([10, 10, 10, 10, 10, nil])
        XCTAssertEqual(rested ?? -1, 10 * (1 - pow(q, 5)) * q, accuracy: 1e-12)
    }

    func testCausalChronicSeriesUsesOnlyTheDaysBefore() {
        XCTAssertEqual(RealHealthMath.causalChronicDailyTRIMPSeries([]).count, 0)
        let trimp: [Double?] = Array(repeating: 10, count: 7)
        let series = RealHealthMath.causalChronicDailyTRIMPSeries(trimp)
        XCTAssertEqual(series.count, 7)
        for i in 0..<5 { XCTAssertNil(series[i], "day \(i) precedes five real days") }
        let q = 1 - alpha
        XCTAssertEqual(series[5] ?? -1, 10 * (1 - pow(q, 5)), accuracy: 1e-12)
        XCTAssertEqual(series[6] ?? -1, 10 * (1 - pow(q, 6)), accuracy: 1e-12)
        // Element i is exactly the chronic load of the prefix ending the day before.
        for i in 5..<7 {
            XCTAssertEqual(series[i] ?? -1,
                           RealHealthMath.chronicDailyTRIMP(Array(trimp[..<i])) ?? -2,
                           accuracy: 1e-12)
        }
    }

    // MARK: todayTRIMP

    func testTodayTRIMPHonorsBothStrainSources() {
        // Day zones (calm dropped): 10 min z1 + 10 min z2 = 30. Workout: 10 min
        // z2 = 20. Workout kcal 22 -> 10, remaining 88 kcal -> 40.
        func today(_ workouts: Bool, _ daily: Bool) -> Double {
            RealHealthMath.todayTRIMP(dayZoneSeconds: [999, 600, 600, 0, 0, 0],
                                      workoutZoneSeconds: [0, 600, 0, 0, 0],
                                      activeKcal: 110, workoutKcal: 22,
                                      includeWorkouts: workouts, includeDaily: daily)
        }
        XCTAssertEqual(today(true, true), 60, accuracy: 1e-9)
        XCTAssertEqual(today(true, false), 20, accuracy: 1e-9)
        XCTAssertEqual(today(false, true), 40, accuracy: 1e-9)
        XCTAssertEqual(today(false, false), 0)
    }

    func testTodayTRIMPCapsTheWorkoutShareAtTheDayZones() {
        // A workout cannot claim more zone load than the whole day recorded.
        let value = RealHealthMath.todayTRIMP(dayZoneSeconds: [0, 600, 0, 0, 0, 0],
                                              workoutZoneSeconds: [0, 0, 0, 0, 3600],
                                              includeWorkouts: true, includeDaily: false)
        XCTAssertEqual(value, 10, accuracy: 1e-9)
    }

    // MARK: circadian modulation

    func testCircadianModulationHitsItsAnchors() {
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 0), -0.7, accuracy: 1e-12)
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 3), -1.0, accuracy: 1e-12)
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 10), 0.8, accuracy: 1e-12)
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 24), -0.7, accuracy: 1e-12)
    }

    func testCircadianModulationInterpolatesBetweenAnchors() {
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 9), 0.35, accuracy: 1e-12)
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 23.5), -0.575, accuracy: 1e-12)
    }

    func testCircadianModulationWrapsAndShiftsWithThePhaseOffset() {
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 12, phaseOffsetHours: 2),
                       0.8, accuracy: 1e-12)
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: -14), 0.8, accuracy: 1e-12)
        XCTAssertEqual(RealHealthMath.energyCircadianModulation(clockHour: 36, phaseOffsetHours: -2),
                       0.25, accuracy: 1e-12)
    }

    // MARK: small helpers

    func testRecoveryModelGains() {
        XCTAssertEqual(RealHealthMath.RecoveryModel.cautious.positiveGain, 0.8)
        XCTAssertEqual(RealHealthMath.RecoveryModel.balanced.positiveGain, 1.0)
        XCTAssertEqual(RealHealthMath.RecoveryModel.aggressive.positiveGain, 1.2)
        XCTAssertEqual(RealHealthMath.RecoveryModel.cautious.negativeGain, 1.1)
        XCTAssertEqual(RealHealthMath.RecoveryModel.balanced.negativeGain, 1.0)
        XCTAssertEqual(RealHealthMath.RecoveryModel.aggressive.negativeGain, 0.9)
        XCTAssertEqual(RealHealthMath.RecoveryModel.cautious.restBonusCap, 2)
        XCTAssertEqual(RealHealthMath.RecoveryModel.balanced.restBonusCap, 4)
        XCTAssertEqual(RealHealthMath.RecoveryModel.aggressive.restBonusCap, 6)
    }

    func testRisingIsGoodVerdicts() {
        XCTAssertEqual(RealHealthMath.risingIsGood(key: "steps"), true)
        XCTAssertEqual(RealHealthMath.risingIsGood(key: "rhr"), false)
        XCTAssertEqual(RealHealthMath.risingIsGood(key: "headphoneSound"), false)
        XCTAssertNil(RealHealthMath.risingIsGood(key: "weight"))
        XCTAssertNil(RealHealthMath.risingIsGood(key: nil))
    }

    func testDurationSleepScore() {
        XCTAssertNil(RealHealthMath.durationSleepScore(hours: nil, needSeconds: 28_800))
        XCTAssertEqual(RealHealthMath.durationSleepScore(hours: 8, needSeconds: 28_800), 100)
        XCTAssertEqual(RealHealthMath.durationSleepScore(hours: 4, needSeconds: 28_800), 25)
    }

    func testSleepScoreNeedsAsleepTime() {
        XCTAssertNil(RealHealthMath.sleepScore(asleepSeconds: nil, needSeconds: 28_800))
        XCTAssertNil(RealHealthMath.sleepScore(asleepSeconds: 0, needSeconds: 28_800))
        XCTAssertNil(RealHealthMath.sleepScore(asleepSeconds: -60, needSeconds: 28_800))
    }

    func testNapDurationFitClampsOutsideItsCurve() {
        XCTAssertEqual(RealHealthMath.napDurationFit(minutes: -5), 0)
        XCTAssertEqual(RealHealthMath.napDurationFit(minutes: 240), 0.5)
        XCTAssertEqual(RealHealthMath.napDurationFit(minutes: 21), 1.0, accuracy: 1e-12)
    }

    // MARK: recovery breakdown

    func testRecoveryWithoutAutonomicInputsIsSleepAndBaselineOnly() {
        let breakdown = RealHealthMath.recoveryBreakdown(hrv: nil, hrvBaseline: nil,
                                                         rhr: nil, rhrBaseline: nil,
                                                         sleepScore: 50, yesterdayStrain: 30)
        XCTAssertEqual(breakdown.missing, [.hrv, .rhr])
        XCTAssertEqual(breakdown.contributions.map(\.kind), [.sleep])
        XCTAssertEqual(breakdown.contributions.first?.id, "sleep")
        XCTAssertEqual(breakdown.contributions.first?.points ?? -1, 0, accuracy: 1e-12)
        XCTAssertEqual(breakdown.contributions.first?.value, 50)
        XCTAssertNil(breakdown.contributions.first?.baseline)
        XCTAssertEqual(breakdown.baseline, 50)
        XCTAssertEqual(breakdown.rawTotal, 50, accuracy: 1e-12)
        XCTAssertEqual(breakdown.score, 50)
        XCTAssertFalse(breakdown.clampedHigh)
        XCTAssertFalse(breakdown.clampedLow)
    }

    func testHRVIsScoredInLogSpaceAgainstTheBaseline() {
        let breakdown = RealHealthMath.recoveryBreakdown(hrv: 110, hrvBaseline: 100, hrvSamples: 14,
                                                         rhr: nil, rhrBaseline: nil,
                                                         sleepScore: 50, yesterdayStrain: 30)
        let hrv = breakdown.contributions.first { $0.kind == .hrv }
        XCTAssertEqual(hrv?.points ?? -1, 150 * log(1.1), accuracy: 1e-9)
        XCTAssertEqual(hrv?.value, 110)
        XCTAssertEqual(hrv?.baseline, 100)
        XCTAssertEqual(breakdown.missing, [.rhr])
        XCTAssertEqual(breakdown.score, 64)
    }

    func testSevenDayMeanDrivesTheHRVTermButTonightIsDisplayed() {
        let withNight = RealHealthMath.recoveryBreakdown(hrv: 90, hrvBaseline: 100, hrv7dMean: 105,
                                                         rhr: nil, rhrBaseline: nil,
                                                         sleepScore: 50, yesterdayStrain: 30)
        let term = withNight.contributions.first { $0.kind == .hrv }
        XCTAssertEqual(term?.points ?? -1, 150 * log(1.05), accuracy: 1e-9)
        XCTAssertEqual(term?.value, 90)

        let meanOnly = RealHealthMath.recoveryBreakdown(hrv: nil, hrvBaseline: 100, hrv7dMean: 105,
                                                        rhr: nil, rhrBaseline: nil,
                                                        sleepScore: 50, yesterdayStrain: 30)
        XCTAssertEqual(meanOnly.contributions.first { $0.kind == .hrv }?.value, 105)
    }

    func testUnusableHRVOrRHRIsReportedMissing() {
        let zeroReading = RealHealthMath.recoveryBreakdown(hrv: 0, hrvBaseline: 100,
                                                           rhr: 0, rhrBaseline: 55,
                                                           sleepScore: 50, yesterdayStrain: 30)
        XCTAssertEqual(zeroReading.missing, [.hrv, .rhr])
        let zeroBaseline = RealHealthMath.recoveryBreakdown(hrv: 60, hrvBaseline: 0,
                                                            rhr: 55, rhrBaseline: 0,
                                                            sleepScore: 50, yesterdayStrain: 30)
        XCTAssertEqual(zeroBaseline.missing, [.hrv, .rhr])
    }

    func testThinBaselinePullsTheTermTowardZero() {
        let half = RealHealthMath.recoveryBreakdown(hrv: 110, hrvBaseline: 100, hrvSamples: 7,
                                                    rhr: 50, rhrBaseline: 55, rhrSamples: 0,
                                                    sleepScore: 50, yesterdayStrain: 30)
        XCTAssertEqual(half.contributions.first { $0.kind == .hrv }?.points ?? -1,
                       150 * log(1.1) * 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.contributions.first { $0.kind == .rhr }?.points ?? -1, 0, accuracy: 1e-12)
    }

    func testLowerRestingHRAddsRecoveryShapedByTheModel() {
        func rhrPoints(_ rhr: Double, _ base: Double, _ model: RealHealthMath.RecoveryModel) -> Double {
            RealHealthMath.recoveryBreakdown(hrv: nil, hrvBaseline: nil, rhr: rhr, rhrBaseline: base,
                                             sleepScore: 50, yesterdayStrain: 30, model: model)
                .contributions.first { $0.kind == .rhr }?.points ?? .nan
        }
        XCTAssertEqual(rhrPoints(50, 55, .balanced), 10, accuracy: 1e-9)
        XCTAssertEqual(rhrPoints(50, 55, .cautious), 8, accuracy: 1e-9)
        XCTAssertEqual(rhrPoints(50, 55, .aggressive), 12, accuracy: 1e-9)
        XCTAssertEqual(rhrPoints(60, 50, .balanced), -100.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(rhrPoints(60, 50, .cautious), -100.0 / 6.0 * 1.1, accuracy: 1e-9)
        XCTAssertEqual(rhrPoints(60, 50, .aggressive), -15, accuracy: 1e-9)
    }

    func testEachTermIsCapped() {
        let high = RealHealthMath.recoveryBreakdown(hrv: 200, hrvBaseline: 100,
                                                    rhr: 40, rhrBaseline: 60,
                                                    sleepScore: 100, yesterdayStrain: 30)
        XCTAssertEqual(high.contributions.first { $0.kind == .hrv }?.points, RealHealthMath.recoveryHRVCap)
        XCTAssertEqual(high.contributions.first { $0.kind == .rhr }?.points, RealHealthMath.recoveryRHRCap)
        XCTAssertEqual(high.contributions.first { $0.kind == .sleep }?.points, RealHealthMath.recoverySleepCap)
        let low = RealHealthMath.recoveryBreakdown(hrv: nil, hrvBaseline: nil,
                                                   rhr: 100, rhrBaseline: 50,
                                                   sleepScore: 50, yesterdayStrain: 30)
        XCTAssertEqual(low.contributions.first { $0.kind == .rhr }?.points, -RealHealthMath.recoveryRHRCap)
    }

    func testJetLagSoftensOnlyTheNegativeAutonomicTerms() {
        func breakdown(jetLag: Double, rhr: Double, base: Double, hrv: Double? = nil)
            -> RecoveryBreakdown {
            RealHealthMath.recoveryBreakdown(hrv: hrv, hrvBaseline: hrv == nil ? nil : 100,
                                             rhr: rhr, rhrBaseline: base,
                                             sleepScore: 30, yesterdayStrain: 30,
                                             jetLagResidualH: jetLag)
        }
        let penalty = -100.0 / 6.0
        XCTAssertEqual(breakdown(jetLag: 2.5, rhr: 60, base: 50)
            .contributions.first { $0.kind == .rhr }?.points ?? .nan, penalty * 0.8, accuracy: 1e-9)
        // Floored at half the penalty however long the residual.
        XCTAssertEqual(breakdown(jetLag: 10, rhr: 60, base: 50)
            .contributions.first { $0.kind == .rhr }?.points ?? .nan, penalty * 0.5, accuracy: 1e-9)
        // A good reading is never inflated.
        XCTAssertEqual(breakdown(jetLag: 5, rhr: 50, base: 55)
            .contributions.first { $0.kind == .rhr }?.points ?? .nan, 10, accuracy: 1e-9)
        let hrvDip = breakdown(jetLag: 2.5, rhr: 55, base: 55, hrv: 90)
        XCTAssertEqual(hrvDip.contributions.first { $0.kind == .hrv }?.points ?? .nan,
                       150 * log(0.9) * 0.8, accuracy: 1e-9)
        // The sleep term is not an autonomic reading and keeps its full weight.
        XCTAssertEqual(hrvDip.contributions.first { $0.kind == .sleep }?.points ?? .nan,
                       -9, accuracy: 1e-9)
    }

    func testRestCreditFollowsYesterdaysStrainAndTheModelCap() {
        func rest(_ strain: Int, _ model: RealHealthMath.RecoveryModel = .balanced) -> Double? {
            RealHealthMath.recoveryBreakdown(hrv: nil, hrvBaseline: nil, rhr: nil, rhrBaseline: nil,
                                             sleepScore: 50, yesterdayStrain: strain, model: model)
                .contributions.first { $0.kind == .rest }?.points
        }
        XCTAssertEqual(rest(0), 4)
        XCTAssertEqual(rest(0, .cautious), 2)
        XCTAssertEqual(rest(0, .aggressive), 6)
        XCTAssertEqual(rest(15) ?? -1, 2, accuracy: 1e-12)
        XCTAssertNil(rest(27), "a 0.4 point credit is below the display threshold")
        XCTAssertNil(rest(50))
        let restTerm = RealHealthMath.recoveryBreakdown(hrv: nil, hrvBaseline: nil, rhr: nil,
                                                        rhrBaseline: nil, sleepScore: 50,
                                                        yesterdayStrain: 0)
            .contributions.first { $0.kind == .rest }
        XCTAssertEqual(restTerm?.id, "rest")
        XCTAssertNil(restTerm?.value)
        XCTAssertNil(restTerm?.baseline)
    }

    func testSoftKneeKeepsAMaxedDayBelowOneHundred() {
        let breakdown = RealHealthMath.recoveryBreakdown(hrv: 200, hrvBaseline: 100,
                                                         rhr: 40, rhrBaseline: 60,
                                                         sleepScore: 100, yesterdayStrain: 0)
        XCTAssertEqual(breakdown.rawTotal, 118, accuracy: 1e-9)
        XCTAssertEqual(breakdown.score, Int((82 + 18 * tanh(1.8)).rounded()))
        XCTAssertEqual(breakdown.score, 99)
        XCTAssertTrue(breakdown.clampedHigh)
        XCTAssertFalse(breakdown.clampedLow)
    }

    func testFloorClampsAnAllBadDayToZero() {
        let breakdown = RealHealthMath.recoveryBreakdown(hrv: 50, hrvBaseline: 100,
                                                         rhr: 100, rhrBaseline: 50,
                                                         sleepScore: 0, yesterdayStrain: 100)
        XCTAssertEqual(breakdown.rawTotal, -14, accuracy: 1e-9)
        XCTAssertEqual(breakdown.score, 0)
        XCTAssertTrue(breakdown.clampedLow)
        XCTAssertFalse(breakdown.clampedHigh)
        XCTAssertNil(breakdown.contributions.first { $0.kind == .rest })
    }

    func testRecoveryWrapperReturnsTheBreakdownScore() {
        let breakdown = RealHealthMath.recoveryBreakdown(hrv: 70, hrvBaseline: 60, hrv7dMean: 66,
                                                         rhr: 58, rhrBaseline: 55,
                                                         sleepScore: 72, yesterdayStrain: 12,
                                                         model: .cautious, jetLagResidualH: 1.5)
        let score = RealHealthMath.recovery(hrv: 70, hrvBaseline: 60, hrv7dMean: 66,
                                            rhr: 58, rhrBaseline: 55,
                                            sleepScore: 72, yesterdayStrain: 12,
                                            model: .cautious, jetLagResidualH: 1.5)
        XCTAssertEqual(score, breakdown.score)
        // 50 + 11.44 (HRV, damped gain) - 5.01 (RHR, jet lag) + 7.92 (sleep) + 1.2 (rest).
        XCTAssertEqual(breakdown.rawTotal, 65.5503, accuracy: 0.001)
        XCTAssertEqual(score, 66)
    }
}
