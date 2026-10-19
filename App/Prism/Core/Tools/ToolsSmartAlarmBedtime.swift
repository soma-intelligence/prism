//
//  ToolsSmartAlarmBedtime.swift
//  Prism
//
//  When to be in bed so the predicted ring lands on a covered sleep need.
//
//  One subtraction, isolated in its own pure type for one reason: the number
//  ends up on several surfaces and in a notification, and a second copy of the
//  rule is exactly how two of them would end up showing two different bedtimes.
//
//  Deliberately NOT done here: no rounding to a whole number of cycles. The
//  ultradian cycle science is a WAKE argument (SmartWakeEngine, step 5).
//  Applying it to falling asleep would be a number without a source.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartAlarmBedtime {

        nonisolated struct Reading: Sendable, Equatable {
            /// When to be in bed, lights out.
            let lightsOut: Date
            /// The ring it was resolved against.
            let ring: Date
            let sleepNeedSeconds: Int
            let onsetLatencySeconds: Double
            /// The habitual bedtime already estimated, or nil when the history
            /// is too short.
            let habitualLightsOut: Date?

            /// Negative = earlier than usual. nil without a known habit.
            var deltaVsHabitSeconds: Double? {
                guard let habitualLightsOut else { return nil }
                return lightsOut.timeIntervalSince(habitualLightsOut)
            }

            /// Time IN BED, latency included. Not the sleep obtained: mixing
            /// the two would sell a quarter hour that does not exist.
            var timeInBedSeconds: Double {
                Double(sleepNeedSeconds) + onsetLatencySeconds
            }

            /// How the delta against the habit reads, or nil without a habit.
            var deltaVsHabit: HabitDelta? {
                guard let delta = deltaVsHabitSeconds else { return nil }
                if abs(delta) < SmartAlarmBedtime.onHabitToleranceSeconds { return .onHabit }
                return delta < 0 ? .earlier(seconds: -delta) : .later(seconds: delta)
            }
        }

        /// Within five minutes of the habit, the bedtime reads as "on habit".
        static let onHabitToleranceSeconds: Double = 5 * 60

        nonisolated enum HabitDelta: Sendable, Equatable {
            case onHabit
            case earlier(seconds: Double)
            case later(seconds: Double)
        }

        /// The floor every caller applies to a derived sleep need: a non
        /// positive need would put lights out at or after the ring.
        static let minimumSleepNeedSeconds = 3600

        static func reading(ring: Date,
                            sleepNeedSeconds: Int,
                            onsetLatencySeconds: Double,
                            habitualLightsOut: Date?) -> Reading {
            Reading(lightsOut: ring.addingTimeInterval(
                        -Double(sleepNeedSeconds) - onsetLatencySeconds),
                    ring: ring,
                    sleepNeedSeconds: sleepNeedSeconds,
                    onsetLatencySeconds: onsetLatencySeconds,
                    habitualLightsOut: habitualLightsOut)
        }

        /// The bedtime derived from a ring with the planner's floor on the
        /// sleep need and the engine's default latency, for surfaces that only
        /// hold the ring.
        static func reading(ring: Date, sleepNeedSeconds: Int) -> Reading {
            reading(ring: ring,
                    sleepNeedSeconds: max(minimumSleepNeedSeconds, sleepNeedSeconds),
                    onsetLatencySeconds: SmartWakeEngine.defaultOnsetLatencySeconds,
                    habitualLightsOut: nil)
        }
    }
}
