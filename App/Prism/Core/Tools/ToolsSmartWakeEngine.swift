//
//  ToolsSmartWakeEngine.swift
//  Prism
//
//  The smart alarm engine: turns a description of the coming night into a
//  ring instant, inside bounds the user has set. Pure, no I/O: no HealthKit,
//  no AlarmKit, no SwiftUI. The ultradian science comes from SleepCycleModel;
//  this file only composes and arbitrates.
//
//  Non-negotiable contract: `plan(_:).ring` NEVER passes `inputs.latest`. That
//  is the user's life constraint (work, school, the first meeting of the
//  morning) and no signal or recovery extension can get around it.
//
//  One decision path. The early latitude lives in the bounds the planner
//  computes (`earliest`), not in a branch of the engine. The user's goal
//  (`Inputs.priority`) REWEIGHTS steps 3, 4 and 6; it skips none and adds
//  none. `.balanced` returns the historical constants, so the default plan is
//  identical to the one from before that setting. See `Weights`.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartWakeEngine {

        // MARK: - Inputs

        nonisolated struct Inputs: Sendable, Equatable {
            /// Hard bounds. `latest` is the user's life constraint, `earliest`
            /// the early latitude it grants. Equal bounds give a fixed alarm.
            var earliest: Date
            var latest: Date

            /// Regularity anchor, clock hour 0..<24, a circular mean.
            var anchorWakeHour: Double?
            /// Circadian regularity factor, 0...100.
            var regularity: Double?
            /// CBTmin, clock hour 0..<24. Circular arithmetic required.
            var cbtMinHour: Double?

            var sleepNeedSeconds: Int
            /// Current debt in hours, always >= 0.
            var debtHours: Double
            /// Overnight HRV divided by the baseline. 1.0 = normal.
            var hrvRatio: Double
            /// Yesterday's strain divided by the usual load. 1.0 = normal.
            var strainRatio: Double

            /// Onset of the coming night (estimated) or of the current one (observed).
            var onset: Date?
            var onsetLatencySeconds: Double
            /// Cycle length measured on history. Never a hard-coded 90 min.
            var meanCycleSeconds: Double?

            /// Segments of the current night. Empty when it is not observed.
            var observedSpans: [SleepCycleModel.StageSpan]
            var observedOnset: Date?

            /// What the user asks the alarm to optimise. Defaulted so a caller
            /// that ignores it keeps exactly the previous result.
            var priority: SmartAlarmPriority = .balanced

            /// Calendar used to place clock hours (anchor, CBTmin) on dates.
            var calendar: Calendar = .current
        }

        // MARK: - Outputs

        nonisolated enum Source: Sendable, Equatable {
            /// No cycle signal used. Without a regularity anchor this implies
            /// `ring == latest`: the alarm lands on the bound.
            case deadline
            case predicted
            case observed
        }

        nonisolated enum Reason: Sendable, Equatable {
            case anchor(hour: Double)
            case sleepNeedShortfall(seconds: Double)
            case recoveryExtension(seconds: Double, debt: Double, hrv: Double, strain: Double)
            case circadianFloor(appliedSeconds: Double)
            case cycleAlignment(shiftSeconds: Double)
            case regularityClamp(shiftSeconds: Double, toleranceSeconds: Double)
            case hardBoundClamp
        }

        nonisolated struct Plan: Sendable, Equatable {
            var ring: Date
            var window: ClosedRange<Date>
            var source: Source
            var reasons: [Reason]
        }

        // MARK: - Settings

        static let maxRecoveryExtensionSeconds: Double = 30 * 60
        static let debtSaturationHours: Double = 5
        static let hrvSaturationDrop: Double = 0.20
        static let strainSaturationRise: Double = 0.30
        static let circadianFloorSeconds: Double = 60 * 60
        static let minToleranceSeconds: Double = 20 * 60
        static let maxToleranceSeconds: Double = 45 * 60
        static let defaultToleranceSeconds: Double = 30 * 60
        static let defaultOnsetLatencySeconds: Double = 15 * 60

        // MARK: - Weighting by goal

        /// What a goal may change, and nothing else: the extension budget
        /// (step 3), the tolerance around the anchor (step 6), and the
        /// authority of the circadian floor over that tolerance (steps 4 and
        /// 6). No goal touches the bounds: step 7 clamps after everyone.
        nonisolated struct Weights: Sendable, Equatable {
            /// Weights of the three signals in the extension severity. They
            /// sum to 1, so severity stays in 0...1.
            var debt: Double
            var hrv: Double
            var strain: Double
            /// Multiplier of the extension cap. 1 is the historical 30 minutes.
            var extensionCap: Double
            /// Multiplier of the tolerance around the anchor, applied AFTER the
            /// interpolation, so it can leave the 20...45 min band on purpose.
            var tolerance: Double
            /// The circadian floor leads: the regularity guard can still pull
            /// the target back toward the anchor, but never BELOW the floor.
            var circadianFloorLeads: Bool
        }

        /// `balanced` returns the historical constants literal for literal,
        /// and its two multipliers are 1, so the default plan does not move.
        static func weights(for priority: SmartAlarmPriority) -> Weights {
            switch priority {
            case .balanced:
                return Weights(debt: 0.5, hrv: 0.3, strain: 0.2,
                               extensionCap: 1, tolerance: 1, circadianFloorLeads: false)
            case .clearDebt:
                // Debt takes most of the severity and the cap doubles, so a
                // saturated debt can buy up to an hour INSIDE the bounds. The
                // tolerance widens with it, or the regularity guard would take
                // back what step 3 just gave.
                return Weights(debt: 0.8, hrv: 0.12, strain: 0.08,
                               extensionCap: 2, tolerance: 1.5, circadianFloorLeads: false)
            case .travel:
                // The circadian floor leads. The regularity anchor describes the
                // habit of the DEPARTURE time zone; its tolerance widens instead
                // of disappearing (still a useful fallback without CBTmin).
                return Weights(debt: 0.5, hrv: 0.3, strain: 0.2,
                               extensionCap: 0.5, tolerance: 2, circadianFloorLeads: true)
            case .regularity:
                // Anchor and tolerance lead: the band tightens to 10...22.5 min
                // and the extension budget drops to a quarter.
                return Weights(debt: 0.5, hrv: 0.3, strain: 0.2,
                               extensionCap: 0.25, tolerance: 0.5, circadianFloorLeads: false)
            }
        }

        // MARK: - Entry point

        static func plan(_ inputs: Inputs) -> Plan {
            let window = normalizedWindow(inputs)
            guard window.lowerBound < window.upperBound else {
                return Plan(ring: window.upperBound, window: window,
                            source: .deadline, reasons: [])
            }
            return optimized(inputs, window: window)
        }

        /// Normalized bounds. An inverted or empty window degenerates to
        /// `latest...latest`: the intent is not guessed, the alarm rings on
        /// the bound.
        private static func normalizedWindow(_ inputs: Inputs) -> ClosedRange<Date> {
            guard inputs.earliest < inputs.latest else { return inputs.latest...inputs.latest }
            return inputs.earliest...inputs.latest
        }

        // MARK: - Decision

        /// Seven ordered steps.
        ///
        /// 1. regularity anchor
        /// 2. sleep need coverage, when it is REACHABLE
        /// 3. one combined debt plus recovery budget, capped
        /// 4. circadian floor (CBTmin plus one hour)
        /// 5. ultradian alignment
        /// 6. regularity guard
        /// 7. final clamp on the bounds
        ///
        /// No step except 7 may put the target on a bound without reason: a
        /// target stuck to a bound robs later steps of the latitude they need,
        /// and the plan degenerates into a fixed alarm.
        private static func optimized(_ inputs: Inputs, window: ClosedRange<Date>) -> Plan {
            let priorityWeights = weights(for: inputs.priority)

            // Step 1. Without an anchor there is no optimal wake to guess: ring
            // on the hard bound and say so.
            guard let anchorHour = inputs.anchorWakeHour,
                  let anchor = instant(forClockHour: anchorHour, nearest: window.upperBound,
                                       calendar: inputs.calendar)
            else {
                return Plan(ring: window.upperBound, window: window,
                            source: .deadline, reasons: [])
            }
            var reasons: [Reason] = [.anchor(hour: anchorHour)]
            var target = clamp(anchor, to: window)

            // Step 2. Sleep need coverage. The shortfall is reported, never
            // hidden. When the need fits in the window, pushing the target to
            // it buys real sleep. When the need goes PAST the bound, no
            // reachable instant covers it: report it and leave the target
            // where it is. Pinning the target to the bound here would cost ALL
            // the early latitude (step 5 would have zero flexibility), and the
            // user in sleep debt, exactly the one this feature serves, would
            // never see the alarm move.
            if let onset = inputs.onset {
                let needEnd = onset
                    .addingTimeInterval(inputs.onsetLatencySeconds)
                    .addingTimeInterval(Double(inputs.sleepNeedSeconds))
                if needEnd > target {
                    let overflow = needEnd.timeIntervalSince(window.upperBound)
                    if overflow > 0 {
                        reasons.append(.sleepNeedShortfall(seconds: overflow))
                    } else {
                        target = needEnd
                    }
                }
            }

            // Step 3. One budget, so the same state is not counted three times.
            let extensionSeconds = recoveryExtension(inputs)
            if extensionSeconds > 0 {
                target = min(target.addingTimeInterval(extensionSeconds), window.upperBound)
                reasons.append(.recoveryExtension(seconds: extensionSeconds,
                                                  debt: inputs.debtHours,
                                                  hrv: inputs.hrvRatio,
                                                  strain: inputs.strainRatio))
            }

            // Step 4. Circadian floor. Waking before the temperature minimum
            // gives the strongest inertia and pushes a phase delay.
            //
            // `leadingFloor` only serves the travel goal: it holds the floor so
            // step 6 cannot bring the target below it, even when the floor did
            // not move anything here.
            var leadingFloor: Date?
            if let cbtHour = inputs.cbtMinHour,
               let cbtMin = instant(forClockHour: cbtHour, nearest: target, calendar: inputs.calendar) {
                let floor = cbtMin.addingTimeInterval(circadianFloorSeconds)
                if floor > target, floor <= window.upperBound {
                    reasons.append(.circadianFloor(appliedSeconds: floor.timeIntervalSince(target)))
                    target = floor
                }
                if priorityWeights.circadianFloorLeads, floor <= window.upperBound {
                    leadingFloor = floor
                }
            }

            // Step 5. Ultradian alignment, real hypnogram when available.
            //
            // A shift under half a minute is NOT a reason: an alarm rings on
            // the minute, so it leaves the instant unchanged, and announcing
            // "shifted by 0 min to land at a cycle end" contradicts itself.
            // `source` stays `.observed` in that case.
            let aligned = align(target, inputs: inputs, window: window)
            if let shift = aligned.shiftSeconds, abs(shift) >= 30 {
                reasons.append(.cycleAlignment(shiftSeconds: shift))
            }
            target = aligned.instant

            // Step 6. Regularity guard. An irregular sleeper gets a tight
            // tolerance and is pulled back toward the anchor; a regular one has
            // earned more latitude. The goal multiplies that tolerance.
            //
            // `leadingFloor` (travel only) raises the HIGH edge of the guard,
            // never the low one, and it is only held when it sits under
            // `window.upperBound`, so it cannot leave the bounds either.
            let tolerance = toleranceSeconds(for: inputs.regularity, priority: inputs.priority)
            let low = anchor.addingTimeInterval(-tolerance)
            let high = max(anchor.addingTimeInterval(tolerance), leadingFloor ?? .distantPast)
            let guarded = min(max(target, low), high)
            if guarded != target {
                reasons.append(.regularityClamp(shiftSeconds: guarded.timeIntervalSince(target),
                                                toleranceSeconds: tolerance))
                target = guarded
            }

            // Step 7. Final clamp. Absolute invariant, no exception.
            let ring = clamp(target, to: window)
            if ring != target { reasons.append(.hardBoundClamp) }
            let source: Source = aligned.source == .deadline ? .predicted : aligned.source
            return Plan(ring: ring, window: window, source: source, reasons: reasons)
        }

        /// Extension budget for debt, autonomic state and load. The weights sum
        /// to 1, so the result never exceeds `maxRecoveryExtensionSeconds`
        /// times the goal's cap. It stays an INTENTION: step 3 applies it as
        /// `min(target + budget, upper bound)`.
        static func recoveryExtension(_ inputs: Inputs) -> Double {
            let w = weights(for: inputs.priority)
            let debt = clamp(inputs.debtHours / debtSaturationHours, 0, 1)
            let hrv = clamp((1 - inputs.hrvRatio) / hrvSaturationDrop, 0, 1)
            let strain = clamp((inputs.strainRatio - 1) / strainSaturationRise, 0, 1)
            let severity = clamp(w.debt * debt + w.hrv * hrv + w.strain * strain, 0, 1)
            return severity * maxRecoveryExtensionSeconds * w.extensionCap
        }

        /// Tolerance around the anchor. Unknown regularity gives the default;
        /// 0 gives the tightest tolerance, 100 the widest. The goal multiplies
        /// the result after the interpolation.
        static func toleranceSeconds(for regularity: Double?,
                                     priority: SmartAlarmPriority = .balanced) -> Double {
            let scale = weights(for: priority).tolerance
            guard let regularity else { return defaultToleranceSeconds * scale }
            let ratio = clamp(regularity / 100, 0, 1)
            return (minToleranceSeconds + (maxToleranceSeconds - minToleranceSeconds) * ratio) * scale
        }

        /// The instant carrying clock hour `hour` nearest to `reference`, in
        /// CIRCULAR arithmetic. Three candidates (day before, same day, day
        /// after) are evaluated, so a CBTmin at 23:00 and a target at 06:00 do
        /// not produce 17 h of gap.
        static func instant(forClockHour hour: Double,
                            nearest reference: Date,
                            calendar: Calendar = .current) -> Date? {
            guard hour.isFinite else { return nil }
            let normalized = hour.truncatingRemainder(dividingBy: 24)
            let wrapped = normalized < 0 ? normalized + 24 : normalized
            let day = calendar.startOfDay(for: reference)
            let candidates = [-1, 0, 1].compactMap { offset -> Date? in
                calendar.date(byAdding: .day, value: offset, to: day)?
                    .addingTimeInterval(wrapped * 3600)
            }
            return candidates.min {
                abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference))
            }
        }

        // MARK: - Ultradian alignment

        private struct Alignment {
            var instant: Date
            var source: Source
            var shiftSeconds: Double?
        }

        /// Aligns `target` on a cycle boundary.
        ///
        /// Observed night: delegates to `SleepCycleModel.recommendedWakeWindow`,
        /// which takes a SYMMETRIC flex around the target. Passing the distance
        /// to the NEAREST bound made the flex zero on a target sitting on a
        /// bound, the common case after steps 2 and 3, and the recorded
        /// hypnogram was thrown away. The distance to the FARTHEST bound is
        /// passed instead, and the chosen candidate is explicitly checked to
        /// fall inside the window: a candidate outside is refused, never
        /// clamped, and the predicted grid takes over.
        private static func align(_ target: Date,
                                  inputs: Inputs,
                                  window: ClosedRange<Date>) -> Alignment {
            if !inputs.observedSpans.isEmpty, let observedOnset = inputs.observedOnset {
                let usableFlexMinutes = max(target.timeIntervalSince(window.lowerBound),
                                            window.upperBound.timeIntervalSince(target)) / 60
                if let found = SleepCycleModel.recommendedWakeWindow(
                    spans: inputs.observedSpans,
                    onset: observedOnset,
                    targetWake: target,
                    flexMinutes: max(0, usableFlexMinutes)) {
                    let mid = found.lowerBound
                        .addingTimeInterval(found.upperBound.timeIntervalSince(found.lowerBound) / 2)
                    if window.contains(mid) {
                        return Alignment(instant: mid, source: .observed,
                                         shiftSeconds: mid.timeIntervalSince(target))
                    }
                }
            }
            if let predicted = predictedBoundary(near: target, inputs: inputs, window: window) {
                return Alignment(instant: predicted, source: .predicted,
                                 shiftSeconds: predicted.timeIntervalSince(target))
            }
            return Alignment(instant: target, source: .deadline, shiftSeconds: nil)
        }

        /// Predicted cycle boundary nearest `target` inside `window`:
        /// `boundary(k) = onset + latency + k * cycle`, measured cycle when known.
        ///
        /// Two ranks, and order matters: a boundary truly inside the window
        /// always wins; admitted boundaries (below) only count when that rank
        /// is empty, or a boundary projected onto a bound could show a zero
        /// distance and beat a real one twenty minutes away.
        private static func predictedBoundary(near target: Date,
                                              inputs: Inputs,
                                              window: ClosedRange<Date>) -> Date? {
            guard let onset = inputs.onset else { return nil }
            let cycle = inputs.meanCycleSeconds ?? SleepCycleModel.anchorCycleSeconds
            guard cycle > 0 else { return nil }
            let first = onset.addingTimeInterval(inputs.onsetLatencySeconds)
            var exact: Date?
            var exactDistance = Double.greatestFiniteMagnitude
            var admitted: Date?
            var admittedDistance = Double.greatestFiniteMagnitude
            let slack = phaseSlackSeconds(inputs)
            // 16 cycles cover 24 h at 90 min, so any plausible night.
            for k in 1...16 {
                let candidate = first.addingTimeInterval(Double(k) * cycle)
                if window.contains(candidate) {
                    let distance = abs(candidate.timeIntervalSince(target))
                    if distance < exactDistance {
                        exactDistance = distance
                        exact = candidate
                    }
                } else if let projected = project(candidate, into: window, slack: slack) {
                    let distance = abs(projected.timeIntervalSince(target))
                    if distance < admittedDistance {
                        admittedDistance = distance
                        admitted = projected
                    }
                }
            }
            return exact ?? admitted
        }

        /// How far the predicted grid may miss the window.
        ///
        /// On an ESTIMATED onset (a circular mean of habitual bedtimes) the
        /// origin's own error runs to tens of minutes, so demanding a boundary
        /// inside the window to the second is false precision. The slack is
        /// the onset latency, the one uncertainty the model already quantifies.
        /// On an OBSERVED onset the origin is measured: no slack.
        static func phaseSlackSeconds(_ inputs: Inputs) -> Double {
            inputs.observedOnset == nil ? inputs.onsetLatencySeconds : 0
        }

        /// Projects onto the LOW bound a boundary that precedes the window by
        /// less than `slack`. The asymmetry is the rule: the slack covers the
        /// MODEL's uncertainty, never the user's constraint, so a boundary
        /// after `window.upperBound` is always refused.
        private static func project(_ candidate: Date,
                                    into window: ClosedRange<Date>,
                                    slack: Double) -> Date? {
            guard slack > 0, candidate < window.lowerBound else { return nil }
            return window.lowerBound.timeIntervalSince(candidate) <= slack
                ? window.lowerBound : nil
        }

        // MARK: - Utilities

        static func clamp(_ date: Date, to range: ClosedRange<Date>) -> Date {
            min(max(date, range.lowerBound), range.upperBound)
        }

        static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
            min(max(value, low), high)
        }
    }
}
