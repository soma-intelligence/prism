//
//  Reminders.swift
//  Prism
//

import Foundation
import UserNotifications

/// One reminder Soma will ask the phone to deliver every day.
nonisolated struct PlannedReminder: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var time: ClockTime
}

/// Which daily reminders the preferences call for.
///
/// Every schedule is re-derived from the
/// switches on each change, so what is pending always mirrors what the page
/// shows. Pure, so the rules are tested without a notification center.
///
/// Only reminders with something behind them are planned. Pod visits, blood
/// tests, tools and a quiet source need a source Soma does not have yet, so
/// their switches are kept but plan nothing.
nonisolated enum ReminderPlan {
    nonisolated enum Identifier {
        static let morning = "soma.reminder.morning"
        static let evening = "soma.reminder.evening"
        static let lastMeal = "soma.reminder.lastMeal"
        static let all = [morning, evening, lastMeal]
    }

    /// How long before the last meal cutoff the evening nudge arrives.
    static let lastMealLead = 30

    static func reminders(_ prefs: NotificationPreferences, lastMealBy: ClockTime) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        if prefs.morningCheckIn {
            planned.append(PlannedReminder(
                id: Identifier.morning,
                title: String(localized: "Morning check-in"),
                body: String(localized: "How you slept and how you feel."),
                time: prefs.morningTime
            ))
        }
        if prefs.eveningCheckIn {
            planned.append(PlannedReminder(
                id: Identifier.evening,
                title: String(localized: "Evening check-in"),
                body: String(localized: "The day in a line, before wind down."),
                time: prefs.eveningTime
            ))
        }
        if prefs.eveningNudges {
            planned.append(PlannedReminder(
                id: Identifier.lastMeal,
                title: String(localized: "Eat before \(lastMealBy.text)"),
                body: String(localized: "An earlier last meal is one of the easiest ways to a better night."),
                time: lastMealBy.adding(minutes: -lastMealLead)
            ))
        }
        return planned.map { delivered($0, prefs: prefs) }
    }

    /// A reminder that falls in quiet hours waits for them to end.
    static func delivered(_ reminder: PlannedReminder, prefs: NotificationPreferences) -> PlannedReminder {
        guard prefs.quietHours, reminder.time.isInside(from: prefs.quietFrom, until: prefs.quietUntil) else {
            return reminder
        }
        var moved = reminder
        moved.time = prefs.quietUntil
        return moved
    }
}

/// The old entry points, kept for callers that predate ``SomaNotifications``.
/// Everything goes through it now, so one plan holds every Soma reminder.
@MainActor
enum ReminderScheduler {
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once. Returns whether alerts are allowed afterwards.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        await SomaNotifications.shared.scheduler.requestAuthorization()
    }

    /// Replaces every Soma reminder with what the preferences call for. The
    /// arguments are read from ``GlobalSettings`` by the shared plan.
    static func apply(_ prefs: NotificationPreferences, lastMealBy: ClockTime) async {
        await SomaNotifications.shared.apply()
    }

    /// How many Soma reminders the phone holds right now.
    static func pendingCount() async -> Int {
        await SomaNotifications.shared.scheduler.pendingIdentifiers()
            .filter(NotificationPlanner.Identifier.isManaged).count
    }
}
