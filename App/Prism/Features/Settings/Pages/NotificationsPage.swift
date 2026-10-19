//
//  NotificationsPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// When Soma speaks: one switch for everything,
/// then grouped switches, each with its coloured tile and the time it fires
/// next under its name.
///
/// Every change applies at once: the whole plan is re-derived
/// (``NotificationPlanner``) and handed to the phone. The permission is asked
/// the first time a switch is turned on, never when the page opens; once
/// refused, the top row says so and opens the system's settings.
struct NotificationsPage: View {
    @Environment(\.somaTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @Environment(JournalStore.self) private var journal

    @State private var settings = GlobalSettings.shared
    @State private var notifications = SomaNotifications.shared
    /// The phone refused when the Journal reminder was switched on.
    @State private var journalRefused = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var notifications = notifications
        let prefs = $settings.notifications
        let schedule = $notifications.schedule

        ListScaffold(eyebrow: "Settings", title: "Notifications") {
            SomaBrowseGroup([SettingsItem(id: "master")]) { _ in master }

            if notifications.schedule.isEnabled {
                SettingsSection("Check-ins") {
                    SomaBrowseGroup([SettingsItem].items("morning", "evening", "journal")) { item in
                        if item.id == "journal" {
                            journalLine
                        } else if item.id == "morning" {
                            line(.morningCheckIn, "Morning", fallback: "How you slept", isOn: prefs.morningCheckIn) {
                                SettingsTimeValue(title: "Morning check-in", time: prefs.morningTime)
                            }
                        } else {
                            line(.eveningCheckIn, "Evening", fallback: "The day in a line", isOn: prefs.eveningCheckIn) {
                                SettingsTimeValue(title: "Evening check-in", time: prefs.eveningTime)
                            }
                        }
                    }
                }

                SettingsSection("Sleep and movement") {
                    SomaBrowseGroup(sleepItems) { item in
                        switch item.id {
                        case "bedtime":
                            line(.bedtime, "Bedtime", fallback: bedtimeFallback, isOn: schedule.bedtime) {
                                SettingsMenuValue(
                                    title: "Minutes before bed", options: NotificationSchedule.bedtimeLeads,
                                    label: { String(localized: "\($0) min") }, selection: schedule.bedtimeLead
                                )
                            }
                        case "stand":
                            line(.stand, "Stand", fallback: "Ten to each hour", isOn: schedule.stand) { EmptyView() }
                        case "standWindow":
                            SettingsLine(String(localized: "Between")) {
                                SettingsTimeValue(title: "Stand from", time: schedule.standFrom)
                                SettingsTimeValue(title: "Stand until", time: schedule.standUntil)
                            }
                        default:
                            line(.lastMeal, "Last meal", fallback: "Before \(settings.customization.lastMealBy.text)", isOn: prefs.eveningNudges) { EmptyView() }
                        }
                    }
                }

                SettingsSection("Insights") {
                    SomaBrowseGroup([SettingsItem].items("weekly", "alerts")) { item in
                        if item.id == "weekly" {
                            line(.weeklySummary, "Weekly summary", fallback: "Sunday evening", isOn: schedule.weekly) {
                                SettingsTimeValue(title: "Weekly summary", time: schedule.weeklyTime)
                            }
                        } else {
                            SettingsTileLine("Data alerts", symbol: SomaNotificationKind.dataAlert.symbol, detail: String(localized: "When a reading leaves your usual")) {
                                SettingsSwitch(title: "Data alerts", isOn: schedule.dataAlerts)
                            }
                        }
                    }
                }

                SettingsSection("Quiet hours") {
                    SomaBrowseGroup(quietItems) { item in
                        switch item.id {
                        case "quiet":
                            SettingsTileLine("Quiet hours", symbol: "moon.zzz",
                                             detail: String(localized: "Reminders wait until it ends")) {
                                SettingsSwitch(title: "Quiet hours", isOn: prefs.quietHours)
                            }
                        default:
                            SettingsLine(String(localized: "From and until")) {
                                SettingsTimeValue(title: "Quiet from", time: prefs.quietFrom)
                                SettingsTimeValue(title: "Quiet until", time: prefs.quietUntil)
                            }
                        }
                    }
                }

                SettingsFootnote("Scheduled on this device. Nothing goes through a server.")
            }
        }
        .task {
            await notifications.refreshAuthorization()
            await syncJournal()
        }
        .onChange(of: phase) { _, phase in
            if phase == .active { Task { await notifications.apply() } }
        }
        .onChange(of: settings.notifications) { old, new in
            Task { await notifications.apply(asking: Self.switchedOn(old, new)) }
        }
        .onChange(of: notifications.schedule) { old, new in
            Task { await notifications.apply(asking: Self.switchedOn(old, new)) }
        }
        .onChange(of: settings.customization.lastMealBy) { Task { await notifications.apply() } }
        .onChange(of: notifications.schedule.isEnabled) { Task { await syncJournal() } }
    }

    // MARK: The Journal

    /// The daily nudge that asks how the day felt. Its own request
    /// (``TrackReminder``), outside the planner, kept in the Journal's
    /// questions as it always was; this row is the only switch for it.
    private var journalLine: some View {
        let questions = journal.questions
        let isOn = Binding(
            get: { journal.questions.asksFeeling },
            set: { setJournal($0) }
        )
        let detail = journalRefused
            ? String(localized: "Notifications are off for Soma")
            : String(localized: "How the day felt")
        return SettingsTileLine(String(localized: "Journal"), symbol: "square.and.pencil", detail: detail) {
            if questions.asksFeeling {
                SettingsMenuValue(
                    title: "Journal reminder", options: Array(0..<24),
                    label: { TrackFormat.hour($0) },
                    selection: Binding(
                        get: { journal.questions.feelingHour },
                        set: { hour in
                            journal.questions.feelingHour = hour
                            Task { await syncJournal() }
                        }
                    )
                )
            }
            SettingsSwitch(title: String(localized: "Journal"), isOn: isOn)
        }
    }

    private func setJournal(_ isOn: Bool) {
        journal.questions.asksFeeling = isOn
        if isOn {
            let hour = journal.questions.feelingHour
            Task { journalRefused = !(await TrackReminder.enable(hour: hour)) }
        } else {
            TrackReminder.cancel()
            journalRefused = false
        }
    }

    /// Follows the master switch: off silences the Journal too, on puts it
    /// back as set, never asking for permission from here.
    private func syncJournal() async {
        if notifications.schedule.isEnabled {
            await TrackReminder.sync(journal.questions)
        } else {
            TrackReminder.cancel()
        }
    }

    private var sleepItems: [SettingsItem] {
        notifications.schedule.stand
            ? .items("bedtime", "stand", "standWindow", "meal")
            : .items("bedtime", "stand", "meal")
    }

    private var quietItems: [SettingsItem] {
        settings.notifications.quietHours ? .items("quiet", "window") : .items("quiet")
    }

    // MARK: The top row

    @ViewBuilder
    private var master: some View {
        if notifications.authorization == .denied {
            SettingsTileRow(
                String(localized: "Turned off in Settings"), symbol: "bell.slash",
                detail: String(localized: "Open"), action: openSystemSettings
            )
        } else {
            SettingsTileLine("Allow notifications", symbol: "bell.badge", detail: nextLine) {
                SettingsSwitch(title: "Allow notifications", isOn: masterBinding)
            }
        }
    }

    /// On only when the phone allows it and the switch is on, so a first
    /// turn of it is the moment the question is asked.
    private var masterBinding: Binding<Bool> {
        Binding(
            get: { notifications.schedule.isEnabled && notifications.authorization == .authorized },
            set: { on in
                if !on {
                    notifications.schedule.isEnabled = false
                } else if !notifications.schedule.isEnabled {
                    // The schedule's onChange applies and asks.
                    notifications.schedule.isEnabled = true
                } else {
                    Task { await notifications.apply(asking: true) }
                }
            }
        )
    }

    private var nextLine: String? {
        guard notifications.isOn, let next = notifications.next else { return nil }
        return String(localized: "Next: \(next.0.title), \(NotificationCenterSheet.when(next.1))")
    }

    private var bedtimeFallback: String {
        notifications.bedtime.map { String(localized: "In bed by \($0.text)") } ?? String(localized: "Waits for a sleep move")
    }

    // MARK: Rows

    /// A switch row whose line reads the next time it fires while on.
    private func line<Extra: View>(
        _ kind: SomaNotificationKind, _ title: LocalizedStringResource, fallback: String,
        isOn: Binding<Bool>, @ViewBuilder extra: () -> Extra
    ) -> some View {
        let next = isOn.wrappedValue ? notifications.nextFire(kind) : nil
        return SettingsTileLine(String(localized: title), symbol: kind.symbol,
                                detail: next.map { NotificationCenterSheet.when($0) } ?? fallback) {
            if isOn.wrappedValue { extra() }
            SettingsSwitch(title: String(localized: title), isOn: isOn)
        }
    }

    private func openSystemSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(url) }
        #else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        #endif
    }

    /// Whether a change turned a switch on, the moment to ask.
    static func switchedOn<Value>(_ old: Value, _ new: Value) -> Bool {
        let before = Mirror(reflecting: old).children.compactMap { $0.value as? Bool }
        let after = Mirror(reflecting: new).children.compactMap { $0.value as? Bool }
        return zip(before, after).contains { !$0 && $1 }
    }
}

#Preview("Notifications") {
    NavigationStack { NotificationsPage() }
        .environment(JournalStore(url: nil))
}
