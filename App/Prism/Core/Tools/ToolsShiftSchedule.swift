//
//  ToolsShiftSchedule.swift
//  Prism
//
//  The shiftwork page's pure pieces: the default roster, the fixed modelling inputs, the elapsed days
//  since the roster date, and the next actions to show inline.
//

import Foundation

extension SomaTools {

    nonisolated enum ShiftSchedule {

        /// Defaults model the common case: a 10pm night-shift start against a
        /// habitual 7am wake. They seed the pickers; they never stand in for a
        /// schedule the user has not declared.
        static let defaultShiftStartHour: Double = 22
        static let defaultUsualWakeHour: Double = 7

        /// Fixed modelling inputs: a modest daylight dose and a typical 11pm
        /// sleep onset laying out the timeline.
        static let recentDaylightMin: Double = 30
        static let habitualSleepHour: Double = 23

        /// The plan for a declared roster, with the fixed modelling inputs.
        static func plan(shiftStartHour: Double,
                         usualWakeHour: Double,
                         daysSinceChange: Int = 0,
                         recentDaylightMin: Double = recentDaylightMin,
                         habitualSleepHour: Double = habitualSleepHour) -> ShiftPlan? {
            ShiftPlanEngine.plan(habitualWakeHour: usualWakeHour,
                                 newShiftStartHour: shiftStartHour,
                                 daysSinceChange: daysSinceChange,
                                 recentDaylightMin: recentDaylightMin,
                                 habitualSleepHour: habitualSleepHour)
        }

        /// Whole days from the roster date to `now`, never negative; 0 without a
        /// date (the plan is then explored for the day of the change). This is
        /// what makes a "days left" figure move.
        static func daysSinceChange(rosterDate: Date?,
                                    now: Date,
                                    calendar: Calendar = .current) -> Int {
            guard let rosterDate else { return 0 }
            let days = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: rosterDate),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            return max(0, days)
        }

        /// Days still to adjust, from the plan's own elapsed count.
        static func daysLeft(_ plan: ShiftPlan) -> Int { plan.state.daysLeft }

        /// 1-based day of the adjustment, capped at the last day.
        static func dayNumber(_ plan: ShiftPlan) -> Int { plan.state.dayNumber }

        /// The two actions still ahead today, or the first two of the plan once
        /// the day is past them.
        static func nextActions(_ plan: ShiftPlan, nowHour: Double, limit: Int = 2) -> [TravelAction] {
            let ahead = plan.actions.filter { $0.startHour >= nowHour }
            return Array((ahead.count >= limit ? ahead : plan.actions).prefix(limit))
        }
    }
}
