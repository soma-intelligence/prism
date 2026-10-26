//
//  ToolsCircadianTests.swift
//  PrismTests
//
//  The circadian engines under SomaTools: circular clock math, chronotype,
//  phase, alignment, the day plan, inputs, trends, social jetlag and the phase
//  alignment readout.
//

import Foundation
import Testing
@testable import Prism

private typealias Night = SomaTools.ChronotypeEstimator.Night

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// A fixed instant used where an engine takes `now` and ignores it.
private let fixedNow = Date(timeIntervalSince1970: 1_787_000_000)

// MARK: - CircadianMath

@Suite("Circadian math")
struct ToolsCircadianMathTests {
    typealias M = SomaTools.CircadianMath

    @Test func wrap24WrapsNegativeAndOverflow() {
        #expect(close(M.wrap24(-1.5), 22.5, 0.0001))
        #expect(close(M.wrap24(25), 1, 0.0001))
        #expect(close(M.wrap24(7), 7, 0.0001))
    }

    @Test func circularMeanAcrossMidnight() throws {
        // 23:00 and 01:00 average to midnight, not noon.
        let mean = try #require(M.circularMeanHours([23, 1]))
        #expect(close(mean, 0, 0.01) || close(mean, 24, 0.01))
    }

    @Test func circularMeanAntipodalIsUndefined() {
        #expect(M.circularMeanHours([0, 12]) == nil)
        #expect(M.circularMeanHours([]) == nil)
    }

    @Test func circularDistanceTakesShortArc() {
        #expect(close(M.circularDistanceHours(23, 1), 2, 0.01))
        #expect(close(M.circularDistanceHours(5, 2.5), 2.5, 0.01))
    }

    @Test func circularStdDevIdenticalHoursIsZero() throws {
        let sd = try #require(M.circularStdDevHours([3, 3, 3, 3]))
        #expect(close(sd, 0, 0.001))
    }

    @Test func circularStdDevWrapsMidnight() throws {
        // 23:00 and 01:00 are 2h apart across midnight, not 22h apart.
        let sd = try #require(M.circularStdDevHours([23, 1]))
        #expect(sd < 1.1)
    }

    @Test func circularStdDevSmallSpreadIsSmall() throws {
        let sd = try #require(M.circularStdDevHours([3.0, 3.5, 2.5, 3.0]))
        #expect(sd < 0.6)
    }

    @Test func circularStdDevEmptyIsNil() {
        #expect(M.circularStdDevHours([]) == nil)
    }

    @Test func circularStdDevAntipodalIsNil() {
        #expect(M.circularStdDevHours([0, 12]) == nil)
    }

    @Test func signedDeltaIsNegativeBeforeAndPositiveAfter() {
        #expect(close(M.signedDeltaHours(from: 4.5, to: 3.0), -1.5, 1e-9))
        #expect(close(M.signedDeltaHours(from: 4.5, to: 6.0), 1.5, 1e-9))
    }

    /// The midnight case: 23:30 is five hours BEFORE 04:30, not nineteen after.
    @Test func signedDeltaCrossesMidnightTheShortWay() {
        #expect(close(M.signedDeltaHours(from: 4.5, to: 23.5), -5.0, 1e-9))
        #expect(close(M.signedDeltaHours(from: 23.5, to: 1.0), 1.5, 1e-9))
    }

    @Test func signedDeltaMagnitudeMatchesUnsignedDistance() {
        for (a, b) in [(4.5, 23.5), (1.0, 22.0), (7.0, 9.5), (0.0, 12.0)] {
            #expect(close(abs(M.signedDeltaHours(from: a, to: b)), M.circularDistanceHours(a, b), 1e-9))
        }
    }
}

// MARK: - Chronotype

@Suite("Chronotype")
struct ToolsChronotypeTests {
    typealias E = SomaTools.ChronotypeEstimator

    @Test func rMEQCategoryBoundaries() {
        // rMEQ total ranges (Adan & Almirall 1991): 4 to 11 evening,
        // 12 to 17 intermediate, 18 to 25 morning.
        #expect(SomaTools.RMEQAnswers(items: [1, 1, 1, 1, 1]).total == 5)
        #expect(SomaTools.RMEQAnswers(items: [1, 1, 1, 1, 1]).category == .evening)
        #expect(SomaTools.RMEQAnswers(items: [3, 3, 2, 2, 2]).category == .intermediate)
        #expect(SomaTools.RMEQAnswers(items: [4, 4, 4, 3, 3]).category == .morning)
    }

    @Test func rMEQIsComplete() {
        #expect(SomaTools.RMEQAnswers(items: [1, 2, 3, 4, 5]).isComplete)
        #expect(!SomaTools.RMEQAnswers(items: [1, 2, 3]).isComplete)
    }

    @Test func midSleepCrossesMidnight() {
        // Onset 23:00, wake 07:00: mid-sleep 03:00.
        #expect(close(E.midSleepHour(bedHour: 23, wakeHour: 7), 3, 0.01))
        // Onset 01:00 (encoded as 25), wake 09:00: mid-sleep 05:00.
        #expect(close(E.midSleepHour(bedHour: 25, wakeHour: 9), 5, 0.01))
    }

    @Test func estimateMSFscSocialJetlagCategory() throws {
        // 5 work nights: bed 23:00, wake 06:00 (dur 7, mid 02:30).
        // 2 free nights: bed 01:00, wake 09:00 (dur 8, mid 05:00).
        var nights: [Night] = []
        for _ in 0..<5 { nights.append(Night(bedHour: 23, wakeHour: 6, isFreeDay: false)) }
        for _ in 0..<2 { nights.append(Night(bedHour: 25, wakeHour: 9, isFreeDay: true)) }

        let c = try #require(E.estimate(nights))
        // SD_f = 8, SD_week = (5*7 + 2*8)/7 = 7.2857; MSF = 5.
        // MSFsc = 5 minus (8 minus 7.2857)/2 = 4.643.
        #expect(close(try #require(c.msfScHours), 4.643, 0.02))
        // SJL = |MSF 5 minus MSW 2.5| = 2.5.
        #expect(close(try #require(c.socialJetlagHours), 2.5, 0.02))
        #expect(c.category == .intermediate)
        #expect(c.source == .behavioral)
    }

    @Test func estimateReturnsNilWithoutEnoughFreeNights() {
        #expect(E.estimate([Night(bedHour: 23, wakeHour: 6, isFreeDay: false)]) == nil)
    }

    @Test func seedCBTminByCategory() {
        #expect(close(E.seedCBTminHours(for: .morning), 3.5, 0.001))
        #expect(close(E.seedCBTminHours(for: .intermediate), 4.5, 0.001))
        #expect(close(E.seedCBTminHours(for: .evening), 5.5, 0.001))
    }

    @Test func estimateNoCorrectionWhenFreeSleepNotLongerThanWeek() throws {
        var nights: [Night] = []
        for _ in 0..<5 { nights.append(Night(bedHour: 23, wakeHour: 6, isFreeDay: false)) } // dur 7, mid 02:30
        for _ in 0..<2 { nights.append(Night(bedHour: 24, wakeHour: 7, isFreeDay: true)) }  // onset 0, dur 7, mid 03:30
        let c = try #require(E.estimate(nights))
        // SD_f = 7, SD_week = 7: no correction, MSFsc == MSF == 3.5.
        #expect(close(try #require(c.msfScHours), 3.5, 0.02))
    }

    @Test func estimateNilSocialJetlagWhenNoWorkNights() throws {
        // Only free-day nights logged: social jetlag is unknown (nil), not zero.
        let nights = [Night(bedHour: 24, wakeHour: 8, isFreeDay: true),
                      Night(bedHour: 24, wakeHour: 8, isFreeDay: true)]
        let c = try #require(E.estimate(nights))
        #expect(c.socialJetlagHours == nil)
    }

    /// MSFsc is a wrapped clock hour, so a mid-sleep before midnight cannot be
    /// categorised with linear `<` and `>`. A 20:00 to 03:00 sleeper has MSFsc
    /// 23.5 and is an extreme MORNING type.
    @Test func categoryBeforeMidnightIsMorningNotEvening() {
        #expect(E.category(forMSFsc: 23.5) == .morning)
        #expect(E.category(forMSFsc: 22.0) == .morning)
        #expect(E.category(forMSFsc: 0.5) == .morning)
    }

    @Test func categoryMatchesBandsInsideTheNormalRange() {
        #expect(E.category(forMSFsc: 3.0) == .morning)
        #expect(E.category(forMSFsc: 3.6) == .intermediate)
        #expect(E.category(forMSFsc: 4.5) == .intermediate)
        #expect(E.category(forMSFsc: 5.4) == .intermediate)
        #expect(E.category(forMSFsc: 6.0) == .evening)
    }

    @Test func earlySleeperIsNotClassifiedAsEveningType() throws {
        // Bed 20:00, wake 03:00 on free days: mid-sleep 23:30.
        let nights = (0..<4).map { _ in Night(bedHour: 20, wakeHour: 3, isFreeDay: true) }
        let c = try #require(E.estimate(nights))
        #expect(close(c.msfScHours ?? -1, 23.5, 0.01))
        #expect(c.category == .morning)
    }
}

// MARK: - Phase provider

@Suite("Circadian phase provider")
struct ToolsCircadianPhaseProviderTests {
    typealias P = SomaTools.CircadianPhaseProvider

    private func nights(count: Int) -> [Night] {
        // ~5:2 work:free split so both arms are populated.
        (0..<count).map { i in
            (i % 7) >= 5 ? Night(bedHour: 25, wakeHour: 9, isFreeDay: true)
                         : Night(bedHour: 23, wakeHour: 6, isFreeDay: false)
        }
    }

    @Test func seededFromRMEQWhenNoSleep() throws {
        let rmeq = SomaTools.RMEQAnswers(items: [1, 1, 1, 1, 1]) // total 5, evening
        let phase = try #require(P.resolve(rMEQ: rmeq, nights: [], now: fixedNow))
        #expect(phase.confidence == .seeded)
        #expect(close(phase.cbtMinHours, 5.5, 0.001))
        #expect(close(phase.dlmoHours, SomaTools.CircadianMath.wrap24(5.5 - 7), 0.01)) // 22.5
        #expect(phase.chronotype.source == .rMEQ)
    }

    @Test func behavioralOverridesSeed() throws {
        let phase = try #require(P.resolve(rMEQ: SomaTools.RMEQAnswers(items: [1, 1, 1, 1, 1]),
                                           nights: nights(count: 14), now: fixedNow))
        #expect(phase.chronotype.source == .behavioral)
        #expect(phase.confidence == .medium)
        #expect(close(phase.cbtMinHours, try #require(phase.chronotype.msfScHours), 0.001))
    }

    @Test func lowConfidenceWithFewNights() {
        #expect(P.resolve(rMEQ: nil, nights: nights(count: 7), now: fixedNow)?.confidence == .low)
    }

    @Test func nilWhenNothingAvailable() {
        #expect(P.resolve(rMEQ: nil, nights: [], now: fixedNow) == nil)
    }
}

// MARK: - Alignment

@Suite("Circadian alignment")
struct ToolsCircadianAlignmentTests {
    typealias A = SomaTools.CircadianAlignment

    private func phase(sjl: Double?, msf: Double? = 4.5) -> SomaTools.CircadianPhase {
        SomaTools.CircadianPhase(
            cbtMinHours: 4.5, dlmoHours: SomaTools.CircadianMath.wrap24(4.5 - 7),
            chronotype: SomaTools.Chronotype(category: .intermediate, msfScHours: msf,
                                             socialJetlagHours: sjl, source: .behavioral),
            confidence: .medium)
    }

    private func night(bed: Double, wake: Double, free: Bool) -> Night {
        Night(bedHour: bed, wakeHour: wake, isFreeDay: free)
    }

    @Test func perfectRegularityAndDurationScoresHigh() throws {
        let nights = (0..<7).map { _ in night(bed: 23, wake: 7, free: false) }
        let a = try #require(A.resolve(nights: nights, phase: phase(sjl: 0), sleepNeedHours: 8))
        #expect(a.score >= 90)
        #expect(a.regularity?.score == 100)
        #expect(a.duration?.score == 100)
    }

    @Test func weekdayOnlyUserStillScores() throws {
        let nights = (0..<5).map { _ in night(bed: 23.5, wake: 7, free: false) }
        let a = try #require(A.resolve(nights: nights, phase: phase(sjl: nil, msf: nil), sleepNeedHours: 8))
        #expect(a.regularity != nil)
        #expect(a.duration != nil)
    }

    @Test func fewerThanThreeNightsAndNoTimingIsNil() {
        let nights = [night(bed: 23, wake: 7, free: false), night(bed: 24, wake: 7, free: false)]
        #expect(A.resolve(nights: nights, phase: phase(sjl: nil, msf: nil), sleepNeedHours: 8) == nil)
    }

    @Test func timingZeroSocialJetlagIs100FourHoursIs0() throws {
        let nights = (0..<7).map { _ in night(bed: 23, wake: 7, free: false) }
        let good = try #require(A.resolve(nights: nights, phase: phase(sjl: 0), sleepNeedHours: 8))
        let bad = try #require(A.resolve(nights: nights, phase: phase(sjl: 4), sleepNeedHours: 8))
        #expect(good.timing?.score == 100)
        #expect(bad.timing?.score == 0)
    }

    @Test func missingTimingRenormalisesOverAvailableFactors() throws {
        let nights = (0..<5).map { _ in night(bed: 23, wake: 7, free: false) }
        let a = try #require(A.resolve(nights: nights, phase: phase(sjl: nil, msf: nil), sleepNeedHours: 8))
        #expect(a.timing == nil)
        #expect(a.score == 100)
    }

    /// A free-days-only sleeper has no social jetlag, and timing must then be
    /// ABSENT rather than scored 100 by construction.
    @Test func timingIsAbsentForFreeDaysOnlySleeper() throws {
        let nights = (0..<5).map { _ in night(bed: 23, wake: 7, free: true) }
        let a = try #require(A.resolve(nights: nights, phase: phase(sjl: nil, msf: 3.0), sleepNeedHours: 8))
        #expect(a.timing == nil)
    }

    @Test func resolvesWithoutAnyPhase() throws {
        let nights = (0..<5).map { _ in night(bed: 23, wake: 7, free: false) }
        let a = try #require(A.resolve(nights: nights, phase: nil, sleepNeedHours: 8))
        #expect(a.regularity != nil)
        #expect(a.duration != nil)
        #expect(a.timing == nil)
        #expect(a.confidence == .low)
    }

    @Test func confidenceTracksNightCount() {
        let few = (0..<5).map { _ in night(bed: 23, wake: 7, free: false) }
        let many = (0..<14).map { _ in night(bed: 23, wake: 7, free: false) }
        #expect(A.resolve(nights: few, phase: phase(sjl: 0), sleepNeedHours: 8)?.confidence == .low)
        #expect(A.resolve(nights: many, phase: phase(sjl: 0), sleepNeedHours: 8)?.confidence == .medium)
    }
}

// MARK: - Format

@Suite("Circadian format")
struct ToolsCircadianFormatTests {
    /// The hour cycle is the region's, so the expectation is rendered through
    /// the same style from KNOWN components. That pins the decimal to clock
    /// arithmetic exactly and leaves the region alone.
    private func rendered(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(
            year: 2001, month: 1, day: 1, hour: hour, minute: minute))!
        return date.formatted(Date.FormatStyle()
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits))
    }

    @Test func clockLabelFormatsDecimalHours() {
        #expect(SomaTools.CircadianFormat.clockLabel(22.25) == rendered(hour: 22, minute: 15))
        #expect(SomaTools.CircadianFormat.clockLabel(6.5) == rendered(hour: 6, minute: 30))
        // Rounds a 59.9-minute fraction up and carries the hour, wrapping 24 to 0.
        #expect(SomaTools.CircadianFormat.clockLabel(23.999) == rendered(hour: 0, minute: 0))
        #expect(SomaTools.CircadianFormat.clockLabel(23.999) != rendered(hour: 23, minute: 59))
    }

    @Test func durationLabelIsCompact() {
        #expect(SomaTools.CircadianFormat.durationLabel(2.0) == "2h")
        #expect(SomaTools.CircadianFormat.durationLabel(1.4) == "1h24")
        // 59.6 minutes rounds to a whole hour, no "0h60".
        #expect(SomaTools.CircadianFormat.durationLabel(0.994) == "1h")
    }
}

// MARK: - Inputs

@Suite("Circadian inputs")
struct ToolsCircadianInputsTests {
    typealias I = SomaTools.CircadianInputs

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func nightsFlagWeekendsAsFree() throws {
        // 2023-01-01 is a Sunday. Three days oldest first: Fri, Sat, Sun.
        let nights = I.nights(bedHours: [23, 24, 25], wakeHours: [7, 8, 9],
                              today: day(2023, 1, 1), calendar: utc)
        try #require(nights.count == 3)
        #expect(!nights[0].isFreeDay)
        #expect(nights[1].isFreeDay)
        #expect(nights[2].isFreeDay)
        #expect(close(nights[2].bedHour, 25, 0.001))
        #expect(close(nights[2].wakeHour, 9, 0.001))
    }

    @Test func nightsSkipNilEntries() {
        let nights = I.nights(bedHours: [nil, 23, nil, 24], wakeHours: [7, 7, 7, 8],
                              today: day(2023, 1, 1), calendar: utc)
        #expect(nights.count == 2)
    }

    @Test func habitualHoursCircularMeanAndEmpty() throws {
        let nights = [Night(bedHour: 23, wakeHour: 7, isFreeDay: false),
                      Night(bedHour: 25, wakeHour: 9, isFreeDay: true)]
        #expect(close(try #require(I.habitualWakeHour(nights)), 8, 0.1))
        let sleep = try #require(I.habitualSleepHour(nights))
        #expect(close(sleep, 0, 0.2) || close(sleep, 24, 0.2))
        #expect(I.habitualWakeHour([]) == nil)
        #expect(I.habitualSleepHour([]) == nil)
    }

    @Test func nightsCapToMaxDaysKeepingRecentTail() throws {
        let n = 60
        let beds: [Double?] = Array(repeating: 23, count: n)
        var wakes: [Double?] = Array(repeating: 7, count: n)
        wakes[n - 1] = 9
        let nights = I.nights(bedHours: beds, wakeHours: wakes, today: day(2023, 1, 1), calendar: utc)
        #expect(nights.count == I.maxDays)
        #expect(close(try #require(nights.last).wakeHour, 9, 0.001))
    }

    private let twoPatternBeds: [Double?] = Array(repeating: 22, count: 5) + Array(repeating: 24, count: 5)
    private let twoPatternWakes: [Double?] = Array(repeating: 6, count: 5) + Array(repeating: 10, count: 5)

    /// Two windows, several nights apart, over a series whose pattern differs,
    /// must disagree: slicing, not relabelling.
    @Test func seriesEndDaySlicesToTheRequestedDay() throws {
        let day10 = day(2023, 3, 10)
        let at5 = I.nights(bedHours: twoPatternBeds, wakeHours: twoPatternWakes,
                           today: day(2023, 3, 5), seriesEndDay: day10, calendar: utc)
        let at10 = I.nights(bedHours: twoPatternBeds, wakeHours: twoPatternWakes,
                            today: day10, seriesEndDay: day10, calendar: utc)
        #expect(at5.count == 5)
        #expect(at10.count == 10)
        let wake5 = try #require(I.habitualWakeHour(at5))
        #expect(close(wake5, 6, 0.01))
        #expect(wake5 != (try #require(I.habitualWakeHour(at10))))
    }

    @Test func seriesEndDayBeforeWindowStartReturnsEmpty() {
        let beds: [Double?] = Array(repeating: 23, count: 10)
        let wakes: [Double?] = Array(repeating: 7, count: 10)
        let nights = I.nights(bedHours: beds, wakeHours: wakes,
                              today: day(2023, 2, 18), seriesEndDay: day(2023, 3, 10), calendar: utc)
        #expect(nights.isEmpty)
    }

    @Test func seriesEndDayAfterWindowEndFallsBackToTheFullWindow() {
        let future = day(2023, 3, 14)
        let sliced = I.nights(bedHours: twoPatternBeds, wakeHours: twoPatternWakes,
                              today: future, seriesEndDay: day(2023, 3, 10), calendar: utc)
        let unsliced = I.nights(bedHours: twoPatternBeds, wakeHours: twoPatternWakes,
                                today: future, calendar: utc)
        #expect(sliced == unsliced)
    }

    @Test func seriesEndDayEqualToTodayMatchesTheUnslicedCall() {
        let day10 = day(2023, 3, 10)
        let sliced = I.nights(bedHours: twoPatternBeds, wakeHours: twoPatternWakes,
                              today: day10, seriesEndDay: day10, calendar: utc)
        let original = I.nights(bedHours: twoPatternBeds, wakeHours: twoPatternWakes,
                                today: day10, calendar: utc)
        #expect(sliced == original)
    }

    @Test func seriesEndDayThinWindowDegradesToFewerNights() {
        let beds: [Double?] = Array(repeating: 23, count: 10)
        let wakes: [Double?] = Array(repeating: 7, count: 10)
        let nights = I.nights(bedHours: beds, wakeHours: wakes,
                              today: day(2023, 3, 2), seriesEndDay: day(2023, 3, 10), calendar: utc)
        #expect(nights.count == 2)
    }
}

// MARK: - Plan

@Suite("Circadian plan")
struct ToolsCircadianPlanTests {
    typealias Planner = SomaTools.CircadianPlanner
    typealias Kind = SomaTools.CircadianWindow.Kind

    private func phase(sjl: Double?) -> SomaTools.CircadianPhase {
        SomaTools.CircadianPhase(
            cbtMinHours: 4.5, dlmoHours: SomaTools.CircadianMath.wrap24(4.5 - 7),
            chronotype: SomaTools.Chronotype(category: .intermediate, msfScHours: 4.5,
                                             socialJetlagHours: sjl, source: .behavioral),
            confidence: .medium)
    }

    private func phase(cbt: Double, category: SomaTools.ChronotypeCategory,
                       msf: Double, sjl: Double) -> SomaTools.CircadianPhase {
        SomaTools.CircadianPhase(
            cbtMinHours: cbt, dlmoHours: SomaTools.CircadianMath.wrap24(cbt - 7),
            chronotype: SomaTools.Chronotype(category: category, msfScHours: msf,
                                             socialJetlagHours: sjl, source: .behavioral),
            confidence: .medium)
    }

    private func window(_ plan: SomaTools.CircadianPlan, _ kind: Kind) throws -> SomaTools.CircadianWindow {
        try #require(plan.windows.first { $0.kind == kind })
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: hour, minute: minute))!
    }

    private var standard: SomaTools.CircadianPlan {
        Planner.plan(phase: phase(sjl: 1.0), habitualWakeHour: 7, habitualSleepHour: 23,
                     typicalDoseMg: nil, now: fixedNow)
    }

    @Test func windowsIntermediateProfile() throws {
        let plan = Planner.plan(phase: phase(sjl: 2.0), habitualWakeHour: 7, habitualSleepHour: 23,
                                typicalDoseMg: nil, now: fixedNow)
        #expect(plan.windows.count == 6)
        // lightSeek: max(wake, CBTmin) to +2.5. CBTmin 4.5 < wake 7, so it anchors to wake.
        #expect(close(try window(plan, .lightSeek).startHour, 7, 0.01))
        #expect(close(try window(plan, .lightSeek).endHour, 9.5, 0.01))
        // lightAvoid: DLMO to sleep. DLMO = wrap24(4.5 minus 7) = 21.5.
        #expect(close(try window(plan, .lightAvoid).startHour, 21.5, 0.01))
        #expect(close(try window(plan, .lightAvoid).endHour, 23, 0.01))
        // caffeineCutoff with no dose: the standard 100 mg cup, 23 minus 10 = 13.
        #expect(close(try window(plan, .caffeineCutoff).startHour, 13, 0.01))
        // exercise: CBTmin+12 to CBTmin+14 = 16.5 to 18.5.
        #expect(close(try window(plan, .exercise).startHour, 16.5, 0.01))
        #expect(close(try window(plan, .exercise).endHour, 18.5, 0.01))
        #expect(close(try window(plan, .windDown).startHour, 22.25, 0.01))
        #expect(close(try window(plan, .sleep).startHour, 23, 0.01))
        #expect(close(try window(plan, .sleep).endHour, 7, 0.01))
    }

    @Test func exerciseShiftsWithChronotype() throws {
        // Morning type: CBTmin 3.5, exercise 15.5 to 17.5.
        let plan = Planner.plan(phase: phase(cbt: 3.5, category: .morning, msf: 2.5, sjl: 0.5),
                                habitualWakeHour: 6, habitualSleepHour: 22,
                                typicalDoseMg: nil, now: fixedNow)
        #expect(close(try window(plan, .exercise).startHour, 15.5, 0.01))
        #expect(close(try window(plan, .exercise).endHour, 17.5, 0.01))
    }

    @Test func lateExerciseGuardHoldsForNightOwl() throws {
        // Evening type, sleep 02:00. exEnd = min(CBTmin+14, sleep minus 2) = min(19.5, 24).
        let plan = Planner.plan(phase: phase(cbt: 5.5, category: .evening, msf: 6.5, sjl: 1.0),
                                habitualWakeHour: 9, habitualSleepHour: 2,
                                typicalDoseMg: nil, now: fixedNow)
        let end = try window(plan, .exercise).endHour
        #expect((end <= 9 ? end + 24 : end) <= 24.0)
    }

    @Test func caffeineCutoffMovesEarlierWithLargeDose() throws {
        // 200 mg: cutoff = 23 minus 5*log2(200/25) = 23 minus 15 = 8.
        let plan = Planner.plan(phase: phase(sjl: 1.0), habitualWakeHour: 7, habitualSleepHour: 23,
                                typicalDoseMg: 200, now: fixedNow)
        #expect(close(try window(plan, .caffeineCutoff).startHour, 8, 0.01))
    }

    @Test func callerCutoffWinsOverTheSingleServingFallback() throws {
        let plan = Planner.plan(phase: phase(sjl: 1.0), habitualWakeHour: 7, habitualSleepHour: 23,
                                typicalDoseMg: nil, caffeineCutoffHour: 11.5, now: fixedNow)
        #expect(close(try window(plan, .caffeineCutoff).startHour, 11.5, 1e-9))
    }

    @Test func exerciseNeverWithinTwoHoursOfSleep() throws {
        let plan = Planner.plan(phase: phase(sjl: nil), habitualWakeHour: 6, habitualSleepHour: 19,
                                typicalDoseMg: nil, now: fixedNow)
        #expect(try window(plan, .exercise).endHour <= 17)
    }

    @Test func alignmentScoreFromSocialJetlag() {
        func score(_ sjl: Double?) -> Int? {
            Planner.plan(phase: phase(sjl: sjl), habitualWakeHour: 7, habitualSleepHour: 23,
                         typicalDoseMg: nil, now: fixedNow).alignmentScore
        }
        #expect(score(0) == 100)
        #expect(score(2) == 50)
        #expect(score(nil) == nil)
        #expect(score(5) == 0)
    }

    @Test func exerciseStaysDaytimeForNightOwlWrappedSleep() throws {
        // Wakes 09:00, sleeps 01:00 passed as the wrapped clock hour 1.
        let plan = Planner.plan(phase: phase(sjl: nil), habitualWakeHour: 9, habitualSleepHour: 1,
                                typicalDoseMg: nil, now: fixedNow)
        #expect(close(try window(plan, .exercise).startHour, 16.5, 0.01))
        #expect(close(try window(plan, .exercise).endHour, 18.5, 0.01))
    }

    @Test func lightSeekNeverInvertsForALateRiser() throws {
        // CBTmin 1.0 with wake 9.0: the advance zone (CBTmin + 6 = 7.0) is over
        // by the time this user wakes, so the window stays forward-going.
        let plan = Planner.plan(phase: phase(cbt: 1.0, category: .morning, msf: 1.0, sjl: 0.5),
                                habitualWakeHour: 9, habitualSleepHour: 23,
                                typicalDoseMg: nil, now: fixedNow)
        #expect(close(try window(plan, .lightSeek).startHour, 9, 0.01))
        #expect(close(try window(plan, .lightSeek).endHour, 9.5, 0.01))
    }

    @Test func momentReportsNextWindowAndHoursUntil() throws {
        // 15:00: the next actionable point is the 16.5 exercise start, 1.5h away.
        let next = try #require(standard.moment(at: at(15), calendar: utc).next)
        #expect(next.window.kind == .exercise)
        #expect(close(next.hoursUntil, 1.5, 0.05))
    }

    @Test func momentCurrentWindowWhenInsideSleep() {
        #expect(standard.moment(at: at(2), calendar: utc).current?.kind == .sleep)
    }

    @Test func momentNextWrapsPastMidnight() throws {
        let next = try #require(standard.moment(at: at(23, 30), calendar: utc).next)
        #expect(next.hoursUntil > 0)
    }

    @Test func momentPrefersTheNarrowestContainingWindow() {
        // Wind down (22.25 to 23) nests inside dim light (21.5 to 23).
        #expect(standard.moment(at: at(22, 30), calendar: utc).current?.kind == .windDown)
    }

    // A weekday-only sleeper gets a phase only from the questionnaire, and the
    // answer moves the dim-light window.

    private let weekdayNights: [Night] = (0..<10).map { _ in
        Night(bedHour: 23, wakeHour: 7, isFreeDay: false)
    }

    private func dimLightStart(answers: SomaTools.RMEQAnswers?) -> Double? {
        guard let phase = SomaTools.CircadianPhaseProvider.resolve(rMEQ: answers,
                                                                   nights: weekdayNights, now: fixedNow),
              let wake = SomaTools.CircadianInputs.habitualWakeHour(weekdayNights),
              let sleep = SomaTools.CircadianInputs.habitualSleepHour(weekdayNights) else { return nil }
        let plan = Planner.plan(phase: phase, habitualWakeHour: wake, habitualSleepHour: sleep,
                                typicalDoseMg: nil, now: fixedNow)
        #expect(plan.alignmentScore == nil, "an rMEQ-only seed knows no social jetlag")
        return plan.windows.first { $0.kind == .lightAvoid }?.startHour
    }

    @Test func noFreeNightsAndNoAnswerMeansNoPlan() {
        #expect(dimLightStart(answers: nil) == nil)
    }

    @Test func theQuestionnaireAnswerMovesTheWindows() throws {
        // Evening seed: CBTmin 5.5, DLMO 22.5. Morning seed: CBTmin 3.5, DLMO 20.5.
        let evening = try #require(dimLightStart(answers: SomaTools.RMEQAnswers(items: [1, 1, 1, 1, 0])))
        let morning = try #require(dimLightStart(answers: SomaTools.RMEQAnswers(items: [5, 4, 5, 5, 6])))
        #expect(close(evening, 22.5, 0.001))
        #expect(close(morning, 20.5, 0.001))
    }
}

// MARK: - Trends

@Suite("Circadian trends")
struct ToolsCircadianTrendsTests {
    typealias T = SomaTools.CircadianTrends

    /// 2026-01-03 is a Saturday.
    private let anchor = utc.date(from: DateComponents(year: 2026, month: 1, day: 3))!

    /// 56 days: weekdays bed 23 / wake 7 (mid-sleep 3), weekends bed 25 /
    /// wake 9 (mid-sleep 5), so roughly 2h of social jetlag.
    private func weekendDelayed() -> (bed: [Double?], wake: [Double?]) {
        var bed: [Double?] = []
        var wake: [Double?] = []
        let start = utc.date(byAdding: .day, value: -55, to: anchor)!
        for i in 0..<56 {
            let day = utc.date(byAdding: .day, value: i, to: start)!
            let wd = utc.component(.weekday, from: day)
            let free = wd == 1 || wd == 7
            bed.append(free ? 25 : 23)
            wake.append(free ? 9 : 7)
        }
        return (bed, wake)
    }

    @Test func emptySeriesIsAllNilOfWeeksLength() {
        let out = T.socialJetlagSeries(bedHours: [], wakeHours: [], endingOn: anchor, weeks: 12, calendar: utc)
        #expect(out.count == 12)
        #expect(out.allSatisfy { $0 == nil })
    }

    @Test func weekendDelayProducesStableNonNilJetlag() {
        let s = weekendDelayed()
        let out = T.socialJetlagSeries(bedHours: s.bed, wakeHours: s.wake, endingOn: anchor,
                                       weeks: 6, windowNights: 28, calendar: utc)
        #expect(out.count == 6)
        let present = out.compactMap { $0 }
        #expect(!present.isEmpty)
        for v in present { #expect(close(v, 2.0, 0.5)) }
    }

    @Test func tooFewFreeDaysYieldsAllNil() {
        let out = T.socialJetlagSeries(bedHours: [23, 23, 23], wakeHours: [7, 7, 7],
                                       endingOn: anchor, weeks: 4, calendar: utc)
        #expect(out.count == 4)
        #expect(out.allSatisfy { $0 == nil })
    }

    @Test func dailySeriesIsOldestFirstAndTracksWeekendDelay() throws {
        let s = weekendDelayed()
        let out = T.socialJetlagDailySeries(bedHours: s.bed, wakeHours: s.wake, endingOn: anchor,
                                            days: 40, windowNights: 28, calendar: utc)
        #expect(out.count == 40)
        let last = try #require(out.last ?? nil)
        #expect(close(last, 2.0, 0.5))
    }

    @Test func healthyUpperEdgeIsTwoHours() {
        #expect(T.healthyUpperHours == 2.0)
    }
}

// MARK: - Social jetlag

@Suite("Social jetlag")
struct ToolsSocialJetlagTests {
    typealias S = SomaTools.SocialJetlag

    @Test func bandCutsAtOneAndTwoHours() {
        #expect(S.band(hours: 0.5) == .aligned)
        #expect(S.band(hours: 1.0) == .drifting)
        #expect(S.band(hours: 1.99) == .drifting)
        #expect(S.band(hours: 2.0) == .outOfRange)
        // A magnitude: the sign never changes the verdict.
        #expect(S.band(hours: -2.5) == .outOfRange)
    }

    @Test func outOfRangeGateMatchesTheHealthyEdge() {
        #expect(!S.isOutOfRange(hours: nil))
        #expect(!S.isOutOfRange(hours: 1.9))
        #expect(S.isOutOfRange(hours: 2.0))
    }

    @Test func comparisonMatchesTheEstimatorsSocialJetlag() throws {
        var nights: [Night] = []
        for _ in 0..<5 { nights.append(Night(bedHour: 23, wakeHour: 6, isFreeDay: false)) } // mid 02:30
        for _ in 0..<2 { nights.append(Night(bedHour: 25, wakeHour: 9, isFreeDay: true)) }  // mid 05:00
        let c = try #require(S.compare(nights))
        #expect(close(c.workdayMidSleepHour, 2.5, 0.01))
        #expect(close(c.freeDayMidSleepHour, 5.0, 0.01))
        #expect(close(c.signedGapHours, 2.5, 0.01))
        #expect(c.band == .outOfRange)
        let sjl = try #require(SomaTools.ChronotypeEstimator.estimate(nights)?.socialJetlagHours)
        #expect(close(c.gapHours, sjl, 1e-9))
    }

    @Test func comparisonNeedsBothSides() {
        let freeOnly = [Night(bedHour: 24, wakeHour: 8, isFreeDay: true),
                        Night(bedHour: 24, wakeHour: 8, isFreeDay: true)]
        #expect(S.compare(freeOnly) == nil)
        let oneFree = [Night(bedHour: 24, wakeHour: 8, isFreeDay: true),
                       Night(bedHour: 23, wakeHour: 7, isFreeDay: false)]
        #expect(S.compare(oneFree) == nil)
    }

    @Test func baselineWaitsForFourteenPriorDaysAndSkipsToday() throws {
        let thirteen: [Double?] = Array(repeating: 1.0, count: 13) + [5.0]
        #expect(S.personalBaseline(thirteen) == nil)
        #expect(S.resolvedPriorDays(thirteen) == 13)

        let series: [Double?] = [nil] + Array(repeating: -1.0, count: 7) + Array(repeating: 2.0, count: 7) + [9.0]
        let baseline = try #require(S.personalBaseline(series))
        // Magnitudes, today excluded: (7 * 1 + 7 * 2) / 14 = 1.5.
        #expect(close(baseline, 1.5, 1e-9))
    }

    @Test func trendNeedsOneResolvedDay() {
        #expect(!S.hasTrend([nil, nil]))
        #expect(S.hasTrend([nil, 1.2]))
    }
}

// MARK: - Phase alignment readout

@Suite("Circadian phase alignment")
struct ToolsCircadianPhaseAlignmentTests {
    typealias PA = SomaTools.CircadianPhaseAlignment

    private let windows: [SomaTools.CircadianWindow] = [
        .init(kind: .lightSeek, startHour: 7.0, endHour: 9.0),
        .init(kind: .lightAvoid, startHour: 21.0, endHour: 23.0),
        .init(kind: .caffeineCutoff, startHour: 15.5, endHour: 15.5),
        .init(kind: .exercise, startHour: 16.5, endHour: 18.5),
        .init(kind: .windDown, startHour: 22.0, endHour: 23.0),
        .init(kind: .sleep, startHour: 23.0, endHour: 7.0),
    ]

    @Test func nextWindowIsTheSoonestStrictlyAhead() throws {
        let next = try #require(PA.nextWindow(after: 15.0, in: windows))
        #expect(next.kind == .caffeineCutoff)
        #expect(close(next.hoursUntil, 0.5, 1e-9))
    }

    @Test func aStartExactlyNowReadsAsAFullDayOut() throws {
        let next = try #require(PA.nextWindow(after: 23.5, in: windows))
        #expect(next.kind == .lightSeek)
        #expect(close(next.hoursUntil, 7.5, 1e-9))
        let onlyOne = [SomaTools.CircadianWindow(kind: .sleep, startHour: 23, endHour: 7)]
        #expect(close(try #require(PA.nextWindow(after: 23, in: onlyOne)).hoursUntil, 24, 1e-9))
        #expect(PA.nextWindow(after: 1, in: []) == nil)
    }

    @Test func decimalHourReadsTheClock() {
        let date = utc.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 14, minute: 30))!
        #expect(close(PA.decimalHour(date, calendar: utc), 14.5, 1e-9))
    }

    @Test func spanWrapsPastMidnight() {
        #expect(close(PA.spanHours(startHour: 22, endHour: 1), 3, 1e-9))
        #expect(close(PA.spanHours(startHour: 7, endHour: 9), 2, 1e-9))
        #expect(PA.spanHours(startHour: 15.5, endHour: 15.5) == 0)
    }

    @Test func bandsCutAtFiftyFiveAndEighty() {
        #expect(PA.band(score: 80) == .aligned)
        #expect(PA.band(score: 79) == .drift)
        #expect(PA.band(score: 55) == .drift)
        #expect(PA.band(score: 54) == .misaligned)
        #expect(PA.shouldAlert(score: 54))
        #expect(!PA.shouldAlert(score: 55))
        #expect(!PA.shouldAlert(score: nil))
    }

    @Test func trendMapsThroughThePlannersFormulaAndKeepsGaps() throws {
        let trend = PA.trend(fromSocialJetlag: [nil, 0, 2, 5])
        #expect(trend.count == 4)
        #expect(trend[0] == nil)
        #expect(trend[1] == 100)
        #expect(trend[2] == 50)
        #expect(trend[3] == 0)
        #expect(!PA.hasTrend([nil, 80, 90]))
        #expect(PA.hasTrend([80, 90, 70]))
        #expect(close(try #require(PA.baselineAverage([nil, 80, 90, 70])), 80, 1e-9))
        #expect(PA.baselineAverage([nil]) == nil)
    }
}
