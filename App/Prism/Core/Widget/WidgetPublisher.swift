//
//  WidgetPublisher.swift
//  Prism
//
//  Writes the widget snapshot into the App Group and asks WidgetKit to redraw
//  only the widgets whose part of it changed.
//

import Foundation
import SwiftUI
import HealthKit
import HealthExportCore
import SomaWidgetKit
#if canImport(WidgetKit) && os(iOS)
import WidgetKit
#endif

@MainActor
final class WidgetPublisher {
    static let shared = WidgetPublisher(store: SnapshotStore.shared, reload: WidgetPublisher.reloadTimelines)

    private let store: SnapshotStore?
    private let reload: (WidgetKind) -> Void
    /// What the widgets last got, to tell which ones need to redraw.
    private var last: SomaWidgetSnapshot?

    /// The app's one Health reader, attached at the root.
    private weak var health: HealthDashboard?
    private var gather: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var trackDebounce: Task<Void, Never>?
    /// Drained items waiting to leave the inbox until a snapshot that counts
    /// them is written.
    private var pendingRemoval: (inbox: LogInbox, ids: Set<UUID>)?

    /// How long a run of Track changes waits before one publish.
    static let debounceInterval: Duration = .seconds(2)

    init(store: SnapshotStore?, reload: @escaping (WidgetKind) -> Void) {
        self.store = store
        self.reload = reload
        last = store?.read()
    }

    func attach(health: HealthDashboard) {
        self.health = health
    }

    /// Writes the snapshot and reloads the kinds whose slice changed. The age
    /// alone never triggers a reload.
    @discardableResult
    func publish(_ snapshot: SomaWidgetSnapshot) -> Bool {
        guard let store else { return false }
        do {
            try store.write(snapshot)
        } catch {
            // The widgets keep the last snapshot; the next publish tries again.
            return false
        }
        let changed = Self.changedKinds(from: last, to: snapshot, calendar: .current)
        last = snapshot
        for kind in WidgetKind.allCases where changed.contains(kind) {
            reload(kind)
        }
        return true
    }

    /// Gathers the inputs from Health and the Track log, builds, publishes.
    /// A second call while one is reading replaces it.
    func publishFromApp() {
        gather?.cancel()
        gather = Task { [weak self] in
            await self?.gatherAndPublish()
        }
    }

    /// Publishes after a quiet spell, for a run of new readings.
    func schedulePublish() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            self?.publishFromApp()
        }
    }

    /// Publishes after a quiet spell, for a run of Track changes, unless the
    /// widgets already show them: the drain's own change to the store lands
    /// in the snapshot the drain publishes.
    func scheduleTrackPublish() {
        trackDebounce?.cancel()
        trackDebounce = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled, let self else { return }
            guard self.trackDiffers(track: .shared, now: Date()) else { return }
            self.publishFromApp()
        }
    }

    /// Whether the Track log reads differently from what the widgets last got.
    func trackDiffers(track: TrackLogStore, now: Date) -> Bool {
        guard let last else { return true }
        return Self.tally(from: track, now: now) != last.tally
            || Self.eatenKcal(from: track, now: now) != last.eatenKcal
    }

    /// Coming forward: the widget's logged drinks go into the store first,
    /// then the snapshot carries them, then they leave the inbox.
    func drainAndPublish() {
        if let inbox = LogInbox.shared {
            stageDrain(inbox, track: .shared)
        }
        publishFromApp()
    }

    /// Moves the inbox into the store and holds the ids for removal after the
    /// next snapshot is written.
    func stageDrain(
        _ inbox: LogInbox,
        track: TrackLogStore,
        saveToHealth: (TrackDrinkEntry) -> Void = WidgetInboxDrain.saveToHealth
    ) {
        let moved = WidgetInboxDrain.move(inbox, into: track, saveToHealth: saveToHealth)
        guard !moved.settled.isEmpty else { return }
        pendingRemoval = (inbox, (pendingRemoval?.ids ?? []).union(moved.settled))
    }

    /// Reads the store after the Health await, so a snapshot written after
    /// `stageDrain` always counts the drained drinks.
    func gatherAndPublish(track: TrackLogStore = .shared) async {
        let now = Date()
        let energy = await Self.energyToday(from: health, now: now)
        guard !Task.isCancelled else { return }
        // Only what was read in this process replaces the widgets' values: a
        // dashboard that has not loaded yet, or a read that failed, keeps the
        // previous snapshot's slice rather than blanking it.
        let read = HealthRead(
            scores: health?.hasReadScores == true,
            vitals: health?.hasReadReadings == true,
            energy: energy.read
        )
        let inputs = WidgetSnapshotBuilder.Inputs(
            scores: health?.scores,
            restingHR: health?.readings[Metric.restingHR]?.value,
            hrv: health?.readings[Metric.hrv]?.value,
            activeKcal: energy.active,
            basalKcal: energy.basal,
            tally: Self.tally(from: track, now: now),
            eatenKcal: Self.eatenKcal(from: track, now: now)
        )
        let removal = pendingRemoval
        let built = WidgetSnapshotBuilder.build(inputs, now: now)
        guard publish(Self.carryingUnread(built, from: last, read: read)) else { return }
        if let removal {
            // A failed removal is safe: the next drain finds the ids in the store.
            try? removal.inbox.remove(ids: removal.ids)
            pendingRemoval = nil
        }
    }

    /// Which Health slices this pass actually read. The Track log is always
    /// read, so it has no flag.
    struct HealthRead: Equatable, Sendable {
        /// Soma's scores and everything derived from them: the rings, the
        /// energy curve, last night, sleep hours and the vitals' traces.
        var scores: Bool
        /// The latest resting heart rate and variability.
        var vitals: Bool
        /// Today's burned energy.
        var energy: Bool

        static let none = HealthRead(scores: false, vitals: false, energy: false)
        static let all = HealthRead(scores: true, vitals: true, energy: true)
    }

    /// The new snapshot with every Health slice that was not read in this pass
    /// taken from the previous one: a pass before the scores load (a cold
    /// launch, the first publish on coming forward) must not blank the widgets
    /// or flip them to "Open Soma". Burned energy is a day's total and carries
    /// within its day only. Read slices go through ``carryingVitals``.
    static func carryingUnread(
        _ new: SomaWidgetSnapshot,
        from old: SomaWidgetSnapshot?,
        read: HealthRead,
        calendar: Calendar = .current
    ) -> SomaWidgetSnapshot {
        guard let old else { return new }
        var result = new
        if !read.scores {
            result.sleep = old.sleep
            result.recovery = old.recovery
            result.strain = old.strain
            result.stress = old.stress
            result.energyNow = old.energyNow
            result.energyCurve = old.energyCurve
            result.sleepBand = old.sleepBand
            result.sleepHours = old.sleepHours
            result.hypnogram = old.hypnogram
            result.restingHR.series7 = old.restingHR.series7
            result.hrv.series7 = old.hrv.series7
        }
        if !read.vitals {
            result.restingHR.value = old.restingHR.value
            result.hrv.value = old.hrv.value
        }
        if !read.energy {
            let sameDay = calendar.isDate(old.generatedAt, inSameDayAs: new.generatedAt)
            result.burnedKcal = sameDay ? old.burnedKcal : nil
        }
        result = carryingVitals(result, from: old, calendar: calendar)
        result.hasData = WidgetSnapshotBuilder.hasData(result)
        return result
    }

    /// A resting heart rate or variability that came back nil keeps the
    /// previous snapshot's value when that one is from the same day: a read
    /// that found nothing (a background wake, a locked store) must not blank
    /// the widget.
    static func carryingVitals(
        _ new: SomaWidgetSnapshot,
        from old: SomaWidgetSnapshot?,
        calendar: Calendar = .current
    ) -> SomaWidgetSnapshot {
        guard let old, calendar.isDate(old.generatedAt, inSameDayAs: new.generatedAt) else { return new }
        var result = new
        if result.restingHR.value == nil { result.restingHR.value = old.restingHR.value }
        if result.hrv.value == nil { result.hrv.value = old.hrv.value }
        if result.restingHR.value != nil || result.hrv.value != nil { result.hasData = true }
        return result
    }

    // MARK: Inputs

    enum Metric {
        static let restingHR = "HKQuantityTypeIdentifierRestingHeartRate"
        static let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
        static let basalEnergy = "HKQuantityTypeIdentifierBasalEnergyBurned"
    }

    /// Today's logged intake, with every drink of the day in `countedIDs`: a
    /// drained widget item keeps its id in the store, so the widget never adds
    /// it a second time.
    static func tally(from track: TrackLogStore, now: Date) -> SomaWidgetSnapshot.Tally {
        let drinks = track.drinks(on: now)
        return SomaWidgetSnapshot.Tally(
            day: track.stamp(now),
            waterMl: track.waterMl(on: now) ?? 0,
            caffeineMg: track.caffeineMg(on: now) ?? 0,
            moods: track.moods(on: now).count,
            meals: track.meals(on: now).count,
            waterGoalMl: track.waterGoalMl,
            countedIDs: Set(drinks.map(\.id))
        )
    }

    /// Kilocalories of today's meals, or nil when none was logged.
    static func eatenKcal(from track: TrackLogStore, now: Date) -> Double? {
        let meals = track.meals(on: now)
        return meals.isEmpty ? nil : meals.reduce(0) { $0 + $1.kilocalories }
    }

    /// Active and resting energy since midnight, from the types the launch
    /// request already covers. Nil where Health holds nothing; `read` is false
    /// when nothing could be asked (no dashboard, a locked phone) or a query
    /// threw.
    private static func energyToday(from health: HealthDashboard?, now: Date) async -> (active: Double?, basal: Double?, read: Bool) {
        guard let health, health.isAvailable, HealthDashboard.isProtectedDataAvailable else { return (nil, nil, false) }
        let source = health.reader
        let midnight = Calendar.current.startOfDay(for: now)
        func total(_ identifier: String) async -> (value: Double?, read: Bool) {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return (nil, true) }
            do {
                return (try await source.total(metric, from: midnight, to: now)?.value, true)
            } catch {
                return (nil, false)
            }
        }
        async let active = total(Metric.activeEnergy)
        async let basal = total(Metric.basalEnergy)
        let (a, b) = await (active, basal)
        return (a.value, b.value, a.read && b.read)
    }

    // MARK: Reload diff

    /// The widget kinds whose slice differs. Everything when there is no
    /// previous snapshot, when `hasData` flips (every widget draws its empty
    /// state from it), or when the previous snapshot was stale or from
    /// another day by now: the widgets drew its age, or a day's totals, and
    /// equal values alone would leave that on screen.
    static func changedKinds(
        from old: SomaWidgetSnapshot?,
        to new: SomaWidgetSnapshot,
        calendar: Calendar = .current
    ) -> Set<WidgetKind> {
        guard let old, old.hasData == new.hasData,
              old.freshness(now: new.generatedAt) == .fresh,
              calendar.isDate(old.generatedAt, inSameDayAs: new.generatedAt)
        else { return Set(WidgetKind.allCases) }
        var kinds: Set<WidgetKind> = []
        if old.sleep != new.sleep || old.recovery != new.recovery
            || old.strain != new.strain || old.stress != new.stress {
            kinds.insert(.scores)
        }
        if old.restingHR != new.restingHR || old.hrv != new.hrv
            || old.sleepHours != new.sleepHours || old.hypnogram != new.hypnogram {
            kinds.insert(.vitals)
        }
        if old.stress != new.stress || old.energyNow != new.energyNow
            || old.energyCurve != new.energyCurve || old.sleepBand != new.sleepBand {
            kinds.insert(.strain)
        }
        if old.burnedKcal != new.burnedKcal || old.eatenKcal != new.eatenKcal {
            kinds.insert(.fuel)
        }
        if old.tally != new.tally {
            kinds.insert(.log)
        }
        return kinds
    }

    nonisolated static func reloadTimelines(_ kind: WidgetKind) {
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        #endif
    }
}
