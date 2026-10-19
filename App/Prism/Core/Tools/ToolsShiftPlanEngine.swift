//
//  ToolsShiftPlanEngine.swift
//  Prism
//
//  Shiftwork re-entrainment as a thin mapper over the jet-lag model. A new work schedule shifts the required wake
//  time the same way crossing time zones does, so the body clock re-entrains
//  by the same phase-shift math. This engine does NOT re-derive that math: it
//  only maps a shift-start hour to the signed circular delta the jet-lag model
//  expects, then reuses JetLagModel and TravelActionPlanner verbatim.
//
//  Semantics note: JetLagModel's `daysSinceArrival` becomes "days since the
//  schedule changed" here. The recovery curve is identical; only the trigger
//  differs (a new roster instead of a flight).
//

import Foundation

extension SomaTools {

    /// A shiftwork re-entrainment plan: the jet-lag-equivalent recovery state,
    /// the day's ordered re-entrainment actions, and the signed shift in hours
    /// that produced them. `shiftHours` is positive for a phase ADVANCE (the new
    /// schedule needs an earlier wake) and negative for a phase DELAY (a later
    /// wake), matching JetLagModel's east-positive convention.
    nonisolated struct ShiftPlan: Sendable, Equatable {
        let state: JetLagState
        let actions: [TravelAction]
        let shiftHours: Double
    }

    nonisolated enum ShiftPlanEngine {

        /// Hours before the shift start the worker must actually wake (commute
        /// plus getting ready). The required wake clock hour is
        /// `shiftStart` minus `gettingReadyOffsetHours`. Fixed and documented so the map
        /// is deterministic; a caller that models a different commute can
        /// pre-subtract it and pass the resulting start hour.
        static let gettingReadyOffsetHours = 1.0

        /// Map a new work schedule onto the jet-lag re-entrainment model.
        ///
        /// The new required wake hour is `newShiftStartHour` minus `gettingReadyOffsetHours`
        /// wrapped onto the 24 h clock. `shiftHours` is the signed shortest
        /// circular delta between that new required wake and the habitual wake:
        /// positive when the clock must ADVANCE (wake earlier, the eastward
        /// equivalent), negative when it must DELAY (wake later, the westward
        /// equivalent). That signed shift is fed straight to `JetLagModel.state`,
        /// and the returned state plus the `TravelActionPlanner.plan` timeline are
        /// reused verbatim.
        ///
        /// Parameters:
        /// . habitualWakeHour: the worker's usual wake clock hour, 0..<24.
        /// . newShiftStartHour: the new shift's start clock hour, 0..<24.
        /// . daysSinceChange: days since the roster changed (the jet-lag model's
        ///   `daysSinceArrival`, identical recovery curve).
        /// . recentDaylightMin: recent daylight minutes, which speed
        ///   re-entrainment. 0 falls back to the unaided rate.
        /// . habitualSleepHour: the worker's usual sleep-onset clock hour, used
        ///   only to lay out the action timeline.
        ///
        /// Returns a `ShiftPlan`, or nil when the schedule change rounds to under
        /// one zone (no re-entrainment burden).
        static func plan(habitualWakeHour: Double,
                         newShiftStartHour: Double,
                         daysSinceChange: Int,
                         recentDaylightMin: Double,
                         habitualSleepHour: Double) -> ShiftPlan? {
            let requiredWake = CircadianMath.wrap24(newShiftStartHour - gettingReadyOffsetHours)
            let shiftHours = signedShiftHours(from: requiredWake, to: habitualWakeHour)
            guard let state = JetLagModel.state(shiftHours: shiftHours,
                                                daysSinceArrival: daysSinceChange,
                                                daylightMin: recentDaylightMin)
            else { return nil }
            let actions = TravelActionPlanner.plan(state: state,
                                                   habitualWakeHour: habitualWakeHour,
                                                   habitualSleepHour: habitualSleepHour)
            return ShiftPlan(state: state, actions: actions, shiftHours: shiftHours)
        }

        /// Signed shortest circular delta on the 24 h clock, in (-12, 12].
        /// Returns `habitual` minus `required` folded to the nearer arc, so it is
        /// positive when the new required wake sits earlier than the habitual wake
        /// (the clock must advance) and negative when it sits later (the clock must
        /// delay).
        static func signedShiftHours(from required: Double, to habitual: Double) -> Double {
            var d = CircadianMath.wrap24(habitual) - CircadianMath.wrap24(required)
            d = d.truncatingRemainder(dividingBy: 24)
            if d > 12 { d -= 24 }
            if d <= -12 { d += 24 }
            return d
        }
    }
}
