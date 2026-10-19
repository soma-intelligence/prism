//
//  ToolNotifier.swift
//  Prism
//

import Foundation
import UserNotifications

/// The one quiet note a tool may send, and only when someone asked for it.
///
/// Every "Remind me" on a tool page lands here: one local notification at one
/// moment, named after the tool so asking twice replaces the first rather than
/// stacking a second. Permission is asked the first time a person taps one,
/// never before.
enum ToolNotifier {
    /// Schedules `title` at `date`. Returns false when notifications are off
    /// or the moment has passed, so the page can say so.
    @discardableResult
    static func remind(id: String, title: String, body: String, at date: Date) async -> Bool {
        guard date > Date() else { return false }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: "tool.\(id)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["tool.\(id)"])
    }
}
