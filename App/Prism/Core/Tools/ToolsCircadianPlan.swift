//
//  ToolsCircadianPlan.swift
//  Prism
//
//  The day's circadian timing windows.
//

import Foundation

extension SomaTools {

    /// One recommended window of the day. Hours are clock hours in [0, 24). For a
    /// point recommendation (the caffeine cutoff) start and end are equal.
    nonisolated struct CircadianWindow: Identifiable, Sendable, Equatable {
        nonisolated enum Kind: String, Sendable, CaseIterable {
            case lightSeek      // bright light to advance, after CBTmin (morning)
            case lightAvoid     // dim / avoid blue light before bed
            case caffeineCutoff // last coffee to protect tonight's sleep
            case exercise       // late-afternoon performance window
            case windDown       // start winding down
            case sleep          // ideal sleep window
        }

        var kind: Kind
        var startHour: Double
        var endHour: Double

        var id: String { kind.rawValue }
    }

    /// The day's plan: timing windows plus a 0 to 100 circadian alignment score.
    /// `alignmentScore` is nil when social jetlag is unknown (rMEQ-only seed).
    nonisolated struct CircadianPlan: Sendable, Equatable {
        var windows: [CircadianWindow]
        var alignmentScore: Int?
    }

    /// Turns an estimated phase plus habitual wake/sleep clock hours into the day's
    /// timing windows. `lightSeek`, `lightAvoid`, and `exercise` are driven off the
    /// estimated CBTmin/DLMO phase; `sleep` and `windDown` stay anchored to the
    /// habitual schedule. Includes a safety guard against intense exercise too
    /// close to sleep. `now` is reserved for a future time-of-day-aware plan.
    nonisolated enum CircadianPlanner {

        /// `caffeineCutoffHour` lets the caller hand in the dose-aware last call
        /// resolved by `CaffeineWindowEngine` from the day's TIMED intakes. The
        /// planner stays clock-only: it never touches the food log. Nil keeps the
        /// single-serving fallback below, which is what callers with no intake
        /// data want.
        static func plan(phase: CircadianPhase,
                         habitualWakeHour: Double,
                         habitualSleepHour: Double,
                         typicalDoseMg: Double?,
                         caffeineCutoffHour: Double? = nil,
                         now: Date) -> CircadianPlan {
            let wake = habitualWakeHour
            // Normalize a post-midnight bedtime to a continuous value greater than
            // wake (a 02:00 sleep passed as 2 becomes 26) so the window math and the
            // late-exercise guard stay correct for night owls.
            let sleep = habitualSleepHour < wake ? habitualSleepHour + 24 : habitualSleepHour
            let cbt = phase.cbtMinHours

            // CBTmin is a clock hour and can sit on the far side of midnight from
            // wake (an early-shift sleeper can have CBTmin near 23:30 and wake at
            // 04:00), so bring it into a continuous frame around wake before
            // comparing the two.
            let cbtRelative: Double = {
                if cbt < wake - 12 { return cbt + 24 }
                if cbt > wake + 12 { return cbt - 24 }
                return cbt
            }()

            // Morning light: from the later of wake and CBTmin (light cannot be
            // sought while asleep), for 2.5 h, and tapering as it passes
            // CBTmin + 6 where the advance effect has decayed. The window never
            // inverts: a late riser past the advance zone still gets a short
            // actionable window rather than a backward one.
            let lightStart = max(wake, cbtRelative)
            let lightEnd = max(lightStart + 0.5, min(lightStart + 2.5, cbtRelative + 6))

            // Exercise: the core-temperature peak, ~12 to 14 h after CBTmin, but
            // never within 2 h of sleep.
            let exEnd = min(cbtRelative + 14, sleep - 2)
            let exStart = min(cbtRelative + 12, exEnd - 1)

            // Caffeine cutoff: the dose-aware last call when the caller resolved one
            // from the day's timed intakes, otherwise PK-derived from a single
            // typical serving against bedtime.
            let cutoff = caffeineCutoffHour
                ?? CaffeineModel.recommendedCutoffHour(bedtimeHour: habitualSleepHour,
                                                       typicalDoseMg: typicalDoseMg)

            let windows: [CircadianWindow] = [
                CircadianWindow(kind: .lightSeek,
                                startHour: CircadianMath.wrap24(lightStart),
                                endHour: CircadianMath.wrap24(lightEnd)),
                CircadianWindow(kind: .lightAvoid,
                                startHour: CircadianMath.wrap24(phase.dlmoHours),
                                endHour: CircadianMath.wrap24(sleep)),
                CircadianWindow(kind: .caffeineCutoff,
                                startHour: cutoff,
                                endHour: cutoff),
                CircadianWindow(kind: .exercise,
                                startHour: CircadianMath.wrap24(exStart),
                                endHour: CircadianMath.wrap24(exEnd)),
                CircadianWindow(kind: .windDown,
                                startHour: CircadianMath.wrap24(sleep - 0.75),
                                endHour: CircadianMath.wrap24(sleep)),
                CircadianWindow(kind: .sleep,
                                startHour: CircadianMath.wrap24(sleep),
                                endHour: CircadianMath.wrap24(wake)),
            ]

            return CircadianPlan(windows: windows,
                                 alignmentScore: alignmentScore(socialJetlagHours: phase.chronotype.socialJetlagHours))
        }

        /// 0 to 100 alignment from social jetlag: 0 h gives 100, 2 h gives 50,
        /// 4 h or more gives 0. nil when social jetlag is unknown.
        static func alignmentScore(socialJetlagHours: Double?) -> Int? {
            guard let sjl = socialJetlagHours else { return nil }
            let penalty = min(100.0, max(0.0, sjl) * 25.0)
            return min(100, max(0, Int((100 - penalty).rounded())))
        }
    }

    /// The plan resolved against a moment in time: the window you are inside now
    /// (if any) and the next window to act on.
    nonisolated struct CircadianMoment: Sendable, Equatable {
        /// A future window and how many hours away its start is (always positive,
        /// wrapping past midnight).
        nonisolated struct Upcoming: Sendable, Equatable {
            var window: CircadianWindow
            var hoursUntil: Double
        }

        var current: CircadianWindow?
        var next: Upcoming?
    }
}

extension SomaTools.CircadianPlan {
    /// Resolve the plan at `date`. `current` is the NARROWEST window whose span
    /// contains the clock hour: these windows nest (wind down sits inside dim
    /// light), and the tightest span is the most specific thing to be doing now.
    /// `next` is the window whose start is soonest ahead, wrapping midnight so
    /// it is never negative.
    nonisolated func moment(at date: Date, calendar: Calendar = .current) -> SomaTools.CircadianMoment {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let nowHour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60

        let current = windows
            .filter { w in
                guard w.startHour != w.endHour else { return false }
                let end = w.endHour > w.startHour ? w.endHour : w.endHour + 24
                let h = nowHour >= w.startHour ? nowHour : nowHour + 24
                return h >= w.startHour && h < end
            }
            .min { Self.spanHours($0) < Self.spanHours($1) }

        // A window starting exactly now reports as `current`, not as `next`,
        // so the zero-delta case is deliberately filtered out here.
        let next = windows
            .map { (w: $0, delta: SomaTools.CircadianMath.wrap24($0.startHour - nowHour)) }
            .filter { $0.delta > 0.0001 }
            .min { $0.delta < $1.delta }
            .map { SomaTools.CircadianMoment.Upcoming(window: $0.w, hoursUntil: $0.delta) }

        return SomaTools.CircadianMoment(current: current, next: next)
    }

    /// A window's length in hours, wrapping past midnight.
    nonisolated static func spanHours(_ w: SomaTools.CircadianWindow) -> Double {
        let end = w.endHour > w.startHour ? w.endHour : w.endHour + 24
        return end - w.startHour
    }
}
