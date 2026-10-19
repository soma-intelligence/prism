//
//  HealthStatsTests.swift
//  HealthScoringTests (parity suite ported from the previous app)
//
//  Locks the shared statistical base every engine now builds on. Each test
//  names the real defect it prevents, because these are the numbers the
//  2026-07-25 audit found the engines disagreeing on.
//
//  The t distribution values are checked against published tables rather than
//  against our own output, so a regression in the incomplete-beta code cannot
//  quietly redefine "correct".
//

import XCTest
@testable import HealthScoring

final class HealthStatsTests: XCTestCase {

    // MARK: - Student t against published tables

    /// Two-sided 95% critical values, i.e. upper tail 2.5%. These are the same
    /// numbers TrendPrediction hardcodes; reproducing them from the continued
    /// fraction proves the general implementation is sound.
    func testStudentTMatchesPublishedTwoSided95Table() {
        let table: [(Int, Double)] = [(1, 12.706), (2, 4.303), (3, 3.182), (4, 2.776),
                                      (5, 2.571), (6, 2.447), (10, 2.228), (20, 2.086),
                                      (30, 2.042)]
        for (df, expected) in table {
            XCTAssertEqual(HealthStats.studentTQuantile(upperTail: 0.025, degreesOfFreedom: df),
                           expected, accuracy: 0.001, "df \(df)")
        }
    }

    func testStudentTMatchesPublishedOneSided5Table() {
        let table: [(Int, Double)] = [(1, 6.314), (5, 2.015), (10, 1.812), (30, 1.697)]
        for (df, expected) in table {
            XCTAssertEqual(HealthStats.studentTQuantile(upperTail: 0.05, degreesOfFreedom: df),
                           expected, accuracy: 0.002, "df \(df)")
        }
    }

    func testStudentTUpperTailIsSymmetricAroundZero() {
        XCTAssertEqual(HealthStats.studentTUpperTail(0, degreesOfFreedom: 7), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.studentTUpperTail(2.228, degreesOfFreedom: 10), 0.025, accuracy: 0.0005)
        XCTAssertEqual(HealthStats.studentTUpperTail(-2.228, degreesOfFreedom: 10), 0.975, accuracy: 0.0005)
    }

    // MARK: - Drift threshold

    /// The legacy constant 1.5 treated the baseline SD as exactly known. These
    /// are the values the corrected statistic actually produces; the docstring
    /// on `driftThreshold` quotes them, so this test is what keeps that comment
    /// honest.
    func testDriftThresholdAnchors() {
        XCTAssertEqual(HealthStats.driftThreshold(baselineCount: 3), 2.833, accuracy: 0.001)
        XCTAssertEqual(HealthStats.driftThreshold(baselineCount: 7), 1.854, accuracy: 0.001)
        XCTAssertEqual(HealthStats.driftThreshold(baselineCount: 14), 1.656, accuracy: 0.001)
        XCTAssertEqual(HealthStats.driftThreshold(baselineCount: 29), 1.571, accuracy: 0.001)
    }

    /// Backwards compatibility: behaviour tuned against the old constant is
    /// preserved where the baseline is long, so only the small-n case changes.
    func testDriftThresholdConvergesToLegacyFifteen() {
        XCTAssertEqual(HealthStats.driftThreshold(baselineCount: 100_000), 1.5, accuracy: 0.01)
    }

    func testDriftThresholdTightensAsBaselineShrinks() {
        let thresholds = [3, 7, 14, 29, 60].map { HealthStats.driftThreshold(baselineCount: $0) }
        for (a, b) in zip(thresholds, thresholds.dropFirst()) {
            XCTAssertGreaterThan(a, b, "threshold must relax as evidence grows")
        }
        XCTAssertTrue(thresholds.allSatisfy { $0 > 1.5 })
    }

    /// A baseline with no spread must never alert rather than alert always.
    func testDriftThresholdWithoutSpreadNeverAlerts() {
        XCTAssertEqual(HealthStats.driftThreshold(baselineCount: 1), .infinity)
        XCTAssertEqual(HealthStats.driftThreshold(baselineCount: 0), .infinity)
    }

    /// The alert rate an engine implicitly chose by sharing one threshold
    /// across different signal counts. Ordering is the point: more signals at
    /// the same bar means more false alerts, which is why the rate has to be
    /// declared rather than inherited.
    func testAlertRateGrowsWithSignalCount() {
        let k3 = HealthStats.alertRateUnderNull(signals: 3, minDeviating: 2)
        let k4 = HealthStats.alertRateUnderNull(signals: 4, minDeviating: 2)
        let k5 = HealthStats.alertRateUnderNull(signals: 5, minDeviating: 2)
        XCTAssertLessThan(k3, k4)
        XCTAssertLessThan(k4, k5)
        XCTAssertEqual(k5, 0.039, accuracy: 0.005)
    }

    func testPerSignalAlphaHitsTheDeclaredRate() {
        let alpha = HealthStats.perSignalAlpha(forOneAlertEvery: 30, signals: 5, minDeviating: 2)
        let achieved = HealthStats.alertRateUnderNull(signals: 5, minDeviating: 2, perSignalAlpha: alpha)
        XCTAssertEqual(achieved, 1.0 / 30.0, accuracy: 0.002)
    }

    // MARK: - Robust baseline

    func testBaselineUsesMedianAndScaledMAD() {
        let b = HealthStats.baseline([10, 11, 12, 13, 14, 15, 16], spreadFloor: 0.1)
        XCTAssertEqual(b?.center, 13)
        XCTAssertEqual(b?.spread ?? 0, 1.4826 * 2, accuracy: 1e-9)
        XCTAssertEqual(b?.count, 7)
    }

    /// With a sample SD, one aberrant night both shifts the center and inflates
    /// the spread, masking the nights that follow it. The robust pair does not.
    func testBaselineResistsASingleOutlier() {
        let values: [Double] = [10, 11, 12, 13, 14, 15, 16, 200]
        let robust = HealthStats.baseline(values, spreadFloor: 0.1)!
        let sampleSD = HealthStats.sampleStdDev(values)!
        XCTAssertLessThan(robust.spread, sampleSD / 5)
        XCTAssertEqual(robust.center, 13.5, accuracy: 0.001)
    }

    /// The divide-by-almost-zero the audit found: overnight SpO2 barely varies,
    /// so an unfloored spread turns sensor rounding into a 2.5 sigma alert.
    func testFlatWindowFallsBackToTheDeclaredFloor() {
        let b = HealthStats.baseline([95, 95, 95, 95, 95],
                                     spreadFloor: HealthStats.SpreadFloor.bloodOxygen)!
        XCTAssertEqual(b.spread, 0.6, accuracy: 1e-9)
        let z = b.z(94, direction: .lowerIsWorse)
        XCTAssertTrue(z.isFinite)
        XCTAssertEqual(z, 1.0 / 0.6, accuracy: 1e-9)
    }

    func testBaselineBelowMinimumGateIsNil() {
        XCTAssertNil(HealthStats.baseline([1, 2], spreadFloor: 1))
        XCTAssertNotNil(HealthStats.baseline([1, 2, 3], spreadFloor: 1))
    }

    // MARK: - Causality and exclusion

    func testCausalBaselineExcludesTheDayBeingJudged() {
        let series: [Double?] = [10, 10, 10, 10, 10, 10, 10, 50]
        let b = HealthStats.causalBaseline(series, endingBefore: 7, spreadFloor: 0.1)
        XCTAssertEqual(b?.center, 10, "today's 50 must not enter its own baseline")
        XCTAssertEqual(b?.count, 7)
    }

    func testCausalBaselineRespectsTheWindow() {
        let series: [Double?] = [1, 1, 1, 90, 91, 92, 93]
        let b = HealthStats.causalBaseline(series, endingBefore: 6, window: 3, spreadFloor: 0.1)
        XCTAssertEqual(b?.center, 91)
        XCTAssertEqual(b?.count, 3)
    }

    /// Altitude Shield promised a "sea level" baseline but built it from a
    /// rolling window with no altitude filter, so on a trek the baseline drifted
    /// to match the altitude nights and the module went quiet exactly when it
    /// should shout. `excluding` is what makes the promise true.
    func testExcludingUnrepresentativeDaysRestoresTheAlert() {
        var series = [Double?](repeating: 97, count: 7)
        series += [Double?](repeating: 90, count: 9)   // nine nights at altitude
        series.append(89)                              // tonight
        let tonight = series.count - 1

        let contaminated = HealthStats.causalBaseline(series, endingBefore: tonight,
                                                     window: 10,
                                                     spreadFloor: HealthStats.SpreadFloor.bloodOxygen)!
        let clean = HealthStats.causalBaseline(series, endingBefore: tonight,
                                              window: tonight,
                                              excluding: Set(7..<16),
                                              spreadFloor: HealthStats.SpreadFloor.bloodOxygen)!

        let zContaminated = contaminated.z(89, direction: .lowerIsWorse)
        let zClean = clean.z(89, direction: .lowerIsWorse)
        XCTAssertEqual(contaminated.center, 90, "baseline had drifted to altitude")
        XCTAssertEqual(clean.center, 97, "sea level really means sea level")
        XCTAssertGreaterThan(zClean, zContaminated + 5)
    }

    /// The replaced `baselineStats` compacted the series before taking `last`,
    /// so a value days old could be presented as tonight's reading.
    func testLatestVersusBaselineRefusesAStaleLatestDay() {
        let stale: [Double?] = [97, 97, 97, 97, 97, 97, 97, nil]
        XCTAssertNil(HealthStats.latestVersusBaseline(stale, spreadFloor: 0.6))

        let fresh: [Double?] = [97, 97, 97, 97, 97, 97, 97, 94]
        let pair = HealthStats.latestVersusBaseline(fresh, spreadFloor: 0.6)
        XCTAssertEqual(pair?.latest, 94)
        XCTAssertEqual(pair?.baseline.count, 7)
    }

    // MARK: - Score scales

    /// The neutral-50 assumption: daily stress is calibrated so a typical day
    /// reads 35, so an engine comparing it against 50 concluded "better than
    /// neutral" on an ordinary day and its adverse verdict became unreachable.
    func testStressDailyNeutralIsThirtyFiveNotFifty() {
        XCTAssertEqual(HealthStats.ScoreScale.stressDaily.neutral, 35)
        XCTAssertEqual(HealthStats.ScoreScale.recovery.neutral, 50)
        XCTAssertEqual(HealthStats.ScoreScale.stressDaily.deviation(35), 0, accuracy: 1e-9)
    }

    func testDeviationSignFollowsPolarity() {
        XCTAssertLessThan(HealthStats.ScoreScale.stressDaily.deviation(60), 0, "more stress is worse")
        XCTAssertGreaterThan(HealthStats.ScoreScale.recovery.deviation(60), 0, "more recovery is better")
    }

    // MARK: - Composite

    /// An absent signal is not a zero. Counting it as one dragged composites
    /// down and made a missing input look like a bad reading.
    func testCompositeRenormalisesOverPresentSignals() {
        let c = HealthStats.composite([
            .init("recovery", value: 80, weight: 0.45),
            .init("stress", value: nil, weight: 0.25),
            .init("load", value: 40, weight: 0.30),
        ])!
        XCTAssertEqual(c.score, 64, accuracy: 1e-9)
        XCTAssertEqual(c.presentCount, 2)
        XCTAssertEqual(c.weightCovered, 0.75, accuracy: 1e-9)
        XCTAssertEqual(c.limiter, "load")

        let asZero = 0.45 * 80 + 0.25 * 0 + 0.30 * 40
        XCTAssertEqual(asZero, 48, accuracy: 1e-9)
        XCTAssertGreaterThan(abs(c.score - asZero), 15, "absent must differ from zero")
    }

    func testCompositeWithNothingPresentIsNil() {
        XCTAssertNil(HealthStats.composite([.init("a", value: nil, weight: 1)]))
        XCTAssertNil(HealthStats.composite([]))
    }

    // MARK: - Screening index

    /// Four engines wrote `mean(max(0, z)) / 3 * 100` inline. Clipping negatives
    /// makes the mean positive even under the null (0.399 per signal), so the
    /// zero of the scale was unreachable and every band was read against a
    /// floor of about 13 instead of 0.
    func testScreeningIndexRemovesTheNullFloor() {
        let nullMean = [Double](repeating: HealthStats.clippedNormalMean, count: 5)
        XCTAssertEqual(HealthStats.screeningIndex(zs: nullMean, subtractNullFloor: false)!,
                       13.298, accuracy: 0.01)
        XCTAssertEqual(HealthStats.screeningIndex(zs: nullMean)!, 0, accuracy: 1e-9)
    }

    func testScreeningIndexIsBounded() {
        XCTAssertEqual(HealthStats.screeningIndex(zs: [99, 99])!, 100)
        XCTAssertEqual(HealthStats.screeningIndex(zs: [-5, -5])!, 0)
        XCTAssertNil(HealthStats.screeningIndex(zs: []))
    }

    // MARK: - Sleep debt

    /// One screen showed 2.0 h and another 21 h for the same nights, both
    /// labelled "sleep debt in hours". Naming the two meanings apart is the fix.
    func testSleepDebtSeparatesNightlyShortfallFromCumulative() {
        let nightly = HealthStats.SleepDebt.nightShortfallHours(asleepHours: 6, needHours: 8)
        XCTAssertEqual(nightly, 2)

        let window = HealthStats.SleepDebt.window(
            Array(repeating: (asleep: Optional(6.0), need: Optional(8.0)), count: 14))
        XCTAssertEqual(window.shortfallHours, 28, accuracy: 1e-9)
        XCTAssertNotEqual(window.shortfallHours, nightly)
    }

    /// The old calculator summed shortfalls only, so sleeping longer changed
    /// nothing and the debt fell only as bad nights aged out of the window.
    /// A screen that says "paid back" has to actually credit the surplus.
    func testSurplusPaysDownTheDebt() {
        let mixed: [(asleep: Double?, need: Double?)] = [(6, 8), (6, 8), (10, 8), (10, 8)]
        let w = HealthStats.SleepDebt.window(mixed)
        XCTAssertEqual(w.shortfallHours, 4, accuracy: 1e-9)
        XCTAssertEqual(w.surplusHours, 2, accuracy: 1e-9, "50% credit on 4 h of surplus")
        XCTAssertEqual(w.netHours, 2, accuracy: 1e-9)

        // Since 2026-07-31 (4ef140b7a) the balance is SIGNED and a surplus
        // banks a credit instead of flooring at zero. Two 4 h surpluses credit
        // 2 h each; the first ages one night before the second lands, and the
        // credit can never pass `creditFloorHours`.
        let decay = HealthStats.SleepDebt.creditDecayPerNight
        let banked = HealthStats.SleepDebt.window([(12, 8), (12, 8)]).netHours
        XCTAssertEqual(banked, -2 * decay - 2, accuracy: 1e-9)
        XCTAssertLessThan(banked, 0, "a surplus now banks a credit")
        let longNights: [(asleep: Double?, need: Double?)] = Array(repeating: (16, 8), count: 14)
        let capped = HealthStats.SleepDebt.window(longNights)
        XCTAssertEqual(capped.netHours, -HealthStats.SleepDebt.creditFloorHours, accuracy: 1e-9,
                       "the credit stops at one full night")
    }

    func testMissingNightIsUnknownNotADeficit() {
        let gappy: [(asleep: Double?, need: Double?)] = [(nil, 8), (nil, 8), (6, 8)]
        let w = HealthStats.SleepDebt.window(gappy)
        XCTAssertEqual(w.shortfallHours, 2, accuracy: 1e-9)
        XCTAssertEqual(w.nightsCounted, 1)
    }

    // MARK: - Clock

    /// Nap Architect computed `bedtime - 6` with no wrap, so anyone asleep
    /// after midnight got a negative cutoff and the module reported "no nap
    /// window" for life.
    func testWrapHandlesAfterMidnightBedtimes() {
        XCTAssertEqual(HealthStats.Clock.wrap24(0.5 - 6), 18.5, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.Clock.wrap24(26), 2, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.Clock.wrap24(-5.5), 18.5, accuracy: 1e-9)
    }

    /// Comparing wrapped hours linearly turned an ultra-early riser (MSFsc
    /// 23.5) into an evening type, and reversed the phase direction for a
    /// night-shift worker.
    func testSignedDeltaTakesTheCircularShortWay() {
        XCTAssertEqual(HealthStats.Clock.signedDelta(from: 23.5, to: 4.5), 5, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.Clock.signedDelta(from: 4.5, to: 23.5), -5, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.Clock.signedDelta(from: 7, to: 21), -10, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.Clock.distance(23.5, 4.5), 5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(HealthStats.Clock.distance(0, 12), 12)
    }

    func testWindowContainmentCrossesMidnight() {
        XCTAssertTrue(HealthStats.Clock.contains(1, start: 23, end: 7))
        XCTAssertTrue(HealthStats.Clock.contains(23, start: 23, end: 7))
        XCTAssertFalse(HealthStats.Clock.contains(12, start: 23, end: 7))
    }

    // MARK: - Correlation inference

    /// The app took its p value from the normal CDF. At n = 6 and r = 0.75 that
    /// reads 0.023 where Student's t reads 0.086, a factor of 3.7 in the
    /// direction that sells the correlation.
    func testPearsonPUsesStudentTNotNormal() {
        let p = HealthStats.pearsonTwoSidedP(r: 0.75, n: 6)!
        XCTAssertEqual(p, 0.086, accuracy: 0.002)

        let df = 4.0
        let t = 0.75 * (df / (1 - 0.5625)).squareRoot()
        let pNormal = 2 * (1 - 0.5 * (1 + erf(t / 2.0.squareRoot())))
        XCTAssertGreaterThan(p / pNormal, 3.3)
    }

    func testPearsonPKnownAnchor() {
        XCTAssertEqual(HealthStats.pearsonTwoSidedP(r: 0.5, n: 12)!, 0.0975, accuracy: 0.002)
        XCTAssertNil(HealthStats.pearsonTwoSidedP(r: 0.9, n: 2))
    }

    /// Screening one target against many candidates and keeping the largest
    /// |r| guarantees surfacing noise: at n = 10 over 40 candidates the biggest
    /// |r| under the null averages about 0.62, which the app's own wording
    /// called "strong". Its confidence interval straddles zero.
    func testFisherIntervalExposesWeakEvidence() {
        let ci = HealthStats.pearsonConfidenceInterval(r: 0.62, n: 10)!
        XCTAssertLessThan(ci.low, 0)
        XCTAssertGreaterThan(ci.high, 0)
    }

    func testBenjaminiHochbergIsMonotoneAndNeverBelowRawP() {
        let ps = [0.001, 0.008, 0.039, 0.041, 0.042, 0.06, 0.5]
        let qs = HealthStats.benjaminiHochberg(ps)
        XCTAssertEqual(qs.count, ps.count)
        for (p, q) in zip(ps, qs) { XCTAssertGreaterThanOrEqual(q, p - 1e-12) }
        for (a, b) in zip(qs, qs.dropFirst()) { XCTAssertLessThanOrEqual(a, b + 1e-12) }
        XCTAssertTrue(qs.allSatisfy { $0 <= 1 })
    }

    func testBenjaminiHochbergReturnsCallerOrder() {
        let qs = HealthStats.benjaminiHochberg([0.5, 0.001, 0.042, 0.008])
        XCTAssertLessThan(qs[1], qs[0], "q must follow the input position, not the sort")
    }

    // MARK: - Data gates

    func testDataGateTiers() {
        XCTAssertNil(HealthStats.DataGate.tier(for: 2))
        XCTAssertEqual(HealthStats.DataGate.tier(for: 3), .minimum)
        XCTAssertEqual(HealthStats.DataGate.tier(for: 7), .reliable)
        XCTAssertEqual(HealthStats.DataGate.tier(for: 20), .confident)
    }

    func testConfidenceSaturatesAtTheConfidentTier() {
        XCTAssertEqual(HealthStats.confidence(count: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.confidence(count: 7), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.confidence(count: 14), 1, accuracy: 1e-9)
        XCTAssertEqual(HealthStats.confidence(count: 100), 1, accuracy: 1e-9)
    }

    /// Shrinkage is what a hardcoded points cap was standing in for: with thin
    /// evidence the whole score moves toward its neutral, instead of a single
    /// term being clipped.
    func testShrinkagePullsThinHistoryTowardTheNeutral() {
        XCTAssertEqual(HealthStats.shrunk(100, toward: 35, count: 3),
                       35 + 65 * (3.0 / 14.0), accuracy: 1e-9)
        XCTAssertEqual(HealthStats.shrunk(100, toward: 35, count: 14), 100, accuracy: 1e-9)
    }

    // MARK: - Sleep debt accumulator

    /// A short night adds its whole shortfall. This is the property the old
    /// exponentially weighted "sleep bank" did not have: with a half-life of
    /// four days its weights summed to about 4.9, so an hour short every night
    /// converged to -4.9 h and never reached the hours actually lost.
    func testDebtSeriesRisesByTheWholeShortfall() {
        let nights: [(asleep: Double?, need: Double?)] = [(6, 8), (6, 8), (6, 8)]
        let series = HealthStats.SleepDebt.series(nights)
        XCTAssertEqual(series[0] ?? .nan, 2, accuracy: 1e-9)
        XCTAssertEqual(series[1] ?? .nan, 4, accuracy: 1e-9)
        XCTAssertEqual(series[2] ?? .nan, 6, accuracy: 1e-9)
    }

    /// A long night pays back half its excess, not all of it.
    func testDebtSeriesPaysBackHalfOfASurplus() {
        let nights: [(asleep: Double?, need: Double?)] = [(6, 8), (10, 8)]
        XCTAssertEqual(HealthStats.SleepDebt.series(nights)[1] ?? .nan, 1, accuracy: 1e-9)
    }

    /// A long night now banks a credit instead of being discarded at a zero
    /// floor. 20 h against an 8 h need is 12 h of excess, credited at half, so
    /// the balance goes to -6 h. The next night, 2 h short, spends part of it:
    /// the credit first ages one night (-6 * 0.5^(1/3) = -4.762) and the 2 h
    /// shortfall lands on top.
    func testDebtSeriesBanksACreditFromALongNight() {
        let nights: [(asleep: Double?, need: Double?)] = [(20, 8), (6, 8)]
        let series = HealthStats.SleepDebt.series(nights)
        XCTAssertEqual(series[0] ?? .nan, -6, accuracy: 1e-9)
        XCTAssertEqual(series[1] ?? .nan, -2.762203155904599, accuracy: 1e-9)
    }

    /// The credit is capped, so a long run of huge nights cannot buy an
    /// unlimited buffer. Five nights of 16 h against an 8 h need would credit
    /// 20 h; the balance stops at one full night.
    func testDebtSeriesCapsTheCreditAtOneNight() {
        let nights = [(asleep: Double?, need: Double?)](
            repeating: (asleep: 16, need: 8), count: 5)
        XCTAssertEqual((HealthStats.SleepDebt.series(nights).last ?? nil) ?? .nan,
                       -HealthStats.SleepDebt.creditFloorHours, accuracy: 1e-9)
    }

    /// An unused credit fades. This is the property that keeps the cap
    /// honest: a credit earned a fortnight ago must not still be protecting
    /// anything. Three nights exactly at the need halve a 2 h credit.
    func testDebtSeriesCreditDecaysWithItsHalfLife() {
        let nights: [(asleep: Double?, need: Double?)] = [(12, 8), (8, 8), (8, 8), (8, 8)]
        let series = HealthStats.SleepDebt.series(nights)
        XCTAssertEqual(series[0] ?? .nan, -2, accuracy: 1e-9)
        XCTAssertEqual(series[3] ?? .nan, -1, accuracy: 1e-9,
                       "une demi-vie de 3 nuits doit exactement diviser le credit par deux")
    }

    /// The decay is one-sided. Nothing repays a debt but sleep, so nights
    /// spent exactly at the need leave it untouched. Ablation: making the
    /// decay unconditional fails this test and only this one.
    func testDebtSeriesDebtDoesNotDecay() {
        let nights: [(asleep: Double?, need: Double?)] = [(6, 8), (8, 8), (8, 8), (8, 8)]
        let series = HealthStats.SleepDebt.series(nights)
        XCTAssertEqual((series.last ?? nil) ?? .nan, 2, accuracy: 1e-9)
    }

    /// A missing night is unknown, so it is not a night of ageing either: the
    /// credit is carried forward undecayed rather than being charged for a
    /// night nobody measured.
    func testDebtSeriesMissingNightDoesNotAgeTheCredit() {
        let nights: [(asleep: Double?, need: Double?)] = [(12, 8), (nil, 8), (8, 8)]
        let series = HealthStats.SleepDebt.series(nights)
        XCTAssertEqual(series[1] ?? .nan, -2, accuracy: 1e-9)
        XCTAssertEqual(series[2] ?? .nan, -2 * pow(0.5, 1.0 / 3.0), accuracy: 1e-9)
    }

    /// Chronic restriction saturates instead of running to an unreadable
    /// number: ten nights six hours short would otherwise total 60 h.
    func testDebtSeriesSaturatesAtTheCeiling() {
        let nights = [(asleep: Double?, need: Double?)](
            repeating: (asleep: 2, need: 8), count: 10)
        XCTAssertEqual((HealthStats.SleepDebt.series(nights).last ?? nil) ?? .nan,
                       HealthStats.SleepDebt.ceilingHours, accuracy: 1e-9)
    }

    /// A missing night is unknown, not a full deficit: it carries the debt
    /// forward rather than inventing one.
    func testDebtSeriesCarriesAMissingNightForward() {
        let nights: [(asleep: Double?, need: Double?)] = [(6, 8), (nil, 8), (6, 8)]
        let series = HealthStats.SleepDebt.series(nights)
        XCTAssertEqual(series[1] ?? .nan, 2, accuracy: 1e-9)
        XCTAssertEqual(series[2] ?? .nan, 4, accuracy: 1e-9)
    }

    /// Nothing is claimed before the first measured night.
    func testDebtSeriesIsNilBeforeAnyMeasuredNight() {
        let nights: [(asleep: Double?, need: Double?)] = [(nil, 8), (6, 8)]
        XCTAssertNil(HealthStats.SleepDebt.series(nights)[0])
    }

    /// Why the displayed debt runs over a window and not since the first
    /// launch. A sleeper one hour short every night pins at the ceiling in
    /// three weeks of lifetime accumulation, and from then on the number never
    /// moves and every chart of it draws a flat line at the cap. Over the
    /// window the same nights stay proportional and readable.
    func testTheWindowKeepsAChronicallyShortSleeperOffTheCeiling() {
        let window = [(asleep: Double?, need: Double?)](
            repeating: (asleep: 7, need: 8),
            count: HealthStats.SleepDebt.windowNights)
        let windowed = HealthStats.SleepDebt.series(window).last.flatMap { $0 } ?? .nan
        XCTAssertEqual(windowed, 14, accuracy: 1e-9)
        XCTAssertLessThan(windowed, HealthStats.SleepDebt.ceilingHours)

        let year = [(asleep: Double?, need: Double?)](
            repeating: (asleep: 7, need: 8), count: 365)
        XCTAssertEqual(HealthStats.SleepDebt.series(year).last.flatMap { $0 } ?? .nan,
                       HealthStats.SleepDebt.ceilingHours, accuracy: 1e-9)
    }

    /// The single defect this whole redesign exists to prevent: a window net
    /// that disagrees with the curve drawn from the same nights. The naive
    /// `max(0, shortfall - surplus)` reads 1 here (5 h short against 4 h of
    /// credited surplus); the accumulator reads 1.698 because the first
    /// night's credit is capped, ages one night before each subsequent night
    /// lands, and is spent along the way. The number itself matters less than
    /// the equality: whatever the accumulator says, the window must say the
    /// same.
    func testWindowNetEqualsTheLastSeriesValue() {
        let nights: [(asleep: Double?, need: Double?)] = [(14, 8), (5, 8), (10, 8), (6, 8)]
        let window = HealthStats.SleepDebt.window(nights)
        let last = HealthStats.SleepDebt.series(nights, ceilingHours: .infinity)
            .compactMap { $0 }.last
        XCTAssertEqual(window.shortfallHours, 5, accuracy: 1e-9)
        XCTAssertEqual(window.surplusHours, 4, accuracy: 1e-9)
        XCTAssertEqual(window.netHours, last ?? .nan, accuracy: 1e-9)
        XCTAssertEqual(window.netHours, 1.6975194771258895, accuracy: 1e-9)
    }
}
