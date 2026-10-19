//
//  WidgetInboxDrain.swift
//  Prism
//
//  The widget's Log buttons cannot reach `TrackLogStore` (it lives in this
//  target), so they append to an inbox in the App Group. The app moves those
//  items into the store when it comes forward.
//

import Foundation
import SomaWidgetKit
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
enum WidgetInboxDrain {
    /// What one pass moved.
    struct Moved: Equatable {
        /// Items added to the store by this pass.
        var added: Set<UUID> = []
        /// Items now in the store (added here or by an earlier pass), safe to
        /// drop from the inbox.
        var settled: Set<UUID> = []
    }

    /// Moves pending items into the store; returns the ids moved.
    ///
    /// The one step form, for callers that publish nothing in between. The app
    /// itself uses ``move(_:into:saveToHealth:)`` and drops the items from the
    /// inbox only after the snapshot that counts them is written.
    @discardableResult
    static func drain(
        _ inbox: LogInbox,
        into store: TrackLogStore,
        saveToHealth: (TrackDrinkEntry) -> Void = WidgetInboxDrain.saveToHealth
    ) -> Set<UUID> {
        let moved = move(inbox, into: store, saveToHealth: saveToHealth)
        // A failed removal is safe: the next drain finds the ids in the store.
        if !moved.settled.isEmpty { try? inbox.remove(ids: moved.settled) }
        return moved.added
    }

    /// Adds pending items to the store without touching the inbox.
    ///
    /// Each drink keeps the item's id, so an item the store already holds (a
    /// drain whose removal did not land) is not added again. Each drink added
    /// goes to Apple Health the way one poured on the Track tab does; tests
    /// pass their own `saveToHealth`.
    static func move(
        _ inbox: LogInbox,
        into store: TrackLogStore,
        saveToHealth: (TrackDrinkEntry) -> Void = WidgetInboxDrain.saveToHealth
    ) -> Moved {
        let pending = inbox.pending()
        guard !pending.isEmpty else { return Moved() }
        let known = Set(store.drinks.map(\.id))
        var moved = Moved()
        for item in pending {
            moved.settled.insert(item.id)
            guard !known.contains(item.id), !moved.added.contains(item.id) else { continue }
            // Caffeine stays nil: the store works it out from the drink.
            let entry = store.addDrink(drink(for: item.kind), ml: item.ml, at: item.date, id: item.id)
            saveToHealth(entry)
            moved.added.insert(item.id)
        }
        return moved
    }

    static func drink(for kind: LogItem.Kind) -> TrackDrink {
        switch kind {
        case .water: .water
        case .coffee: .coffee
        }
    }

    // MARK: Apple Health

    /// The Health types a drained drink writes.
    enum HealthPart: Sendable { case water, caffeine }

    /// The Track tab's own path to Health for a poured drink, limited to the
    /// types the person has already answered for. The drain runs as the app
    /// comes forward, and Health asks once: a type still undecided is skipped
    /// rather than raising its write sheet here.
    static func saveToHealth(_ entry: TrackDrinkEntry) {
        let quantities = healthQuantities(for: entry, isDecided: isDecided)
        guard !quantities.isEmpty else { return }
        Task { await TrackHealthWriter.save(quantities, at: entry.date) }
    }

    /// What `saveDrink` would write for the entry, minus the undecided types.
    static func healthQuantities(
        for entry: TrackDrinkEntry,
        isDecided: (HealthPart) -> Bool
    ) -> [TrackHealthWriter.Quantity] {
        var quantities: [TrackHealthWriter.Quantity] = []
        if entry.ml > 0, isDecided(.water) { quantities.append(.water(millilitres: entry.ml)) }
        if entry.caffeineMg > 0, isDecided(.caffeine) { quantities.append(.caffeine(milligrams: entry.caffeineMg)) }
        return quantities
    }

    /// False while the write permission for the type has never been asked.
    static func isDecided(_ part: HealthPart) -> Bool {
        #if canImport(HealthKit)
        guard TrackHealthWriter.isAvailable else { return false }
        let type = switch part {
        case .water: HKQuantityType(.dietaryWater)
        case .caffeine: HKQuantityType(.dietaryCaffeine)
        }
        return healthStore.authorizationStatus(for: type) != .notDetermined
        #else
        return false
        #endif
    }

    #if canImport(HealthKit)
    private static let healthStore = HKHealthStore()
    #endif
}
