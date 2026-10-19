//
//  OnboardingPermissionSteps.swift
//  Prism
//

import SwiftUI
import SomaUI

// MARK: - Connect

/// Every permission on one screen: Apple Health, location, calendar and
/// notifications, each a row with its one reason and its own Allow. Allow
/// raises the system's prompt there and then; a row left alone is the same as
/// Later, and Continue never waits on any of them.
///
/// Health goes through `HealthDashboard.start()`, whose request is
/// `HealthAccess.requestEverything`: the one sheet for every type the app
/// reads and writes, then the phone's Motion & Fitness question. Health never
/// tells an app that a read was refused, so its row says it was asked, never
/// that it is on.
struct OnboardingConnectView: View {
    let model: OnboardingModel

    @Environment(HealthDashboard.self) private var health
    @Environment(\.openURL) private var openURL

    @State private var healthState: OnboardingRowState = .notAsked
    @State private var location: OnboardingRowState = .notAsked
    @State private var calendar: OnboardingRowState = .notAsked
    @State private var notifications: OnboardingRowState = .notAsked

    var body: some View {
        OnboardingPage(title: String(localized: "Connect your day.")) {
            OnboardingRowsCard(items: rows) { row in
                OnboardingRow(title: row.title, detail: row.detail) {
                    OnboardingGlyph(symbol: row.symbol)
                } trailing: {
                    OnboardingAllowButton(state: row.state) {
                        switch row.state {
                        case .declined: OpenSystemSettings(openURL: openURL)()
                        default: Task { await ask(row.id) }
                        }
                    }
                }
            }
            .onboardingArrival(1)
        }
        .task { await readStates() }
    }

    private struct Row: Identifiable {
        let id: Kind
        let symbol: String
        let title: String
        let detail: String
        let state: OnboardingRowState
    }

    private enum Kind { case health, location, calendar, notifications }

    private var rows: [Row] {
        [
            Row(id: .health, symbol: "heart", title: String(localized: "Apple Health"),
                detail: String(localized: "Heart and sleep, read only."), state: healthState),
            Row(id: .location, symbol: "location", title: String(localized: "Location"),
                detail: String(localized: "Weather and daylight, approximate."), state: location),
            Row(id: .calendar, symbol: "calendar", title: String(localized: "Calendar"),
                detail: String(localized: "Busy times and event names, for Mind."), state: calendar),
            Row(id: .notifications, symbol: "bell", title: String(localized: "Notifications"),
                detail: String(localized: "A morning brief, few nudges."), state: notifications),
        ]
    }

    private func readStates() async {
        location = OnboardingRowState(OnboardingPermission.locationState())
        calendar = OnboardingRowState(OnboardingPermission.calendarState())
        notifications = OnboardingRowState(await OnboardingPermission.notificationState())
        switch health.status {
        case .unavailable: healthState = .unavailable
        case .ready: healthState = .asked
        default: break
        }
    }

    private func ask(_ kind: Kind) async {
        switch kind {
        case .health:
            healthState = .asking
            await health.start()
            switch health.status {
            case .unavailable: healthState = .unavailable
            case .failed: healthState = .declined
            default: healthState = .asked
            }
        case .location:
            location = .asking
            location = OnboardingRowState(await OnboardingPermission.requestLocation())
        case .calendar:
            calendar = .asking
            calendar = OnboardingRowState(await OnboardingPermission.requestCalendar())
        case .notifications:
            notifications = .asking
            notifications = OnboardingRowState(await OnboardingPermission.requestNotifications())
        }
    }
}

/// Where one row of the Connect screen stands.
enum OnboardingRowState: Equatable {
    case notAsked
    case asking
    /// Allowed, as far as the system says.
    case allowed
    /// Asked, with an answer the system keeps to itself: Apple Health.
    case asked
    /// Refused: only Settings can turn it back on.
    case declined
    /// Nothing to ask on this device.
    case unavailable

    init(_ state: OnboardingPermissionState) {
        switch state {
        case .notAsked: self = .notAsked
        case .allowed: self = .allowed
        case .declined: self = .declined
        }
    }
}

/// A row's trailing control: Allow, then a check once answered, or Settings
/// when the answer was no.
struct OnboardingAllowButton: View {
    let state: OnboardingRowState
    let action: () -> Void

    @Environment(\.somaTheme) private var theme

    var body: some View {
        let colors = theme.colors
        let metrics = theme.metrics

        Group {
            switch state {
            case .allowed, .asked:
                Image(systemName: "checkmark")
                    .font(.system(size: metrics.browseChevronSize, weight: .semibold))
                    .foregroundStyle(colors.accent.color)
                    .frame(minWidth: metrics.minimumTapTarget, minHeight: metrics.minimumTapTarget)
                    .accessibilityLabel(Text(state == .allowed ? "Allowed" : "Asked"))
                    .transition(.opacity)
            case .unavailable:
                Text("Not here")
                    .somaFont(theme.typography.caption)
                    .foregroundStyle(colors.inkSecondary.color)
            case .notAsked, .asking, .declined:
                OnboardingChip(
                    title: state == .declined ? String(localized: "Settings") : String(localized: "Allow"),
                    isOn: false,
                    action: action
                )
                .disabled(state == .asking)
                .opacity(state == .asking ? 0.5 : 1)
                .transition(.opacity)
            }
        }
        .animation(theme.motion.onboardingStepStill, value: state)
    }
}
