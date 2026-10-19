//
//  OnboardingPermissions.swift
//  Prism
//

import SwiftUI
import CoreLocation
import EventKit
import UserNotifications

/// Where one system permission stands.
enum OnboardingPermissionState: Equatable, Sendable {
    /// Never asked: Continue raises the system prompt.
    case notAsked
    case allowed
    /// Refused, or restricted by the device. iOS does not ask twice, so the
    /// only way back is Settings.
    case declined
}

/// The three system permissions the onboarding asks for, each read and asked
/// through the platform's own API. Nothing here stores an answer of its own:
/// the system keeps the record, so the answer cannot drift from what it did.
enum OnboardingPermission {
    // MARK: Location

    static func locationState() -> OnboardingPermissionState {
        state(for: CLLocationManager().authorizationStatus)
    }

    /// Asks for location while in use, and waits for the answer.
    static func requestLocation() async -> OnboardingPermissionState {
        let current = locationState()
        guard current == .notAsked else { return current }
        let status = await LocationAsker().ask()
        return state(for: status)
    }

    static func state(for status: CLAuthorizationStatus) -> OnboardingPermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .denied, .restricted: .declined
        default: .allowed
        }
    }

    // MARK: Calendar

    static func calendarState() -> OnboardingPermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notAsked
        case .fullAccess: .allowed
        // Write only cannot see when someone is busy, which is all this asks
        // for, so it counts as off.
        default: .declined
        }
    }

    /// Asks for calendar access. Soma reads when a person is busy and never
    /// an event's title, but free and busy needs events, so this is the full
    /// read the system offers.
    static func requestCalendar() async -> OnboardingPermissionState {
        let current = calendarState()
        guard current == .notAsked else { return current }
        _ = try? await EKEventStore().requestFullAccessToEvents()
        return calendarState()
    }

    // MARK: Notifications

    static func notificationState() async -> OnboardingPermissionState {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .declined
        default: .allowed
        }
    }

    static func requestNotifications() async -> OnboardingPermissionState {
        let current = await notificationState()
        guard current == .notAsked else { return current }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return await notificationState()
    }
}

/// Holds a location manager until the person answers its prompt.
///
/// The manager reports its status once on creation, before anything is asked,
/// so only a settled answer ends the wait.
@MainActor
private final class LocationAsker: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    /// Keeps the asker alive while the prompt is up.
    private var keepAlive: LocationAsker?

    func ask() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            keepAlive = self
            manager.delegate = self
            // Approximate is enough for weather and the sun.
            manager.desiredAccuracy = kCLLocationAccuracyReduced
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: status)
        keepAlive = nil
    }
}

/// Opens this app's page in the system Settings, where a refused permission
/// is turned back on.
struct OpenSystemSettings {
    let openURL: OpenURLAction

    func callAsFunction() {
#if os(iOS) || os(visionOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
#elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            openURL(url)
        }
#endif
    }
}
