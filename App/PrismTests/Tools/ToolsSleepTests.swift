//
//  ToolsSleepTests.swift
//  PrismTests
//
//  SAFTE alertness model, nap architect, sleep forecast and sleep cycle model.
//

import Foundation
import Testing
@testable import Prism

private typealias SAFTE = SomaTools.SAFTEEngine
private typealias Nap = SomaTools.NapArchitectEngine
private typealias Forecast = SomaTools.SleepForecastEngine
private typealias Cycle = SomaTools.SleepCycleModel
private typealias Clock = SomaTools.SleepSupport.Clock

private func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}

// MARK: SAFTE

@Suite("SAFTE engine")
struct ToolsSAFTEEngineTests {

    @Test func circadianTermAtKnownClockHours() {
        // C(18) = cos(0) + 0.5*cos(4pi*(18-21)/24) = 1.
        #expect(near(SAFTE.circadianTerm(clockHour: 18), 1.0, 0.001))
        // C(6) = cos(-pi) + 0.5*cos(-5pi/2) = -1.
        #expect(near(SAFTE.circadianTerm(clockHour: 6), -1.0, 0.001))
    }

    @Test func inertiaStartsNegativeAndFades() {
        #expect(near(SAFTE.inertia(minutesSinceWake: 0, sleepIntensityAtWake: 1), -5.0, 0.001))
        #expect(near(SAFTE.inertia(minutesSinceWake: 150, sleepIntensityAtWake: 1), 0.0, 0.001))
    }

    @Test func effectivenessInRangeAndCircadianSign() {
        let peak = SAFTE.effectiveness(reservoir: 2880, clockHour: 18, minutesSinceWake: 200, sleepIntensityAtWake: 2)
        #expect(near(peak, 100, 0.001))
        let trough = SAFTE.effectiveness(reservoir: 2880, clockHour: 6, minutesSinceWake: 200, sleepIntensityAtWake: 2)
        #expect(near(trough, 93, 0.5))
        let empty = SAFTE.effectiveness(reservoir: 0, clockHour: 6, minutesSinceWake: 200, sleepIntensityAtWake: 2)
        #expect(empty >= 0 && empty <= 100)
    }

    @Test func wakeDepletesLinearly() {
        // 8 h awake at 0.5/min from a full reservoir: 2880 minus 240.
        let seg = [SAFTE.Segment(minutes: 480, asleep: false, startClockHour: 8)]
        #expect(near(SAFTE.reservoir(over: seg, from: 2880), 2640, 0.5))
    }

    @Test func sleepRecovers() {
        let seg = [SAFTE.Segment(minutes: 480, asleep: true, startClockHour: 0)]
        #expect(SAFTE.reservoir(over: seg, from: 1500) > 1500)
    }

    private let night = [
        SAFTE.Segment(minutes: 8 * 60, asleep: true, startClockHour: 23),
        SAFTE.Segment(minutes: 16 * 60, asleep: false, startClockHour: 7)
    ]

    @Test func curveStaysInRangeAndIsNonEmpty() {
        let samples = SAFTE.curve(over: night, from: SAFTE.reservoirCapacity * 0.55)
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.effectiveness >= 0 && $0.effectiveness <= 100 })
    }

    @Test func earlierChronotypePeaksEarlier() {
        func peakHour(cbt: Double) -> Double {
            let awake = SAFTE.curve(over: night, from: SAFTE.reservoirCapacity * 0.55, cbtMinHour: cbt)
                .filter { $0.minutesSinceWake >= 0 }
            return awake.max(by: { $0.effectiveness < $1.effectiveness })?.clockHour ?? 0
        }
        #expect(peakHour(cbt: 2.0) < peakHour(cbt: 6.0))
    }

    /// The scale multiplies the awake drain and nothing else.
    @Test func depletionScaleDeepensTheAwakeDrain() {
        let plain = SAFTE.Segment(minutes: 120, asleep: false, startClockHour: 9)
        var hard = plain
        hard.depletionScale = 1.5
        let after = SAFTE.reservoir(over: [plain], from: 2000, stepMin: 1)
        let afterHard = SAFTE.reservoir(over: [hard], from: 2000, stepMin: 1)
        #expect(near(after, 2000 - 0.5 * 120, 0.01))
        #expect(near(afterHard, 2000 - 0.5 * 1.5 * 120, 0.01))
        #expect(afterHard < after)
    }

    @Test func depletionScaleIsIgnoredWhileAsleep() {
        let plain = SAFTE.Segment(minutes: 120, asleep: true, startClockHour: 2)
        var scaled = plain
        scaled.depletionScale = 3
        #expect(near(SAFTE.reservoir(over: [plain], from: 1000, stepMin: 1),
                     SAFTE.reservoir(over: [scaled], from: 1000, stepMin: 1), 0.0001))
    }

    @Test func defaultScaleIsOne() {
        #expect(SAFTE.Segment(minutes: 60, asleep: false, startClockHour: 9).depletionScale == 1.0)
    }

    @Test func chronotypeSeeds() {
        #expect(SAFTE.Chronotype.morning.seedCBTminHour == 3.5)
        #expect(SAFTE.Chronotype.intermediate.seedCBTminHour == 4.5)
        #expect(SAFTE.Chronotype.evening.seedCBTminHour == 5.5)
    }
}

// MARK: Nap architect

@Suite("Nap architect engine")
struct ToolsNapArchitectEngineTests {

    /// The curve the nap page feeds the engine: one night, one awake stretch,
    /// reservoir seeded at 55% of capacity.
    private func curve(bedHour: Double, nightHours: Double, cbtMinHour: Double = 4) -> [SAFTE.Sample] {
        let wakeHour = Clock.wrap24(bedHour + nightHours)
        let sleepMinutes = max(1, Clock.forward(from: bedHour, to: wakeHour) * 60)
        return Nap.dayCurve(bedHour: bedHour, wakeHour: wakeHour,
                            sleepMinutes: sleepMinutes, cbtMinHour: cbtMinHour)
    }

    private func dipPressure(_ samples: [SAFTE.Sample]) -> Double {
        let dip = samples
            .filter { $0.clockHour >= Nap.dipSearchStart && $0.clockHour <= Nap.dipSearchEnd }
            .min { $0.effectiveness < $1.effectiveness }
        return 100 - (dip?.effectiveness ?? 0)
    }

    /// An unwrapped `bedtime minus 6` went negative for every bedtime between
    /// 00:00 and 05:59, so those users never had a window.
    @Test(arguments: [0.5, 1.0, 2.0, 3.0, 5.5])
    func cutoffWrapsForAfterMidnightBedtimes(bedtime: Double) throws {
        let plan = try #require(Nap.plan(samples: curve(bedHour: bedtime, nightHours: 7),
                                         nowHour: 14.5, expectedBedtimeHour: bedtime))
        #expect(near(plan.hardCutoffHour, Clock.wrap24(bedtime - Nap.bedtimeGuardHours), 1e-9))
        #expect(plan.hasWindow)
        #expect(plan.hardCutoffHour > 0)
    }

    @Test func pastCutoffIsReachableAfterMidnightBedtimes() throws {
        // Bedtime 00:30 puts the cutoff at 18:30; 19:30 is inside the guard.
        let plan = try #require(Nap.plan(samples: curve(bedHour: 0.5, nightHours: 7),
                                         nowHour: 19.5, expectedBedtimeHour: 0.5))
        #expect(plan.pastCutoff)
        #expect(!plan.isOpenNow)
        let earlier = try #require(Nap.plan(samples: curve(bedHour: 0.5, nightHours: 7),
                                            nowHour: 18.0, expectedBedtimeHour: 0.5))
        #expect(!earlier.pastCutoff)
    }

    @Test(arguments: [19.0, 20.0])
    func earlyBedtimeStillHasNoWindow(bedtime: Double) throws {
        let plan = try #require(Nap.plan(samples: curve(bedHour: 23, nightHours: 7),
                                         nowHour: 14.5, expectedBedtimeHour: bedtime))
        #expect(!plan.hasWindow)
        #expect(plan.maxMinutes == 0)
        #expect(plan.recommendedMinutes == 0)
        #expect(!plan.isOpenNow)
        #expect(!plan.pastCutoff)
    }

    /// The anchors are recomputed from SAFTE, so a recalibration of the curve
    /// fails here instead of silently stranding the bars.
    @Test func pressureThresholdsSitInsideTheReachableRange() {
        let shortNight = dipPressure(curve(bedHour: 23, nightHours: 4))
        let normalNight = dipPressure(curve(bedHour: 23, nightHours: 8))
        #expect(near(shortNight, 36.4, 0.5))
        #expect(near(normalNight, 24.0, 0.5))
        #expect(Nap.heavyPressure < shortNight)
        #expect(Nap.heavyPressure > normalNight)
        #expect(Nap.pressureThreshold < shortNight)
        #expect(Nap.pressureThreshold > normalNight)
        #expect(Nap.pressureThreshold < Nap.heavyPressure)
    }

    @Test func durationOptimizerActuallyReachesAFullCycle() throws {
        let short = try #require(Nap.plan(samples: curve(bedHour: 23, nightHours: 4),
                                          nowHour: 14.5, expectedBedtimeHour: 23))
        #expect(short.recommendedMinutes == Nap.fullCycleMinutes)
        let rested = try #require(Nap.plan(samples: curve(bedHour: 23, nightHours: 9),
                                           nowHour: 14.5, expectedBedtimeHour: 23))
        #expect(rested.recommendedMinutes == Nap.powerNapMinutes)
        #expect(!rested.isOpenNow, "a 9 h night does not need a nap urged")
    }

    @Test func windowOpensOnAShortenedNight() throws {
        let plan = try #require(Nap.plan(samples: curve(bedHour: 23, nightHours: 6),
                                         nowHour: 14.5, expectedBedtimeHour: 23))
        #expect(plan.isOpenNow)
        #expect(plan.currentPressure >= Nap.pressureThreshold)
    }

    @Test func maxMinutesMeasuresTheRoomLeftBeforeTheCutoff() throws {
        let samples = curve(bedHour: 23, nightHours: 5)   // cutoff 17:00
        let wide = try #require(Nap.plan(samples: samples, nowHour: 14.5, expectedBedtimeHour: 23))
        #expect(wide.maxMinutes == Nap.fullCycleMinutes)
        let narrow = try #require(Nap.plan(samples: samples, nowHour: 16.0, expectedBedtimeHour: 23))
        #expect(narrow.maxMinutes == 60)
        let sliver = try #require(Nap.plan(samples: samples, nowHour: 16.9, expectedBedtimeHour: 23))
        #expect(sliver.maxMinutes == 6)
        #expect(sliver.recommendedMinutes == 0, "no room left is not a 6 minute nap")
        #expect(!sliver.isOpenNow)
    }

    @Test func degenerateCurveReturnsNilInsteadOfAFabricatedDip() {
        let nightOnly = [SAFTE.Sample(clockHour: 3, minutesSinceWake: -1, effectiveness: 70)]
        #expect(Nap.plan(samples: nightOnly, nowHour: 14, expectedBedtimeHour: 23) == nil)
        #expect(Nap.plan(samples: [], nowHour: 14, expectedBedtimeHour: 23) == nil)
    }

    @Test func pressureUsesCircularNearestSample() throws {
        let samples = [
            SAFTE.Sample(clockHour: 23.9, minutesSinceWake: 600, effectiveness: 40),
            SAFTE.Sample(clockHour: 12.0, minutesSinceWake: 300, effectiveness: 90),
            SAFTE.Sample(clockHour: 14.0, minutesSinceWake: 420, effectiveness: 70)
        ]
        // 00:10 is 0.27 h from 23:54 on the circle and 11.8 h from 12:00.
        let plan = try #require(Nap.plan(samples: samples, nowHour: 0.1667, expectedBedtimeHour: 23))
        #expect(near(plan.currentPressure, 60, 1e-9))
    }

    // MARK: Lifted from the page

    @Test func planFromLastNightMatchesTheCurvePath() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let bed = utc.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 23))!
        let wake = utc.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 5))!
        let now = utc.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 14, minute: 30))!
        let plan = try #require(Nap.plan(lastNightBed: bed, wake: wake, now: now,
                                         cbtMinHour: 4, calendar: utc))
        let direct = try #require(Nap.plan(samples: curve(bedHour: 23, nightHours: 6),
                                           nowHour: 14.5, expectedBedtimeHour: 23))
        #expect(plan == direct)
    }

    @Test func pressureBandsFollowTheEngineThresholds() {
        #expect(Nap.PressureBand(pressure: 10) == .light)
        #expect(Nap.PressureBand(pressure: Nap.pressureThreshold) == .moderate)
        #expect(Nap.PressureBand(pressure: Nap.heavyPressure) == .heavy)
        #expect(Nap.PressureBand.moderate.bounds.lower == Nap.pressureThreshold)
        #expect(Nap.PressureBand.moderate.bounds.upper == Nap.heavyPressure)
    }

    @Test func trendNeedsSevenDaysAndExcludesToday() throws {
        #expect(Nap.trend(series: [20, 22, nil, 24]) == nil)
        let series: [Double?] = [20, 20, 20, 20, 20, 20, 20, 50]
        let trend = try #require(Nap.trend(series: series))
        #expect(trend.baselineMean == 20)
        #expect(trend.series.count == 8)
    }

    @Test func programWeeksClampAndFinish() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = utc.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let day10 = utc.date(byAdding: .day, value: 10, to: start)!
        let day40 = utc.date(byAdding: .day, value: 40, to: start)!
        #expect(Nap.programWeekIndex(start: start, now: day10, calendar: utc) == 1)
        #expect(Nap.programWeekIndex(start: start, now: day40, calendar: utc) == 3)
        #expect(!Nap.programIsFinished(start: start, now: day10, calendar: utc))
        #expect(Nap.programIsFinished(start: start, now: day40, calendar: utc))
    }

    @Test func agendaFitFindsTheLongestGapOrReportsFull() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = utc.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3600) }
        let plan = Nap.Plan(dipHour: 14, windowStartHour: 14, hardCutoffHour: 17, hasWindow: true,
                            recommendedMinutes: 20, maxMinutes: 90, currentPressure: 30,
                            isOpenNow: true, pastCutoff: false)
        let fit = Nap.agendaFit(plan: plan, day: day,
                                busy: [DateInterval(start: at(14), end: at(15)),
                                       DateInterval(start: at(15.5), end: at(17))],
                                calendar: utc)
        #expect(fit == .gap(start: 15, end: 15.5))
        let full = Nap.agendaFit(plan: plan, day: day,
                                 busy: [DateInterval(start: at(13), end: at(18))], calendar: utc)
        #expect(full == .full)
        #expect(Nap.agendaFit(plan: plan, day: day, busy: [], calendar: utc) == nil)
    }
}

// MARK: Sleep forecast

@Suite("Sleep forecast engine")
struct ToolsSleepForecastEngineTests {

    /// Seven nights whose median is 6.9 h, spread 0.2965 h (MAD floored).
    private let sleepHistory = [6.4, 7.1, 6.8, 7.3, 6.6, 6.9, 7.0]

    private func inputs(need: Double = 8,
                        baselineScore: Double = 78,
                        caffeineMg: Double = 0,
                        debt: Double = 0,
                        hrvRatio: Double = 1,
                        jetlag: Double = 0,
                        sleep: [Double] = [],
                        deepFractions: [Double] = [],
                        remFractions: [Double] = [],
                        caffeineHistory: [Double] = [],
                        jetlagHistory: [Double] = []) -> Forecast.Inputs {
        Forecast.Inputs(sleepNeedHours: need,
                        baselineScore: baselineScore,
                        caffeineMg: caffeineMg,
                        priorNightDebtHours: debt,
                        hrvRatio: hrvRatio,
                        socialJetlagHours: jetlag,
                        recentSleepHours: sleep,
                        recentDeepFractions: deepFractions,
                        recentRemFractions: remFractions,
                        recentCaffeineMg: caffeineHistory,
                        recentSocialJetlagHours: jetlagHistory)
    }

    /// With no personal duration history the engine reports NO prediction
    /// rather than restating the target as a forecast.
    @Test func noHistoryMeansNoDurationPrediction() {
        let f = Forecast.forecast(inputs(debt: 0.5))
        #expect(f.predictedHoursEstimate == nil)
        #expect(f.predictedHoursRange == nil)
        #expect(!f.hasDurationPrediction)
        #expect(near(f.predictedHours, 8, 0.0001))
    }

    /// Habitual median (6.9 h) plus the prior-night pressure (0.5 / 4 h).
    @Test func durationIsPredictedFromHabitualDuration() {
        let f = Forecast.forecast(inputs(debt: 0.5, sleep: sleepHistory))
        #expect(near(f.predictedHoursEstimate ?? .nan, 7.025, 0.0001))
        #expect(near(f.predictedHoursRange?.lowerBound ?? .nan, 6.7285, 0.001))
        #expect(near(f.predictedHoursRange?.upperBound ?? .nan, 7.3215, 0.001))
        #expect(abs((f.predictedHoursEstimate ?? 0) - 8) > 0.9)
    }

    @Test func stageFractionsAreNotDisguisedConstants() {
        let f = Forecast.forecast(inputs(debt: 0.5, sleep: sleepHistory))
        #expect(f.deepFractionEstimate == nil)
        #expect(f.remFractionEstimate == nil)
        #expect(!f.hasStagePrediction)
    }

    @Test func stageFractionsFollowTheUsersOwnNights() {
        let f = Forecast.forecast(inputs(debt: 0.5,
                                         sleep: sleepHistory,
                                         deepFractions: [0.11, 0.13, 0.12, 0.14, 0.12],
                                         remFractions: [0.26, 0.24, 0.27, 0.25, 0.26]))
        #expect(f.hasStagePrediction)
        #expect(near(f.deepFractionEstimate ?? .nan, 0.1275, 0.0001))
        #expect(near(f.remFractionEstimate ?? .nan, 0.26, 0.0001))
    }

    /// One extra coffee (100 mg over the habit) is the full penalty.
    @Test func caffeineScaleMatchesItsPerServingUnit() {
        let habitZero = [Double](repeating: 0, count: 7)
        let quiet = Forecast.forecast(inputs(sleep: sleepHistory, caffeineHistory: habitZero))
        let coffee = Forecast.forecast(inputs(caffeineMg: 100, sleep: sleepHistory, caffeineHistory: habitZero))
        #expect(near((quiet.predictedHoursEstimate ?? 0) - (coffee.predictedHoursEstimate ?? 0), 1.0, 0.0001))
        #expect(quiet.predictedScore - coffee.predictedScore == 15)
    }

    @Test func habitualCaffeineIsNotPenalisedTwice() {
        let habit = [Double](repeating: 90, count: 7)
        let usual = Forecast.forecast(inputs(caffeineMg: 90, sleep: sleepHistory, caffeineHistory: habit))
        #expect(usual.predictedScore == 78)
        #expect(!usual.levers.contains { $0.kind == .caffeine })
        let doubled = Forecast.forecast(inputs(caffeineMg: 180, sleep: sleepHistory, caffeineHistory: habit))
        #expect(doubled.predictedScore < usual.predictedScore)
        #expect(doubled.levers.contains { $0.kind == .caffeine })
    }

    @Test func habitualSocialJetlagIsNotPenalisedTwice() {
        let habit = [Double](repeating: 2.0, count: 7)
        let usual = Forecast.forecast(inputs(jetlag: 2.0, sleep: sleepHistory, jetlagHistory: habit))
        #expect(usual.predictedScore == 78)
        #expect(!usual.levers.contains { $0.kind == .consistency })
    }

    @Test func noScoringHistoryUsesTheCanonicalNeutralAnchor() {
        let f = Forecast.forecast(inputs(baselineScore: 0))
        #expect(near(Double(f.predictedScore), SomaTools.SleepSupport.sleepScoreNeutral, 0.5))
    }

    /// One saturation for one quantity: a four hour shortfall is full debt.
    @Test func nightShortfallSaturationPutsTheFullDebtCapAtStake() {
        #expect(SomaTools.SleepSupport.NightSleepDebtScale.saturationHours == 4)
        let f = Forecast.forecast(inputs(debt: SomaTools.SleepSupport.NightSleepDebtScale.saturationHours))
        #expect(f.levers.first { $0.kind == .sleepDebt }?.pointsAtStake == 12)
    }

    @Test func reconciliationFlagsWhenNothingWasActuallyPredicted() {
        let blind = Forecast.forecast(inputs())
        let r1 = Forecast.reconcile(forecast: blind, actualHours: 6.4, actualScore: 70)
        #expect(!r1.durationWasPredicted)
        let real = Forecast.forecast(inputs(sleep: sleepHistory))
        let r2 = Forecast.reconcile(forecast: real, actualHours: 6.4, actualScore: 70)
        #expect(r2.durationWasPredicted)
        #expect(near(r2.predictedHours, real.predictedHoursEstimate ?? .nan, 0.0001))
    }

    @Test func leverCapMatchesTheCapTheScoreActuallyApplies() {
        #expect(Forecast.leverCap(.caffeine) == 15)
        #expect(Forecast.leverCap(.consistency) == 12)
        #expect(Forecast.leverCap(.recovery) == 10)
        #expect(Forecast.leverCap(.sleepDebt) == 12)
    }

    @Test func noLeverEverExceedsItsOwnCap() {
        let extreme = Forecast.forecast(Forecast.Inputs(sleepNeedHours: 8, baselineScore: 90,
                                                        caffeineMg: 2000, priorNightDebtHours: 12,
                                                        hrvRatio: 0.1, socialJetlagHours: 12))
        #expect(!extreme.levers.isEmpty)
        for lever in extreme.levers {
            #expect(lever.pointsAtStake <= Forecast.leverCap(lever.kind), "\(lever.kind) exceeded its cap")
        }
    }

    // MARK: Lifted from the page

    @Test func causalTailIsStrictlyBeforeTheIndex() {
        let series: [Double?] = [1, nil, 3, 4, 5]
        #expect(Forecast.causalTail(series, endingBefore: 4, days: 10) == [1, 3, 4])
        #expect(Forecast.causalTail(series, endingBefore: 4, days: 2) == [3, 4])
        #expect(Forecast.causalTail(series, endingBefore: 0, days: 5).isEmpty)
        #expect(Forecast.trendWindow(series, endingBefore: 3, days: 5) == [1, nil, 3])
    }

    @Test func stageFractionsSkipMissingStages() {
        let asleep: [Double?] = [8, 7, nil, 6]
        let deep: [Double?] = [1, nil, 1, 1.5]
        #expect(Forecast.stageFractions(asleep: asleep, stage: deep, endingBefore: 4, days: 28) == [0.125, 0.25])
    }

    @Test func recentMeanIgnoresNonPositiveScores() {
        #expect(Forecast.recentMean([0, 70, 80]) == 75)
        #expect(Forecast.recentMean([]) == 0)
    }

    @Test func caffeineHistorySkipsDaysWithoutAnEntry() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = utc.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let history = Forecast.caffeineHistory(endingBefore: date, days: 3, calendar: utc) { day in
            utc.component(.day, from: day) == 13 ? nil : Double(utc.component(.day, from: day))
        }
        #expect(history == [12, 14])
    }

    @Test func bandsAndRailWrap() {
        #expect(Forecast.band(29) == .low)
        #expect(Forecast.band(30) == .fair)
        #expect(Forecast.band(60) == .good)
        #expect(Forecast.isAhead(0.5, of: 23))
        #expect(!Forecast.isAhead(22, of: 23))
        #expect(!Forecast.isAhead(12, of: 23.5))
    }
}

// MARK: Sleep cycle model

@Suite("Sleep cycle model")
struct ToolsSleepCycleModelTests {

    private let onset = Date(timeIntervalSince1970: 1_000_000)

    /// Three synthetic 90 min cycles, core, deep, core, rem. Surfacings land at
    /// 45, 90, 135, 180, 225 min.
    private func makeNight() -> [Cycle.StageSpan] {
        let cycle: [(String, Double)] = [("core", 15), ("deep", 30), ("core", 15), ("rem", 30)]
        var spans: [Cycle.StageSpan] = []
        for _ in 0..<3 {
            for (stage, minutes) in cycle {
                spans.append(.init(stage: stage, seconds: minutes * 60))
            }
        }
        return spans
    }

    @Test func emptyNightYieldsNoBoundaries() {
        #expect(Cycle.cycles(from: []).isEmpty)
        #expect(Cycle.meanCycleSeconds([]) == nil)
    }

    @Test func syntheticHypnogramYieldsCycleBoundaries() {
        let cycles = Cycle.cycles(from: makeNight())
        #expect(cycles.count == 3)
        #expect(near(cycles.first?.lowerBound ?? .nan, 0, 0.001))
        #expect(near(cycles[0].upperBound, 90 * 60, 0.001))
        #expect(near(cycles[1].upperBound, 180 * 60, 0.001))
        #expect(near(cycles.last?.upperBound ?? .nan, 270 * 60, 0.001))
        #expect(cycles[0].upperBound == cycles[1].lowerBound)
        #expect(cycles[1].upperBound == cycles[2].lowerBound)
        #expect(near(Cycle.meanCycleSeconds(makeNight()) ?? .nan, 90 * 60, 0.001))
    }

    @Test func recommendedWakeWindowLandsOnLightOrRemBoundaryInsideFlex() throws {
        // Target 235 min, flex 20 min: window [215, 255]. rem@240 wins.
        let target = onset.addingTimeInterval(235 * 60)
        let range = try #require(Cycle.recommendedWakeWindow(
            spans: makeNight(), onset: onset, targetWake: target, flexMinutes: 20))
        let boundary = onset.addingTimeInterval(240 * 60)
        #expect(range.lowerBound <= boundary)
        #expect(range.upperBound >= boundary)
        #expect(range.lowerBound >= onset.addingTimeInterval(215 * 60))
        #expect(range.upperBound <= onset.addingTimeInterval(255 * 60))
    }

    @Test func recommendedWakeWindowNilWhenNoBoundaryInRange() {
        let target = onset.addingTimeInterval(25 * 60)
        #expect(Cycle.recommendedWakeWindow(spans: makeNight(), onset: onset,
                                            targetWake: target, flexMinutes: 10) == nil)
    }

    @Test func nextLightWindowReturnsNextSurfacing() {
        let after = onset.addingTimeInterval(100 * 60)
        let next = Cycle.nextLightWindow(spans: makeNight(), onset: onset, after: after)
        #expect(next == onset.addingTimeInterval(135 * 60))
    }

    @Test func nextLightWindowNilAfterLastSurfacing() {
        let after = onset.addingTimeInterval(250 * 60)
        #expect(Cycle.nextLightWindow(spans: makeNight(), onset: onset, after: after) == nil)
    }
}
