//
//  NotificationPlan.swift
//  Prism
//

import Foundation
import SomaUI

/// Every kind of thing Soma sends or finds, with the glyph and the colour it
/// wears in the inbox and on the settings page.
nonisolated enum SomaNotificationKind: String, Codable, CaseIterable, Sendable {
    case morningCheckIn, eveningCheckIn, lastMeal, bedtime, stand, weeklySummary, dataAlert, checkInLater, test, other

    var symbol: String {
        switch self {
        case .morningCheckIn: "sunrise"
        case .eveningCheckIn: "moon.stars"
        case .lastMeal: "fork.knife"
        case .bedtime: "bed.double"
        case .stand: "figure.stand"
        case .weeklySummary: "calendar"
        case .dataAlert: "waveform.path.ecg"
        case .checkInLater: "questionmark.bubble"
        case .test: "bell.badge"
        case .other: "bell"
        }
    }

    /// The kind behind a notification identifier, for what the phone delivered.
    static func kind(forIdentifier id: String) -> SomaNotificationKind {
        switch id {
        case ReminderPlan.Identifier.morning: return .morningCheckIn
        case ReminderPlan.Identifier.evening: return .eveningCheckIn
        case ReminderPlan.Identifier.lastMeal: return .lastMeal
        case NotificationPlanner.Identifier.bedtime: return .bedtime
        case NotificationPlanner.Identifier.weekly: return .weeklySummary
        case CheckInReminder.identifier: return .checkInLater
        default: break
        }
        if id.hasPrefix(NotificationPlanner.Identifier.standPrefix) { return .stand }
        if id.hasPrefix(NotificationPlanner.Identifier.alertPrefix) { return .dataAlert }
        if id.hasPrefix(NotificationPlanner.Identifier.testPrefix) { return .test }
        return .other
    }
}

/// The switches the notifications page adds to ``NotificationPreferences``:
/// the master switch, bedtime, stand, the weekly summary and data alerts.
///
/// Decoded field by field, so a file written by an older build keeps every
/// value it has and takes the default for the rest.
nonisolated struct NotificationSchedule: Codable, Equatable, Sendable {
    /// Off silences every Soma notification and keeps the switches as set.
    var isEnabled = true
    /// Wind down before the bedtime the sleep move asks for.
    var bedtime = true
    /// Minutes before that bedtime.
    var bedtimeLead = 30
    /// Ten to each waking hour inside the window, a minute to stand.
    var stand = false
    var standFrom = ClockTime(hour: 8)
    var standUntil = ClockTime(hour: 20)
    /// Sunday evening: the week in one place.
    var weekly = true
    /// 1 is Sunday, as `Calendar` counts.
    var weeklyWeekday = 1
    var weeklyTime = ClockTime(hour: 18)
    /// What Soma finds in the data, like a resting heart rate above usual.
    var dataAlerts = true

    static let bedtimeLeads = [15, 30, 45, 60]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = NotificationSchedule()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? base.isEnabled
        bedtime = try c.decodeIfPresent(Bool.self, forKey: .bedtime) ?? base.bedtime
        bedtimeLead = try c.decodeIfPresent(Int.self, forKey: .bedtimeLead) ?? base.bedtimeLead
        stand = try c.decodeIfPresent(Bool.self, forKey: .stand) ?? base.stand
        standFrom = try c.decodeIfPresent(ClockTime.self, forKey: .standFrom) ?? base.standFrom
        standUntil = try c.decodeIfPresent(ClockTime.self, forKey: .standUntil) ?? base.standUntil
        weekly = try c.decodeIfPresent(Bool.self, forKey: .weekly) ?? base.weekly
        weeklyWeekday = try c.decodeIfPresent(Int.self, forKey: .weeklyWeekday) ?? base.weeklyWeekday
        weeklyTime = try c.decodeIfPresent(ClockTime.self, forKey: .weeklyTime) ?? base.weeklyTime
        dataAlerts = try c.decodeIfPresent(Bool.self, forKey: .dataAlerts) ?? base.dataAlerts
    }
}

/// One notification Soma will hand the phone.
nonisolated struct PlannedNotification: Equatable, Sendable, Identifiable {
    nonisolated enum Trigger: Equatable, Sendable {
        /// Every day at this time.
        case daily(ClockTime)
        /// Once a week: weekday 1 is Sunday.
        case weekly(weekday: Int, ClockTime)
        /// Once, at this moment.
        case at(Date)
    }

    var id: String
    var kind: SomaNotificationKind
    var title: String
    var body: String
    var trigger: Trigger
    var link: SomaDeepLink?
}

/// Which notifications the switches call for, and when each fires next.
///
/// Pure: the rules (quiet hours, windows, dedupe) are tested without a
/// notification center. ``SomaNotifications`` hands the result to the phone.
nonisolated enum NotificationPlanner {
    nonisolated enum Identifier {
        static let bedtime = "soma.reminder.bedtime"
        static let weekly = "soma.reminder.weekly"
        /// The stand reminders, one request a waking hour. Settings owns the
        /// switch; Today's stand sheet only links to it.
        static let standPrefix = "soma.stand."
        static let alertPrefix = "soma.alert."
        static let testPrefix = "soma.test."

        static func stand(_ hour: Int) -> String { "\(standPrefix)\(hour)" }

        /// What the planner owns: anything else pending (a tool's alarm, the
        /// Journal's reminder, the check-in's Later) is left alone.
        static func isManaged(_ id: String) -> Bool {
            id.hasPrefix("soma.reminder.") || id.hasPrefix(standPrefix)
        }
    }

    struct Input: Sendable {
        var prefs: NotificationPreferences
        var schedule: NotificationSchedule
        var lastMealBy: ClockTime
        /// Tonight's "In bed by" from the sleep move, when there is one.
        var bedtime: ClockTime?
    }

    static func plan(_ input: Input) -> [PlannedNotification] {
        let schedule = input.schedule
        let prefs = input.prefs
        guard schedule.isEnabled else { return [] }

        var planned: [PlannedNotification] = ReminderPlan.reminders(prefs, lastMealBy: input.lastMealBy).map { reminder in
            let kind = SomaNotificationKind.kind(forIdentifier: reminder.id)
            let link: SomaDeepLink? = switch kind {
            case .morningCheckIn: .checkIn(.morning)
            case .eveningCheckIn: .checkIn(.evening)
            default: .today
            }
            return PlannedNotification(
                id: reminder.id, kind: kind, title: reminder.title, body: reminder.body,
                trigger: .daily(reminder.time), link: link
            )
        }

        // A bedtime or a stand reminder is only worth its moment: inside quiet
        // hours it is dropped, never moved to the morning.
        if schedule.bedtime, let target = input.bedtime {
            let time = target.adding(minutes: -schedule.bedtimeLead)
            if !isQuiet(time, prefs) {
                planned.append(PlannedNotification(
                    id: Identifier.bedtime, kind: .bedtime,
                    title: String(localized: "Wind down"),
                    body: String(localized: "In bed by \(target.text) tonight."),
                    trigger: .daily(time), link: .sleep
                ))
            }
        }

        if schedule.stand {
            for hour in standHours(schedule) where !isQuiet(ClockTime(hour: hour, minute: 50), prefs) {
                planned.append(PlannedNotification(
                    id: Identifier.stand(hour), kind: .stand,
                    title: String(localized: "Stand for a minute"),
                    body: String(localized: "Ten minutes left to count this hour."),
                    trigger: .daily(ClockTime(hour: hour, minute: 50)), link: .today
                ))
            }
        }

        if schedule.weekly {
            let time = isQuiet(schedule.weeklyTime, prefs) ? prefs.quietUntil : schedule.weeklyTime
            planned.append(PlannedNotification(
                id: Identifier.weekly, kind: .weeklySummary,
                title: String(localized: "Your week"),
                body: String(localized: "Sleep, heart and activity, side by side."),
                trigger: .weekly(weekday: schedule.weeklyWeekday, time), link: .trends
            ))
        }

        return staggered(deduped(planned))
    }

    /// The hours whose ten-to falls inside the stand window.
    static func standHours(_ schedule: NotificationSchedule) -> [Int] {
        (0..<24).filter { hour in
            let time = ClockTime(hour: hour, minute: 50)
            return time >= schedule.standFrom && time < schedule.standUntil
        }
    }

    static func isQuiet(_ time: ClockTime, _ prefs: NotificationPreferences) -> Bool {
        prefs.quietHours && time.isInside(from: prefs.quietFrom, until: prefs.quietUntil)
    }

    /// One request per identifier: the first planned wins.
    static func deduped(_ planned: [PlannedNotification]) -> [PlannedNotification] {
        var seen: Set<String> = []
        return planned.filter { seen.insert($0.id).inserted }
    }

    /// Two daily reminders never land in the same minute: the later one in the
    /// plan steps a minute on, so both arrive and in a fixed order (quiet
    /// hours can push a morning and an evening check-in onto 07:00).
    static func staggered(_ planned: [PlannedNotification]) -> [PlannedNotification] {
        var taken: Set<Int> = []
        return planned.map { item in
            guard case .daily(var time) = item.trigger else { return item }
            while taken.contains(time.minutes) { time = time.adding(minutes: 1) }
            taken.insert(time.minutes)
            var moved = item
            moved.trigger = .daily(time)
            return moved
        }
    }

    /// When a trigger next fires after `now`.
    static func nextFire(_ trigger: PlannedNotification.Trigger, after now: Date, calendar: Calendar = .current) -> Date? {
        switch trigger {
        case .daily(let time):
            return calendar.nextDate(
                after: now, matching: DateComponents(hour: time.hour, minute: time.minute),
                matchingPolicy: .nextTime
            )
        case .weekly(let weekday, let time):
            return calendar.nextDate(
                after: now, matching: DateComponents(hour: time.hour, minute: time.minute, weekday: weekday),
                matchingPolicy: .nextTime
            )
        case .at(let date):
            return date > now ? date : nil
        }
    }

    /// The soonest of a plan, and when.
    static func next(_ planned: [PlannedNotification], after now: Date, calendar: Calendar = .current) -> (PlannedNotification, Date)? {
        planned
            .compactMap { item in nextFire(item.trigger, after: now, calendar: calendar).map { (item, $0) } }
            .min { $0.1 < $1.1 }
    }

    /// The time out of the sleep move's title, "In bed by 11:00 PM" or
    /// "In bed by 23:00". Nil when the title holds no time.
    static func bedtime(fromMoveTitle title: String) -> ClockTime? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d{1,2})[:.](\\d{2})\\s*([AaPp])?\\.?\\s*[Mm]?") else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        guard let match = regex.firstMatch(in: title, range: range),
              let hourRange = Range(match.range(at: 1), in: title),
              let minuteRange = Range(match.range(at: 2), in: title),
              var hour = Int(title[hourRange]), let minute = Int(title[minuteRange]),
              hour < 24, minute < 60 else { return nil }
        if let markRange = Range(match.range(at: 3), in: title) {
            let isPM = title[markRange].lowercased() == "p"
            guard hour >= 1, hour <= 12 else { return nil }
            hour = hour % 12 + (isPM ? 12 : 0)
        }
        return ClockTime(hour: hour, minute: minute)
    }

    /// Whether Settings should take over a stand reminder Today switched on:
    /// stand requests are pending, the planner did not put them there, and the
    /// switch here is off.
    static func adoptsStand(pending: [String], applied: Set<String>, schedule: NotificationSchedule) -> Bool {
        guard !schedule.stand else { return false }
        let pendingStand = pending.filter { $0.hasPrefix(Identifier.standPrefix) }
        return !pendingStand.isEmpty && !pendingStand.contains(where: applied.contains)
    }
}

/// What Soma finds in the data and says once.
nonisolated enum DataAlertRules {
    /// The key under which the resting heart rate alert is deduped.
    static let restingHigh = "restingHigh"
    /// An alert of one kind is raised at most once in this span.
    static let quietSpan: TimeInterval = 3 * 24 * 3600

    /// The last three days each sit above the top of the usual band.
    static func restingAboveUsual(days: [Double?], band: ClosedRange<Double>?) -> Bool {
        guard let band, days.count >= 3 else { return false }
        let last = days.suffix(3)
        return last.allSatisfy { value in value.map { $0 > band.upperBound } ?? false }
    }

    static func shouldRaise(lastRaised: Date?, now: Date) -> Bool {
        guard let lastRaised else { return true }
        return now.timeIntervalSince(lastRaised) >= quietSpan
    }
}
