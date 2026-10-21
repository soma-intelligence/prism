//
//  NextMoveDay.swift
//  Prism
//
//  The person's own day: when they woke, when they usually sleep, and which
//  part of that day it is now. Advice is timed against this, never against
//  the clock alone, so a night owl's eight o'clock is not an early riser's.
//

import Foundation

/// A part of the person's own day, from waking to the usual bedtime.
enum NextMoveDayPart: String, Sendable, CaseIterable {
    /// The first four hours after waking.
    case morning
    /// The three hours after that.
    case midday
    /// From there to four hours before the usual bedtime.
    case afternoon
    /// The four hours before the usual bedtime: winding down.
    case evening
    /// Past the usual bedtime, until an hour before the usual wake.
    case night

    /// Every part a person is usually up in.
    static let awake: Set<NextMoveDayPart> = [.morning, .midday, .afternoon, .evening]
    /// The parts a day's plan is still ahead in.
    static let daytime: Set<NextMoveDayPart> = [.morning, .midday, .afternoon]
}

/// When this person wakes and sleeps, read from their recent nights.
///
/// Without enough nights the day falls back to a conventional one, seven to
/// eleven, and says so through `isPersonal`: timing still has to be decided,
/// but no rule may claim that it knows this person's bedtime.
struct NextMoveDay: Sendable, Equatable {
    /// The usual wake and bed times, as decimal clock hours (23.5 is half
    /// past eleven). Nil when there were too few nights to say.
    var usualWakeHour: Double? = nil
    var usualBedHour: Double? = nil
    /// When this person woke today, when a night ending today is recorded.
    var wokeToday: Date? = nil

    static let conventionalWake = 7.0
    static let conventionalBed = 23.0

    static let morningHours = 4.0
    static let middayHours = 3.0
    static let eveningHours = 4.0
    /// People often wake a little before their usual: the last hour before it
    /// already counts as morning.
    static let earlyWakeGrace = 1.0

    var isPersonal: Bool { usualWakeHour != nil && usualBedHour != nil }
    var wakeHour: Double { usualWakeHour ?? Self.conventionalWake }
    var bedHour: Double { usualBedHour ?? Self.conventionalBed }

    /// The hour the day is measured from: today's actual wake when known,
    /// the usual one otherwise.
    func anchorHour(calendar: Calendar) -> Double {
        wokeToday.map { Self.decimalHour($0, calendar: calendar) } ?? wakeHour
    }

    /// Hours since the day began, in 0..<24.
    func hoursSinceWake(at now: Date, calendar: Calendar) -> Double {
        Self.wrap(Self.decimalHour(now, calendar: calendar) - anchorHour(calendar: calendar))
    }

    /// Hours from waking to the usual bedtime, kept within what a day can be.
    func awakeSpan(calendar: Calendar) -> Double {
        let span = Self.wrap(bedHour - anchorHour(calendar: calendar))
        return (10...21).contains(span) ? span : Self.wrap(bedHour - wakeHour)
    }

    /// Hours past the usual bedtime, or nil when it has not come yet today.
    func hoursPastBedtime(at now: Date, calendar: Calendar) -> Double? {
        let since = hoursSinceWake(at: now, calendar: calendar)
        let span = awakeSpan(calendar: calendar)
        return since >= span ? since - span : nil
    }

    /// Hours until the usual wake.
    func hoursUntilWake(at now: Date, calendar: Calendar) -> Double {
        Self.wrap(wakeHour - Self.decimalHour(now, calendar: calendar))
    }

    func part(at now: Date, calendar: Calendar) -> NextMoveDayPart {
        let since = hoursSinceWake(at: now, calendar: calendar)
        let span = awakeSpan(calendar: calendar)
        if since >= span {
            // Woken early: the hour before the usual wake is the morning.
            return wokeToday == nil && hoursUntilWake(at: now, calendar: calendar) <= Self.earlyWakeGrace
                ? .morning : .night
        }
        if since >= span - Self.eveningHours { return .evening }
        if since < Self.morningHours { return .morning }
        if since < Self.morningHours + Self.middayHours { return .midday }
        return .afternoon
    }

    /// Today's date at a decimal clock hour, on the morning side of the day
    /// `now` belongs to.
    func date(atHour hour: Double, on now: Date, calendar: Calendar) -> Date? {
        let minutes = Int((Self.wrap(hour) * 60).rounded())
        return calendar.date(bySettingHour: minutes / 60 % 24, minute: minutes % 60, second: 0, of: now)
    }

    static func decimalHour(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    static func wrap(_ hours: Double) -> Double {
        let wrapped = hours.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }
}
