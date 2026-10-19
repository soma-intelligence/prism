//
//  SomaNotifications.swift
//  Prism
//

import Foundation
import Observation
import SomaUI

/// One line in the notification center: something Soma sent, or something it
/// found.
nonisolated struct InboxItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: SomaNotificationKind
    var title: String
    var body: String
    var date: Date
    var isRead = false
    var link: SomaDeepLink?
}

/// The inbox in the two groups the bell shows.
nonisolated struct InboxSections: Equatable, Sendable {
    var today: [InboxItem]
    var earlier: [InboxItem]

    static func make(_ items: [InboxItem], now: Date, calendar: Calendar = .current) -> InboxSections {
        let sorted = items.sorted { $0.date > $1.date }
        return InboxSections(
            today: sorted.filter { calendar.isDate($0.date, inSameDayAs: now) },
            earlier: sorted.filter { !calendar.isDate($0.date, inSameDayAs: now) }
        )
    }
}

/// Soma's notifications, end to end: the switches beyond the check-ins, what
/// is scheduled from them, and the inbox the bell opens.
///
/// Every change re-derives the whole plan (``NotificationPlanner``) and hands
/// it to the phone, so what is pending always matches the page. Permission is
/// asked the first time a switch is turned on (``apply(asking:)``), never at
/// launch. Kept in one small file on the phone.
@MainActor
@Observable
final class SomaNotifications {
    static let shared = SomaNotifications()

    var schedule: NotificationSchedule { didSet { save() } }
    private(set) var inbox: [InboxItem] { didSet { save() } }
    private(set) var authorization: NotificationAuthorization = .notDetermined
    /// What the last apply handed the phone.
    private(set) var planned: [PlannedNotification] = []
    /// Tonight's "In bed by", from the latest sleep move.
    private(set) var bedtime: ClockTime? { didSet { save() } }
    /// When Today was last read from Apple Health.
    private(set) var lastSync: Date? { didSet { save() } }
    private var lastAlerts: [String: Date] { didSet { save() } }
    /// The identifiers the planner put on the phone, so it can tell its own
    /// stand reminders from the ones Today switched on.
    private var applied: Set<String> { didSet { save() } }

    @ObservationIgnored let scheduler: any NotificationScheduling
    @ObservationIgnored let settings: GlobalSettings
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var calendar: Calendar = .current
    @ObservationIgnored private let url: URL?

    static let inboxLimit = 100
    static let inboxDays = 30

    private struct Stored: Codable {
        var schedule: NotificationSchedule?
        var inbox: [InboxItem]?
        var bedtime: ClockTime?
        var lastSync: Date?
        var lastAlerts: [String: Date]?
        var applied: Set<String>?
    }

    init(
        scheduler: any NotificationScheduling = SystemNotificationScheduler(),
        settings: GlobalSettings = .shared,
        url: URL? = SomaNotifications.defaultURL
    ) {
        self.scheduler = scheduler
        self.settings = settings
        self.url = url
        let stored = url.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        schedule = stored?.schedule ?? NotificationSchedule()
        inbox = stored?.inbox ?? []
        bedtime = stored?.bedtime
        lastSync = stored?.lastSync
        lastAlerts = stored?.lastAlerts ?? [:]
        applied = stored?.applied ?? []
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "notifications.json")
    }

    // MARK: Planning

    var planInput: NotificationPlanner.Input {
        NotificationPlanner.Input(
            prefs: settings.notifications, schedule: schedule,
            lastMealBy: settings.customization.lastMealBy, bedtime: bedtime
        )
    }

    /// Whether any switch asks for something.
    var wantsAny: Bool {
        schedule.isEnabled && (!NotificationPlanner.plan(planInput).isEmpty || schedule.dataAlerts)
    }

    /// Whether Soma can notify at all: the phone allows it and the master
    /// switch is on.
    var isOn: Bool { authorization == .authorized && schedule.isEnabled }

    /// The next notification and when, from what was handed to the phone.
    var next: (PlannedNotification, Date)? {
        NotificationPlanner.next(planned, after: now(), calendar: calendar)
    }

    /// When the first notification of a kind fires next, for the inline time
    /// on the settings page. Computed from the plan, so it shows even before
    /// permission is given.
    func nextFire(_ kind: SomaNotificationKind) -> Date? {
        let plan = NotificationPlanner.plan(planInput).filter { $0.kind == kind }
        return NotificationPlanner.next(plan, after: now(), calendar: calendar)?.1
    }

    func refreshAuthorization() async {
        authorization = await scheduler.authorization()
    }

    /// Re-derives the plan and puts it on the phone.
    ///
    /// - Parameter asking: true when a person just turned a switch on: the
    ///   permission question comes then, in context, if it was never asked.
    func apply(asking: Bool = false) async {
        authorization = await scheduler.authorization()
        if asking, authorization == .notDetermined, wantsAny {
            _ = await scheduler.requestAuthorization()
            authorization = await scheduler.authorization()
        }

        let pending = await scheduler.pendingIdentifiers()
        if NotificationPlanner.adoptsStand(pending: pending, applied: applied, schedule: schedule) {
            schedule.stand = true
        }

        let plan = NotificationPlanner.plan(planInput)
        let stale = pending.filter { NotificationPlanner.Identifier.isManaged($0) }
        await scheduler.remove(Array(Set(stale).union(plan.map(\.id))).sorted())

        guard authorization == .authorized else {
            planned = []
            applied = []
            return
        }
        var added: [PlannedNotification] = []
        for item in plan {
            do {
                try await scheduler.add(item)
                added.append(item)
            } catch {
                continue
            }
        }
        planned = added
        applied = Set(added.map(\.id))
    }

    // MARK: What the data says

    /// Reads the day Pulse worked out: the bedtime from the sleep move, a
    /// resting heart rate above usual, and when Health was last read.
    func observe(_ today: PulseToday?) async {
        guard let today else { return }
        let title = today.moves.first { $0.aspect == .sleep }?.title
        await observe(bedtimeTitle: title, restingDays: today.restingDays, restingBand: today.restingBand)
    }

    func observe(bedtimeTitle: String?, restingDays: [Double?], restingBand: ClosedRange<Double>?) async {
        let now = now()
        lastSync = now
        let target = bedtimeTitle.flatMap(NotificationPlanner.bedtime(fromMoveTitle:))
        // A day without a sleep move keeps last night's target rather than
        // dropping the reminder.
        if let target, target != bedtime {
            bedtime = target
            await apply()
        }

        guard schedule.dataAlerts,
              DataAlertRules.restingAboveUsual(days: restingDays, band: restingBand),
              DataAlertRules.shouldRaise(lastRaised: lastAlerts[DataAlertRules.restingHigh], now: now) else { return }
        lastAlerts[DataAlertRules.restingHigh] = now
        let alert = PlannedNotification(
            id: NotificationPlanner.Identifier.alertPrefix + DataAlertRules.restingHigh + ".\(Int(now.timeIntervalSince1970))",
            kind: .dataAlert,
            title: String(localized: "Resting HR above usual 3 days"),
            body: String(localized: "Worth an easier day and an earlier night."),
            trigger: .at(now.addingTimeInterval(1)),
            link: .vaultMetric("HKQuantityTypeIdentifierRestingHeartRate")
        )
        add(InboxItem(id: alert.id, kind: .dataAlert, title: alert.title, body: alert.body, date: now, link: alert.link))
        let quiet = NotificationPlanner.isQuiet(ClockTime(hour: calendar.component(.hour, from: now), minute: calendar.component(.minute, from: now)), settings.notifications)
        if isOn, !quiet {
            try? await scheduler.add(alert)
        }
    }

    /// Sends one notification in five seconds, from the developer tools.
    func sendTest() async {
        if authorization == .notDetermined {
            _ = await scheduler.requestAuthorization()
        }
        authorization = await scheduler.authorization()
        guard authorization == .authorized else { return }
        let test = PlannedNotification(
            id: NotificationPlanner.Identifier.testPrefix + UUID().uuidString,
            kind: .test, title: String(localized: "Soma"), body: String(localized: "Notifications reach this device."),
            trigger: .at(now().addingTimeInterval(5)), link: .inbox
        )
        try? await scheduler.add(test)
    }

    // MARK: Inbox

    var unreadCount: Int { inbox.count { !$0.isRead } }

    var sections: InboxSections { InboxSections.make(inbox, now: now(), calendar: calendar) }

    /// Adds an item; the same id twice is kept once.
    func add(_ item: InboxItem) {
        guard !inbox.contains(where: { $0.id == item.id }) else { return }
        inbox = Self.trimmed(inbox + [item], now: now())
    }

    /// Records what the phone showed. A repeating reminder keeps one
    /// identifier, so each delivery is told apart by its time.
    func record(_ delivered: DeliveredNotification, isRead: Bool = false) {
        let kind = SomaNotificationKind.kind(forIdentifier: delivered.id)
        // A data alert is in the inbox from the moment it was found.
        if kind == .dataAlert, let index = inbox.firstIndex(where: { $0.id == delivered.id }) {
            if isRead { inbox[index].isRead = true }
            return
        }
        let id = "\(delivered.id)@\(Int(delivered.date.timeIntervalSince1970 / 60))"
        if let index = inbox.firstIndex(where: { $0.id == id }) {
            if isRead { inbox[index].isRead = true }
            return
        }
        add(InboxItem(
            id: id, kind: kind, title: delivered.title, body: delivered.body,
            date: delivered.date, isRead: isRead, link: delivered.link
        ))
    }

    /// Takes in what the phone delivered while Soma was closed.
    func syncDelivered() async {
        for item in await scheduler.delivered() { record(item) }
    }

    func markRead(_ id: InboxItem.ID) {
        guard let index = inbox.firstIndex(where: { $0.id == id }), !inbox[index].isRead else { return }
        inbox[index].isRead = true
    }

    func markAllRead() {
        guard unreadCount > 0 else { return }
        inbox = inbox.map { var item = $0; item.isRead = true; return item }
    }

    func remove(_ id: InboxItem.ID) {
        inbox.removeAll { $0.id == id }
    }

    func clear() {
        inbox = []
    }

    static func trimmed(_ items: [InboxItem], now: Date) -> [InboxItem] {
        let floor = now.addingTimeInterval(-Double(inboxDays) * 24 * 3600)
        return Array(items.filter { $0.date >= floor }.sorted { $0.date > $1.date }.prefix(inboxLimit))
    }

    // MARK: Store

    private func save() {
        guard let url else { return }
        let stored = Stored(
            schedule: schedule, inbox: inbox, bedtime: bedtime,
            lastSync: lastSync, lastAlerts: lastAlerts, applied: applied
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
