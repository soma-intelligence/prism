//
//  SomaNotificationRouter.swift
//  Prism
//

import Foundation
import UserNotifications

/// The notification center's one delegate: what was tapped goes to the inbox
/// as read, to the check-in presenter (so its automatic run stands aside, and
/// a check-in reminder opens it), and to ``SomaDeepLinkRouter``.
///
/// It replaces `CheckInNotificationRouter`: a center holds one delegate, and
/// this one forwards everything that one did. Install it at launch with
/// ``install()``; the shell's ``SomaDeepLinkHandling`` installs it too, for
/// a build whose app entry does not yet.
final class SomaNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SomaNotificationRouter()

    static func install() {
        let center = UNUserNotificationCenter.current()
        guard !(center.delegate is SomaNotificationRouter) else { return }
        center.delegate = shared
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let delivered = DeliveredNotification(response.notification)
        let isDefaultTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        await MainActor.run {
            SomaNotifications.shared.record(delivered, isRead: isDefaultTap)
            CheckInPresenter.shared.openFromNotification(identifier: delivered.id)
            guard isDefaultTap else { return }
            let link = delivered.link ?? Self.fallbackLink(for: delivered.id)
            // A check-in reminder is opened by the presenter itself.
            if case .checkIn = link, CheckInPresenter.opens(delivered.id) { return }
            if let link { SomaDeepLinkRouter.shared.open(link) }
        }
    }

    /// While the app is open the reminders stay quiet, as before: they are for
    /// when it is not. What arrives still lands in the inbox, and the
    /// delivery test shows, since showing is its whole point.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let delivered = DeliveredNotification(notification)
        await MainActor.run { SomaNotifications.shared.record(delivered) }
        let kind = SomaNotificationKind.kind(forIdentifier: delivered.id)
        return kind == .test || kind == .dataAlert ? [.banner, .list, .sound] : [.list]
    }

    /// Where a notification sent before links were attached opens.
    nonisolated static func fallbackLink(for identifier: String) -> SomaDeepLink? {
        switch SomaNotificationKind.kind(forIdentifier: identifier) {
        case .morningCheckIn: .checkIn(.morning)
        case .eveningCheckIn, .checkInLater: .checkIn(.evening)
        case .bedtime: .sleep
        case .weeklySummary: .trends
        case .dataAlert, .test: .inbox
        case .lastMeal, .stand, .other: .today
        }
    }
}
