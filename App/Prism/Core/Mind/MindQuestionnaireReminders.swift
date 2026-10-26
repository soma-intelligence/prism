//
//  MindQuestionnaireReminders.swift
//  Prism
//

import Foundation

/// The two Mind questionnaires a person can ask to be reminded of: PHQ-9
/// and GAD-7 two weeks after the last time, and the connection check a month
/// after the last time. Both off until switched on.
///
/// Pure, like ``ScreeningReminderRules``: each reminder is a wall clock
/// time, so 10:00 stays 10:00 local the day the clocks change and after a
/// flight. Only the next one is handed to the phone; saving a questionnaire,
/// turning a switch or opening the page derives it again. Outside the
/// planner's managed set.
nonisolated enum MindQuestionnaireReminders {
    static let prefix = "soma.assessment."
    /// A quiet moment of the morning. Inside quiet hours it waits for them
    /// to end.
    static let morning = ClockTime(hour: 10)
    /// PHQ-9 and GAD-7 ask about the last two weeks, so two weeks apart.
    static let assessmentDays = 14
    /// The connection check, once a month.
    static let connectionMonths = 1

    /// - Parameters:
    ///   - lastAssessment: the last PHQ-9 or GAD-7 answered to the end, nil
    ///     when none was: the first reminder then comes two weeks from now.
    ///   - lastConnection: the same for the connection check.
    static func reminders(
        lastAssessment: Date?,
        lastConnection: Date?,
        schedule: NotificationSchedule,
        prefs: NotificationPreferences,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        guard schedule.isEnabled else { return [] }
        let time = NotificationPlanner.isQuiet(morning, prefs) ? prefs.quietUntil : morning
        var planned: [PlannedNotification] = []

        func add(_ step: String, due: Date?, title: String, body: String, link: SomaDeepLink) {
            guard let due else { return }
            var parts = calendar.dateComponents([.year, .month, .day], from: due)
            parts.hour = time.hour
            parts.minute = time.minute
            // Past due: the next morning still ahead, never a moment gone.
            if let fire = calendar.date(from: parts), fire <= now {
                var today = calendar.dateComponents([.year, .month, .day], from: now)
                today.hour = time.hour
                today.minute = time.minute
                parts = today
                if let atToday = calendar.date(from: today), atToday <= now,
                   let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                    parts = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                    parts.hour = time.hour
                    parts.minute = time.minute
                }
            }
            let key = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            planned.append(PlannedNotification(
                id: prefix + step + "." + key, kind: .assessment, title: title, body: body,
                trigger: .wallClock(parts), link: link
            ))
        }

        if schedule.assessmentReminders {
            add("mood", due: calendar.date(byAdding: .day, value: assessmentDays, to: lastAssessment ?? now),
                title: String(localized: "Two minute check-in"),
                body: String(localized: "PHQ-9 and GAD-7, as you asked every two weeks. Your answers stay on this phone."),
                link: .mindAssessments)
        }
        if schedule.connectionReminders {
            add("connection", due: calendar.date(byAdding: .month, value: connectionMonths, to: lastConnection ?? now),
                title: String(localized: "Monthly connection check"),
                body: String(localized: "Four short questions on feeling connected. Your answers stay on this phone."),
                link: .mindConnection)
        }
        return planned
    }

    /// Derives the reminders again and puts them on the phone, in place of
    /// the ones pending.
    ///
    /// - Parameter asking: true when a person just turned a switch on: the
    ///   notification permission is asked then, in context, if it never was.
    @MainActor
    static func sync(asking: Bool = false) async {
        let notifications = SomaNotifications.shared
        if asking {
            await notifications.apply(asking: true)
        } else {
            await notifications.refreshAuthorization()
        }
        let store = MindStore.shared
        let lastAssessment = [store.latest(.phq9)?.date, store.latest(.gad7)?.date].compactMap { $0 }.max()
        let planned = reminders(
            lastAssessment: lastAssessment, lastConnection: MindConnectionCheck.lastDate(in: store),
            schedule: notifications.schedule, prefs: notifications.settings.notifications, now: Date())
        let scheduler = notifications.scheduler
        let stale = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        await scheduler.remove(stale)
        guard notifications.isOn else { return }
        for item in planned {
            try? await scheduler.add(item)
        }
    }
}
