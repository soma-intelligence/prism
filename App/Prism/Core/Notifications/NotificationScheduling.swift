//
//  NotificationScheduling.swift
//  Prism
//

import Foundation
import UserNotifications

/// Whether the phone lets Soma notify, in the three states the pages tell
/// apart.
nonisolated enum NotificationAuthorization: String, Sendable, Equatable {
    case notDetermined, denied, authorized

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .authorized
        case .denied: self = .denied
        default: self = .notDetermined
        }
    }
}

/// A notification the phone already showed, as the inbox keeps it.
nonisolated struct DeliveredNotification: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var date: Date
    var link: SomaDeepLink?
}

/// The seam between the rules and the notification center, so the rules are
/// tested against a fake and the app talks to `UNUserNotificationCenter`.
protocol NotificationScheduling: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification) async throws
    func remove(_ identifiers: [String]) async
    func delivered() async -> [DeliveredNotification]
}

/// The phone's own notification center. Local only: nothing goes through a
/// server.
nonisolated struct SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> NotificationAuthorization {
        NotificationAuthorization(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func add(_ notification: PlannedNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.kind.rawValue
        if notification.kind == .dose { content.categoryIdentifier = MedicationReminders.categoryIdentifier }
        if let link = notification.link {
            content.userInfo = [SomaDeepLink.userInfoKey: link.url.absoluteString]
        }
        let trigger: UNNotificationTrigger = switch notification.trigger {
        case .daily(let time):
            UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: time.hour, minute: time.minute), repeats: true)
        case .weekly(let weekday, let time):
            UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: time.hour, minute: time.minute, weekday: weekday), repeats: true
            )
        case .at(let date):
            UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        case .wallClock(let parts):
            // No time zone in the components: the phone's own, wherever it is.
            UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
    }

    func remove(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func delivered() async -> [DeliveredNotification] {
        await center.deliveredNotifications().map(DeliveredNotification.init)
    }
}

extension DeliveredNotification {
    nonisolated init(_ notification: UNNotification) {
        let content = notification.request.content
        self.init(
            id: notification.request.identifier,
            title: content.title,
            body: content.body,
            date: notification.date,
            link: SomaDeepLink(userInfo: content.userInfo)
        )
    }
}
