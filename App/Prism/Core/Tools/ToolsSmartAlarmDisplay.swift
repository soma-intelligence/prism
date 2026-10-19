//
//  ToolsSmartAlarmDisplay.swift
//  Prism
//
//  The pure pieces of the alarm surfaces: WHEN the alarm card has something
//  true to say (its admission window in clock hours) and WHAT its detail line
//  says at a given instant. No clock read, no copy: everything is verifiable
//  on fixtures.
//

import Foundation

extension SomaTools {

    nonisolated enum SmartAlarmDisplay {

        /// A window of clock hours, possibly crossing midnight. Empty when
        /// start and end coincide.
        nonisolated struct HourWindow: Sendable, Equatable {
            var startHour: Int
            var endHour: Int

            func contains(hour: Int) -> Bool {
                if startHour <= endHour {
                    return hour >= startHour && hour < endHour
                }
                return hour >= startHour || hour < endHour
            }
        }

        /// The hours when the alarm card has something true to say. Opens one
        /// hour before the derived lights out (in the evening the card serves
        /// BEDTIME) and closes at the top of the hour after the ring. The lead
        /// is capped at twelve hours: the sleep need has a floor everywhere and
        /// never a ceiling, and a degenerate value would wrap the opening round
        /// the dial onto the closing and the card would vanish for good.
        static func cardWindow(ring: Date,
                               sleepNeedSeconds: Int,
                               calendar: Calendar = .current) -> HourWindow {
            let lightsOut = SmartAlarmBedtime.reading(ring: ring, sleepNeedSeconds: sleepNeedSeconds).lightsOut
            let lead = min(12 * 3600, ring.timeIntervalSince(lightsOut) + 3600)
            let open = ring.addingTimeInterval(-lead)
            return HourWindow(startHour: calendar.component(.hour, from: open),
                              endHour: (calendar.component(.hour, from: ring) + 1) % 24)
        }

        /// What the detail line announces, by instant. Compares ABSOLUTE
        /// instants, not minutes of the day: a minutes-of-day comparison treats
        /// any earlier target as "tomorrow" and read "in 19 h" at noon.
        nonisolated enum Moment: Sendable, Equatable {
            case beforeLightsOut(minutes: Int)
            case beforeRing(minutes: Int)
            case atRing
            case afterRing(minutes: Int)
        }

        /// The half hour either side of the ring where the card says "now"
        /// rather than a countdown.
        static let ringNowToleranceMinutes = 30

        static func moment(now: Date, ring: Date, lightsOut: Date) -> Moment {
            let toRing = Int((ring.timeIntervalSince(now) / 60).rounded())
            if abs(toRing) <= ringNowToleranceMinutes { return .atRing }
            if toRing < 0 { return .afterRing(minutes: -toRing) }
            let toLightsOut = Int((lightsOut.timeIntervalSince(now) / 60).rounded())
            return toLightsOut > 0
                ? .beforeLightsOut(minutes: toLightsOut)
                : .beforeRing(minutes: toRing)
        }

        /// Which day the ring falls on, relative to `now`.
        nonisolated enum RingDay: Sendable, Equatable {
            case today
            case tomorrow
            /// Calendar weekday, 1 = Sunday.
            case weekday(Int)
        }

        static func ringDay(_ ring: Date, now: Date, calendar: Calendar = .current) -> RingDay {
            if calendar.isDate(ring, inSameDayAs: now) { return .today }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
               calendar.isDate(ring, inSameDayAs: tomorrow) { return .tomorrow }
            return .weekday(calendar.component(.weekday, from: ring))
        }

        /// Signed display value of a factor's shift, in whole minutes; nil for
        /// a factor that is a bound or a context (zero shift).
        static func shiftMinutes(_ factor: SmartAlarmExplainer.Factor) -> Int? {
            guard factor.shiftSeconds != 0 else { return nil }
            let minutes = Int((abs(factor.shiftSeconds) / 60).rounded())
            return factor.shiftSeconds > 0 ? minutes : -minutes
        }
    }
}
