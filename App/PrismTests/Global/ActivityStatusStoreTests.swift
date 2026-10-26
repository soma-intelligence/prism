//
//  ActivityStatusStoreTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// How a person says they are this week is a choice, kept in this phone's
/// defaults with the day each change took effect. It has to come back after a
/// relaunch, take the earlier app's stored name as its seed, and read Training wherever
/// nothing was chosen.
@Suite("Activity status store")
@MainActor
struct ActivityStatusStoreTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func day(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    @Test("A phone that never chose reads Training, with no history")
    func fresh() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ActivityStatusStore(defaults: defaults, calendar: calendar)
        #expect(store.current == .training)
        #expect(store.changes.isEmpty)
        #expect(store.status(on: day(1)) == .training)
    }

    @Test("The earlier stored status seeds the first launch, Soma's own wins, and a name no build knows reads Training")
    func seed() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("sick", forKey: ActivityStatusStore.legacyKey)
        #expect(ActivityStatusStore(defaults: defaults, calendar: calendar).current == .unwell)

        defaults.set(ActivityStatus.travelling.rawValue, forKey: ActivityStatusStore.storageKey)
        #expect(ActivityStatusStore(defaults: defaults, calendar: calendar).current == .travelling)

        defaults.set("nonsense", forKey: ActivityStatusStore.storageKey)
        #expect(ActivityStatusStore(defaults: defaults, calendar: calendar).current == .training)
    }

    @Test("Each choice and its day survive a relaunch, one a day")
    func persistence() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let store = ActivityStatusStore(defaults: defaults, calendar: calendar)
        store.set(.unwell, at: day(10, 9))
        store.set(.resting, at: day(10, 20))
        store.set(.training, at: day(14))

        let reopened = ActivityStatusStore(defaults: defaults, calendar: calendar)
        #expect(reopened.current == .training)
        #expect(reopened.changes == store.changes)
        #expect(reopened.changes.map(\.status) == [.resting, .training])
        #expect(reopened.status(on: day(9)) == .training)
        #expect(reopened.status(on: day(12)) == .resting)
        #expect(reopened.status(on: day(20)) == .training)
    }

    @Test("Before any change is recorded, only today reads the seeded status")
    func seededWithoutHistory() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(ActivityStatus.resting.rawValue, forKey: ActivityStatusStore.storageKey)
        let store = ActivityStatusStore(defaults: defaults, calendar: calendar)
        #expect(store.status(on: Date()) == .resting)
        #expect(store.status(on: day(1)) == .training)
    }

    @Test("Every status but the usual marks the calendar, and only rest or illness holds training back")
    func effects() {
        #expect(ActivityStatus.allCases.filter(\.marksCalendar) == [.resting, .travelling, .unwell])
        #expect(ActivityStatus.allCases.filter(\.holdsTrainingBack) == [.resting, .unwell])
        #expect(Set(ActivityStatus.allCases.map(\.symbol)).count == ActivityStatus.allCases.count)
    }
}
