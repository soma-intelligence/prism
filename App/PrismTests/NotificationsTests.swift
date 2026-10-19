//
//  NotificationsTests.swift
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

@Suite("Notification rules")
struct NotificationPlannerTests {
    private func input(
        _ edit: (inout NotificationPreferences, inout NotificationSchedule) -> Void = { _, _ in },
        bedtime: ClockTime? = ClockTime(hour: 22)
    ) -> NotificationPlanner.Input {
        var prefs = NotificationPreferences()
        var schedule = NotificationSchedule()
        edit(&prefs, &schedule)
        return NotificationPlanner.Input(prefs: prefs, schedule: schedule, lastMealBy: ClockTime(hour: 20, minute: 30), bedtime: bedtime)
    }

    private func time(_ item: PlannedNotification?) -> ClockTime? {
        guard case .daily(let time)? = item?.trigger else { return nil }
        return time
    }

    @Test("The master switch silences everything")
    func masterOff() {
        #expect(NotificationPlanner.plan(input { _, s in s.isEnabled = false }).isEmpty)
    }

    @Test("Default plan: check-ins, last meal, bedtime and the week")
    func defaults() {
        let ids = NotificationPlanner.plan(input()).map(\.id)
        #expect(ids == [
            ReminderPlan.Identifier.morning, ReminderPlan.Identifier.evening, ReminderPlan.Identifier.lastMeal,
            NotificationPlanner.Identifier.bedtime, NotificationPlanner.Identifier.weekly,
        ])
    }

    @Test("Bedtime fires its lead before the sleep move's time, and waits for one")
    func bedtime() {
        let plan = NotificationPlanner.plan(input({ p, s in p.quietHours = false; s.bedtimeLead = 45 }, bedtime: ClockTime(hour: 23)))
        #expect(time(plan.first { $0.kind == .bedtime }) == ClockTime(hour: 22, minute: 15))
        #expect(plan.first { $0.kind == .bedtime }?.link == .sleep)
        #expect(!NotificationPlanner.plan(input(bedtime: nil)).contains { $0.kind == .bedtime })
    }

    @Test("Inside quiet hours a bedtime or stand reminder is dropped, not moved")
    func quietDrops() {
        let late = input({ p, s in
            p.quietFrom = ClockTime(hour: 22); p.quietUntil = ClockTime(hour: 7)
            s.stand = true; s.standFrom = ClockTime(hour: 6); s.standUntil = ClockTime(hour: 23)
        }, bedtime: ClockTime(hour: 22, minute: 45))
        let plan = NotificationPlanner.plan(late)
        #expect(!plan.contains { $0.kind == .bedtime })
        let standHours = plan.filter { $0.kind == .stand }.map(\.id)
        #expect(!standHours.contains(NotificationPlanner.Identifier.stand(6)))
        #expect(standHours.contains(NotificationPlanner.Identifier.stand(7)))
        #expect(standHours.contains(NotificationPlanner.Identifier.stand(21)))
        #expect(!standHours.contains(NotificationPlanner.Identifier.stand(22)))
    }

    @Test("Stand reminders fall at ten to each hour inside the window")
    func standWindow() {
        var schedule = NotificationSchedule()
        schedule.standFrom = ClockTime(hour: 8)
        schedule.standUntil = ClockTime(hour: 20)
        #expect(NotificationPlanner.standHours(schedule) == Array(8...19))
        schedule.standFrom = ClockTime(hour: 9, minute: 55)
        #expect(NotificationPlanner.standHours(schedule).first == 10)
    }

    @Test("The weekly summary in quiet hours waits for them to end")
    func weeklyQuiet() {
        let plan = NotificationPlanner.plan(input { p, s in
            p.quietFrom = ClockTime(hour: 17); p.quietUntil = ClockTime(hour: 7); s.weeklyTime = ClockTime(hour: 18)
        })
        #expect(plan.first { $0.kind == .weeklySummary }?.trigger == .weekly(weekday: 1, ClockTime(hour: 7)))
    }

    @Test("Two reminders never share a minute, and an identifier is planned once")
    func dedupeAndStagger() {
        // Quiet hours push both check-ins onto 07:00.
        let plan = NotificationPlanner.plan(input { p, _ in
            p.morningTime = ClockTime(hour: 6); p.eveningTime = ClockTime(hour: 23)
        })
        #expect(time(plan.first { $0.kind == .morningCheckIn }) == ClockTime(hour: 7))
        #expect(time(plan.first { $0.kind == .eveningCheckIn }) == ClockTime(hour: 7, minute: 1))
        #expect(Set(plan.map(\.id)).count == plan.count)

        let twice = PlannedNotification(id: "a", kind: .other, title: "", body: "", trigger: .daily(ClockTime(hour: 9)))
        #expect(NotificationPlanner.deduped([twice, twice]).count == 1)
    }

    @Test("Check-in reminders link to the check-in")
    func links() {
        let plan = NotificationPlanner.plan(input())
        #expect(plan.first { $0.kind == .morningCheckIn }?.link == .checkIn(.morning))
        #expect(plan.first { $0.kind == .eveningCheckIn }?.link == .checkIn(.evening))
        #expect(plan.first { $0.kind == .weeklySummary }?.link == .trends)
    }

    @Test("Next fire: later today, else tomorrow; weekly on its day")
    func nextFire() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        // Saturday 3 October 2026, 08:00.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 8)))
        let later = NotificationPlanner.nextFire(.daily(ClockTime(hour: 21)), after: now, calendar: calendar)
        #expect(later == calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21)))
        let tomorrow = NotificationPlanner.nextFire(.daily(ClockTime(hour: 7, minute: 30)), after: now, calendar: calendar)
        #expect(tomorrow == calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 7, minute: 30)))
        let sunday = NotificationPlanner.nextFire(.weekly(weekday: 1, ClockTime(hour: 18)), after: now, calendar: calendar)
        #expect(sunday == calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 18)))
        #expect(NotificationPlanner.nextFire(.at(now.addingTimeInterval(-1)), after: now, calendar: calendar) == nil)
    }

    @Test("The bedtime is read out of the sleep move in either clock")
    func bedtimeParsing() {
        #expect(NotificationPlanner.bedtime(fromMoveTitle: "In bed by 11:00\u{202F}PM") == ClockTime(hour: 23))
        #expect(NotificationPlanner.bedtime(fromMoveTitle: "In bed by 10:45 pm") == ClockTime(hour: 22, minute: 45))
        #expect(NotificationPlanner.bedtime(fromMoveTitle: "In bed by 12:15 AM") == ClockTime(hour: 0, minute: 15))
        #expect(NotificationPlanner.bedtime(fromMoveTitle: "In bed by 23:30") == ClockTime(hour: 23, minute: 30))
        #expect(NotificationPlanner.bedtime(fromMoveTitle: "Breathe for 10 minutes") == nil)
    }

    @Test("Settings takes over a stand reminder Today switched on, never its own")
    func standAdoption() {
        let schedule = NotificationSchedule()
        let stand = NotificationPlanner.Identifier.stand(9)
        #expect(NotificationPlanner.adoptsStand(pending: [stand], applied: [], schedule: schedule))
        #expect(!NotificationPlanner.adoptsStand(pending: [stand], applied: [stand], schedule: schedule))
        #expect(!NotificationPlanner.adoptsStand(pending: ["tool.x"], applied: [], schedule: schedule))
    }

    @Test("Resting heart rate above usual three days running, said once in three days")
    func restingAlert() {
        let band = 52.0...58.0
        #expect(DataAlertRules.restingAboveUsual(days: [55, 60, 61, 62], band: band))
        #expect(!DataAlertRules.restingAboveUsual(days: [60, 61, nil], band: band))
        #expect(!DataAlertRules.restingAboveUsual(days: [61, 57, 62], band: band))
        #expect(!DataAlertRules.restingAboveUsual(days: [61, 62, 63], band: nil))
        let now = Date()
        #expect(DataAlertRules.shouldRaise(lastRaised: nil, now: now))
        #expect(!DataAlertRules.shouldRaise(lastRaised: now.addingTimeInterval(-2 * 86_400), now: now))
        #expect(DataAlertRules.shouldRaise(lastRaised: now.addingTimeInterval(-3 * 86_400), now: now))
    }

    @Test("A stored schedule from an older build keeps its values")
    func scheduleDecoding() throws {
        let old = Data(#"{"stand":true}"#.utf8)
        let decoded = try JSONDecoder().decode(NotificationSchedule.self, from: old)
        #expect(decoded.stand)
        #expect(decoded.isEnabled && decoded.weekly && decoded.bedtimeLead == 30)
    }
}

@Suite("Deep links")
struct SomaDeepLinkTests {
    @Test("Every link survives its URL")
    func roundTrip() {
        let links: [SomaDeepLink] = [.checkIn(.morning), .checkIn(.evening), .sleep,
                                     .vaultMetric("HKQuantityTypeIdentifierRestingHeartRate"), .trends, .today, .inbox]
        for link in links {
            #expect(SomaDeepLink(url: link.url) == link)
            #expect(SomaDeepLink(userInfo: [SomaDeepLink.userInfoKey: link.url.absoluteString]) == link)
        }
        #expect(SomaDeepLink(string: "https://somalabs.me/sleep") == nil)
        #expect(SomaDeepLink(string: "soma://checkin/noon") == nil)
    }

    @Test("Widget URLs parse")
    func widgetURLsParse() {
        #expect(SomaDeepLink(url: URL(string: "soma://score/recovery")!) == .score("recovery"))
        #expect(SomaDeepLink(url: URL(string: "soma://vitals")!) == .vitals)
        #expect(SomaDeepLink(url: URL(string: "soma://fuel")!) == .fuel)
        #expect(SomaDeepLink(url: URL(string: "soma://journal")!) == .journal)
        #expect(SomaDeepLink(url: URL(string: "soma://track/mood")!) == .trackMood)
        #expect(SomaDeepLink(url: URL(string: "soma://track/meal")!) == .trackMeal)
        #expect(SomaDeepLink(url: URL(string: "soma://capture/start")!) == .captureStart)
        #expect(SomaDeepLink(url: URL(string: "soma://score/nonsense")!) == nil)
        #expect(SomaDeepLink(url: URL(string: "soma://track/nonsense")!) == nil)
        #expect(SomaDeepLink(url: URL(string: "soma://capture")!) == nil)
    }

    @Test("Widget links survive their URL")
    func widgetRoundTrip() {
        let links: [SomaDeepLink] = [.score("sleep"), .score("recovery"), .score("strain"), .score("stress"),
                                     .vitals, .fuel, .journal, .trackMood, .trackMeal, .captureStart]
        for link in links { #expect(SomaDeepLink(url: link.url) == link) }
    }

    @Test("The app claims the soma scheme, so a widget's link opens it")
    func schemeRegistered() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(SomaDeepLink.scheme))
    }

    @Test("A notification without a link still opens its place")
    func fallbacks() {
        #expect(SomaNotificationRouter.fallbackLink(for: ReminderPlan.Identifier.morning) == .checkIn(.morning))
        #expect(SomaNotificationRouter.fallbackLink(for: NotificationPlanner.Identifier.bedtime) == .sleep)
        #expect(SomaNotificationRouter.fallbackLink(for: "soma.alert.restingHigh.1") == .inbox)
    }
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
