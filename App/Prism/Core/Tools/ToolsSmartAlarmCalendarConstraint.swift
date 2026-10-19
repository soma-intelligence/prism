//
//  ToolsSmartAlarmCalendarConstraint.swift
//  Prism
//
//  The bound the calendar puts on the alarm. Pure, no EventKit: it eats plain
//  `Event` values the caller maps from its calendar source, so it is tested on
//  fixtures exactly like SmartWakeEngine.
//
//  Contract: this bound can only bring the ring FORWARD. The planner applies
//  `min(set time, bound)`, so an afternoon meeting never pushes a morning
//  alarm back. The rule lives with the caller, who knows the set time; this
//  file only returns the raw bound.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartAlarmCalendarConstraint {

        /// The calendar facts this constraint reads, and nothing else.
        nonisolated struct Event: Sendable, Equatable {
            var title: String
            var start: Date
            var isAllDay: Bool
            /// False for declined or tentative events.
            var accepted: Bool

            init(title: String, start: Date, isAllDay: Bool = false, accepted: Bool = true) {
                self.title = title
                self.start = start
                self.isAllDay = isAllDay
                self.accepted = accepted
            }
        }

        /// Absolute floor, local clock hour. A bound before it is NOT applied:
        /// bringing an alarm forward into the middle of the night costs more
        /// than being late for a flight, and someone leaving at 05:00 has set
        /// their own alarm anyway. It is still returned as `.tooEarly`, so the
        /// user learns the app saw it.
        static let floorHour: Int = 4

        /// Last event start that counts, local clock hour. An afternoon meeting
        /// does not decide when to get up.
        static let latestRelevantHour: Int = 12

        nonisolated struct Constraint: Sendable, Equatable {
            var eventTitle: String
            var eventStart: Date
            /// `eventStart` minus the prep margin. May fall below the floor:
            /// `Outcome` decides whether it applies.
            var bound: Date
        }

        nonisolated enum Outcome: Sendable, Equatable {
            /// No morning event constrains the alarm.
            case none
            /// The bound comes from the calendar and applies.
            case bound(Constraint)
            /// An event exists but its bound falls under the floor. It does not
            /// apply, and the caller must say so.
            case tooEarly(Constraint)
        }

        /// The bound for the morning of `wake`.
        ///
        /// Filters, in order: same calendar day as `wake`, not all day,
        /// accepted, start before `latestRelevantHour`. The earliest survivor
        /// wins; equal starts are broken on the title so the result does not
        /// depend on the order the source listed them in.
        static func outcome(events: [Event],
                            wake: Date,
                            prepSeconds: Double,
                            calendar: Calendar = .current) -> Outcome {
            let morning = calendar.startOfDay(for: wake)
            guard let noon = calendar.date(bySettingHour: latestRelevantHour, minute: 0,
                                           second: 0, of: morning),
                  let floor = calendar.date(bySettingHour: floorHour, minute: 0,
                                            second: 0, of: morning)
            else { return .none }

            let eligible: [Event] = events.filter { event in
                guard !event.isAllDay, event.accepted else { return false }
                guard calendar.isDate(event.start, inSameDayAs: morning) else { return false }
                return event.start < noon
            }

            let candidate: Event? = eligible.min { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title < rhs.title
            }

            guard let candidate else { return .none }

            let constraint = Constraint(
                eventTitle: candidate.title,
                eventStart: candidate.start,
                bound: candidate.start.addingTimeInterval(-max(0, prepSeconds)))

            // `<` and not `<=`: a bound exactly at 04:00 stays usable. A 00:30
            // meeting, whose bound falls the evening before, is covered by the
            // same comparison.
            return constraint.bound < floor ? .tooEarly(constraint) : .bound(constraint)
        }
    }
}
