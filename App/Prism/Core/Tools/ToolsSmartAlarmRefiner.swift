//
//  ToolsSmartAlarmRefiner.swift
//  Prism
//
//  The decision rule of the overnight refinement pass, pure. The pass itself
//  (a background processing task requested before the window opens, then a
//  replan and possibly a rewrite of the armed alarm) belongs to the
//  scheduling layer. It is OPPORTUNISTIC by nature: the Watch writes its
//  samples in batches with variable latency and iOS guarantees no background
//  slot, so without a Watch or without a slot the alarm simply stays on the
//  predicted instant. The weekly recurring safety net guarantees it rings.
//
//  Also holds the two value types the rule reads: what is armed on the
//  platform, and the result of reading it.
//

import Foundation

extension SomaTools {

    /// What the alarm asks the platform to arm. Two states only.
    nonisolated enum SmartAlarmProgramming: Equatable, Sendable {
        /// Permanent safety net: weekly recurrence at the hard bound. Needs no
        /// background execution.
        case recurring(timeMinutes: Int, weekdays: Set<Int>)
        /// Refined instant for one specific night. Replaces the safety net.
        case oneOff(Date)
    }

    /// The result of reading what is armed on the platform. Deliberately not a
    /// plain optional: reading the armed alarms can fail, and a failed read
    /// must never be mistaken for "nothing armed", or a refinement set earlier
    /// could be overwritten on the strength of a swallowed error.
    nonisolated enum SmartAlarmProgrammingQuery: Equatable, Sendable {
        /// Something is armed, and we know what.
        case scheduled(SmartAlarmProgramming)
        /// Nothing is armed: a confirmed state, not a guess.
        case nothingScheduled
        /// The read failed (or returned an unknown case): state unknown.
        case queryFailed
    }

    nonisolated enum SmartAlarmRefiner {

        /// Minimum gain that justifies a rewrite. Below it nothing moves:
        /// rescheduling an alarm for 90 seconds is noise.
        static let minimumGainSeconds: Double = 180

        /// How long before the window opens the background slot is requested.
        static let leadSeconds: Double = 25 * 60

        nonisolated enum SkipReason: Equatable, Sendable {
            case gainTooSmall
            case wouldMoveLater
            case alreadyPast
            case noSignal
            case disabled
            /// The armed state could not be read. Distinct from "nothing
            /// armed": rescheduling on an unknown state could overwrite a
            /// refinement already in place.
            case queryFailed
        }

        nonisolated enum Decision: Equatable, Sendable {
            case refine(Date)
            case skip(SkipReason)
        }

        /// The rule. Bringing the alarm forward needs four conditions: a real
        /// cycle signal, a future instant, a real gain, and never a move later.
        /// A fifth condition beats all others: the armed state must be
        /// confirmed, not unknown.
        static func decision(plan: SmartWakeEngine.Plan,
                             current: SmartAlarmProgrammingQuery,
                             now: Date) -> Decision {
            // Unknown state: never rewrite on a guess. This guard comes before
            // everything, because a failed read says NOTHING about what is armed.
            if case .queryFailed = current { return .skip(.queryFailed) }

            guard plan.source != .deadline else { return .skip(.noSignal) }
            guard plan.ring > now else { return .skip(.alreadyPast) }

            let reference: Date
            switch current {
            case .scheduled(.oneOff(let existing)):
                reference = existing
            case .scheduled(.recurring), .nothingScheduled:
                reference = plan.window.upperBound
            case .queryFailed:
                // Unreachable after the guard above; still treated as unknown so
                // a refactor that drops the guard fails instead of rewriting.
                return .skip(.queryFailed)
            }
            guard plan.ring <= reference else { return .skip(.wouldMoveLater) }
            guard reference.timeIntervalSince(plan.ring) >= minimumGainSeconds else {
                return .skip(.gainTooSmall)
            }
            return .refine(plan.ring)
        }

        /// When to ask for the background slot: `leadSeconds` before the
        /// window, never less than a minute in the future. A hint, not a
        /// guarantee: the system decides.
        static func earliestBeginDate(before windowStart: Date, now: Date) -> Date {
            max(windowStart.addingTimeInterval(-leadSeconds), now.addingTimeInterval(60))
        }
    }
}
