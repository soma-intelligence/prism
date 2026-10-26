//
//  SomaNotificationsTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// A notification center in memory: what is pending, what was asked.
@MainActor
private final class FakeScheduler: NotificationScheduling {
    var status: NotificationAuthorization
    var grants: Bool
    private(set) var pending: [String: PlannedNotification] = [:]
    private(set) var foreign: Set<String> = []
    private(set) var asked = 0
    private(set) var adds = 0
    var deliveredItems: [DeliveredNotification] = []

    init(status: NotificationAuthorization = .authorized, grants: Bool = true) {
        self.status = status
        self.grants = grants
    }

    func authorization() async -> NotificationAuthorization { status }

    func requestAuthorization() async -> Bool {
        asked += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) + Array(foreign) }

    func add(_ notification: PlannedNotification) async throws {
        adds += 1
        pending[notification.id] = notification
    }

    func remove(_ identifiers: [String]) async {
        for id in identifiers {
            pending[id] = nil
            foreign.remove(id)
        }
    }

    func delivered() async -> [DeliveredNotification] { deliveredItems }

    func addForeign(_ id: String) { foreign.insert(id) }
    func setDelivered(_ items: [DeliveredNotification]) { deliveredItems = items }
}

@Suite("Notification engine")
@MainActor
struct SomaNotificationsEngineTests {
    private func engine(_ scheduler: FakeScheduler) -> SomaNotifications {
        SomaNotifications(scheduler: scheduler, settings: GlobalSettings(url: nil), url: nil)
    }

    @Test("Never asks unless a switch was turned on, and asks once then")
    func asksInContext() async {
        let scheduler = FakeScheduler(status: .notDetermined)
        let model = engine(scheduler)
        await model.apply()
        #expect(await scheduler.asked == 0)
        #expect(await scheduler.pending.isEmpty)
        await model.apply(asking: true)
        #expect(await scheduler.asked == 1)
        #expect(model.authorization == .authorized)
        #expect(await !scheduler.pending.isEmpty)
    }

    @Test("Applying twice leaves one request per reminder and drops the stale")
    func applyIsIdempotent() async {
        let scheduler = FakeScheduler()
        await scheduler.addForeign("tool.alarm")
        await scheduler.addForeign("soma.reminder.retired")
        let model = engine(scheduler)
        await model.apply()
        await model.apply()
        let pending = await scheduler.pendingIdentifiers()
        #expect(Set(pending).count == pending.count)
        #expect(pending.contains("tool.alarm"))
        #expect(!pending.contains("soma.reminder.retired"))
        #expect(Set(pending.filter(NotificationPlanner.Identifier.isManaged)) == Set(model.planned.map(\.id)))

        model.schedule.isEnabled = false
        await model.apply()
        #expect(await scheduler.pendingIdentifiers().filter(NotificationPlanner.Identifier.isManaged).isEmpty)
    }

    @Test("Denied: nothing scheduled, the state says so")
    func denied() async {
        let scheduler = FakeScheduler(status: .notDetermined, grants: false)
        let model = engine(scheduler)
        await model.apply(asking: true)
        #expect(model.authorization == .denied)
        #expect(model.planned.isEmpty)
        #expect(!model.isOn)
    }

    @Test("A stand reminder switched on from Today is adopted")
    func adoptsStand() async {
        let scheduler = FakeScheduler()
        await scheduler.addForeign(NotificationPlanner.Identifier.stand(10))
        let model = engine(scheduler)
        await model.apply()
        #expect(model.schedule.stand)
        #expect(model.planned.contains { $0.kind == .stand })
    }

    @Test("The sleep move sets tonight's reminder; an alert lands in the inbox once")
    func observes() async {
        let scheduler = FakeScheduler()
        let model = engine(scheduler)
        model.settings.notifications.quietHours = false
        await model.observe(bedtimeTitle: "In bed by 11:00 PM", restingDays: [50, 70, 71, 72], restingBand: 50...60)
        #expect(model.bedtime == ClockTime(hour: 23))
        #expect(model.planned.contains { $0.id == NotificationPlanner.Identifier.bedtime })
        #expect(model.inbox.count { $0.kind == .dataAlert } == 1)
        await model.observe(bedtimeTitle: nil, restingDays: [50, 70, 71, 72], restingBand: 50...60)
        #expect(model.inbox.count { $0.kind == .dataAlert } == 1)
        #expect(model.bedtime == ClockTime(hour: 23))
        #expect(model.inbox.first?.link == .vaultMetric("HKQuantityTypeIdentifierRestingHeartRate"))
    }

    @Test("Inbox: deliveries dedupe, group by day, read and clear")
    func inbox() async throws {
        let scheduler = FakeScheduler()
        let model = engine(scheduler)
        let now = Date()
        model.now = { now }
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let morning = DeliveredNotification(id: ReminderPlan.Identifier.morning, title: "Morning check-in", body: "", date: now, link: .checkIn(.morning))
        await scheduler.setDelivered([
            morning, morning,
            DeliveredNotification(id: ReminderPlan.Identifier.morning, title: "Morning check-in", body: "", date: yesterday, link: nil),
        ])
        await model.syncDelivered()
        await model.syncDelivered()
        #expect(model.inbox.count == 2)
        #expect(model.unreadCount == 2)
        #expect(model.sections.today.count == 1)
        #expect(model.sections.earlier.count == 1)
        #expect(model.sections.today.first?.kind == .morningCheckIn)

        let first = try #require(model.sections.today.first)
        model.markRead(first.id)
        #expect(model.unreadCount == 1)
        model.remove(first.id)
        #expect(model.inbox.count == 1)
        model.clear()
        #expect(model.inbox.isEmpty)
    }

    @Test("The inbox keeps thirty days and a hundred items")
    func trimming() {
        let now = Date()
        let old = InboxItem(id: "old", kind: .other, title: "", body: "", date: now.addingTimeInterval(-31 * 86_400))
        let many = (0..<120).map { InboxItem(id: "\($0)", kind: .other, title: "", body: "", date: now.addingTimeInterval(-Double($0))) }
        let kept = SomaNotifications.trimmed(many + [old], now: now)
        #expect(kept.count == SomaNotifications.inboxLimit)
        #expect(!kept.contains { $0.id == "old" })
        #expect(kept.first?.id == "0")
    }
}
