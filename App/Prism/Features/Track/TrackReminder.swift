//
//  TrackReminder.swift
//  Prism
//

import Foundation
import UserNotifications

/// The daily nudge that asks how the day felt, at the hour set in Settings,
/// Notifications (the Journal row, its only switch).
///
/// A local notification and nothing else: it is scheduled on the device and
/// carries no data out of it.
enum TrackReminder {
    static let identifier = "journal.feeling"

    /// Asks for permission if it was never asked, then schedules the nudge.
    /// Returns whether notifications are allowed.
    @discardableResult
    static func enable(hour: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return false }
        await schedule(hour: hour)
        return true
    }

    /// Keeps the schedule in step with the questions when permission was
    /// already given, without ever putting the permission prompt up.
    static func sync(_ questions: JournalQuestions) async {
        guard questions.asksFeeling else {
            cancel()
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        await schedule(hour: questions.feelingHour)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static func schedule(hour: Int) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "How did today feel?")
        content.body = String(localized: "One tap in the Journal. Soma sets it beside your body.")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try? await center.add(request)
    }
}
