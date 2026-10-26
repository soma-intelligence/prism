//
//  ToolsTravelShiftTests.swift
//  PrismTests
//
//  Jet lag, the travel action day, shiftwork and trips under SomaTools.
//

import Foundation
import Testing
@testable import Prism

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

// MARK: - JetLagModel

/// Expected values are derived from the documented constants (advanceRate 1.0,
/// delayRate 1.5, antidromicZones 8, daylightFullBoostMin 120, melatoninZones 5)
/// rather than hard-coded.
@Suite("Jet lag model")
struct ToolsJetLagModelTests {
    typealias J = SomaTools.JetLagModel

    @Test func zonesRoundToNearestInt() {
        #expect(J.zones(shiftHours: 2.6) == 3)
        #expect(J.zones(shiftHours: 0.4) == 0)
        #expect(J.zones(shiftHours: -8) == 8)
    }

    @Test func isEastIsTheSignOfTheShift() {
        #expect(J.isEast(shiftHours: 3))
        #expect(!J.isEast(shiftHours: -3))
    }

    @Test func recoveryDaysEastwardNoDaylight() {
        #expect(J.recoveryDays(zones: 3, east: true, daylightMin: 0) == 3)
    }

    @Test func recoveryDaysWestwardNoDaylight() {
        #expect(J.recoveryDays(zones: 3, east: false, daylightMin: 0) == 2)
    }

    @Test func westwardIsFasterThanEastward() {
        let east = J.recoveryDays(zones: 6, east: true, daylightMin: 0)
        let west = J.recoveryDays(zones: 6, east: false, daylightMin: 0)
        #expect(east == 6)
        #expect(west == 4)
        #expect(west < east)
    }

    @Test func fullDaylightRoughlyHalves() {
        let noBoost = J.recoveryDays(zones: 8, east: false, daylightMin: 0)
        #expect(noBoost == 6)
        let fullBoost = J.recoveryDays(zones: 8, east: false, daylightMin: J.daylightFullBoostMin)
        #expect(fullBoost == 3)
        #expect(fullBoost == noBoost / 2)
    }

    @Test func daylightBoostIsCappedAt2x() {
        let atCap = J.recoveryDays(zones: 6, east: false, daylightMin: J.daylightFullBoostMin)
        let beyondCap = J.recoveryDays(zones: 6, east: false, daylightMin: J.daylightFullBoostMin * 10)
        #expect(atCap == beyondCap)
    }

    @Test func antidromicCorrectionForLargeEastward() {
        let zones = 11
        let directDays = Int((Double(zones) / J.advanceRate).rounded(.up))
        #expect(directDays == 11)
        let longWayDays = Int((Double(24 - zones) / J.delayRate).rounded(.up))
        #expect(longWayDays == 9)
        #expect(J.recoveryDays(zones: zones, east: true, daylightMin: 0) == min(directDays, longWayDays))
    }

    @Test func noAntidromicBelowThreshold() {
        #expect(J.recoveryDays(zones: J.antidromicZones - 1, east: true, daylightMin: 0) == 7)
    }

    @Test func recoveryDaysFloorIsOne() {
        #expect(J.recoveryDays(zones: 1, east: false, daylightMin: J.daylightFullBoostMin) == 1)
        #expect(J.recoveryDays(zones: 0, east: true, daylightMin: 0) == 0)
    }

    @Test func stateNilWhenNoZonesCrossed() {
        #expect(J.state(shiftHours: 0.3, daysSinceArrival: 1, daylightMin: 0) == nil)
    }

    @Test func stateAtArrival() throws {
        let state = try #require(J.state(shiftHours: 3, daysSinceArrival: 0, daylightMin: 0))
        #expect(state.zones == 3)
        #expect(state.recoveryPct == 0)
        #expect(close(state.residualMisalignmentH, 3, 1e-9))
        #expect(state.active)
        #expect(state.dayNumber == 1)
        #expect(state.daysLeft == 3)
    }

    @Test func statePartwayThroughRecovery() throws {
        #expect(J.recoveryDays(zones: 4, east: true, daylightMin: 0) == 4)
        let state = try #require(J.state(shiftHours: 4, daysSinceArrival: 2, daylightMin: 0))
        #expect(state.recoveryPct == 50)
        #expect(close(state.residualMisalignmentH, 2, 1e-9))
        #expect(state.active)
        #expect(state.residualWholeHours == 2)
        #expect(state.bodyClockIsBehind)
    }

    @Test func stateFullyRecovered() throws {
        let days = J.recoveryDays(zones: 4, east: true, daylightMin: 0)
        let atEnd = try #require(J.state(shiftHours: 4, daysSinceArrival: days, daylightMin: 0))
        #expect(atEnd.recoveryPct == 100)
        #expect(close(atEnd.residualMisalignmentH, 0, 1e-9))
        #expect(!atEnd.active)
        #expect(atEnd.daysLeft == 0)
        let beyond = try #require(J.state(shiftHours: 4, daysSinceArrival: days + 10, daylightMin: 0))
        #expect(beyond.recoveryPct == 100)
        #expect(!beyond.active)
    }

    @Test func melatoninThreshold() {
        let below = J.state(shiftHours: Double(J.melatoninZones - 1), daysSinceArrival: 0, daylightMin: 0)
        #expect(below?.melatoninSuggested == false)
        let atThreshold = J.state(shiftHours: Double(J.melatoninZones), daysSinceArrival: 0, daylightMin: 0)
        #expect(atThreshold?.melatoninSuggested == true)
    }

    @Test func directionAndLightGuidance() {
        let east = J.state(shiftHours: 3, daysSinceArrival: 0, daylightMin: 0)
        #expect(east?.direction == .advance)
        #expect(east?.lightGuidance.seekMorningLight == true)
        #expect(east?.lightGuidance.seekEveningLight == false)
        let west = J.state(shiftHours: -3, daysSinceArrival: 0, daylightMin: 0)
        #expect(west?.direction == .delay)
        #expect(west?.lightGuidance.seekEveningLight == true)
        #expect(west?.lightGuidance.seekMorningLight == false)
    }

    @Test func cbtMinCaveatForLargeEastwardOnly() {
        let bigEast = J.state(shiftHours: Double(J.antidromicZones), daysSinceArrival: 0, daylightMin: 0)
        #expect(bigEast?.lightGuidance.cbtMinCaveat == true)
        let bigWest = J.state(shiftHours: -Double(J.antidromicZones), daysSinceArrival: 0, daylightMin: 0)
        #expect(bigWest?.lightGuidance.cbtMinCaveat == false)
    }

    // The offset-history detection rule, now a pure function over samples.

    private func sample(_ day: Int, _ offset: Double, _ tz: String) -> J.OffsetSample {
        J.OffsetSample(day: day, offset: offset, timeZoneID: tz)
    }

    @Test func detectsATripThatPersistedOvernight() throws {
        let samples = [sample(100, 2, "Europe/Paris"), sample(101, 2, "Europe/Paris"),
                       sample(102, 9, "Asia/Tokyo"), sample(103, 9, "Asia/Tokyo")]
        let travel = try #require(J.latestTravel(samples))
        #expect(close(travel.shiftHours, 7, 1e-9))
        #expect(travel.arrivalDay == 102)
        let state = try #require(J.state(samples: samples, today: 104, daylightMin: 0))
        #expect(state.daysSinceArrival == 2)
        #expect(state.direction == .advance)
    }

    @Test func ignoresDSTAndSameDayLayovers() {
        // DST: the offset moves but the identifier stays.
        let dst = [sample(100, 1, "Europe/Paris"), sample(101, 2, "Europe/Paris"), sample(102, 2, "Europe/Paris")]
        #expect(J.latestTravel(dst) == nil)
        // A new zone seen on one day only has not persisted overnight.
        let layover = [sample(100, 2, "Europe/Paris"), sample(101, 4, "Asia/Dubai")]
        #expect(J.latestTravel(layover) == nil)
        #expect(J.latestTravel([]) == nil)
    }
}

// MARK: - TravelActionPlanner

@Suite("Travel action planner")
struct ToolsTravelActionPlannerTests {
    typealias TP = SomaTools.TravelActionPlanner

    private func state(_ shift: Double) -> SomaTools.JetLagState {
        SomaTools.JetLagModel.state(shiftHours: shift, daysSinceArrival: 0, daylightMin: 0)!
    }

    @Test func eastwardSeeksMorningLightAndDimsTheEvening() throws {
        let actions = TP.plan(state: state(3), habitualWakeHour: 7, habitualSleepHour: 23)
        #expect(actions.map(\.kind) == [.morningLight, .caffeineCutoff, .avoidLight, .sleep])
        let morning = try #require(actions.first { $0.kind == .morningLight })
        #expect(morning.startHour == 7 && morning.endHour == 9)
        let dim = try #require(actions.first { $0.kind == .avoidLight })
        #expect(dim.startHour == 20 && dim.endHour == 23)
        #expect(dim.title == "Dim the evening")
        #expect(actions.first { $0.kind == .caffeineCutoff }?.startHour == 17)
    }

    @Test func westwardSeeksEveningLightAndMelatoninAfterWake() throws {
        let actions = TP.plan(state: state(-6), habitualWakeHour: 7, habitualSleepHour: 23)
        #expect(Set(actions.map(\.kind)) == [.eveningLight, .avoidLight, .caffeineCutoff, .melatonin, .sleep])
        let dim = try #require(actions.first { $0.kind == .avoidLight })
        #expect(dim.startHour == 7 && dim.title == "Dim the early morning")
        // Westward (delay): melatonin one hour after wake.
        #expect(actions.first { $0.kind == .melatonin }?.startHour == 8)
        // Sorted by start hour.
        #expect(actions.map(\.startHour) == actions.map(\.startHour).sorted())
    }

    @Test func timingHandlesPointAndWrappingActions() {
        let cutoff = SomaTools.TravelAction(kind: .caffeineCutoff, startHour: 17, endHour: nil, title: "", detail: "")
        #expect(TP.timing(of: cutoff, nowHour: 16) == .future)
        #expect(TP.timing(of: cutoff, nowHour: 17.25) == .current)
        #expect(TP.timing(of: cutoff, nowHour: 18) == .past)
        #expect(TP.timing(of: cutoff, nowHour: 17.25, isDone: true) == .done)
        let sleep = SomaTools.TravelAction(kind: .sleep, startHour: 23, endHour: 7, title: "", detail: "")
        #expect(TP.timing(of: sleep, nowHour: 2) == .current)
        #expect(TP.timing(of: sleep, nowHour: 12) == .future)
    }

    @Test func focusPrefersTheCurrentActionThenTheNextNotDone() throws {
        let actions = TP.plan(state: state(3), habitualWakeHour: 7, habitualSleepHour: 23)
        let now = try #require(TP.focus(actions: actions, nowHour: 8))
        #expect(now.action.kind == .morningLight && now.isCurrent)
        let next = try #require(TP.focus(actions: actions, nowHour: 12))
        #expect(next.action.kind == .caffeineCutoff && !next.isCurrent)
        let skipDone = try #require(TP.focus(actions: actions, nowHour: 12, isDone: { $0 == .caffeineCutoff }))
        #expect(skipDone.action.kind == .avoidLight)
    }

    @Test func countdownSplitsHoursAndMinutes() {
        #expect(TP.countdown(from: 12, to: 14.25) == (2, 15))
        #expect(TP.countdown(from: 15, to: 14) == (0, 0))
    }
}

// MARK: - ShiftPlanEngine

@Suite("Shift plan engine")
struct ToolsShiftPlanEngineTests {
    typealias S = SomaTools.ShiftPlanEngine

    /// A 07:00 wake / 23:00 sleep worker moved onto a night shift starting at
    /// 23:00: a real direction, multi-day recovery, and a non-empty timeline.
    @Test func dayToNightShiftProducesActiveRecoveryWithActions() throws {
        let plan = try #require(S.plan(habitualWakeHour: 7, newShiftStartHour: 23, daysSinceChange: 0,
                                       recentDaylightMin: 0, habitualSleepHour: 23))
        #expect(plan.state.recoveryDays > 0)
        #expect(!plan.actions.isEmpty)
        #expect(abs(plan.shiftHours) > 1)
    }

    /// The required wake equals the habitual wake: zero shift, no burden.
    @Test func noScheduleChangeIsNil() {
        let start = 7 + S.gettingReadyOffsetHours
        #expect(S.plan(habitualWakeHour: 7, newShiftStartHour: start, daysSinceChange: 0,
                       recentDaylightMin: 0, habitualSleepHour: 23) == nil)
    }

    @Test func signedShiftFollowsTheEastPositiveConvention() {
        // Required wake 05:00 against a habitual 07:00: wake earlier, advance.
        #expect(close(S.signedShiftHours(from: 5, to: 7), 2, 1e-9))
        // Required wake 21:00 against 07:00: the short arc is 10 h later, delay.
        #expect(close(S.signedShiftHours(from: 21, to: 7), 10, 1e-9))
        #expect(close(S.signedShiftHours(from: 9, to: 7), -2, 1e-9))
    }
}

// MARK: - ShiftSchedule

@Suite("Shift schedule")
struct ToolsShiftScheduleTests {
    typealias SS = SomaTools.ShiftSchedule

    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test func daysSinceChangeCountsWholeDaysAndNeverGoesNegative() {
        let roster = utc.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 22))!
        let now = utc.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 6))!
        #expect(SS.daysSinceChange(rosterDate: roster, now: now, calendar: utc) == 3)
        #expect(SS.daysSinceChange(rosterDate: now, now: roster, calendar: utc) == 0)
        #expect(SS.daysSinceChange(rosterDate: nil, now: now, calendar: utc) == 0)
    }

    @Test func defaultRosterHasAPlanAndItsDaysMove() throws {
        let day0 = try #require(SS.plan(shiftStartHour: SS.defaultShiftStartHour,
                                        usualWakeHour: SS.defaultUsualWakeHour))
        let day2 = try #require(SS.plan(shiftStartHour: SS.defaultShiftStartHour,
                                        usualWakeHour: SS.defaultUsualWakeHour, daysSinceChange: 2))
        #expect(SS.dayNumber(day0) == 1)
        #expect(SS.dayNumber(day2) == 3)
        #expect(SS.daysLeft(day2) == SS.daysLeft(day0) - 2)
    }

    @Test func nextActionsAreTheTwoStillAheadOrTheFirstTwo() throws {
        let plan = try #require(SS.plan(shiftStartHour: SS.defaultShiftStartHour,
                                        usualWakeHour: SS.defaultUsualWakeHour))
        let early = SS.nextActions(plan, nowHour: 0)
        #expect(early.count == 2)
        #expect(early == Array(plan.actions.prefix(2)))
        let late = SS.nextActions(plan, nowHour: 23.9)
        #expect(late == Array(plan.actions.prefix(2)))
    }
}

// MARK: - TripPlanner

@Suite("Trip planner")
struct ToolsTripPlannerTests {
    typealias TP = SomaTools.TripPlanner

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Paris to Tokyo, out on the 10th, back on the 17th.
    private func tokyoTrip() -> SomaTools.Trip {
        SomaTools.Trip(
            id: UUID(),
            startDate: day(2026, 8, 10, 11),
            title: "Board Tokyo",
            destinationName: "Tokyo",
            destinationTimeZoneID: "Asia/Tokyo",
            endDate: day(2026, 8, 17, 20),
            legs: [
                SomaTools.TripLeg(id: UUID(), departAt: day(2026, 8, 10, 11), arriveAt: day(2026, 8, 11, 6),
                                  fromTimeZoneID: "Europe/Paris", toTimeZoneID: "Asia/Tokyo",
                                  isRedEye: true, sourceEventID: nil),
                SomaTools.TripLeg(id: UUID(), departAt: day(2026, 8, 17, 10), arriveAt: day(2026, 8, 17, 20),
                                  fromTimeZoneID: "Asia/Tokyo", toTimeZoneID: "Europe/Paris",
                                  isRedEye: false, sourceEventID: nil),
            ],
            updatedAt: day(2026, 8, 1),
            deletedAt: nil)
    }

    @Test func preDepartureCountsDaysOut() {
        #expect(TP.phase(for: day(2026, 8, 8), trip: tokyoTrip(), calendar: cal) == .preDeparture(daysOut: 2))
    }

    @Test func preDepartureStopsAtSevenDaysOut() {
        #expect(TP.phase(for: day(2026, 7, 20), trip: tokyoTrip(), calendar: cal) == SomaTools.TripPhase.none)
    }

    @Test func departureDayIsOutbound() {
        #expect(TP.phase(for: day(2026, 8, 10), trip: tokyoTrip(), calendar: cal) == .outbound(legIndex: 0))
    }

    @Test func middleOfTripIsAtDestination() {
        #expect(TP.phase(for: day(2026, 8, 13), trip: tokyoTrip(), calendar: cal) == .atDestination(day: 3, of: 7))
    }

    @Test func returnDayIsReturnLeg() {
        #expect(TP.phase(for: day(2026, 8, 17), trip: tokyoTrip(), calendar: cal) == .returnLeg)
    }

    @Test func afterReturnCountsPostDays() {
        #expect(TP.phase(for: day(2026, 8, 19), trip: tokyoTrip(), calendar: cal) == .postReturn(day: 2))
    }

    /// A trip with no end date never returns returnLeg or postReturn.
    @Test func openEndedTripStaysAtDestination() throws {
        var trip = tokyoTrip()
        trip.endDate = nil
        trip.legs = [try #require(trip.legs?.first)]
        #expect(TP.phase(for: day(2026, 9, 30), trip: trip, calendar: cal) == .atDestination(day: 51, of: nil))
    }

    @Test func arrivalShiftIsPositiveGoingEast() throws {
        // Paris +2, Tokyo +9 in August.
        #expect(close(try #require(TP.arrivalShiftHours(trip: tokyoTrip())), 7, 0.01))
    }

    @Test func arrivalShiftIsNegativeGoingWest() throws {
        var trip = tokyoTrip()
        trip.destinationTimeZoneID = "America/Los_Angeles"
        trip.legs = [SomaTools.TripLeg(id: UUID(), departAt: day(2026, 8, 10, 11), arriveAt: day(2026, 8, 10, 20),
                                       fromTimeZoneID: "Europe/Paris", toTimeZoneID: "America/Los_Angeles",
                                       isRedEye: false, sourceEventID: nil)]
        // Paris +2, Los Angeles -7.
        #expect(close(try #require(TP.arrivalShiftHours(trip: trip)), -9, 0.01))
    }

    @Test func arrivalShiftIsNilWithoutTimeZones() {
        var trip = tokyoTrip()
        trip.destinationTimeZoneID = nil
        trip.legs = nil
        #expect(TP.arrivalShiftHours(trip: trip) == nil)
    }

    @Test func redEyeLegFoundOnTheNightItSpans() {
        let leg = TP.redEyeLeg(on: day(2026, 8, 10), trip: tokyoTrip(), calendar: cal)
        #expect(leg?.isRedEye == true)
    }

    @Test func noRedEyeLegOnAnUnrelatedDay() {
        #expect(TP.redEyeLeg(on: day(2026, 8, 13), trip: tokyoTrip(), calendar: cal) == nil)
    }

    /// A deleted trip is silent, in phase and in legs.
    @Test func deletedTripIsSilent() {
        var trip = tokyoTrip()
        trip.deletedAt = day(2026, 8, 2)
        #expect(TP.phase(for: day(2026, 8, 13), trip: trip, calendar: cal) == SomaTools.TripPhase.none)
        #expect(TP.redEyeLeg(on: day(2026, 8, 10), trip: trip, calendar: cal) == nil)
    }

    @Test func tripProducesTheJetLagStateFromItsArrivalDay() throws {
        let state = try #require(TP.jetLagState(for: day(2026, 8, 13), trip: tokyoTrip(), calendar: cal))
        #expect(state.zones == 7)
        #expect(state.direction == .advance)
        #expect(state.daysSinceArrival == 2)
        #expect(TP.jetLagState(for: day(2026, 8, 9), trip: tokyoTrip(), calendar: cal) == nil)
    }
}
