//
//  ToolsTravelActionPlanner.swift
//  Prism
//
//  A jet-lag re-entrainment day as ordered, timed actions, plus the pure timing helpers
//  its travel page uses (the now/next focus, the action state at an hour, the countdown split).
//

import Foundation

extension SomaTools {

    /// One actionable step in a jet-lag re-entrainment day.
    nonisolated enum TravelActionKind: String, Codable, Sendable, CaseIterable {
        case morningLight, eveningLight, avoidLight, caffeineCutoff, melatonin, sleep
    }

    /// A timed re-entrainment action. `endHour` is nil for point actions (cutoff,
    /// melatonin). `id` is stable per day (one action of each kind), so a
    /// checklist can track it.
    nonisolated struct TravelAction: Identifiable, Sendable, Equatable {
        var kind: TravelActionKind
        var startHour: Double
        var endHour: Double?
        /// Plain English title and detail. `avoidLight` reads differently in the
        /// morning and the evening, so the copy is resolved by the planner.
        var title: String
        var detail: String

        var id: String { kind.rawValue }
    }

    /// Where an action sits relative to an hour of the day.
    nonisolated enum TravelActionTiming: Sendable, Equatable {
        case done, past, current, future
    }

    /// Derives the day's ordered re-entrainment actions from a jet-lag state plus
    /// the user's habitual wake/sleep clock hours. Pure and testable. Timing
    /// follows the light phase-response curve encoded in `state.lightGuidance`
    /// (advance east, delay west); all times are directional, not clinical.
    nonisolated enum TravelActionPlanner {

        /// Habitual hours assumed when there is not yet enough sleep data.
        static let fallbackWakeHour = 7.0
        static let fallbackSleepHour = 23.0

        static func plan(state: JetLagState,
                         habitualWakeHour wake: Double,
                         habitualSleepHour sleep: Double) -> [TravelAction] {
            func wrap(_ h: Double) -> Double { CircadianMath.wrap24(h) }
            var actions: [TravelAction] = []
            let guidance = state.lightGuidance

            if guidance.seekMorningLight {
                actions.append(TravelAction(kind: .morningLight, startHour: wrap(wake), endHour: wrap(wake + 2),
                    title: "Bright morning light",
                    detail: "Get outside in the first hours after waking to pull your clock earlier."))
                actions.append(TravelAction(kind: .avoidLight, startHour: wrap(sleep - 3), endHour: wrap(sleep),
                    title: "Dim the evening",
                    detail: "Avoid bright and blue light in the last hours before bed."))
            } else if guidance.seekEveningLight {
                actions.append(TravelAction(kind: .eveningLight, startHour: wrap(sleep - 3), endHour: wrap(sleep - 1),
                    title: "Bright evening light",
                    detail: "Seek light in the evening to push your clock later."))
                actions.append(TravelAction(kind: .avoidLight, startHour: wrap(wake), endHour: wrap(wake + 2),
                    title: "Dim the early morning",
                    detail: "Avoid bright light first thing until your body catches up."))
            }

            actions.append(TravelAction(kind: .caffeineCutoff, startHour: wrap(sleep - 6), endHour: nil,
                title: "Caffeine cutoff",
                detail: "Last caffeine of the day to protect tonight’s sleep."))

            if state.melatoninSuggested {
                let melatoninHour = state.direction == .advance ? wrap(sleep - 6) : wrap(wake + 1)
                actions.append(TravelAction(kind: .melatonin, startHour: melatoninHour, endHour: nil,
                    title: "Low-dose melatonin",
                    detail: "About 0.5 mg can nudge your clock. Information, not a prescription."))
            }

            actions.append(TravelAction(kind: .sleep, startHour: wrap(sleep), endHour: wrap(wake),
                title: "Target sleep window",
                detail: "Aim for your destination-local sleep window tonight."))

            return actions.sorted { $0.startHour < $1.startHour }
        }

        // MARK: Timing at an hour

        /// The state of an action at `nowHour`. A point action counts as a
        /// half-hour span. `isDone` comes from the caller's checklist.
        static func timing(of action: TravelAction, nowHour: Double, isDone: Bool = false) -> TravelActionTiming {
            if isDone { return .done }
            let start = action.startHour
            let end = action.endHour ?? (action.startHour + 0.5)
            if end >= start {
                if nowHour > end { return .past }
                if nowHour >= start { return .current }
                return .future
            } else {
                if nowHour >= start || nowHour <= end { return .current }
                return .future
            }
        }

        /// The action that matters at this instant: the one in progress, or else
        /// the next one still ahead today (not done). `isCurrent` says which.
        /// nil once every action is behind or done.
        static func focus(actions: [TravelAction],
                          nowHour: Double,
                          isDone: (TravelActionKind) -> Bool = { _ in false })
            -> (action: TravelAction, isCurrent: Bool)? {
            if let current = actions.first(where: {
                timing(of: $0, nowHour: nowHour, isDone: isDone($0.kind)) == .current
            }) {
                return (current, true)
            }
            let next = actions
                .filter { $0.startHour > nowHour && !isDone($0.kind) }
                .min(by: { $0.startHour < $1.startHour })
            return next.map { ($0, false) }
        }

        /// The time left before an action starts, split into whole hours and
        /// minutes, never negative. A surface words it ("in 2 h 15 min"); under
        /// an hour it should say at least one minute.
        static func countdown(from nowHour: Double, to startHour: Double) -> (hours: Int, minutes: Int) {
            let delta = max(0, startHour - nowHour)
            let h = Int(delta)
            let m = Int((delta - Double(h)) * 60)
            return (h, m)
        }
    }
}
