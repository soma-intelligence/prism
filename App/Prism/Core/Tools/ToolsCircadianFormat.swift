//
//  ToolsCircadianFormat.swift
//  Prism
//
//  Circadian clock and duration formatters.
//

import Foundation

extension SomaTools {

    /// Shared circadian clock/duration formatters.
    nonisolated enum CircadianFormat {

        /// Decimal clock hour to a clock the reader recognises: "22:15" where the
        /// region runs a 24-hour clock, "10:15 PM" where it runs a 12-hour one.
        ///
        /// The hour cycle is a REGION setting, so this reads the system locale on
        /// purpose, the same way `.formatted(date: .omitted, time: .shortened)`
        /// does for a `Date`, so every time printed on one screen agrees.
        ///
        /// The fallback keeps a plain "H:MM" string if the calendar cannot build
        /// the date, which it always can.
        static func clockLabel(_ hour: Double) -> String {
            let wrapped = CircadianMath.wrap24(hour)
            var h = Int(wrapped)
            var m = Int(((wrapped - Double(h)) * 60).rounded())
            if m == 60 { m = 0; h = (h + 1) % 24 }
            guard let date = Calendar.current.date(from: DateComponents(
                year: 2001, month: 1, day: 1, hour: h, minute: m)) else {
                return String(format: "%d:%02d", h, m)
            }
            return date.formatted(Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits))
        }

        /// The same clock, for a surface that already holds the instant.
        static func clockLabel(_ date: Date) -> String {
            date.formatted(Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits))
        }

        /// Hours as a short duration, e.g. 1.4 to "1h24", 2.0 to "2h".
        static func durationLabel(_ hours: Double) -> String {
            var h = Int(hours)
            var m = Int(((hours - Double(h)) * 60).rounded())
            if m == 60 { m = 0; h += 1 }
            return m == 0 ? "\(h)h" : String(format: "%dh%02d", h, m)
        }
    }
}
