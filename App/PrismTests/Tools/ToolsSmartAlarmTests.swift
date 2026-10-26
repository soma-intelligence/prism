//
//  ToolsSmartAlarmTests.swift
//  PrismTests
//
//  Smart wake engine, goals, planner, refiner, explainer, bedtime, bedtime
//  schedule, settings, calendar constraint and the alarm card helpers. Every
//  suite runs on a fixed calendar so the result never depends on the time
//  zone of the machine running it.
//

import Foundation
import Testing
@testable import Prism

private typealias Engine = SomaTools.SmartWakeEngine
private typealias Span = SomaTools.SleepCycleModel.StageSpan
private typealias Priority = SomaTools.SmartAlarmPriority
private typealias Settings = SomaTools.SmartAlarmSettings
private typealias Explainer = SomaTools.SmartAlarmExplainer
private typealias CalendarConstraint = SomaTools.SmartAlarmCalendarConstraint
private typealias Planner = SomaTools.SmartAlarmPlanner
private typealias Refiner = SomaTools.SmartAlarmRefiner
private typealias Bedtime = SomaTools.SmartAlarmBedtime
private typealias BedtimeSchedule = SomaTools.SmartAlarmBedtimeSchedule
private typealias Display = SomaTools.SmartAlarmDisplay

private func calendar(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

private let utc = calendar("UTC")
private let losAngeles = calendar("America/Los_Angeles")

private func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}

/// 2026-07-24 22:00 UTC, the reference onset of the engine suites.
private let referenceOnset = Date(timeIntervalSince1970: 1_785_016_800)

/// Instant on the day of `reference` at the given clock hour, on the same
/// calendar the engine receives.
private func clockInstant(hour: Double, sameDayAs reference: Date) -> Date {
    utc.startOfDay(for: reference).addingTimeInterval(hour * 3600)
}

/// Minimal engine input: the two bounds and the anchor, on the UTC calendar.
private func engineInputs(latest: Date,
                          earliest: Date,
                          anchorWakeHour: Double?,
                          priority: Priority? = nil,
                          debtHours: Double = 0,
                          hrvRatio: Double = 1,
                          strainRatio: Double = 1,
                          regularity: Double? = nil,
                          cbtMinHour: Double? = nil,
                          sleepNeedSeconds: Int = 8 * 3600,
                          onset: Date? = nil,
                          observed: [Span] = [],
                          observedOnset: Date? = nil) -> Engine.Inputs {
    var out = Engine.Inputs(
        earliest: earliest,
        latest: latest,
        anchorWakeHour: anchorWakeHour,
        regularity: regularity,
        cbtMinHour: cbtMinHour,
        sleepNeedSeconds: sleepNeedSeconds,
        debtHours: debtHours,
        hrvRatio: hrvRatio,
        strainRatio: strainRatio,
        onset: onset,
        onsetLatencySeconds: Engine.defaultOnsetLatencySeconds,
        meanCycleSeconds: nil,
        observedSpans: observed,
        observedOnset: observedOnset)
    if let priority { out.priority = priority }
    out.calendar = utc
    return out
}

private func hasReason(_ plan: Engine.Plan, _ match: (Engine.Reason) -> Bool) -> Bool {
    plan.reasons.contains(where: match)
}

// MARK: Smart wake engine

@Suite("Smart wake engine")
struct ToolsSmartWakeEngineTests {

    private let onset = referenceOnset
    private var tomorrow: Date { onset.addingTimeInterval(86_400) }

    /// Synthetic night: cycles of 90 min, core, deep, core, rem.
    private func spans(cycles: Int) -> [Span] {
        var out: [Span] = []
        for _ in 0..<cycles {
            out.append(.init(stage: "core", seconds: 20 * 60))
            out.append(.init(stage: "deep", seconds: 25 * 60))
            out.append(.init(stage: "core", seconds: 25 * 60))
            out.append(.init(stage: "rem", seconds: 20 * 60))
        }
        return out
    }

    @Test func clampKeepsValuesInsideTheRange() {
        let low = onset
        let high = onset.addingTimeInterval(3600)
        #expect(Engine.clamp(low.addingTimeInterval(-60), to: low...high) == low)
        #expect(Engine.clamp(high.addingTimeInterval(60), to: low...high) == high)
        #expect(Engine.clamp(low.addingTimeInterval(1800), to: low...high) == low.addingTimeInterval(1800))
    }

    @Test func degenerateWindowCollapsesToLatest() {
        let target = onset.addingTimeInterval(8 * 3600)
        var inputs = engineInputs(latest: target, earliest: target.addingTimeInterval(-1800), anchorWakeHour: 6.5)
        inputs.earliest = target.addingTimeInterval(600)
        let plan = Engine.plan(inputs)
        #expect(plan.ring == target)
        #expect(plan.window == target...target)
        #expect(plan.source == .deadline)
    }

    @Test func zeroLatitudeRingsExactlyOnTheBound() {
        let target = onset.addingTimeInterval(8 * 3600)
        let plan = Engine.plan(engineInputs(latest: target, earliest: target, anchorWakeHour: 6.5,
                                            debtHours: 99, observed: spans(cycles: 6), observedOnset: onset))
        #expect(plan.ring == target)
        #expect(plan.source == .deadline)
    }

    @Test func planIsPure() {
        let latest = clockInstant(hour: 7.5, sameDayAs: tomorrow)
        let inputs = engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                  anchorWakeHour: 6.5, observed: spans(cycles: 6), observedOnset: onset)
        #expect(Engine.plan(inputs) == Engine.plan(inputs))
    }

    @Test func withoutAnchorRingsAtTheHardBound() {
        let latest = onset.addingTimeInterval(9 * 3600)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                            anchorWakeHour: nil))
        #expect(plan.ring == latest)
        #expect(plan.source == .deadline)
    }

    @Test func startsFromTheAnchor() {
        let latest = clockInstant(hour: 7.5, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                            anchorWakeHour: 6.5))
        #expect(plan.ring == clockInstant(hour: 6.5, sameDayAs: latest))
        #expect(plan.reasons.contains(.anchor(hour: 6.5)))
    }

    @Test func debtExtendsByAtMostThirtyMinutes() {
        let latest = clockInstant(hour: 9, sameDayAs: tomorrow)
        let anchor = clockInstant(hour: 6.5, sameDayAs: latest)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-3 * 3600),
                                            anchorWakeHour: 6.5, debtHours: 99, hrvRatio: 0.5, strainRatio: 5))
        #expect(near(plan.ring.timeIntervalSince(anchor), Engine.maxRecoveryExtensionSeconds, 1))
        #expect(hasReason(plan) { if case .recoveryExtension = $0 { true } else { false } })
    }

    @Test func debtIsMonotonic() {
        let latest = clockInstant(hour: 9, sameDayAs: tomorrow)
        let earliest = latest.addingTimeInterval(-3 * 3600)
        let low = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 6.5, debtHours: 1))
        let high = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 6.5, debtHours: 4))
        #expect(high.ring >= low.ring)
    }

    /// Onset 02:00, need 8 h, bound 07:00: three hours short. Step 5 then finds
    /// a cycle boundary at 06:45 (onset, latency, three 90 min cycles).
    @Test func sleepNeedShortfallIsReportedNotHidden() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let onsetLate = clockInstant(hour: 2, sameDayAs: latest)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                            anchorWakeHour: 6.5, onset: onsetLate))
        #expect(plan.ring == clockInstant(hour: 6.75, sameDayAs: latest))
        #expect(hasReason(plan) { if case .sleepNeedShortfall(let s) = $0 { s > 0 } else { false } })
    }

    @Test func circadianFloorWorksAcrossMidnight() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-4 * 3600),
                                            anchorWakeHour: 5, cbtMinHour: 4.5))
        #expect(plan.ring == clockInstant(hour: 5.5, sameDayAs: latest))
        #expect(hasReason(plan) { if case .circadianFloor = $0 { true } else { false } })
    }

    @Test func cbtMinBeforeMidnightDoesNotPushForward() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-4 * 3600),
                                            anchorWakeHour: 6.5, cbtMinHour: 23))
        #expect(plan.ring == clockInstant(hour: 6.5, sameDayAs: latest))
        #expect(!hasReason(plan) { if case .circadianFloor = $0 { true } else { false } })
    }

    /// Regularity 0 gives a 20 min tolerance. Every recovery signal is
    /// saturated so the wanted extension is the full 30 min, the only case the
    /// guard has something to correct.
    @Test func tightensToleranceForAnIrregularSleeper() {
        let latest = clockInstant(hour: 10, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-5 * 3600),
                                            anchorWakeHour: 6.5, debtHours: 99, hrvRatio: 0, strainRatio: 99,
                                            regularity: 0))
        let anchor = clockInstant(hour: 6.5, sameDayAs: latest)
        #expect(near(plan.ring.timeIntervalSince(anchor), Engine.minToleranceSeconds, 1))
        #expect(hasReason(plan) { if case .regularityClamp = $0 { true } else { false } })
    }

    @Test func grantsMoreLatitudeToARegularSleeper() {
        let latest = clockInstant(hour: 10, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-5 * 3600),
                                            anchorWakeHour: 6.5, debtHours: 99, hrvRatio: 0, strainRatio: 99,
                                            regularity: 100))
        let anchor = clockInstant(hour: 6.5, sameDayAs: latest)
        #expect(near(plan.ring.timeIntervalSince(anchor), Engine.maxRecoveryExtensionSeconds, 1))
    }

    @Test func usesObservedHypnogramWhenAvailable() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        let observedOnset = latest.addingTimeInterval(-8 * 3600)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                            anchorWakeHour: 7, sleepNeedSeconds: 6 * 3600,
                                            onset: observedOnset, observed: spans(cycles: 7),
                                            observedOnset: observedOnset))
        #expect(plan.source == .observed)
        #expect(plan.window.contains(plan.ring))
    }

    /// An UNREACHABLE shortfall is reported; it does not consume the latitude
    /// the user granted by pinning the target on the bound.
    @Test func unreachableSleepNeedStillLeavesTheCycleInCharge() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let bedtime = clockInstant(hour: 23.5, sameDayAs: latest).addingTimeInterval(-86_400)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-45 * 60),
                                            anchorWakeHour: 6.5, sleepNeedSeconds: 8 * 3600, onset: bedtime,
                                            observed: spans(cycles: 6), observedOnset: bedtime))
        #expect(plan.ring < latest)
        #expect(plan.window.contains(plan.ring))
        #expect(hasReason(plan) { if case .sleepNeedShortfall(let s) = $0 { s > 0 } else { false } })
    }

    /// With the target on the upper bound, the usable flex must not fall to
    /// zero: across a cycle of bedtimes some observed alignment moves the ring
    /// off the bound.
    @Test func observedAlignmentSurvivesATargetOnTheBound() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        var movedOffTheBound = 0
        for step in 0..<18 {
            let observedOnset = latest.addingTimeInterval(-8 * 3600).addingTimeInterval(Double(step) * 5 * 60)
            let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                                anchorWakeHour: 7 + 40.0 / 60,
                                                debtHours: 99, hrvRatio: 0, strainRatio: 99,
                                                regularity: 100, sleepNeedSeconds: 6 * 3600,
                                                onset: observedOnset, observed: spans(cycles: 7),
                                                observedOnset: observedOnset))
            #expect(plan.window.contains(plan.ring))
            if plan.source == .observed, plan.ring < latest { movedOffTheBound += 1 }
        }
        #expect(movedOffTheBound > 0)
    }

    @Test func observedAlignmentNeverLeavesTheWindow() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        for earlyMinutes in [15, 30, 45, 60, 90] {
            for anchorHour in [5.0, 6.0, 6.5, 7.0, 7.5, 8.0, 9.0] {
                let observedOnset = latest.addingTimeInterval(-8 * 3600)
                let plan = Engine.plan(engineInputs(latest: latest,
                                                    earliest: latest.addingTimeInterval(-Double(earlyMinutes) * 60),
                                                    anchorWakeHour: anchorHour, sleepNeedSeconds: 8 * 3600,
                                                    onset: observedOnset, observed: spans(cycles: 7),
                                                    observedOnset: observedOnset))
                #expect(plan.window.contains(plan.ring), "early \(earlyMinutes) anchor \(anchorHour)")
            }
        }
    }

    /// A cycle boundary already on the target moves nothing, so it is not a
    /// reason, and the source stays observed.
    @Test func aCycleBoundaryOnTheTargetIsNotAReason() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        let observedOnset = latest.addingTimeInterval(-7.5 * 3600)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                            anchorWakeHour: 7 + 40.0 / 60,
                                            debtHours: 99, hrvRatio: 0, strainRatio: 99,
                                            regularity: 100, sleepNeedSeconds: 6 * 3600,
                                            onset: observedOnset, observed: spans(cycles: 7),
                                            observedOnset: observedOnset))
        #expect(plan.ring == latest)
        #expect(plan.source == .observed)
        #expect(!hasReason(plan) { if case .cycleAlignment = $0 { true } else { false } })
    }

    @Test func neverExceedsHardBoundWithEverySignalMaxed() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                            anchorWakeHour: 6.9, debtHours: 99, hrvRatio: 0, strainRatio: 99,
                                            regularity: 100, cbtMinHour: 6.5,
                                            onset: latest.addingTimeInterval(-2 * 3600)))
        #expect(plan.ring <= latest)
    }

    @Test func clampFiresWhenTheAnchorSitsOutsideTheWindow() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        let inputs = engineInputs(latest: latest, earliest: latest.addingTimeInterval(-3600),
                                  anchorWakeHour: 4, regularity: 100)
        let plan = Engine.plan(inputs)
        #expect(plan.ring == inputs.earliest)
        #expect(plan.reasons.contains(.hardBoundClamp))
    }

    // MARK: Phase slack of the predicted grid

    @Test func phaseSlackOnlyAppliesToAnEstimatedOnset() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        var inputs = engineInputs(latest: latest, earliest: latest.addingTimeInterval(-45 * 60),
                                  anchorWakeHour: 7, onset: onset)
        #expect(Engine.phaseSlackSeconds(inputs) == Engine.defaultOnsetLatencySeconds)
        inputs.observedOnset = onset
        #expect(Engine.phaseSlackSeconds(inputs) == 0)
    }

    /// Bedtime 22:20, boundaries every 90 min from 22:35: the fifth falls at
    /// 06:05, ten minutes before the 06:15 low bound, and is projected onto it.
    @Test func predictedBoundaryJustBeforeTheWindowIsProjectedOntoIt() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let earliest = latest.addingTimeInterval(-45 * 60)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 7,
                                            regularity: 100,
                                            onset: latest.addingTimeInterval(-(8 * 3600 + 40 * 60))))
        #expect(plan.ring == earliest)
        #expect(plan.source == .predicted)
        #expect(hasReason(plan) { if case .cycleAlignment = $0 { true } else { false } })
    }

    @Test func anObservedOnsetGetsNoPhaseSlack() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let estimated = latest.addingTimeInterval(-(8 * 3600 + 40 * 60))
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-45 * 60),
                                            anchorWakeHour: 7, regularity: 100,
                                            onset: estimated, observedOnset: estimated))
        #expect(plan.ring == latest)
    }

    /// A boundary after the hard bound is never admitted, even five minutes
    /// after: that bound is a fact, not an estimate.
    @Test func aBoundaryPastTheHardBoundIsNeverAdmitted() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-45 * 60),
                                            anchorWakeHour: 7, regularity: 100,
                                            onset: latest.addingTimeInterval(-(7 * 3600 + 40 * 60))))
        #expect(plan.ring == latest)
        #expect(!hasReason(plan) { if case .cycleAlignment = $0 { true } else { false } })
    }

    /// Window 05:40 to 07:00, bedtime 22:50: 06:35 is inside the window and
    /// beats 05:05, which is outside the slack anyway.
    @Test func anExactBoundaryBeatsAProjectedOne() {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let earliest = latest.addingTimeInterval(-80 * 60)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 7,
                                            regularity: 100,
                                            onset: latest.addingTimeInterval(-(8 * 3600 + 10 * 60))))
        #expect(plan.ring == latest.addingTimeInterval(-25 * 60))
        #expect(plan.ring != earliest)
    }
}

// MARK: Goals

@Suite("Smart alarm goals")
struct ToolsSmartAlarmPriorityTests {

    private var tomorrow: Date { referenceOnset.addingTimeInterval(86_400) }

    @Test func balancedCarriesTheHistoricalWeights() {
        let w = Engine.weights(for: .balanced)
        #expect(w.debt == 0.5)
        #expect(w.hrv == 0.3)
        #expect(w.strain == 0.2)
        #expect(w.extensionCap == 1)
        #expect(w.tolerance == 1)
        #expect(!w.circadianFloorLeads)
    }

    /// Compared to the formula from before the goal existed, to the bit.
    @Test func balancedRecoveryExtensionMatchesThePreChangeFormula() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        for debt in [0.0, 1.5, 3.0, 99.0] {
            for hrv in [1.0, 0.9, 0.5] {
                for strain in [1.0, 1.2, 5.0] {
                    let fixture = engineInputs(latest: latest, earliest: latest.addingTimeInterval(-3 * 3600),
                                               anchorWakeHour: 6.5, debtHours: debt,
                                               hrvRatio: hrv, strainRatio: strain)
                    let d = min(max(debt / Engine.debtSaturationHours, 0), 1)
                    let h = min(max((1 - hrv) / Engine.hrvSaturationDrop, 0), 1)
                    let s = min(max((strain - 1) / Engine.strainSaturationRise, 0), 1)
                    let severity = min(max(0.5 * d + 0.3 * h + 0.2 * s, 0), 1)
                    #expect(Engine.recoveryExtension(fixture) == severity * Engine.maxRecoveryExtensionSeconds)
                }
            }
        }
    }

    @Test func balancedToleranceMatchesThePreChangeFormula() {
        for regularity in [nil, 0.0, 37.5, 100.0] as [Double?] {
            let expected: Double
            if let regularity {
                let ratio = min(max(regularity / 100, 0), 1)
                expected = Engine.minToleranceSeconds
                    + (Engine.maxToleranceSeconds - Engine.minToleranceSeconds) * ratio
            } else {
                expected = Engine.defaultToleranceSeconds
            }
            #expect(Engine.toleranceSeconds(for: regularity) == expected)
            #expect(Engine.toleranceSeconds(for: regularity, priority: .balanced) == expected)
        }
    }

    @Test func balancedReproducesThePinnedFixtures() {
        let latest = clockInstant(hour: 9, sameDayAs: tomorrow)
        let anchor = clockInstant(hour: 6.5, sameDayAs: latest)
        let implicit = engineInputs(latest: latest, earliest: latest.addingTimeInterval(-3 * 3600),
                                    anchorWakeHour: 6.5, debtHours: 99, hrvRatio: 0.5, strainRatio: 5)
        let explicit = engineInputs(latest: latest, earliest: latest.addingTimeInterval(-3 * 3600),
                                    anchorWakeHour: 6.5, priority: .balanced,
                                    debtHours: 99, hrvRatio: 0.5, strainRatio: 5)
        #expect(Engine.plan(implicit) == Engine.plan(explicit))
        #expect(near(Engine.plan(explicit).ring.timeIntervalSince(anchor), Engine.maxRecoveryExtensionSeconds, 1))

        let wide = clockInstant(hour: 10, sameDayAs: tomorrow)
        let tight = Engine.plan(engineInputs(latest: wide, earliest: wide.addingTimeInterval(-5 * 3600),
                                             anchorWakeHour: 6.5, priority: .balanced,
                                             debtHours: 99, hrvRatio: 0, strainRatio: 99, regularity: 0))
        #expect(near(tight.ring.timeIntervalSince(clockInstant(hour: 6.5, sameDayAs: wide)),
                     Engine.minToleranceSeconds, 1))
    }

    /// Hostile sweep: every signal saturated, anchors past the bound, a
    /// circadian floor just under it, latitudes from zero to 90 min.
    @Test(arguments: Priority.allCases)
    func noPriorityCanRingPastTheHardBound(priority: SomaTools.SmartAlarmPriority) {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        for earlyMinutes in [0.0, 15, 45, 90] {
            for anchorHour in [4.0, 6.5, 6.9, 8.0, 11.0] {
                let plan = Engine.plan(engineInputs(latest: latest,
                                                    earliest: latest.addingTimeInterval(-earlyMinutes * 60),
                                                    anchorWakeHour: anchorHour, priority: priority,
                                                    debtHours: 99, hrvRatio: 0, strainRatio: 99,
                                                    regularity: 100, cbtMinHour: 6.5,
                                                    onset: latest.addingTimeInterval(-8 * 3600)))
                #expect(plan.ring <= latest)
                #expect(plan.window.contains(plan.ring))
            }
        }
    }

    @Test(arguments: Priority.allCases)
    func withoutAnAnchorEveryPriorityRingsOnTheBound(priority: SomaTools.SmartAlarmPriority) {
        let latest = clockInstant(hour: 7, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-45 * 60),
                                            anchorWakeHour: nil, priority: priority, debtHours: 99))
        #expect(plan.ring == latest)
        #expect(plan.source == .deadline)
    }

    @Test func regularityStaysCloserToTheAnchorThanClearDebt() {
        let latest = clockInstant(hour: 10, sameDayAs: tomorrow)
        let earliest = latest.addingTimeInterval(-5 * 3600)
        let anchor = clockInstant(hour: 6.5, sameDayAs: latest)
        func ring(_ priority: Priority) -> Double {
            Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 6.5,
                                     priority: priority, debtHours: 99, regularity: 100))
                .ring.timeIntervalSince(anchor)
        }
        let regular = ring(.regularity)
        let balanced = ring(.balanced)
        let debt = ring(.clearDebt)
        #expect(abs(regular) < abs(debt))
        #expect(abs(regular) < abs(balanced))
        #expect(debt > balanced)
        // Saturated debt weighed 0.8 on a doubled cap: 48 min.
        #expect(near(debt, 0.8 * Engine.maxRecoveryExtensionSeconds * 2, 1))
    }

    @Test func clearDebtIsMonotonicAndOutweighsBalanced() {
        let latest = clockInstant(hour: 10, sameDayAs: tomorrow)
        let earliest = latest.addingTimeInterval(-5 * 3600)
        var previous = Date.distantPast
        for debtHours in [0.0, 1, 2, 3, 5] {
            let plan = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 6.5,
                                                priority: .clearDebt, debtHours: debtHours, regularity: 100))
            #expect(plan.ring >= previous)
            previous = plan.ring
            let balanced = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 6.5,
                                                    debtHours: debtHours, regularity: 100))
            #expect(plan.ring >= balanced.ring)
        }
    }

    /// Anchor at 05:00 (home habit), local CBTmin 05:30 so the floor is 06:30.
    /// Travel keeps the floor; balanced lets the anchor pull below it.
    @Test func travelLetsTheCircadianFloorOutrankTheAnchor() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        let earliest = latest.addingTimeInterval(-3 * 3600)
        let floor = clockInstant(hour: 6.5, sameDayAs: latest)
        let travel = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 5,
                                              priority: .travel, cbtMinHour: 5.5))
        #expect(travel.ring == floor)
        #expect(!hasReason(travel) { if case .regularityClamp = $0 { true } else { false } })
        let balanced = Engine.plan(engineInputs(latest: latest, earliest: earliest, anchorWakeHour: 5,
                                                cbtMinHour: 5.5))
        #expect(balanced.ring < travel.ring)
    }

    @Test func travelWithoutACircadianPhaseStaysInsideTheBounds() {
        let latest = clockInstant(hour: 8, sameDayAs: tomorrow)
        let plan = Engine.plan(engineInputs(latest: latest, earliest: latest.addingTimeInterval(-90 * 60),
                                            anchorWakeHour: 7, priority: .travel, debtHours: 4))
        #expect(plan.window.contains(plan.ring))
        #expect(plan.ring <= latest)
    }

    // MARK: Persistence

    @Test func settingsSavedBeforeTheGoalDecodeAsBalanced() {
        let legacy = #"{"isEnabled":true,"wakeMinutes":400,"earlyWindowMinutes":60,"snoozeMinutes":9}"#
        let settings = Settings.decoded(from: Data(legacy.utf8))
        #expect(settings.priority == .balanced)
        #expect(settings.isEnabled)
        #expect(settings.wakeMinutes == 400)
        #expect(settings.earlyWindowMinutes == 60)
    }

    @Test(arguments: Priority.allCases)
    func priorityRoundTrips(priority: SomaTools.SmartAlarmPriority) {
        var settings = Settings.default
        settings.priority = priority
        let back = Settings.decoded(from: settings.encoded())
        #expect(back.priority == priority)
        #expect(back == settings)
    }

    @Test func anUnknownPriorityFallsBackWithoutWipingTheRest() {
        let blob = #"{"isEnabled":true,"wakeMinutes":400,"priority":"telepathy"}"#
        let settings = Settings.decoded(from: Data(blob.utf8))
        #expect(settings.priority == .balanced)
        #expect(settings.isEnabled)
        #expect(settings.wakeMinutes == 400)
    }

    // MARK: Explanation

    @Test func theChosenPriorityIsNamedAmongTheFactors() {
        let ring = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = Engine.Plan(ring: ring, window: ring.addingTimeInterval(-1800)...ring,
                               source: .predicted,
                               reasons: [.anchor(hour: 6.5), .cycleAlignment(shiftSeconds: 420)])
        var settings = Settings.default
        settings.priority = .clearDebt
        let factors = Explainer.factors(for: plan, settings: settings)
        #expect(factors.map(\.kind) == [.cycle, .priority, .anchor])
        #expect(factors.first { $0.kind == .priority }?.numbers.priority == .clearDebt)
        #expect(factors.first { $0.kind == .priority }?.shiftSeconds == 0)
    }

    @Test func balancedAddsNoFactor() {
        let ring = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = Engine.Plan(ring: ring, window: ring.addingTimeInterval(-1800)...ring,
                               source: .predicted, reasons: [])
        let factors = Explainer.factors(for: plan, settings: .default)
        #expect(factors.isEmpty)
        #expect(Explainer.dominant(factors) == nil)
    }
}

// MARK: Refiner

@Suite("Smart alarm refiner")
struct ToolsSmartAlarmRefinerTests {

    private let now = Date(timeIntervalSince1970: 1_785_040_000)

    private func plan(ring: Date, upper: Date, source: Engine.Source) -> Engine.Plan {
        Engine.Plan(ring: ring, window: upper.addingTimeInterval(-5400)...upper, source: source, reasons: [])
    }

    private var recurring: SomaTools.SmartAlarmProgrammingQuery {
        .scheduled(.recurring(timeMinutes: 7 * 60, weekdays: [2]))
    }

    @Test func refinesWhenTheNewInstantIsMeaningfullyEarlier() {
        let deadline = now.addingTimeInterval(3600)
        let candidate = deadline.addingTimeInterval(-900)
        #expect(Refiner.decision(plan: plan(ring: candidate, upper: deadline, source: .observed),
                                 current: recurring, now: now) == .refine(candidate))
    }

    @Test func skipsWhenTheGainIsBelowTheThreshold() {
        let deadline = now.addingTimeInterval(3600)
        let candidate = deadline.addingTimeInterval(-120)
        #expect(Refiner.decision(plan: plan(ring: candidate, upper: deadline, source: .observed),
                                 current: recurring, now: now) == .skip(.gainTooSmall))
    }

    @Test func neverMovesAnAlarmLater() {
        let deadline = now.addingTimeInterval(3600)
        let already = deadline.addingTimeInterval(-1800)
        let candidate = deadline.addingTimeInterval(-600)
        #expect(Refiner.decision(plan: plan(ring: candidate, upper: deadline, source: .observed),
                                 current: .scheduled(.oneOff(already)), now: now) == .skip(.wouldMoveLater))
    }

    @Test func skipsWhenTheInstantIsAlreadyPast() {
        let deadline = now.addingTimeInterval(3600)
        let candidate = now.addingTimeInterval(-60)
        #expect(Refiner.decision(plan: plan(ring: candidate, upper: deadline, source: .observed),
                                 current: recurring, now: now) == .skip(.alreadyPast))
    }

    @Test func skipsWhenNoCycleSignalWasUsed() {
        let deadline = now.addingTimeInterval(3600)
        let candidate = deadline.addingTimeInterval(-1200)
        #expect(Refiner.decision(plan: plan(ring: candidate, upper: deadline, source: .deadline),
                                 current: recurring, now: now) == .skip(.noSignal))
    }

    /// An unknown armed state never authorizes a rewrite, even for an obvious
    /// candidate.
    @Test func skipsWhenTheCurrentStateIsUnknown() {
        let deadline = now.addingTimeInterval(3600)
        let candidate = deadline.addingTimeInterval(-900)
        #expect(Refiner.decision(plan: plan(ring: candidate, upper: deadline, source: .observed),
                                 current: .queryFailed, now: now) == .skip(.queryFailed))
    }

    @Test func earliestBeginDateLeadsTheWindowButNeverThePresent() {
        let window = now.addingTimeInterval(3 * 3600)
        #expect(Refiner.earliestBeginDate(before: window, now: now) == window.addingTimeInterval(-Refiner.leadSeconds))
        #expect(Refiner.earliestBeginDate(before: now, now: now) == now.addingTimeInterval(60))
    }
}

// MARK: Explainer

@Suite("Smart alarm explainer")
struct ToolsSmartAlarmExplainerTests {

    private let ring = Date(timeIntervalSince1970: 1_700_000_000)
    private let settings = Settings.default

    private func plan(_ reasons: [Engine.Reason]) -> Engine.Plan {
        Engine.Plan(ring: ring, window: ring.addingTimeInterval(-1800)...ring, source: .predicted, reasons: reasons)
    }

    @Test func recoveryExtensionIsPositiveShift() {
        let f = Explainer.factors(for: plan([.recoveryExtension(seconds: 1080, debt: 3.1, hrv: 0.88, strain: 1.2)]),
                                  settings: settings)
        #expect(f.count == 1)
        #expect(f[0].kind == .recovery)
        #expect(f[0].shiftSeconds == 1080)
    }

    @Test func shortfallIsNegativeShift() {
        let f = Explainer.factors(for: plan([.sleepNeedShortfall(seconds: 2100)]), settings: settings)
        #expect(f[0].kind == .shortfall)
        #expect(f[0].shiftSeconds == -2100)
    }

    @Test func circadianFloorIsPositiveShift() {
        let f = Explainer.factors(for: plan([.circadianFloor(appliedSeconds: 1320)]), settings: settings)
        #expect(f[0].kind == .circadianFloor)
        #expect(f[0].shiftSeconds == 1320)
    }

    @Test func cycleAlignmentKeepsItsSign() {
        let f = Explainer.factors(for: plan([.cycleAlignment(shiftSeconds: -420)]), settings: settings)
        #expect(f[0].kind == .cycle)
        #expect(f[0].shiftSeconds == -420)
    }

    @Test func regularityClampKeepsSignAndCarriesTolerance() {
        let f = Explainer.factors(for: plan([.regularityClamp(shiftSeconds: -720, toleranceSeconds: 1320)]),
                                  settings: settings)
        #expect(f[0].kind == .regularity)
        #expect(f[0].shiftSeconds == -720)
        #expect(f[0].numbers.toleranceSeconds == 1320)
    }

    @Test func hardBoundAndAnchorCarryNoShift() {
        let f = Explainer.factors(for: plan([.hardBoundClamp, .anchor(hour: 6.75)]), settings: settings)
        #expect(f.map(\.kind) == [.hardBound, .anchor])
        #expect(f[0].shiftSeconds == 0)
        #expect(f[1].shiftSeconds == 0)
        #expect(f[1].numbers.anchorHour == 6.75)
    }

    @Test func hardBoundLeadsEvenAgainstLargestShift() {
        let f = Explainer.factors(for: plan([.recoveryExtension(seconds: 1800, debt: 5, hrv: 0.8, strain: 1.4),
                                             .circadianFloor(appliedSeconds: 1500),
                                             .hardBoundClamp]),
                                  settings: settings)
        #expect(f.first?.kind == .hardBound)
    }

    @Test func anchorIsAlwaysLast() {
        let f = Explainer.factors(for: plan([.anchor(hour: 6.5), .cycleAlignment(shiftSeconds: 120)]),
                                  settings: settings)
        #expect(f.last?.kind == .anchor)
    }

    @Test func middleIsSortedByAbsoluteMagnitude() {
        let f = Explainer.factors(for: plan([.cycleAlignment(shiftSeconds: 120),
                                             .recoveryExtension(seconds: 1080, debt: 3, hrv: 0.9, strain: 1.1),
                                             .sleepNeedShortfall(seconds: 600)]),
                                  settings: settings)
        #expect(f.map(\.kind) == [.recovery, .shortfall, .cycle])
    }

    @Test func equalMagnitudeOrderIsDeterministic() {
        let reasons: [Engine.Reason] = [.cycleAlignment(shiftSeconds: 600), .circadianFloor(appliedSeconds: 600)]
        let a = Explainer.factors(for: plan(reasons), settings: settings)
        let b = Explainer.factors(for: plan(reasons.reversed()), settings: settings)
        #expect(a.map(\.kind) == b.map(\.kind))
    }

    @Test func emptyPlanYieldsNothing() {
        let f = Explainer.factors(for: plan([]), settings: settings)
        #expect(f.isEmpty)
        #expect(Explainer.dominant(f) == nil)
    }

    @Test func numbersAreScopedToTheirFactor() {
        let f = Explainer.factors(for: plan([.recoveryExtension(seconds: 900, debt: 2.5, hrv: 0.85, strain: 1.3)]),
                                  settings: settings)
        #expect(f[0].numbers.debtHours == 2.5)
        #expect(f[0].numbers.hrvRatio == 0.85)
        #expect(f[0].numbers.strainRatio == 1.3)
        #expect(f[0].numbers.toleranceSeconds == nil)
        #expect(f[0].numbers.anchorHour == nil)
    }

    @Test func dominantIsTheFirstFactor() {
        let f = Explainer.factors(for: plan([.cycleAlignment(shiftSeconds: 120),
                                             .recoveryExtension(seconds: 1080, debt: 3, hrv: 0.9, strain: 1.1)]),
                                  settings: settings)
        #expect(Explainer.dominant(f)?.kind == .recovery)
    }

    @Test func hardBoundCarriesTheDeadline() {
        let f = Explainer.factors(for: plan([.hardBoundClamp]), settings: settings)
        #expect(f[0].numbers.deadline == ring)
    }

    private func constraint(title: String = "Standup") -> CalendarConstraint.Constraint {
        CalendarConstraint.Constraint(eventTitle: title, eventStart: ring.addingTimeInterval(3600), bound: ring)
    }

    @Test func calendarBoundReplacesHardBoundAtTheHead() {
        let f = Explainer.factors(for: plan([.hardBoundClamp,
                                             .recoveryExtension(seconds: 1080, debt: 3, hrv: 0.9, strain: 1.1)]),
                                  settings: settings,
                                  calendarOutcome: .bound(constraint()))
        #expect(f.first?.kind == .calendarBound)
        #expect(!f.contains { $0.kind == .hardBound })
        #expect(f.first?.numbers.eventTitle == "Standup")
        #expect(f.first?.numbers.deadline == ring)
    }

    @Test func calendarTooEarlyIsStillReported() {
        let f = Explainer.factors(for: plan([]), settings: settings,
                                  calendarOutcome: .tooEarly(constraint(title: "Flight")))
        #expect(f.first?.kind == .calendarTooEarly)
        #expect(f.first?.numbers.eventTitle == "Flight")
        #expect(f.first?.shiftSeconds == 0)
        #expect(f.first?.numbers.deadline == nil)
    }

    @Test func noCalendarOutcomeLeavesHardBoundInCharge() {
        let f = Explainer.factors(for: plan([.hardBoundClamp, .cycleAlignment(shiftSeconds: 420)]),
                                  settings: settings, calendarOutcome: .none)
        #expect(f.first?.kind == .hardBound)
    }

    @Test func shiftMinutesKeepTheSign() {
        let f = Explainer.factors(for: plan([.cycleAlignment(shiftSeconds: -420), .anchor(hour: 7)]),
                                  settings: settings)
        #expect(Display.shiftMinutes(f[0]) == -7)
        #expect(Display.shiftMinutes(f[1]) == nil)
    }
}

// MARK: Bedtime

@Suite("Smart alarm bedtime")
struct ToolsSmartAlarmBedtimeTests {

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    @Test func lightsOutIsRingMinusNeedMinusLatency() {
        let r = Bedtime.reading(ring: date(17, 7), sleepNeedSeconds: Int(7.5 * 3600),
                                onsetLatencySeconds: 15 * 60, habitualLightsOut: nil)
        #expect(r.lightsOut == date(16, 23, 15))
    }

    @Test func lightsOutCrossesMidnightBackwards() {
        let r = Bedtime.reading(ring: date(17, 1), sleepNeedSeconds: 8 * 3600,
                                onsetLatencySeconds: 15 * 60, habitualLightsOut: nil)
        #expect(r.lightsOut == date(16, 16, 45))
    }

    @Test func timeInBedIsNeedPlusLatency() {
        let r = Bedtime.reading(ring: date(17, 7), sleepNeedSeconds: 7 * 3600,
                                onsetLatencySeconds: 15 * 60, habitualLightsOut: nil)
        #expect(r.timeInBedSeconds == 7 * 3600 + 15 * 60)
    }

    @Test func noHabitGivesNoDelta() {
        let r = Bedtime.reading(ring: date(17, 7), sleepNeedSeconds: 7 * 3600,
                                onsetLatencySeconds: 15 * 60, habitualLightsOut: nil)
        #expect(r.deltaVsHabitSeconds == nil)
        #expect(r.deltaVsHabit == nil)
    }

    @Test func earlierThanHabitIsNegative() throws {
        let r = Bedtime.reading(ring: date(17, 7), sleepNeedSeconds: Int(7.5 * 3600),
                                onsetLatencySeconds: 15 * 60, habitualLightsOut: date(16, 23, 40))
        #expect(near(try #require(r.deltaVsHabitSeconds), -25 * 60, 0.5))
        #expect(r.deltaVsHabit == .earlier(seconds: 25 * 60))
    }

    @Test func laterThanHabitIsPositive() throws {
        let r = Bedtime.reading(ring: date(17, 7), sleepNeedSeconds: Int(7.5 * 3600),
                                onsetLatencySeconds: 15 * 60, habitualLightsOut: date(16, 22, 45))
        #expect(near(try #require(r.deltaVsHabitSeconds), 30 * 60, 0.5))
        #expect(r.deltaVsHabit == .later(seconds: 30 * 60))
    }

    @Test func withinFiveMinutesReadsAsOnHabit() {
        let r = Bedtime.reading(ring: date(17, 7), sleepNeedSeconds: Int(7.5 * 3600),
                                onsetLatencySeconds: 15 * 60, habitualLightsOut: date(16, 23, 12))
        #expect(r.deltaVsHabit == .onHabit)
    }
}

// MARK: Bedtime schedule

@Suite("Smart alarm bedtime schedule")
struct ToolsSmartAlarmBedtimeScheduleTests {

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute, second: second))!
    }

    /// 2026-08-16 is a Sunday, so 2026-08-17 is a Monday (weekday 2).
    private func schedule(enabled: Bool = true, lead: Double = 30,
                          weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]) -> BedtimeSchedule.Schedule {
        .init(reminderEnabled: enabled, leadMinutes: lead, activeWeekdays: weekdays,
              wakeMinutes: 7 * 60, sleepNeedSeconds: Int(7.5 * 3600), onsetLatencySeconds: 15 * 60)
    }

    @Test func nothingScheduledWhenTheReminderIsOff() {
        #expect(BedtimeSchedule.slots(for: schedule(enabled: false), tonight: nil,
                                      now: date(16, 20), calendar: utc).isEmpty)
    }

    @Test func nothingScheduledWithNoActiveWeekday() {
        #expect(BedtimeSchedule.slots(for: schedule(weekdays: []), tonight: nil,
                                      now: date(16, 20), calendar: utc).isEmpty)
    }

    @Test func allWeekGivesOneSlotPerHorizonNight() {
        let slots = BedtimeSchedule.slots(for: schedule(), tonight: nil, now: date(16, 20), calendar: utc)
        #expect(slots.count == BedtimeSchedule.horizonNights)
        #expect(Set(slots.map(\.index)).count == slots.count)
    }

    @Test func onlyNightsWhoseMorningIsActiveAreKept() {
        let slots = BedtimeSchedule.slots(for: schedule(weekdays: [2]), tonight: nil,
                                          now: date(16, 20), calendar: utc)
        #expect(slots.count == 1)
        #expect(slots.first?.ring == date(17, 7))
    }

    @Test func leadMovesTheFireDateEarlier() throws {
        let slots = BedtimeSchedule.slots(for: schedule(lead: 45), tonight: nil, now: date(16, 20), calendar: utc)
        let first = try #require(slots.first)
        #expect(first.lightsOut == date(16, 23, 15))
        #expect(first.fireDate == date(16, 22, 30))
    }

    @Test func everyFireDateIsInTheFuture() {
        let slots = BedtimeSchedule.slots(for: schedule(), tonight: nil, now: date(16, 23, 30), calendar: utc)
        #expect(slots.allSatisfy { $0.fireDate > date(16, 23, 30) })
        #expect(slots.count == BedtimeSchedule.horizonNights)
    }

    /// A trigger drops the seconds, so a fire date 30 s ahead is too late.
    @Test func fireDateNeedsAtLeastAMinuteOfMargin() throws {
        let now = date(16, 22, 44, 30)
        let slots = BedtimeSchedule.slots(for: schedule(), tonight: nil, now: now, calendar: utc)
        #expect(slots.allSatisfy { $0.fireDate > now.addingTimeInterval(60) })
        #expect(slots.count == BedtimeSchedule.horizonNights)
        #expect(try #require(slots.first).ring == date(18, 7))
    }

    @Test func tonightUsesTheRealPlanWhenThereIsOne() throws {
        let tonight = Bedtime.reading(ring: date(17, 6, 30), sleepNeedSeconds: Int(7.5 * 3600),
                                      onsetLatencySeconds: 15 * 60, habitualLightsOut: nil)
        let slots = BedtimeSchedule.slots(for: schedule(), tonight: tonight, now: date(16, 20), calendar: utc)
        #expect(try #require(slots.first).ring == date(17, 6, 30))
        #expect(try #require(slots.dropFirst().first).ring == date(18, 7))
    }
}

// MARK: Settings

@Suite("Smart alarm settings")
struct ToolsSmartAlarmSettingsTests {

    private func decode(_ json: String) -> Settings {
        Settings.decoded(from: Data(json.utf8))
    }

    @Test func calendarAwarenessIsOffUntilTheUserTurnsItOn() {
        #expect(!Settings.default.calendarAware)
        #expect(!Settings.decoded(from: nil).calendarAware)
    }

    @Test func missingDataFallsBackToTheSeed() {
        var seed = Settings.default
        seed.wakeMinutes = 7 * 60 + 15
        let settings = Settings.decoded(from: nil, seed: seed)
        #expect(!settings.isEnabled)
        #expect(settings.snoozeMinutes == 9)
        #expect(settings.wakeMinutes == 7 * 60 + 15)
    }

    @Test func roundTrips() {
        var settings = Settings.default
        settings.isEnabled = true
        settings.wakeMinutes = 6 * 60 + 45
        settings.earlyWindowMinutes = 60
        settings.calendarAware = true
        settings.calendarPrepMinutes = 90
        settings.activeWeekdays = [2, 3, 4, 5, 6]
        settings.snoozeEnabled = false
        #expect(Settings.decoded(from: settings.encoded()) == settings)
    }

    @Test func partialBlobDoesNotWipeSettings() {
        let settings = decode(#"{"isEnabled":true,"wakeMinutes":400}"#)
        #expect(settings.isEnabled)
        #expect(settings.wakeMinutes == 400)
        #expect(settings.snoozeMinutes == 9)
        #expect(settings.activeWeekdays == Settings.default.activeWeekdays)
        #expect(settings.earlyWindowMinutes == Settings.default.earlyWindowMinutes)
        #expect(settings.calendarAware == Settings.default.calendarAware)
        #expect(settings.calendarPrepMinutes == Settings.default.calendarPrepMinutes)
    }

    @Test func legacyOptimizedBlobBecomesTheWidestEarlyWindow() {
        let settings = decode(#"{"isEnabled":true,"wakeMinutes":420,"mode":{"optimized":true},"snoozeMinutes":9}"#)
        #expect(settings.isEnabled)
        #expect(settings.wakeMinutes == 420)
        #expect(settings.earlyWindowMinutes == Settings.maxEarlyWindowMinutes)
    }

    @Test func legacyWindowBlobKeepsItsFlexAsEarlyLatitude() {
        let settings = decode(#"{"isEnabled":true,"wakeMinutes":420,"mode":{"window":30},"snoozeMinutes":9}"#)
        #expect(settings.earlyWindowMinutes == 30)
    }

    @Test(arguments: [#"{"wakeMinutes":420,"mode":{"window":90}}"#,
                      #"{"wakeMinutes":420,"mode":{"optimized":true}}"#,
                      #"{"wakeMinutes":420}"#])
    func migrationNeverRingsLaterThanTheStoredWakeTime(blob: String) {
        let settings = decode(blob)
        #expect(settings.wakeMinutes == 420)
        #expect(settings.earlyWindowMinutes >= 0)
    }

    @Test func malformedLegacyModeFallsBackWithoutLosingOtherFields() {
        let settings = decode(#"{"isEnabled":true,"wakeMinutes":400,"mode":"optimized"}"#)
        #expect(settings.isEnabled)
        #expect(settings.wakeMinutes == 400)
        #expect(settings.earlyWindowMinutes == Settings.default.earlyWindowMinutes)
    }

    @Test func slidersAreClampedThroughARoundTrip() {
        var high = Settings.default
        high.earlyWindowMinutes = 500
        high.calendarPrepMinutes = 500
        let loadedHigh = Settings.decoded(from: high.encoded())
        #expect(loadedHigh.earlyWindowMinutes == Settings.maxEarlyWindowMinutes)
        #expect(loadedHigh.calendarPrepMinutes == Settings.maxCalendarPrepMinutes)

        var low = Settings.default
        low.earlyWindowMinutes = -50
        low.calendarPrepMinutes = 1
        let loadedLow = Settings.decoded(from: low.encoded())
        #expect(loadedLow.earlyWindowMinutes == Settings.minEarlyWindowMinutes)
        #expect(loadedLow.calendarPrepMinutes == Settings.minCalendarPrepMinutes)
    }

    @Test func zeroEarlyWindowSurvivesTheRoundTrip() {
        var settings = Settings.default
        settings.earlyWindowMinutes = 0
        #expect(Settings.decoded(from: settings.encoded()).earlyWindowMinutes == 0)
    }

    @Test func bedtimeReminderIsOffByDefault() {
        #expect(!Settings.default.bedtimeReminderEnabled)
        #expect(Settings.default.bedtimeReminderLeadMinutes == 30)
    }

    @Test func leadIsClampedThroughARoundTrip() {
        var settings = Settings.default
        settings.bedtimeReminderLeadMinutes = 999
        #expect(Settings.decoded(from: settings.encoded()).bedtimeReminderLeadMinutes
                == Settings.maxBedtimeLeadMinutes)
    }

    @Test func aBlobWithoutTheBedtimeFieldsKeepsEveryOtherSetting() {
        let loaded = decode("""
        {"isEnabled":true,"wakeMinutes":330,"earlyWindowMinutes":20,\
        "calendarAware":false,"calendarPrepMinutes":60,"activeWeekdays":[2,3],\
        "snoozeEnabled":false,"snoozeMinutes":5}
        """)
        #expect(loaded.isEnabled)
        #expect(loaded.wakeMinutes == 330)
        #expect(loaded.snoozeMinutes == 5)
        #expect(!loaded.bedtimeReminderEnabled)
        #expect(loaded.bedtimeReminderLeadMinutes == 30)
    }
}

// MARK: Calendar constraint

@Suite("Smart alarm calendar constraint")
struct ToolsSmartAlarmCalendarConstraintTests {

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        losAngeles.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, start: Date, isAllDay: Bool = false,
                       accepted: Bool = true) -> CalendarConstraint.Event {
        CalendarConstraint.Event(title: title, start: start, isAllDay: isAllDay, accepted: accepted)
    }

    /// Reference wake: 15 June 2026, 07:00.
    private var wake: Date { date(15, 7) }
    private let prep: Double = 60 * 60

    private func outcome(_ events: [CalendarConstraint.Event], prep: Double? = nil) -> CalendarConstraint.Outcome {
        CalendarConstraint.outcome(events: events, wake: wake, prepSeconds: prep ?? self.prep, calendar: losAngeles)
    }

    @Test func noEventsYieldsNone() {
        #expect(outcome([]) == .none)
    }

    @Test func allDayEventDoesNotConstrain() {
        #expect(outcome([event("Off", start: date(15, 0), isAllDay: true)]) == .none)
    }

    @Test func declinedEventDoesNotConstrain() {
        #expect(outcome([event("Standup", start: date(15, 9), accepted: false)]) == .none)
    }

    @Test func afternoonEventDoesNotConstrain() {
        #expect(outcome([event("Review", start: date(15, 15))]) == .none)
    }

    @Test func eventOnAnotherDayDoesNotConstrain() {
        #expect(outcome([event("Standup", start: date(16, 9))]) == .none)
    }

    @Test func boundIsEventStartMinusPrep() {
        let result = outcome([event("Standup", start: date(15, 9, 30))])
        guard case .bound(let constraint) = result else {
            Issue.record("expected .bound, got \(result)")
            return
        }
        #expect(constraint.eventTitle == "Standup")
        #expect(constraint.eventStart == date(15, 9, 30))
        #expect(constraint.bound == date(15, 8, 30))
    }

    @Test func earliestMorningEventWins() {
        let result = outcome([event("Review", start: date(15, 11)),
                              event("Standup", start: date(15, 8)),
                              event("Sync", start: date(15, 9, 30))])
        guard case .bound(let constraint) = result else {
            Issue.record("expected .bound, got \(result)")
            return
        }
        #expect(constraint.eventTitle == "Standup")
        #expect(constraint.bound == date(15, 7))
    }

    @Test func equalStartsBreakOnTheTitle() {
        let result = outcome([event("Zed", start: date(15, 8)), event("Alpha", start: date(15, 8))])
        guard case .bound(let constraint) = result else {
            Issue.record("expected .bound, got \(result)")
            return
        }
        #expect(constraint.eventTitle == "Alpha")
    }

    @Test func zeroPrepBoundsAtTheEventItself() {
        let result = outcome([event("Standup", start: date(15, 8))], prep: 0)
        guard case .bound(let constraint) = result else {
            Issue.record("expected .bound, got \(result)")
            return
        }
        #expect(constraint.bound == date(15, 8))
    }

    @Test func boundBelowTheFloorIsReportedButNotApplied() {
        let result = outcome([event("Flight", start: date(15, 4, 30))])
        guard case .tooEarly(let constraint) = result else {
            Issue.record("expected .tooEarly, got \(result)")
            return
        }
        #expect(constraint.eventTitle == "Flight")
        #expect(constraint.bound == date(15, 3, 30))
    }

    @Test func boundExactlyOnTheFloorStillApplies() {
        let result = outcome([event("Flight", start: date(15, 5))])
        guard case .bound(let constraint) = result else {
            Issue.record("expected .bound, got \(result)")
            return
        }
        #expect(constraint.bound == date(15, 4))
    }

    @Test func midnightEventWouldBoundThePreviousEveningAndIsRejected() {
        let result = outcome([event("On call", start: date(15, 0, 30))])
        guard case .tooEarly(let constraint) = result else {
            Issue.record("expected .tooEarly, got \(result)")
            return
        }
        #expect(constraint.bound == date(14, 23, 30))
    }
}

// MARK: Planner

@Suite("Smart alarm planner")
struct ToolsSmartAlarmPlannerTests {

    private func la(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        losAngeles.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func wallClock(_ instant: Date) -> (day: Int, hour: Int, minute: Int) {
        let c = losAngeles.dateComponents([.day, .hour, .minute], from: instant)
        return (c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Daylight saving

    /// 8 March 2026 has 23 hours: midnight plus 7 h of seconds would be 08:00.
    @Test func springForwardKeepsTheWallClockWakeTime() {
        let result = Planner.nextOccurrence(ofMinutes: 7 * 60, after: la(2026, 3, 7, 12, 0),
                                            weekdays: [], calendar: losAngeles)
        let clock = wallClock(result)
        #expect(clock.day == 8)
        #expect(clock.hour == 7)
        #expect(clock.minute == 0)
    }

    @Test func fallBackKeepsTheWallClockWakeTime() {
        let result = Planner.nextOccurrence(ofMinutes: 7 * 60, after: la(2026, 10, 31, 12, 0),
                                            weekdays: [], calendar: losAngeles)
        let clock = wallClock(result)
        #expect(clock.day == 1)
        #expect(clock.hour == 7)
        #expect(clock.minute == 0)
    }

    @Test func springForwardWithAWakeTimeInsideTheLostHour() {
        let after = la(2026, 3, 7, 12, 0)
        let result = Planner.nextOccurrence(ofMinutes: 2 * 60 + 30, after: after, weekdays: [], calendar: losAngeles)
        #expect(result > after)
    }

    @Test func neverReturnsAnInstantInThePast() {
        let after = la(2026, 6, 15, 9, 0)
        let result = Planner.nextOccurrence(ofMinutes: 7 * 60, after: after, weekdays: [], calendar: losAngeles)
        #expect(result > after)
        #expect(wallClock(result).day == 16)
        #expect(wallClock(result).hour == 7)
    }

    @Test func restrictsToActiveWeekdays() {
        // 2026-06-15 is a Monday; Saturday only lands on the 20th.
        let result = Planner.nextOccurrence(ofMinutes: 6 * 60 + 45, after: la(2026, 6, 15, 9, 0),
                                            weekdays: [7], calendar: losAngeles)
        #expect(losAngeles.component(.weekday, from: result) == 7)
        #expect(wallClock(result).day == 20)
        #expect(wallClock(result).hour == 6)
        #expect(wallClock(result).minute == 45)
    }

    @Test func emptyWeekdaySetAcceptsToday() {
        let result = Planner.nextOccurrence(ofMinutes: 22 * 60, after: la(2026, 6, 15, 9, 0),
                                            weekdays: [], calendar: losAngeles)
        #expect(wallClock(result).day == 15)
        #expect(wallClock(result).hour == 22)
    }

    // MARK: Calendar bound

    private func constraint(bound: Date) -> CalendarConstraint.Constraint {
        CalendarConstraint.Constraint(eventTitle: "Standup", eventStart: bound.addingTimeInterval(3600), bound: bound)
    }

    @Test func calendarBoundOnlyMovesEarlierAndOnlyWhenBinding() {
        let wake = la(2026, 6, 15, 7, 0)
        let earlier = la(2026, 6, 15, 6, 30)
        #expect(Planner.hardBound(wake: wake, outcome: .bound(constraint(bound: earlier))) == earlier)
        #expect(Planner.hardBound(wake: wake, outcome: .bound(constraint(bound: la(2026, 6, 15, 10, 0)))) == wake)
        #expect(Planner.hardBound(wake: wake, outcome: .tooEarly(constraint(bound: la(2026, 6, 15, 3, 30)))) == wake)
        #expect(Planner.hardBound(wake: wake, outcome: .none) == wake)
    }

    @Test func calendarAwareOffIgnoresEvents() {
        var settings = Settings.default
        settings.calendarAware = false
        let wake = la(2026, 6, 15, 7, 0)
        let standup = CalendarConstraint.Event(title: "Standup", start: la(2026, 6, 15, 8, 0))
        #expect(Planner.calendarOutcome(settings: settings, wake: wake, events: [standup],
                                        calendar: losAngeles) == .none)
    }

    @Test func calendarAwareOnReadsTheEvents() {
        var settings = Settings.default
        settings.calendarAware = true
        settings.calendarPrepMinutes = 60
        let wake = la(2026, 6, 15, 7, 0)
        let standup = CalendarConstraint.Event(title: "Standup", start: la(2026, 6, 15, 8, 0))
        let outcome = Planner.calendarOutcome(settings: settings, wake: wake, events: [standup], calendar: losAngeles)
        guard case .bound(let c) = outcome else {
            Issue.record("expected .bound, got \(outcome)")
            return
        }
        #expect(c.bound == wake)
        #expect(Planner.hardBound(wake: wake, outcome: outcome) == wake)
    }

    // MARK: Freshness of the observed night

    @Test func lastNightIsRejectedForTonightsAlarm() {
        #expect(!Planner.belongsToNight(endingAt: la(2026, 6, 15, 7, 0), onset: la(2026, 6, 13, 23, 30)))
    }

    @Test func tonightsOnsetIsAccepted() {
        #expect(Planner.belongsToNight(endingAt: la(2026, 6, 15, 7, 0), onset: la(2026, 6, 14, 23, 30)))
    }

    @Test func onsetWindowEdges() {
        let alarm = la(2026, 6, 15, 7, 0)
        #expect(Planner.belongsToNight(endingAt: alarm,
                                       onset: alarm.addingTimeInterval(-Planner.maxObservedNightSpanSeconds)))
        #expect(!Planner.belongsToNight(endingAt: alarm,
                                        onset: alarm.addingTimeInterval(-Planner.maxObservedNightSpanSeconds - 60)))
        #expect(!Planner.belongsToNight(endingAt: alarm, onset: alarm.addingTimeInterval(60)))
        #expect(!Planner.belongsToNight(endingAt: alarm, onset: alarm))
    }

    // MARK: Assembly

    private func d(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    /// Monday 2026-06-15, 22:00: the plan is for Tuesday morning at 07:00.
    private var now: Date { d(15, 22) }
    private var wake: Date { d(16, 7) }

    private func settings(calendarAware: Bool = false) -> Settings {
        var s = Settings.default
        s.isEnabled = true
        s.wakeMinutes = 7 * 60
        s.activeWeekdays = []
        s.earlyWindowMinutes = 45
        s.calendarAware = calendarAware
        s.calendarPrepMinutes = 45
        return s
    }

    private func regularSleeper() -> Planner.Signals {
        Planner.Signals(anchorWakeHour: 7, regularity: 100, habitualBedHour: 23,
                        sleepNeedSeconds: 8 * 3600, sleepDebtHours: 2,
                        hrvBaseline: 50, overnightHRV: 40,
                        strainToday: 60, strainSeries: [nil, 30, 0, 30, 30, 60])
    }

    private func plan(_ signals: Planner.Signals, settings: Settings? = nil,
                      events: [CalendarConstraint.Event] = []) -> Planner.Outcome {
        Planner.plan(settings: settings ?? self.settings(), signals: signals, events: events,
                     now: now, calendar: utc)
    }

    private func recovery(_ plan: Engine.Plan) -> (debt: Double, hrv: Double, strain: Double)? {
        for reason in plan.reasons {
            if case .recoveryExtension(_, let debt, let hrv, let strain) = reason { return (debt, hrv, strain) }
        }
        return nil
    }

    @Test func withoutHistoryTheAlarmRingsOnTheSetTime() {
        let outcome = plan(Planner.Signals())
        #expect(outcome.plan.ring == wake)
        #expect(outcome.plan.window == wake.addingTimeInterval(-45 * 60)...wake)
        #expect(outcome.plan.source == .deadline)
        #expect(outcome.calendar == .none)
        #expect(outcome.bedtime.ring == wake)
        #expect(outcome.bedtime.lightsOut == wake.addingTimeInterval(-8 * 3600 - Engine.defaultOnsetLatencySeconds))
        #expect(outcome.bedtime.habitualLightsOut == nil)
    }

    @Test func aDegenerateSleepNeedIsFlooredAtOneHour() {
        let outcome = plan(Planner.Signals(sleepNeedSeconds: -600))
        #expect(outcome.bedtime.sleepNeedSeconds == 3600)
        #expect(outcome.bedtime.lightsOut == wake.addingTimeInterval(-3600 - Engine.defaultOnsetLatencySeconds))
    }

    @Test func recoverySignalsReachTheEngine() throws {
        let outcome = plan(regularSleeper())
        guard case .anchor(let hour)? = outcome.plan.reasons.first else {
            Issue.record("a regular sleeper anchors the ring")
            return
        }
        #expect(near(hour, 7, 1e-6))
        let signals = try #require(recovery(outcome.plan))
        #expect(signals.debt == 2)
        #expect(near(signals.hrv, 0.8, 1e-9))
        #expect(near(signals.strain, 2, 1e-9), "today 60 over the mean of the earlier positive days (30)")
        #expect(outcome.bedtime.habitualLightsOut == d(15, 23))
        #expect(outcome.plan.ring <= wake)
    }

    @Test func aSleepCreditNeverShortensTheNight() {
        var signals = regularSleeper()
        signals.sleepDebtHours = -3
        #expect(recovery(plan(signals).plan)?.debt == 0)
    }

    @Test func noHRVBaselineReadsAsNormal() {
        var signals = regularSleeper()
        signals.hrvBaseline = 0
        #expect(recovery(plan(signals).plan)?.hrv == 1)
    }

    @Test func strainIsNeutralWithoutEnoughHistoryOrWithoutToday() {
        var short = regularSleeper()
        short.strainSeries = [30, 30, 60]
        #expect(recovery(plan(short).plan)?.strain == 1, "two earlier days are not a habit")
        var rest = regularSleeper()
        rest.strainToday = 0
        #expect(recovery(plan(rest).plan)?.strain == 1)
        var none = regularSleeper()
        none.strainSeries = nil
        #expect(recovery(plan(none).plan)?.strain == 1)
    }

    private func standup(at start: Date) -> CalendarConstraint.Event {
        CalendarConstraint.Event(title: "Standup", start: start)
    }

    @Test func aMorningMeetingPullsTheHardBoundForward() {
        let events = [standup(at: d(16, 7, 30))]
        let outcome = plan(Planner.Signals(), settings: settings(calendarAware: true), events: events)
        let expected = CalendarConstraint.outcome(events: events, wake: wake, prepSeconds: 45 * 60, calendar: utc)
        #expect(outcome.calendar == expected)
        #expect(outcome.plan.window.upperBound == d(16, 6, 45))
        #expect(outcome.plan.window.lowerBound == d(16, 6))
    }

    @Test func theCalendarIsIgnoredWhenTheToggleIsOff() {
        let outcome = plan(Planner.Signals(), settings: settings(calendarAware: false),
                           events: [standup(at: d(16, 7, 30))])
        #expect(outcome.calendar == .none)
        #expect(outcome.plan.window.upperBound == wake)
    }

    private var cycleNight: [Span] {
        let stages: [(String, Double)] = [("awake", 300), ("core", 1800), ("deep", 2400), ("core", 900),
                                          ("rem", 1200), ("core", 1800), ("deep", 1200), ("core", 900),
                                          ("rem", 1800), ("awake", 120), ("core", 2400), ("rem", 1500)]
        return stages.map { Span(stage: $0.0, seconds: $0.1) }
    }

    /// The engine inputs `regularSleeper()` must produce with a night observed
    /// from `bed`, written out field by field.
    private func observedInputs(bed: Date, spans: [Span]) -> Engine.Inputs {
        var inputs = Engine.Inputs(
            earliest: wake.addingTimeInterval(-45 * 60), latest: wake,
            anchorWakeHour: 7, regularity: 100, cbtMinHour: nil,
            sleepNeedSeconds: 8 * 3600, debtHours: 2, hrvRatio: 0.8, strainRatio: 2,
            onset: bed, onsetLatencySeconds: Engine.defaultOnsetLatencySeconds,
            meanCycleSeconds: SomaTools.SleepCycleModel.meanCycleSeconds(spans),
            observedSpans: spans, observedOnset: bed, priority: .balanced)
        inputs.calendar = utc
        return inputs
    }

    @Test func tonightsRecordedNightDrivesTheEngine() {
        var signals = regularSleeper()
        let bed = d(15, 23, 10)
        signals.observedNight = Planner.ObservedNight(spans: cycleNight, onset: bed)
        let observed = plan(signals)
        #expect(observed.inputs == observedInputs(bed: bed, spans: cycleNight))
        #expect(observed.plan == Engine.plan(observedInputs(bed: bed, spans: cycleNight)))
        #expect(!SomaTools.SleepCycleModel.cycles(from: cycleNight).isEmpty)
    }

    @Test func aNightTooOldForTheRingIsIgnored() {
        var stale = regularSleeper()
        stale.observedNight = Planner.ObservedNight(
            spans: cycleNight, onset: wake.addingTimeInterval(-(Planner.maxObservedNightSpanSeconds + 60)))
        var empty = regularSleeper()
        empty.observedNight = Planner.ObservedNight(spans: [], onset: d(15, 23))
        let estimated = plan(regularSleeper())
        #expect(plan(stale).plan == estimated.plan)
        #expect(plan(empty).plan == estimated.plan)
    }

    @Test func aNightOfOneAwakeSpanStillReachesTheEngineWithItsOwnOnset() {
        var signals = regularSleeper()
        let bed = d(16, 6, 50)
        let spans = [Span(stage: "awake", seconds: 300)]
        signals.observedNight = Planner.ObservedNight(spans: spans, onset: bed)
        let outcome = plan(signals)
        #expect(outcome.plan == Engine.plan(observedInputs(bed: bed, spans: spans)))
        #expect(outcome.inputs.observedOnset == bed)
    }

    // MARK: Reason kind

    private func labelPlan(_ reasons: [Engine.Reason]) -> Engine.Plan {
        Engine.Plan(ring: wake, window: wake...wake, source: .predicted, reasons: reasons)
    }

    @Test func reasonKindNamesTheFactorThatActuallyPlacedTheRing() {
        let cases: [([Engine.Reason], Planner.ReasonKind)] = [
            ([], .anchor),
            ([.anchor(hour: 7), .hardBoundClamp], .anchor),
            ([.anchor(hour: 7), .cycleAlignment(shiftSeconds: -300), .hardBoundClamp], .cycle),
            ([.recoveryExtension(seconds: 600, debt: 1, hrv: 1, strain: 1)], .recovery),
            ([.recoveryExtension(seconds: 600, debt: 1, hrv: 1, strain: 1), .circadianFloor(appliedSeconds: 60)],
             .phase),
            ([.regularityClamp(shiftSeconds: 120, toleranceSeconds: 1200)], .regularity),
            ([.sleepNeedShortfall(seconds: 900)], .shortfall)
        ]
        for (reasons, expected) in cases {
            #expect(Planner.reasonKind(for: labelPlan(reasons)) == expected, "\(reasons)")
        }
    }

    @Test func aBindingMeetingLeadsTheReasonButATooEarlyOneDoesNot() {
        let constraint = CalendarConstraint.Constraint(eventTitle: "Standup", eventStart: wake,
                                                       bound: wake.addingTimeInterval(-2700))
        let p = labelPlan([.cycleAlignment(shiftSeconds: -300)])
        #expect(Planner.reasonKind(for: p, calendarOutcome: .bound(constraint)) == .calendar(eventTitle: "Standup"))
        #expect(Planner.reasonKind(for: p, calendarOutcome: .tooEarly(constraint)) == .cycle)
    }
}

// MARK: Alarm card helpers

@Suite("Smart alarm display")
struct ToolsSmartAlarmDisplayTests {

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    private func window(ring: Date, needSeconds: Int) -> Display.HourWindow {
        Display.cardWindow(ring: ring, sleepNeedSeconds: needSeconds, calendar: utc)
    }

    /// Ring 07:12, need eight hours: lights out 22:57 the evening before, the
    /// card opens at 21:00 and closes at 08:00.
    @Test func middayIsOutsideTheWindow() {
        let w = window(ring: date(11, 7, 12), needSeconds: 8 * 3600)
        #expect(w.startHour == 21)
        #expect(w.endHour == 8)
        #expect(!w.contains(hour: 12))
        #expect(!w.contains(hour: 9))
        #expect(!w.contains(hour: 20))
        #expect(w.contains(hour: 22))
        #expect(w.contains(hour: 3))
        #expect(w.contains(hour: 7))
    }

    @Test func windowWrapsPastMidnightOnALateRing() {
        let w = window(ring: date(11, 23, 40), needSeconds: 8 * 3600)
        #expect(w.endHour == 0)
        #expect(w.contains(hour: 23))
        #expect(!w.contains(hour: 0))
        #expect(!w.contains(hour: 12))
    }

    @Test(arguments: [0, -3600, 60])
    func degenerateSleepNeedStillLeavesARealWindow(need: Int) {
        let w = window(ring: date(11, 7, 12), needSeconds: need)
        #expect(w.startHour != w.endHour)
        #expect(w.contains(hour: 7))
        #expect(!w.contains(hour: 12))
    }

    @Test func absurdSleepNeedIsCappedAtTwelveHoursOfLead() {
        let w = window(ring: date(11, 7, 12), needSeconds: 20 * 3600)
        #expect(w.startHour == 19)
        #expect(w.endHour == 8)
        #expect(!w.contains(hour: 12))
    }

    private func moment(_ now: Date, ring: Date, need: Int = 8 * 3600) -> Display.Moment {
        let lightsOut = Bedtime.reading(ring: ring, sleepNeedSeconds: need).lightsOut
        return Display.moment(now: now, ring: ring, lightsOut: lightsOut)
    }

    @Test func theDetailLineFollowsTheNight() {
        let ring = date(11, 7, 12)
        #expect(moment(date(10, 21, 57), ring: ring) == .beforeLightsOut(minutes: 60))
        #expect(moment(date(11, 3, 12), ring: ring) == .beforeRing(minutes: 240))
        #expect(moment(date(11, 7, 0), ring: ring) == .atRing)
        #expect(moment(date(11, 7, 50), ring: ring) == .afterRing(minutes: 38))
    }

    @Test func theNowStateIsHalfAnHourEachSide() {
        let ring = date(11, 7, 12)
        #expect(moment(date(11, 6, 42), ring: ring) == .atRing)
        #expect(moment(date(11, 6, 41), ring: ring) == .beforeRing(minutes: 31))
        #expect(moment(date(11, 7, 42), ring: ring) == .atRing)
        #expect(moment(date(11, 7, 43), ring: ring) == .afterRing(minutes: 31))
    }

    @Test func middayReadsAsBeforeLightsOutNotAsATwentyHourCountdown() {
        #expect(moment(date(10, 12, 0), ring: date(11, 7, 12)) == .beforeLightsOut(minutes: 657))
    }

    @Test func ringDayIsRelativeToNow() {
        let now = date(10, 22, 0)
        #expect(Display.ringDay(date(10, 23, 0), now: now, calendar: utc) == .today)
        #expect(Display.ringDay(date(11, 7, 0), now: now, calendar: utc) == .tomorrow)
        // 2026-03-13 is a Friday (weekday 6).
        #expect(Display.ringDay(date(13, 7, 0), now: now, calendar: utc) == .weekday(6))
    }
}
