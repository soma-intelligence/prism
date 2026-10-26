//
//  WidgetInboxDrainTests.swift
//  PrismTests
//

import Foundation
import Testing
import SomaWidgetKit
@testable import Prism

@Suite("Widget inbox drain")
@MainActor
struct WidgetInboxDrainTests {
    private func inbox() -> LogInbox {
        LogInbox(directory: FileManager.default.temporaryDirectory.appending(path: "inbox-\(UUID().uuidString)"))
    }

    @Test func drainMovesItems() throws {
        let now = Date()
        let box = inbox()
        let water = LogItem(kind: .water, ml: 250, date: now)
        let coffee = LogItem(kind: .coffee, ml: 250, date: now)
        try box.append(water)
        try box.append(coffee)
        let store = TrackLogStore(url: nil)

        let moved = WidgetInboxDrain.drain(box, into: store, saveToHealth: { _ in })

        #expect(moved == [water.id, coffee.id])
        // Coffee counts as poured, like the Track tab's own water total.
        #expect(store.waterMl(on: now) == 500)
        #expect(store.caffeineMg(on: now) == 80)
        #expect(Set(store.drinks.map(\.id)) == [water.id, coffee.id])
        #expect(store.drinks.first { $0.id == coffee.id }?.drink == .coffee)
        #expect(box.pending().isEmpty)
    }

    @Test func drainIsIdempotent() throws {
        let now = Date()
        let box = inbox()
        let water = LogItem(kind: .water, ml: 250, date: now)
        try box.append(water)
        let store = TrackLogStore(url: nil)

        WidgetInboxDrain.drain(box, into: store, saveToHealth: { _ in })
        // The same item again, as if the removal had not landed.
        try box.append(water)
        let second = WidgetInboxDrain.drain(box, into: store, saveToHealth: { _ in })

        #expect(second.isEmpty)
        #expect(store.drinks.count == 1)
        #expect(store.waterMl(on: now) == 250)
        #expect(box.pending().isEmpty)
    }

    @Test func drainedDrinksGoToHealthOnce() throws {
        let now = Date()
        let box = inbox()
        let coffee = LogItem(kind: .coffee, ml: 250, date: now)
        try box.append(coffee)
        let store = TrackLogStore(url: nil)
        var saved: [TrackDrinkEntry] = []

        WidgetInboxDrain.drain(box, into: store, saveToHealth: { saved.append($0) })
        try box.append(coffee)
        WidgetInboxDrain.drain(box, into: store, saveToHealth: { saved.append($0) })

        #expect(saved.map(\.id) == [coffee.id])
        #expect(saved.first?.ml == 250)
        #expect(saved.first?.caffeineMg == 80)
        #expect(saved.first?.date == now)
    }

    @Test func healthSkipsUndecidedTypes() {
        let entry = TrackDrinkEntry(drink: .coffee, ml: 250, caffeineMg: 80, date: Date())
        let describe = { (q: [TrackHealthWriter.Quantity]) in q.map { String(describing: $0) } }

        let both = WidgetInboxDrain.healthQuantities(for: entry, isDecided: { _ in true })
        let waterOnly = WidgetInboxDrain.healthQuantities(for: entry, isDecided: { $0 == .water })
        let none = WidgetInboxDrain.healthQuantities(for: entry, isDecided: { _ in false })

        #expect(describe(both) == ["water(millilitres: 250.0)", "caffeine(milligrams: 80.0)"])
        #expect(describe(waterOnly) == ["water(millilitres: 250.0)"])
        #expect(none.isEmpty)
    }

    @Test func moveLeavesTheInbox() throws {
        let box = inbox()
        let water = LogItem(kind: .water, ml: 250, date: Date())
        try box.append(water)
        let store = TrackLogStore(url: nil)

        let moved = WidgetInboxDrain.move(box, into: store, saveToHealth: { _ in })

        #expect(moved.added == [water.id])
        #expect(moved.settled == [water.id])
        #expect(box.pending() == [water])
    }

    /// The snapshot that counts the drained drinks is written before they
    /// leave the inbox, so no render sees an emptied inbox with a stale
    /// snapshot.
    @Test func publishesBeforeClearingTheInbox() async throws {
        let box = inbox()
        let water = LogItem(kind: .water, ml: 250, date: Date())
        try box.append(water)
        let store = TrackLogStore(url: nil)
        let dir = FileManager.default.temporaryDirectory.appending(path: "snap-\(UUID().uuidString)")
        var pendingAtReload: [Int] = []
        let pub = WidgetPublisher(store: SnapshotStore(directory: dir), reload: { _ in
            pendingAtReload.append(box.pending().count)
        })

        pub.stageDrain(box, track: store, saveToHealth: { _ in })
        await pub.gatherAndPublish(track: store)

        #expect(!pendingAtReload.isEmpty)
        #expect(pendingAtReload.allSatisfy { $0 == 1 })
        #expect(box.pending().isEmpty)
        #expect(SnapshotStore(directory: dir).read()?.tally.countedIDs.contains(water.id) == true)
    }

    /// The drain's own change to the store does not need a second publish.
    @Test func trackChangeAfterPublishIsCoalesced() async throws {
        let store = TrackLogStore(url: nil)
        let dir = FileManager.default.temporaryDirectory.appending(path: "snap-\(UUID().uuidString)")
        let pub = WidgetPublisher(store: SnapshotStore(directory: dir), reload: { _ in })
        store.addDrink(.water, ml: 250, at: Date())
        await pub.gatherAndPublish(track: store)

        #expect(!pub.trackDiffers(track: store, now: Date()))
        store.addDrink(.water, ml: 250, at: Date())
        #expect(pub.trackDiffers(track: store, now: Date()))
    }

    @Test func drainKeepsTheItemsDate() throws {
        let yesterday = Date().addingTimeInterval(-86_400)
        let box = inbox()
        try box.append(LogItem(kind: .water, ml: 330, date: yesterday))
        let store = TrackLogStore(url: nil)

        WidgetInboxDrain.drain(box, into: store, saveToHealth: { _ in })

        #expect(store.waterMl(on: yesterday) == 330)
        #expect(store.waterMl(on: Date()) == nil)
    }

    @Test func tallyCountsDrainedIDs() throws {
        let now = Date()
        let box = inbox()
        let water = LogItem(kind: .water, ml: 250, date: now)
        try box.append(water)
        let store = TrackLogStore(url: nil)
        WidgetInboxDrain.drain(box, into: store, saveToHealth: { _ in })

        let tally = WidgetPublisher.tally(from: store, now: now)

        #expect(tally.waterMl == 250)
        #expect(tally.countedIDs.contains(water.id))
        // The widget adds the same pending item to this tally: counted once.
        #expect(tally.adding([water], day: tally.day, calendar: .current).waterMl == 250)
    }
}
