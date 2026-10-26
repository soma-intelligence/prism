//
//  MedicationReminders.swift
//  Prism
//
//  When the next dose of something on the plan falls, and the reminder for
//  each one. The rhythm and the time are what the person declared on the
//  dose page; Soma never proposes an amount or a time of its own.
//

import Foundation
import UserNotifications

/// The dose times a supplement's declared rhythm calls for.
///
/// Pure: built on ``TrackAdherence/isDue(_:on:startedOn:calendar:)``, the one
/// place the rhythm is read, so the reminders and the adherence count never
/// disagree about which day is a dose day.
nonisolated enum MedicationSchedule {
    /// How far ahead `next` looks before it gives up: a year covers the
    /// longest weekly or on and off rhythm many times over.
    static let searchDays = 366

    /// The first dose time strictly after `date`, or nil when the supplement
    /// is paused or nothing falls inside a year.
    static func next(for supplement: TrackSupplement, after date: Date, calendar: Calendar = .current) -> Date? {
        doseTimes(for: supplement, after: date, days: searchDays, count: 1, calendar: calendar).first
    }

    /// Every dose time strictly after `date` over `days` calendar days,
    /// counted from that day (or from the day the supplement starts, when
    /// that is later).
    static func upcoming(for supplement: TrackSupplement, after date: Date, days: Int, calendar: Calendar = .current) -> [Date] {
        doseTimes(for: supplement, after: date, days: days, calendar: calendar)
    }

    /// The dose time on `day` at the supplement's usual minute, in
    /// `calendar`'s zone. Nil only when the calendar cannot build the date.
    static func time(of supplement: TrackSupplement, on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(from: wallClock(of: supplement, on: day, calendar: calendar))
    }

    /// The day and the declared hour and minute, with no time zone: the
    /// phone's own wherever it is, so 09:00 stays 09:00 local.
    static func wallClock(of supplement: TrackSupplement, on day: Date, calendar: Calendar = .current) -> DateComponents {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        let minute = min(max(supplement.minute, 0), 24 * 60 - 1)
        parts.hour = minute / 60
        parts.minute = minute % 60
        return parts
    }

    /// Walks the days in order and stops at `count` dose times.
    private static func doseTimes(for supplement: TrackSupplement, after date: Date, days: Int,
                                  count: Int = .max, calendar: Calendar) -> [Date] {
        guard supplement.isActive, days > 0, count > 0 else { return [] }
        let start = max(calendar.startOfDay(for: date), calendar.startOfDay(for: supplement.startedOn))
        var times: [Date] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            guard TrackAdherence.isDue(supplement.cadence, on: day, startedOn: supplement.startedOn, calendar: calendar),
                  let fire = time(of: supplement, on: day, calendar: calendar), fire > date else { continue }
            times.append(fire)
            if times.count == count { break }
        }
        return times
    }
}

/// One reminder per dose, for the supplements the person asked to be
/// reminded of on the dose page, each with a "Taken" action that logs the
/// dose without opening the app.
///
/// Pure, like ``ScreeningReminderRules``: each reminder is a wall clock
/// time, so a 09:00 dose stays at 09:00 local the morning the clocks change
/// and after a flight. A rhythm of every other day or of weeks on and off
/// has no repeating trigger, so the next ``horizonDays`` are handed to the
/// phone one by one and re-derived each time the app opens or the plan
/// changes. Quiet hours do not move them: the time is the one the person
/// chose for the dose.
nonisolated enum MedicationReminders {
    static let prefix = "soma.dose."
    /// The notification category that carries the "Taken" action.
    static let categoryIdentifier = "soma.dose"
    static let takenAction = "soma.dose.taken"
    /// Days of reminders kept on the phone at a time.
    static let horizonDays = 7
    /// The phone keeps 64 pending requests for an app; the dose reminders
    /// take at most this many, the soonest first, and leave the rest.
    static let limit = 32

    static func reminders(
        for supplements: [TrackSupplement],
        doses: [TrackDoseEntry],
        schedule: NotificationSchedule,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        guard schedule.isEnabled else { return [] }
        var planned: [(fire: Date, item: PlannedNotification)] = []
        for supplement in supplements where supplement.isActive && supplement.reminds == true {
            let taken = Set(doses.filter { $0.supplementID == supplement.id }.map { calendar.startOfDay(for: $0.date) })
            for fire in MedicationSchedule.upcoming(for: supplement, after: now, days: horizonDays, calendar: calendar)
            where !taken.contains(calendar.startOfDay(for: fire)) {
                let parts = MedicationSchedule.wallClock(of: supplement, on: fire, calendar: calendar)
                let key = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                planned.append((fire, PlannedNotification(
                    id: prefix + supplement.id.uuidString + "." + key,
                    kind: .dose,
                    title: String(localized: "\(supplement.name) at \(ScoreMath.clock(fire, calendar: calendar))"),
                    body: String(localized: "\(amount(supplement.amount)) \(supplement.unit.symbol), as on your plan."),
                    trigger: .wallClock(parts),
                    link: .journal
                )))
            }
        }
        return planned.sorted { $0.fire < $1.fire }.prefix(limit).map(\.item)
    }

    /// The supplement a dose reminder is for, read back from its identifier.
    static func supplementID(fromIdentifier id: String) -> UUID? {
        guard id.hasPrefix(prefix) else { return nil }
        let rest = id.dropFirst(prefix.count)
        return rest.split(separator: ".").first.flatMap { UUID(uuidString: String($0)) }
    }

    /// Logs the dose a reminder's "Taken" was pressed on: the declared
    /// amount, at the moment of the press. Nil when the identifier is not a
    /// dose reminder, the supplement is gone, or a dose of it is already
    /// logged that day (a second press, or a dose logged in the app first).
    @MainActor
    @discardableResult
    static func logTaken(identifier: String, in store: TrackLogStore, at date: Date) -> TrackDoseEntry? {
        guard let id = supplementID(fromIdentifier: identifier),
              let supplement = store.supplements.first(where: { $0.id == id }),
              store.dose(of: supplement, on: date) == nil else { return nil }
        return store.logDose(name: supplement.name, amount: supplement.amount, unit: supplement.unit,
                             supplementID: supplement.id, at: date)
    }

    /// The category the router registers. "Taken" asks for the phone to be
    /// unlocked: the Track record is written with complete file protection,
    /// so a locked phone could not read it to add the dose.
    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [UNNotificationAction(identifier: takenAction, title: String(localized: "Taken"),
                                           options: [.authenticationRequired])],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Re-derives the dose reminders and puts them on the phone, in place
    /// of the ones pending.
    ///
    /// - Parameter asking: true when a person just turned a reminder on: the
    ///   notification permission is asked then, in context, if it never was.
    @MainActor
    static func sync(asking: Bool = false) async {
        let notifications = SomaNotifications.shared
        let scheduler = notifications.scheduler
        if asking, await scheduler.authorization() == .notDetermined {
            _ = await scheduler.requestAuthorization()
        }
        await notifications.refreshAuthorization()
        let log = TrackLogStore.shared
        let planned = reminders(for: log.supplements, doses: log.doses, schedule: notifications.schedule, now: .now)
        let stale = await scheduler.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        await scheduler.remove(stale)
        guard notifications.isOn else { return }
        for item in planned {
            try? await scheduler.add(item)
        }
    }

    private static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
