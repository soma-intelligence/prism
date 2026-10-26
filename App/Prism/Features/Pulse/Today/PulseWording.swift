//
//  PulseWording.swift
//  Prism
//

import Foundation
import SomaUI

/// What the Today page says, in its own words.
///
/// Every sentence is written from numbers the store returned, and names them,
/// so a line can be checked against Health by anyone who reads it. When a
/// number is missing the sentence that needs it is not written at all.
struct PulseWording {
    let calendar: Calendar
    let locale: Locale

    // MARK: - Numbers

    /// Seconds as hours and minutes on a clock face: 7:12.
    func clock(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// Seconds as whole minutes: 68 min.
    func minutes(_ seconds: TimeInterval) -> String {
        "\(whole(seconds / 60)) min"
    }

    /// A gap between two durations: 46 min, or 1 h 24 min once it passes the
    /// hour, so it never reads as a time of day.
    func span(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    func whole(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(locale))
    }

    /// A clock time in the person's own format: 07:16, or 7:16 AM.
    func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return date.formatted(style)
    }

    // MARK: - The day's parts

    enum Part { case morning, afternoon, evening }

    func part(of date: Date) -> Part {
        switch calendar.component(.hour, from: date) {
        case ..<12: .morning
        case ..<17: .afternoon
        default: .evening
        }
    }

    /// The title over the moves: they are for what is left of the day.
    func movesTitle(at date: Date) -> String {
        part(of: date) == .evening ? "Tonight" : "For today"
    }

    // MARK: - The orb

    /// The move written on an aspect's orb, in two words.
    static func orbMove(_ aspect: SomaAspect) -> LocalizedStringResource {
        switch aspect {
        case .body: "Stand tall"
        case .mind: "Slow down"
        case .sleep: "Wind down"
        case .heart: "Ease off"
        case .gut: "Eat early"
        case .activity: "Move now"
        }
    }

    // MARK: - Counting

    func count(_ n: Int, _ one: String, _ many: String) -> String {
        let words = ["no", "one", "two", "three", "four"]
        let number = n < words.count ? words[n] : "\(n)"
        return "\(number) \(n == 1 ? one : many)"
    }

    func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    // MARK: - Events

    func wokeUp(_ night: PulseNight) -> String {
        guard let deep = night.deep else { return "Slept \(clock(night.asleep))." }
        return "Slept \(clock(night.asleep)), \(minutes(deep)) of deep sleep."
    }

    func workout(_ workout: PulseWorkout) -> String {
        let length = "\(whole(workout.minutes)) min"
        if let steps = workout.steps {
            return "\(length), \(whole(steps)) steps."
        }
        if let zone = workout.zoneThreeMinutes {
            let inZone = Int(zone.rounded())
            return inZone == 0
                ? "\(length), all of it under zone 3."
                : "\(length), \(inZone) of them in zone 3 and above."
        }
        if let average = workout.averageHeartRate {
            return "\(length), \(whole(average)) bpm on average."
        }
        return "\(length)."
    }

    func peak(_ peak: PulsePeak) -> String {
        "Heart at \(whole(peak.peak)) while still, \(whole(peak.above)) above resting."
    }

    func now(steps: Double?, exercise: Double?) -> String {
        switch (steps, exercise) {
        case let (steps?, exercise?):
            "\(whole(steps)) steps and \(whole(exercise)) min of exercise so far."
        case let (steps?, nil):
            "\(whole(steps)) steps so far."
        case let (nil, exercise?):
            "\(whole(exercise)) min of exercise so far."
        case (nil, nil):
            "Nothing recorded yet today."
        }
    }

    // MARK: - Cards

    func sleepSummary(_ night: PulseNight?, week: [PulseNight]) -> String {
        guard let night else { return "No night recorded yet." }
        let deep = night.deep.map { ", \(minutes($0)) deep." } ?? "."
        let others = week.filter { $0.day != night.day }
        guard others.count >= 2 else { return "Asleep \(clock(night.asleep))" + deep }
        if night.asleep >= (others.map(\.asleep).max() ?? 0) {
            return "Your longest night this week" + deep
        }
        let average = others.map(\.asleep).reduce(0, +) / Double(others.count)
        let gap = night.asleep - average
        if abs(gap) < 10 * 60 { return "Close to your week's average" + deep }
        return "\(span(abs(gap))) \(gap < 0 ? "under" : "over") your week's average" + deep
    }

    func heartSummary(resting: Double, usual: Double?, lowest: (value: Double, at: Date)?) -> String {
        var line: String
        if let usual {
            let gap = (resting - usual).rounded()
            line = abs(gap) < 2 ? "Close to your usual" : "\(whole(abs(gap))) \(gap < 0 ? "below" : "above") your usual"
        } else {
            line = "Your usual needs a few more days"
        }
        if let lowest {
            line += ", lowest at \(time(lowest.at)) last night."
        } else {
            line += "."
        }
        return line
    }

    func bodySummary(age: Int?) -> String {
        let base = "Measured at the pod. No visit yet."
        guard let age else { return base }
        return base + " You are \(age)."
    }

    /// A 0 to 100 score as the row prints it.
    func score(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// The line under the energy bank: what it is made of, or what fills it.
    func energyNote(_ scores: SomaScores?) -> String {
        guard let scores else { return "Reading ninety days of Apple Health to work out your energy." }
        guard scores.energy != nil else {
            return "Energy fills in once Apple Health holds a night of sleep to charge from."
        }
        var note = "Charged by last night's sleep, spent by the hours awake and today's activity."
        if let stress = scores.stress {
            note += " Stress today is \(score(stress)) of 100."
        }
        return note
    }
}
