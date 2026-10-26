//
//  NotificationKindTests.swift
//  PrismTests
//

import Foundation
import Testing
import UserNotifications
@testable import Prism

/// What the phone delivers comes back as an identifier and nothing else, so
/// the kind is read off the identifier: it picks the inbox glyph, whether a
/// banner shows while Soma is open, and where a tap lands when the
/// notification carries no link of its own.
@Suite("Notification kinds")
@MainActor
struct NotificationKindTests {
    /// One identifier the app schedules for each kind.
    let identifiers: [SomaNotificationKind: String] = [
        .morningCheckIn: ReminderPlan.Identifier.morning,
        .eveningCheckIn: ReminderPlan.Identifier.evening,
        .lastMeal: ReminderPlan.Identifier.lastMeal,
        .bedtime: NotificationPlanner.Identifier.bedtime,
        .stand: NotificationPlanner.Identifier.stand(14),
        .weeklySummary: NotificationPlanner.Identifier.weekly,
        .dataAlert: NotificationPlanner.Identifier.alertPrefix + "restingHigh.1",
        .checkInLater: CheckInReminder.identifier,
        .test: NotificationPlanner.Identifier.testPrefix + "1",
        .screeningDue: ScreeningReminderRules.prefix + "bloodPressure.soon.20261002",
        .appointment: AppointmentReminderRules.prefix + "x.hour",
        .dose: MedicationReminders.prefix + "x",
        .assessment: MindQuestionnaireReminders.prefix + "x",
        .other: "com.example.someone-else",
    ]

    @Test("Each identifier the app schedules reads back as its own kind")
    func kinds() {
        #expect(Set(identifiers.keys) == Set(SomaNotificationKind.allCases))
        for (kind, identifier) in identifiers {
            #expect(SomaNotificationKind.kind(forIdentifier: identifier) == kind, "\(identifier)")
        }
    }

    @Test("A tap on any kind lands somewhere, even without a link")
    func fallbacks() {
        let expected: [SomaNotificationKind: SomaDeepLink] = [
            .morningCheckIn: .checkIn(.morning),
            .eveningCheckIn: .checkIn(.evening),
            .checkInLater: .checkIn(.evening),
            .bedtime: .sleep,
            .weeklySummary: .trends,
            .dataAlert: .inbox,
            .test: .inbox,
            .lastMeal: .today,
            .stand: .today,
            .other: .today,
            .screeningDue: .screeningLedger,
            .appointment: .medicalRecord,
            .dose: .journal,
            .assessment: .mindAssessments,
        ]
        for (kind, identifier) in identifiers {
            #expect(SomaNotificationRouter.fallbackLink(for: identifier) == expected[kind], "\(kind)")
        }
    }

    @Test("Each kind has an inbox glyph of its own")
    func symbols() {
        let symbols = SomaNotificationKind.allCases.map(\.symbol)
        #expect(Set(symbols).count == symbols.count)
    }

    @Test("The phone's permission reads as one of the three states the pages tell apart")
    func authorization() {
        #expect(NotificationAuthorization(.authorized) == .authorized)
        #expect(NotificationAuthorization(.provisional) == .authorized)
        #expect(NotificationAuthorization(.denied) == .denied)
        #expect(NotificationAuthorization(.notDetermined) == .notDetermined)
    }
}
