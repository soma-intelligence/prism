//
//  WidgetRefresh.swift
//  Prism
//
//  Wakes the app in the background to republish the widget snapshot: hourly,
//  and when Health gets new readings. iOS only, like the widgets.
//

#if os(iOS)
import Foundation
import BackgroundTasks
import UIKit
import HealthKit
import OSLog
import HealthExportCore

@MainActor
enum WidgetRefresh {
    static let taskID = "Soma.Prism.widgets.refresh"

    /// How long after one refresh the next may begin.
    static let interval: TimeInterval = 3600

    /// Set once Health observation started: it only starts after access was
    /// granted, so a background launch may read Health without asking.
    static let grantedKey = "widgets.refresh.healthObserved"

    /// Whether files under complete protection, and Health, can be read now.
    /// A seam for tests.
    static var isProtectedDataAvailable: () -> Bool = { UIApplication.shared.isProtectedDataAvailable }

    private static var health: HealthDashboard?
    /// Whether `health` is the app's own dashboard (true) or one made for a
    /// background launch (false), which must never ask for access.
    private static var mayRequestAccess = false
    private static var observing = false

    static func earliestBegin(now: Date) -> Date {
        now.addingTimeInterval(interval)
    }

    /// The app's one Health reader, attached at the root.
    static func attach(health: HealthDashboard) {
        self.health = health
        mayRequestAccess = true
    }

    /// The one Health store the observer queries and background delivery
    /// run on, kept for the life of the process: a temporary store would take
    /// its queries with it.
    static let store = HKHealthStore()

    /// Hands the app's dashboard over at launch, before a Health wake can
    /// run, so a wake reuses it rather than building a second one (and a
    /// second ninety day read). It may not ask for access: a background
    /// launch never shows the sheet. The root's `attach` lifts that.
    static func adopt(health: HealthDashboard) {
        guard self.health == nil else { return }
        self.health = health
        mayRequestAccess = false
    }

    /// The dashboard a refresh reads with, for tests.
    static var attached: HealthDashboard? { health }

    /// Forgets the attached dashboard, as on a fresh process.
    static func detach() {
        health = nil
        mayRequestAccess = false
    }

    /// Registers the hourly task. Must run before launch finishes.
    nonisolated static func register() {
        // A HealthKit wake only reaches an observer registered again in this
        // process, and the root view may never be built in a background launch.
        // `PrismApp.init` runs on the main actor.
        if UserDefaults.standard.bool(forKey: grantedKey) {
            MainActor.assumeIsolated { observeHealth() }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            let handle = TaskHandle(task)
            let work = Task { @MainActor in
                let finished = await refresh()
                schedule()
                handle.complete(finished)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule(now: Date = .now) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = earliestBegin(now: now)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Refused in the simulator and when background refresh is off;
            // coming forward publishes instead.
            #if DEBUG
            Logger(subsystem: "Soma.Prism", category: "widgets").debug("refresh not scheduled: \(error)")
            #endif
        }
    }

    /// Watches the types the widgets read and wakes the app when one gets a
    /// sample. Call only after Health access was granted: this asks for
    /// nothing. Safe to call again.
    static func observeHealth(_ store: HKHealthStore = WidgetRefresh.store) {
        guard !observing, HKHealthStore.isHealthDataAvailable() else { return }
        observing = true
        UserDefaults.standard.set(true, forKey: grantedKey)
        let types: [HKObjectType] = [
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
        ]
        for type in types {
            guard let sampleType = type as? HKSampleType else { continue }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
                // The system wants this called on every path, or it stops
                // delivering.
                let done = CompletionHandle(completion)
                guard error == nil else {
                    done.call()
                    return
                }
                Task { @MainActor in
                    _ = await refresh()
                    done.call()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }
        }
    }

    /// Reads the scores again and publishes. False when there was nothing to
    /// read with: no Health observed yet and no dashboard attached, or the
    /// phone is locked (Health and the Track log are closed then, and a read
    /// would publish empty values; the next run tries again).
    static func refresh() async -> Bool {
        guard isProtectedDataAvailable() else {
            schedule()
            return false
        }
        let dashboard: HealthDashboard
        if let health {
            dashboard = health
        } else if UserDefaults.standard.bool(forKey: grantedKey) {
            // A background launch: the root view may not exist.
            dashboard = HealthDashboard(source: HealthDashboard.launchSource())
            health = dashboard
            mayRequestAccess = false
        } else {
            return false
        }
        WidgetPublisher.shared.attach(health: dashboard)
        await dashboard.loadScores(force: true, requestAccess: mayRequestAccess)
        let latest = [WidgetPublisher.Metric.restingHR, WidgetPublisher.Metric.hrv]
            .compactMap(HealthMetricCatalog.metric(for:))
        await dashboard.loadLatest(latest, requestAccess: mayRequestAccess)
        guard !Task.isCancelled else { return false }
        await WidgetPublisher.shared.gatherAndPublish()
        return !Task.isCancelled
    }
}

/// Carries the system's task into the main actor's work; only
/// `setTaskCompleted` is called on it.
private final class TaskHandle: @unchecked Sendable {
    private let task: BGTask

    init(_ task: BGTask) { self.task = task }

    func complete(_ success: Bool) { task.setTaskCompleted(success: success) }
}

/// HealthKit's completion handler, carried across the hop to the main actor.
private final class CompletionHandle: @unchecked Sendable {
    private let handler: HKObserverQueryCompletionHandler

    init(_ handler: @escaping HKObserverQueryCompletionHandler) { self.handler = handler }

    func call() { handler() }
}
#endif
