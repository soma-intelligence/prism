//
//  ToolsCaffeineTests.swift
//  PrismTests
//
//  The caffeine engines under SomaTools: pharmacokinetics, the dose-aware
//  reading, the curve window, day buckets, the habitual day and the reopen
//  instant.
//

import Foundation
import Testing
@testable import Prism

private typealias Dose = SomaTools.CaffeineModel.Dose

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

private func hours(_ h: Double) -> TimeInterval { h * 3600 }

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

// MARK: - CaffeineModel

@Suite("Caffeine model")
struct ToolsCaffeineModelTests {
    typealias C = SomaTools.CaffeineModel
    private let t0 = Date(timeIntervalSince1970: 0)

    @Test func residualHalvesEveryHalfLife() {
        let doses = [Dose(mg: 200, time: t0)]
        // 5 h half-life: 100 mg at 5 h, 50 mg at 10 h.
        #expect(close(C.residual(doses: doses, at: t0.addingTimeInterval(hours(5))), 100, 0.5))
        #expect(close(C.residual(doses: doses, at: t0.addingTimeInterval(hours(10))), 50, 0.5))
    }

    @Test func residualIgnoresFutureDoses() {
        let doses = [Dose(mg: 200, time: t0.addingTimeInterval(3600))]
        #expect(close(C.residual(doses: doses, at: t0), 0, 0.0001))
    }

    @Test func recommendedCutoffFromTypicalDose() {
        // lead = 5 * log2(200/25) = 15 h; bedtime 23:00 gives 08:00.
        #expect(close(C.recommendedCutoffHour(bedtimeHour: 23, typicalDoseMg: 200), 8, 0.01))
    }

    @Test func recommendedCutoffUnknownDoseUsesStandardServing() {
        // No dose: the standard 100 mg cup, lead = 5 * log2(100/25) = 10 h.
        #expect(close(C.recommendedCutoffHour(bedtimeHour: 23, typicalDoseMg: nil), 13, 0.01))
    }

    @Test func recommendedCutoffDoseUnderThresholdNeedsNoCutoff() {
        #expect(close(C.recommendedCutoffHour(bedtimeHour: 23, typicalDoseMg: 20), 23, 0.01))
    }

    @Test func residualSumsMultipleDoses() {
        let doses = [Dose(mg: 200, time: t0),
                     Dose(mg: 100, time: t0.addingTimeInterval(hours(5)))]
        // At +5h: 200 mg halved (100) plus 100 mg fresh = 200 mg.
        #expect(close(C.residual(doses: doses, at: t0.addingTimeInterval(hours(5))), 200, 0.5))
    }
}

// MARK: - CaffeineWindowEngine

@Suite("Caffeine window engine")
struct ToolsCaffeineWindowEngineTests {
    typealias W = SomaTools.CaffeineWindowEngine
    typealias C = SomaTools.CaffeineModel
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// With nothing logged the headroom is the whole 25 mg threshold, so the
    /// engine lands on exactly the plain formula's lead: a 100 mg cup is two
    /// half-lives, 10 h.
    @Test func lastCallWithNoDosesMatchesTheSingleServingFormula() throws {
        let bedtime = t0.addingTimeInterval(hours(14))
        let reading = W.read(doses: [], nextDoseMg: 100, bedtime: bedtime, now: t0)
        let lastCall = try #require(reading.lastCall)
        #expect(close(lastCall.timeIntervalSince(bedtime), -hours(10), 60))
        #expect(close(reading.headroomMg, C.bedtimeThresholdMg, 0.001))
        #expect(!reading.isOverBudget)
    }

    @Test func lastCallScalesWithTheCupSize() {
        let bedtime = t0.addingTimeInterval(hours(18))
        let reading = W.read(doses: [], nextDoseMg: 200, bedtime: bedtime, now: t0)
        #expect(close(reading.lastCall?.timeIntervalSince(bedtime) ?? 0, -hours(15), 60))
    }

    @Test func lastCallSmallCupNeedsNoLead() {
        let bedtime = t0.addingTimeInterval(hours(8))
        let reading = W.read(doses: [], nextDoseMg: 20, bedtime: bedtime, now: t0)
        #expect(reading.lastCall == bedtime)
    }

    /// The same cup after a heavy morning must come with an EARLIER deadline.
    @Test func lastCallMovesEarlierAsTheDaysIntakeGrows() {
        let bedtime = t0.addingTimeInterval(hours(20))
        func deadline(_ doses: [Dose]) -> Date {
            W.read(doses: doses, nextDoseMg: 100, bedtime: bedtime, now: t0).lastCall ?? .distantPast
        }
        let none = deadline([])
        let one = deadline([Dose(mg: 90, time: t0)])
        let three = deadline([Dose(mg: 90, time: t0),
                              Dose(mg: 90, time: t0.addingTimeInterval(hours(2))),
                              Dose(mg: 90, time: t0.addingTimeInterval(hours(4)))])
        #expect(one < none)
        #expect(three < one)
    }

    @Test func overBudgetHasNoDeadlineLeft() {
        let bedtime = t0.addingTimeInterval(hours(4))
        let reading = W.read(doses: [Dose(mg: 400, time: t0)], nextDoseMg: 100, bedtime: bedtime, now: t0)
        #expect(reading.isOverBudget)
        #expect(reading.lastCall == nil)
        #expect(reading.lastCallHasPassed)
        #expect(reading.maxDoseNowMg == 0)
        #expect(reading.atBedtimeMg > C.bedtimeThresholdMg)
    }

    @Test func headroomIsTheThresholdMinusTheProjection() {
        let bedtime = t0.addingTimeInterval(hours(5))
        let reading = W.read(doses: [Dose(mg: 30, time: t0)], nextDoseMg: 100, bedtime: bedtime, now: t0)
        #expect(close(reading.onBoardNowMg, 30, 0.5))
        #expect(close(reading.atBedtimeMg, 15, 0.5))
        #expect(close(reading.headroomMg, 10, 0.5))
    }

    @Test func maxDoseNowLandsExactlyOnTheThreshold() {
        let bedtime = t0.addingTimeInterval(hours(6))
        let doses = [Dose(mg: 60, time: t0.addingTimeInterval(-hours(3)))]
        let reading = W.read(doses: doses, nextDoseMg: 100, bedtime: bedtime, now: t0)
        let withMax = doses + [Dose(mg: reading.maxDoseNowMg, time: t0)]
        #expect(close(C.residual(doses: withMax, at: bedtime), C.bedtimeThresholdMg, 0.5))
    }

    @Test func drinkingAtTheDeadlineLandsOnTheThreshold() {
        let bedtime = t0.addingTimeInterval(hours(20))
        let doses = [Dose(mg: 100, time: t0)]
        let reading = W.read(doses: doses, nextDoseMg: 120, bedtime: bedtime, now: t0)
        let withCup = doses + [Dose(mg: 120, time: reading.lastCall ?? bedtime)]
        #expect(close(C.residual(doses: withCup, at: bedtime), C.bedtimeThresholdMg, 0.5))
    }

    @Test func clearanceTimeIsThreeHalfLivesForEightTimesTheThreshold() {
        let clears = W.clearanceTime(doses: [Dose(mg: 200, time: t0)], from: t0)
        #expect(close(clears?.timeIntervalSince(t0) ?? 0, hours(15), 60))
    }

    @Test func clearanceTimeIsNilWhenAlreadyUnderTheThreshold() {
        #expect(W.clearanceTime(doses: [Dose(mg: 20, time: t0)], from: t0) == nil)
    }

    @Test func curveStepsUpAtEachDoseAndDecaysBetween() throws {
        let doses = [Dose(mg: 100, time: t0), Dose(mg: 100, time: t0.addingTimeInterval(hours(4)))]
        let values = W.curve(doses: doses, from: t0.addingTimeInterval(-hours(1)),
                             to: t0.addingTimeInterval(hours(10)), count: 45)
        #expect(values.count == 45)
        #expect(close(try #require(values.first), 0, 0.001))
        let peak = try #require(values.max())
        #expect(peak > 100)
        #expect(try #require(values.last) < peak)
    }

    @Test func curveAddingIsAlwaysAboveTheMeasuredCurve() {
        let doses = [Dose(mg: 80, time: t0)]
        let end = t0.addingTimeInterval(hours(8))
        let base = W.curve(doses: doses, from: t0, to: end, count: 20)
        let projected = W.curveAdding(doses: doses, dose: 100, at: t0, from: t0, to: end, count: 20)
        for (b, p) in zip(base, projected) { #expect(p > b) }
    }

    @Test func personalServingIsTheMedianOfWhatWasLogged() {
        #expect(W.personalServingMg(servings: [80, 120, 200]) == 120)
        #expect(W.personalServingMg(servings: [80, 120]) == 100)
    }

    @Test func personalServingClampsAndFallsBack() {
        #expect(W.personalServingMg(servings: []) == W.fallbackServingMg)
        #expect(W.personalServingMg(servings: [4000]) == W.servingBounds.upperBound)
        #expect(W.personalServingMg(servings: [2]) == W.servingBounds.lowerBound)
        // A zero is not a serving: it must not drag the median down.
        #expect(W.personalServingMg(servings: [0, 0, 90]) == 90)
    }

    @Test func nextOccurrenceWrapsPastMidnight() {
        let epochDay = 1_700_000_000 - (1_700_000_000 % 86_400)
        let midnight = Date(timeIntervalSince1970: TimeInterval(epochDay))
        let at22 = midnight.addingTimeInterval(hours(22))
        // 23:00 is still ahead of 22:00: tonight.
        #expect(W.nextOccurrence(ofHour: 23, after: at22, calendar: utc) == midnight.addingTimeInterval(hours(23)))
        // 07:00 is behind: tomorrow morning, never this morning.
        #expect(W.nextOccurrence(ofHour: 7, after: at22, calendar: utc) == midnight.addingTimeInterval(hours(24 + 7)))
    }
}

// MARK: - CaffeineCurveMath

@Suite("Caffeine curve math")
struct ToolsCaffeineCurveMathTests {
    typealias CM = SomaTools.CaffeineCurveMath

    /// A reading built directly: `isOpen` only reads `isOverBudget`, `lastCall`
    /// and `lastCallHour` off it.
    private func reading(headroomMg: Double, lastCall: Date?,
                         bedtime: Date, now: Date) -> SomaTools.CaffeineWindowEngine.Reading {
        SomaTools.CaffeineWindowEngine.Reading(
            onBoardNowMg: 0, atBedtimeMg: 0, headroomMg: headroomMg, maxDoseNowMg: 0,
            nextDoseMg: 100, lastCall: lastCall, clearsAt: nil, totalMg: 0, doseCount: 0,
            bedtime: bedtime, now: now)
    }

    /// `Reading.lastCallHour` reads the device calendar, so the instants are
    /// built on it too, on a fixed day with no DST change, and the two sides
    /// can never disagree about the hour they mean.
    private func date(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hour))!
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func windowStartsThirtyMinutesBeforeTheFirstDose() {
        let window = CM.window(doses: [Dose(mg: 100, time: t0)],
                               now: t0.addingTimeInterval(3600), bedtime: t0.addingTimeInterval(hours(8)))
        #expect(window.start == t0.addingTimeInterval(-1800))
    }

    @Test func windowEndsOneHourAfterBedtime() {
        let bedtime = t0.addingTimeInterval(hours(8))
        let window = CM.window(doses: [Dose(mg: 100, time: t0)], now: t0, bedtime: bedtime)
        #expect(window.end == bedtime.addingTimeInterval(3600))
    }

    @Test func windowAnchorsOnNowWhenThereAreNoDoses() {
        let window = CM.window(doses: [], now: t0, bedtime: t0.addingTimeInterval(hours(8)))
        #expect(window.start == t0.addingTimeInterval(-1800))
    }

    @Test func windowAnchorsOnNowWhenTheFirstDoseIsInTheFuture() {
        let window = CM.window(doses: [Dose(mg: 100, time: t0.addingTimeInterval(3600))],
                               now: t0, bedtime: t0.addingTimeInterval(hours(8)))
        #expect(window.start == t0.addingTimeInterval(-1800))
    }

    @Test func isOpenFalseWhenOverBudget() {
        let r = reading(headroomMg: 0, lastCall: date(hour: 20), bedtime: t0, now: t0)
        #expect(!CM.isOpen(reading: r, wakeHour: 7, bedtimeHour: 23))
    }

    @Test func isOpenFalseWhenThereIsNoLastCall() {
        let r = reading(headroomMg: 10, lastCall: nil, bedtime: t0, now: t0)
        #expect(!CM.isOpen(reading: r, wakeHour: 7, bedtimeHour: 23))
    }

    @Test func isOpenTrueWhenDeadlineFallsBeforeBedtime() {
        let r = reading(headroomMg: 10, lastCall: date(hour: 13), bedtime: t0, now: t0)
        #expect(CM.isOpen(reading: r, wakeHour: 7, bedtimeHour: 23))
    }

    /// A deadline that lands AFTER bedtime leaves no drawable stretch.
    @Test func isOpenFalseWhenDeadlineFallsAfterBedtime() {
        let r = reading(headroomMg: 10, lastCall: date(hour: 2), bedtime: t0, now: t0)
        #expect(!CM.isOpen(reading: r, wakeHour: 7, bedtimeHour: 23))
    }

    @Test func isOpenWrapsPastMidnightForANightOwl() {
        let r = reading(headroomMg: 10, lastCall: date(hour: 1), bedtime: t0, now: t0)
        #expect(CM.isOpen(reading: r, wakeHour: 22, bedtimeHour: 6))
    }

    /// `toDeadline > 0` is strict: a deadline exactly ON the wake hour has zero room.
    @Test func isOpenFalseWhenDeadlineEqualsWakeHour() {
        let r = reading(headroomMg: 10, lastCall: date(hour: 7), bedtime: t0, now: t0)
        #expect(!CM.isOpen(reading: r, wakeHour: 7, bedtimeHour: 23))
    }

    /// `toDeadline <= toBedtime` is inclusive: a deadline AT bedtime is open.
    @Test func isOpenTrueWhenDeadlineEqualsBedtimeHour() {
        let r = reading(headroomMg: 10, lastCall: date(hour: 23), bedtime: t0, now: t0)
        #expect(CM.isOpen(reading: r, wakeHour: 7, bedtimeHour: 23))
    }
}

// MARK: - Day buckets and habitual day

@Suite("Caffeine day buckets and habitual day")
struct ToolsCaffeineDayTests {
    typealias B = SomaTools.CaffeineDayBuckets
    typealias H = SomaTools.CaffeineHabitualDay

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    @Test func dosesOfOneDayAreSortedAndBounded() {
        let all = [Dose(mg: 80, time: date(16, 15)),
                   Dose(mg: 100, time: date(16, 0, 30)),
                   Dose(mg: 60, time: date(15, 23, 50)),
                   Dose(mg: 50, time: date(17, 0, 0))]
        let day = B.doses(all, on: date(16, 12), calendar: utc)
        #expect(day.map(\.mg) == [100, 80])
    }

    @Test func byDayIsOldestFirstWithEmptySlots() {
        let all = [Dose(mg: 100, time: date(14, 8)),
                   Dose(mg: 50, time: date(16, 14)),
                   Dose(mg: 90, time: date(16, 8))]
        let slots = B.byDay(all, days: 3, endingOn: date(16, 20), calendar: utc)
        #expect(slots.count == 3)
        #expect(slots[0].map(\.mg) == [100])
        #expect(slots[1].isEmpty)
        #expect(slots[2].map(\.mg) == [90, 50])
        #expect(B.byDay(all, days: 0, endingOn: date(16, 20), calendar: utc).isEmpty)
    }

    @Test func profileNeedsThreeLoggedDays() {
        let two = [[Dose(mg: 100, time: date(14, 8))], [], [Dose(mg: 100, time: date(16, 8))]]
        #expect(H.profile(dosesByDay: two, calendar: utc) == nil)
    }

    @Test func profileIsMediansPerCupSlot() throws {
        let days: [[Dose]] = [
            [Dose(mg: 100, time: date(13, 8)), Dose(mg: 60, time: date(13, 14))],
            [Dose(mg: 120, time: date(14, 9)), Dose(mg: 80, time: date(14, 15))],
            [Dose(mg: 400, time: date(15, 7))],
            [],
        ]
        let profile = try #require(H.profile(dosesByDay: days, calendar: utc))
        #expect(profile.dayCount == 3)
        // Median count of (2, 2, 1) is 2 cups.
        try #require(profile.cups.count == 2)
        // First cups: hours 8, 9, 7 (median 8), doses 100, 120, 400 (median 120).
        #expect(close(profile.cups[0].hour, 8, 1e-9))
        #expect(close(profile.cups[0].mg, 120, 1e-9))
        // Second cups: hours 14 and 15 (median 14.5), doses 60 and 80 (median 70).
        #expect(close(profile.cups[1].hour, 14.5, 1e-9))
        #expect(close(profile.cups[1].mg, 70, 1e-9))
        #expect(close(profile.totalMg, 190, 1e-9))

        let placed = H.doses(for: profile, on: date(20, 12), calendar: utc)
        #expect(placed.map(\.time) == [date(20, 8), date(20, 14, 30)])
    }

    @Test func medianIsNilOnEmpty() {
        #expect(H.median([]) == nil)
        #expect(H.median([3, 1, 2]) == 2)
        #expect(H.median([4, 1, 3, 2]) == 2.5)
    }
}

// MARK: - CaffeineReopen

@Suite("Caffeine reopen")
struct ToolsCaffeineReopenTests {
    typealias R = SomaTools.CaffeineReopen

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    /// Closed on an evening: it reopens when the user wakes TOMORROW.
    @Test func eveningReopensNextMorning() {
        #expect(R.instant(wakeHour: 7.25, after: date(16, 22), calendar: utc) == date(17, 7, 15))
    }

    /// Awake at 03:00 with a 07:15 wake hour: this morning, not 27 hours out.
    @Test func smallHoursReopenThisMorning() {
        #expect(R.instant(wakeHour: 7.25, after: date(16, 3), calendar: utc) == date(16, 7, 15))
    }

    @Test func nilWakeHourGivesNil() {
        #expect(R.instant(wakeHour: nil, after: date(16, 22), calendar: utc) == nil)
    }

    @Test func reopenMinutesPlanWinsOverConflictingPreference() {
        #expect(R.reopenMinutes(planSleepEndHour: 7.5, persistedWakeMinutes: 6 * 60) == 450)
    }

    @Test func reopenMinutesFallsBackToPreferenceWhenPlanIsNil() {
        #expect(R.reopenMinutes(planSleepEndHour: nil, persistedWakeMinutes: 420) == 420)
    }

    @Test func reopenMinutesNilInBothGivesNil() {
        #expect(R.reopenMinutes(planSleepEndHour: nil, persistedWakeMinutes: nil) == nil)
    }

    @Test func exactMinutesRemainingWithReadingStillAhead() {
        #expect(R.exactMinutesRemaining(lastCall: date(16, 13, 30), now: date(16, 12), clockHourFallback: 999) == 90)
    }

    @Test func exactMinutesRemainingWithReadingBehindClampsToZero() {
        #expect(R.exactMinutesRemaining(lastCall: date(16, 12), now: date(16, 13, 30), clockHourFallback: 999) == 0)
    }

    @Test func exactMinutesRemainingWithNoReadingUsesFallback() {
        #expect(R.exactMinutesRemaining(lastCall: nil, now: date(16, 12), clockHourFallback: 45) == 45)
    }
}

// MARK: - Logged cups and Apple Health

@Suite("Caffeine from Soma and Apple Health")
struct ToolsCaffeineMergeTests {
    @Test("A cup logged in Soma and written to Health counts once")
    func mergeDropsTheEcho() {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let logged = [Dose(mg: 95, time: t0)]
        let health = [Dose(mg: 95, time: t0), Dose(mg: 80, time: t0.addingTimeInterval(3_600))]
        let merged = ToolDay.merged(health: health, logged: logged)
        #expect(merged.map(\.mg) == [95, 80])
    }

    @Test("Two real cups at the same moment both count")
    func mergeKeepsARealSecondCup() {
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let merged = ToolDay.merged(health: [Dose(mg: 95, time: t0), Dose(mg: 95, time: t0)], logged: [Dose(mg: 95, time: t0)])
        #expect(merged.count == 2)
    }

    @Test("Caffeine logged on Pulse reaches the tools")
    @MainActor
    func pulseCupReachesTools() {
        let store = TrackLogStore(url: nil)
        store.addDrink(.water, ml: 500, at: Date())
        store.addDrink(.coffee, ml: 30, caffeineMg: 63, at: Date())
        #expect(store.caffeineCups.map(\.mg) == [63])
    }
}
