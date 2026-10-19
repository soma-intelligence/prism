//
//  ToolsAirlockDeepWork.swift
//  Prism
//
//  Where a deep work block should really sit, once the real day is laid over
//  the vigilance peak band.
//
//  WHY IT EXISTS. A deep work window taken from circadian vigilance alone,
//  without looking at the calendar, lands in the middle of meetings on a busy
//  day. This planner does not move the peak band (a meeting does not move a
//  body clock); it CHOOSES, inside that band, the stretch the day leaves free.
//
//  THE FLOOR IS NOT INVENTED: 120 minutes is the usable block the schedule
//  load score already uses for "long enough to do something deep".
//
//  Pure, no actor. The agenda is a minimal day of meetings of its own.
//

import Foundation

extension SomaTools {

    /// One day of meetings, in the one shape the planner reads.
    nonisolated struct AirlockAgenda: Sendable, Equatable {

        /// A meeting as the calendar source hands it over.
        struct Event: Sendable, Equatable {
            let start: Date
            let end: Date
            var isAllDay: Bool
            /// Declined invitations are not busy time.
            var accepted: Bool

            init(start: Date, end: Date, isAllDay: Bool = false, accepted: Bool = true) {
                self.start = start
                self.end = end
                self.isAllDay = isAllDay
                self.accepted = accepted
            }
        }

        /// Start of the day this agenda speaks about.
        let day: Date
        /// The day's meetings: chronological, all day events and refusals
        /// excluded, clipped to the day.
        let meetings: [DateInterval]

        /// The only initialiser that filters.
        init(day: Date, events: [Event], calendar: Calendar = .current) {
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            self.day = start
            self.meetings = events
                .filter { !$0.isAllDay && $0.accepted }
                .filter { $0.start < end && $0.end > start }
                .map { DateInterval(start: max($0.start, start), end: min($0.end, end)) }
                .sorted { $0.start < $1.start }
        }

        /// EMPTY means "nothing to say", never "a free day": no access and a
        /// switched off source look exactly the same.
        var isEmpty: Bool { meetings.isEmpty }

        /// Free stretches of at least `minimumMinutes` inside `window`.
        func freeGaps(minimumMinutes: Int, within window: DateInterval) -> [DateInterval] {
            let minimum = TimeInterval(minimumMinutes * 60)
            var gaps: [DateInterval] = []
            var cursor = window.start
            for span in Self.merged(meetings) {
                guard span.end > window.start, span.start < window.end else { continue }
                let blockedStart = max(span.start, window.start)
                if blockedStart.timeIntervalSince(cursor) >= minimum {
                    gaps.append(DateInterval(start: cursor, end: blockedStart))
                }
                cursor = max(cursor, min(span.end, window.end))
            }
            if window.end.timeIntervalSince(cursor) >= minimum {
                gaps.append(DateInterval(start: cursor, end: window.end))
            }
            return gaps
        }

        /// The longest free stretch of `window`, or nil when none reaches the
        /// minimum.
        func longestFreeGap(minimumMinutes: Int, within window: DateInterval) -> DateInterval? {
            freeGaps(minimumMinutes: minimumMinutes, within: window).max { $0.duration < $1.duration }
        }

        /// Busy intervals, overlaps merged.
        static func merged(_ spans: [DateInterval]) -> [DateInterval] {
            var out: [DateInterval] = []
            for span in spans where span.end > span.start {
                if let last = out.last, span.start <= last.end {
                    out[out.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
                } else {
                    out.append(span)
                }
            }
            return out
        }
    }

    nonisolated enum AirlockDeepWorkPlanner {

        /// The block it takes to do something deep. Below it the day is choppy
        /// even if its busy total stays modest.
        static let usableBlockMinutes = 120.0

        /// What the day leaves of the peak band.
        enum Outcome: Sendable, Equatable {
            /// The window to protect, in clock hours. Equal to the peak band when
            /// the agenda says nothing, shorter when it says something.
            case band(startHour: Double, endHour: Double)
            /// The band is taken and no free stretch is long enough. NO window,
            /// and the caller must SAY so: a window that vanishes silently reads
            /// as a setting that switched itself off.
            case bookedOut
        }

        /// The window to protect today.
        /// - Parameters:
        ///   - peakStartHour, peakEndHour: the vigilance band, as is.
        ///   - agenda: the real day. EMPTY leaves the band unchanged.
        ///   - day: the day the clock hours speak about.
        static func window(peakStartHour: Double,
                           peakEndHour: Double,
                           agenda: AirlockAgenda,
                           day: Date,
                           calendar: Calendar = .current) -> Outcome {
            let unchanged = Outcome.band(startHour: peakStartHour, endHour: peakEndHour)

            // A band that crosses midnight is not a daytime vigilance band: left
            // alone rather than read some invented way.
            let bandMinutes = (peakEndHour - peakStartHour) * 60
            guard bandMinutes > 0 else { return unchanged }
            guard !agenda.isEmpty else { return unchanged }

            let dayStart = calendar.startOfDay(for: day)
            guard let start = calendar.date(byAdding: .second, value: Int(peakStartHour * 3600), to: dayStart),
                  let end = calendar.date(byAdding: .second, value: Int(peakEndHour * 3600), to: dayStart),
                  end > start else { return unchanged }

            // Bounded by the band's length: a peak band shorter than the usable
            // block exists (a broken night makes one), and without this bound it
            // would be called booked out with an empty agenda in front of it.
            let floor = Int(min(usableBlockMinutes, bandMinutes))

            guard let gap = agenda.longestFreeGap(minimumMinutes: floor,
                                                  within: DateInterval(start: start, end: end)) else {
                return .bookedOut
            }
            return .band(startHour: gap.start.timeIntervalSince(dayStart) / 3600,
                         endHour: gap.end.timeIntervalSince(dayStart) / 3600)
        }
    }
}
