//
//  ToolsSmartAlarmExplainer.swift
//  Prism
//
//  Unfolds the reasons of `SmartWakeEngine.Plan` into ordered factors, each
//  carrying its signed magnitude and the numbers its sentence cites. Pure, no
//  I/O, and above all NO copy: the words live in the view layer, exactly as
//  SmartWakeEngine keeps its science out of the presentation.
//
//  It does not replace `SmartAlarmPlanner.reasonKind`, which serves one-line
//  labels (a stack card, a Live Activity, alarm metadata). The explainer
//  serves the surfaces that have room to say why AND what to do.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartAlarmExplainer {

        /// Which cause placed the instant.
        nonisolated enum Kind: String, Sendable, Equatable, CaseIterable {
            /// The bound comes from the first morning meeting. The same bound
            /// as `hardBound`, but the sentence must name the event.
            case calendarBound
            /// A morning meeting exists but its bound falls under the floor:
            /// it was NOT applied. Saying so beats letting the user think the
            /// app saw nothing.
            case calendarTooEarly
            case hardBound
            case recovery
            case circadianFloor
            case shortfall
            case regularity
            case cycle
            /// The goal the user picked. It moves nothing by itself; it says
            /// under which rule everything else was weighed.
            case priority
            case anchor
        }

        /// The raw numbers a factor's sentence cites. A factor only fills what
        /// actually moved it, so a view cannot show a number that played no
        /// part in the computation.
        nonisolated struct Numbers: Sendable, Equatable {
            var debtHours: Double?
            var hrvRatio: Double?
            var strainRatio: Double?
            var toleranceSeconds: Double?
            var anchorHour: Double?
            var deadline: Date?
            var eventTitle: String?
            var eventStart: Date?
            /// The active goal, carried by the `.priority` factor only.
            var priority: SmartAlarmPriority?
        }

        nonisolated struct Factor: Sendable, Equatable, Identifiable {
            var kind: Kind
            /// Signed. Positive: the instant was pushed LATER. Negative: earlier
            /// or missing. Zero: a bound or a context, not a shift.
            var shiftSeconds: Double
            var numbers: Numbers

            var id: Kind { kind }
            var magnitude: Double { abs(shiftSeconds) }
        }

        /// The plan's factors, ordered for reading.
        ///
        /// `hardBound` first: when the user's life bound decided, it is THE
        /// reason. `anchor` last: context, not a shift. In between, descending
        /// absolute magnitude, then `Kind` declaration order so equal
        /// magnitudes never depend on the order the engine stacked reasons.
        ///
        /// A calendar outcome REPLACES `hardBound` at the head (the same bound,
        /// showing both would count it twice). `.tooEarly` is emitted with a
        /// zero shift so the surface can say the meeting was seen.
        ///
        /// Of `settings`, only the goal is read: it yields the `.priority`
        /// factor just before `anchor`, and only when it is NOT `.balanced`.
        static func factors(for plan: SmartWakeEngine.Plan,
                            settings: SmartAlarmSettings,
                            calendarOutcome: SmartAlarmCalendarConstraint.Outcome = .none) -> [Factor] {
            let mapped = plan.reasons.map { factor(for: $0, plan: plan) }
            let calendar = calendarFactor(calendarOutcome)
            let head: [Factor] = calendar.map { [$0] } ?? mapped.filter { $0.kind == .hardBound }
            var tail: [Factor] = []
            if let priority = priorityFactor(settings.priority) { tail.append(priority) }
            tail.append(contentsOf: mapped.filter { $0.kind == .anchor })
            let middle = mapped
                .filter { $0.kind != .hardBound && $0.kind != .anchor }
                .sorted { lhs, rhs in
                    if lhs.magnitude != rhs.magnitude { return lhs.magnitude > rhs.magnitude }
                    return rank(lhs.kind) < rank(rhs.kind)
                }
            return head + middle + tail
        }

        private static func calendarFactor(_ outcome: SmartAlarmCalendarConstraint.Outcome) -> Factor? {
            switch outcome {
            case .none:
                return nil
            case .bound(let constraint):
                return Factor(kind: .calendarBound, shiftSeconds: 0,
                              numbers: Numbers(deadline: constraint.bound,
                                               eventTitle: constraint.eventTitle,
                                               eventStart: constraint.eventStart))
            case .tooEarly(let constraint):
                return Factor(kind: .calendarTooEarly, shiftSeconds: 0,
                              numbers: Numbers(eventTitle: constraint.eventTitle,
                                               eventStart: constraint.eventStart))
            }
        }

        private static func priorityFactor(_ priority: SmartAlarmPriority) -> Factor? {
            guard priority != .balanced else { return nil }
            return Factor(kind: .priority, shiftSeconds: 0, numbers: Numbers(priority: priority))
        }

        /// The factor a compact card shows. nil when the plan has no reason.
        static func dominant(_ factors: [Factor]) -> Factor? { factors.first }

        // MARK: Internal

        private static func factor(for reason: SmartWakeEngine.Reason,
                                   plan: SmartWakeEngine.Plan) -> Factor {
            switch reason {
            case .hardBoundClamp:
                return Factor(kind: .hardBound, shiftSeconds: 0,
                              numbers: Numbers(deadline: plan.window.upperBound))
            case .recoveryExtension(let seconds, let debt, let hrv, let strain):
                return Factor(kind: .recovery, shiftSeconds: seconds,
                              numbers: Numbers(debtHours: debt, hrvRatio: hrv, strainRatio: strain))
            case .circadianFloor(let applied):
                return Factor(kind: .circadianFloor, shiftSeconds: applied, numbers: Numbers())
            case .sleepNeedShortfall(let seconds):
                // Negative: a shortfall, not a push later.
                return Factor(kind: .shortfall, shiftSeconds: -seconds, numbers: Numbers())
            case .regularityClamp(let shift, let tolerance):
                return Factor(kind: .regularity, shiftSeconds: shift,
                              numbers: Numbers(toleranceSeconds: tolerance))
            case .cycleAlignment(let shift):
                return Factor(kind: .cycle, shiftSeconds: shift, numbers: Numbers())
            case .anchor(let hour):
                return Factor(kind: .anchor, shiftSeconds: 0, numbers: Numbers(anchorHour: hour))
            }
        }

        /// `Kind` declaration order, for a total and stable sort.
        private static func rank(_ kind: Kind) -> Int {
            Kind.allCases.firstIndex(of: kind) ?? Kind.allCases.count
        }
    }
}
