//
//  ToolFormat.swift
//  Prism
//

import Foundation

/// How the tool pages write times, durations and doses.
///
/// Clock times follow the region's hour cycle through `Date.FormatStyle`, so a
/// reader in a 12 hour region sees the same clock here as everywhere else in
/// the app. A missing value is the caller's dash; nothing here invents one.
nonisolated enum ToolFormat {
    /// "23:30", or "11:30 PM" where the region reads a 12 hour clock.
    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
    }

    /// A decimal clock hour (may run past 24) as a clock time.
    static func clock(hour: Double, calendar: Calendar = .current) -> String {
        var wrapped = hour.truncatingRemainder(dividingBy: 24)
        if wrapped < 0 { wrapped += 24 }
        var h = Int(wrapped)
        var m = Int(((wrapped - Double(h)) * 60).rounded())
        if m == 60 { m = 0; h = (h + 1) % 24 }
        guard let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: h, minute: m)) else {
            return String(format: "%02d:%02d", h, m)
        }
        return clock(date)
    }

    /// Hours on an axis: "22", "01", "04".
    static func hourLabel(_ hour: Double) -> String {
        var wrapped = Int(hour.rounded()) % 24
        if wrapped < 0 { wrapped += 24 }
        return String(format: "%02d", wrapped)
    }

    /// Hours as "7:12".
    static func hoursMinutes(_ hours: Double) -> String {
        let total = Int((abs(hours) * 60).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A span as "3 h 28", "45 min" or "2 h".
    static func span(hours: Double) -> String {
        let total = Int((abs(hours) * 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(String(format: "%02d", m))"
    }

    /// "16 September", or "Wednesday 16 September" with the weekday.
    static func day(_ date: Date, weekday: Bool = false) -> String {
        var style = Date.FormatStyle().day().month(.wide)
        if weekday { style = style.weekday(.wide) }
        return date.formatted(style)
    }

    /// A short day: "Wed 30 Sep".
    static func shortDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated))
    }

    /// A whole number with grouping: "9,840".
    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// The first letter up, for a sentence built from parts.
    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// A count in words up to twelve, the way the copy reads ("three nights").
    static func words(_ count: Int) -> String {
        let names = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return count >= 0 && count < names.count ? names[count] : "\(count)"
    }
}
