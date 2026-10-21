//
//  NextMoveClock.swift
//  Prism
//

import Foundation

/// The time the orb's advice is worked out for.
///
/// Always now on a device. A Debug build launched with `-nextmove.now HH:mm`
/// reads today at that clock time instead, so the advice of any part of the
/// day can be looked at on a simulator whose clock cannot be set.
enum NextMoveClock {
    /// The defaults key behind `-nextmove.now HH:mm`.
    static let launchKey = "nextmove.now"

    static func now(defaults: UserDefaults = .standard, calendar: Calendar = .current, real: Date = Date()) -> Date {
#if DEBUG
        if let text = defaults.string(forKey: launchKey), let date = time(text, on: real, calendar: calendar) {
            return date
        }
#endif
        return real
    }

    /// `HH:mm` on the day of `day`, or nil when the text is not a clock time.
    static func time(_ text: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
