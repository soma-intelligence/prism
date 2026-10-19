//
//  CloudBackground.swift
//  Prism
//

import SwiftUI
#if os(iOS) || os(visionOS)
import BackgroundTasks
#endif

/// The sync's background work: a processing task (long, on power, for the
/// Health upload) and an app refresh (short, for records), both listed in
/// `Prism-Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
enum CloudBackground {
    static let processingIdentifier = "Soma.Prism.cloud-sync"
    static let refreshIdentifier = "Soma.Prism.cloud-refresh"

    /// Registers both handlers. Must run before launch finishes, which is why
    /// `PrismApp.init` calls it.
    static func register() {
#if os(iOS) || os(visionOS)
        for identifier in [processingIdentifier, refreshIdentifier] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                let handle = TaskHandle(task)
                let work = Task { @MainActor in
                    let finished = await CloudSync.shared.backgroundPass()
                    schedule()
                    handle.complete(finished)
                }
                task.expirationHandler = { work.cancel() }
            }
        }
#endif
    }

    /// Asks for the next background passes. Called after each one and when
    /// the app goes to the background.
    static func schedule() {
#if os(iOS) || os(visionOS)
        let processing = BGProcessingTaskRequest(identifier: processingIdentifier)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        let refresh = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(processing)
            try BGTaskScheduler.shared.submit(refresh)
        } catch {
            // Refused in the simulator and when background refresh is off;
            // the next foreground pass does the work instead.
        }
#endif
    }
}

#if os(iOS) || os(visionOS)
/// Carries the system's task into the main actor's work. The scheduler hands
/// it over on its own queue and only `setTaskCompleted` is called on it.
private final class TaskHandle: @unchecked Sendable {
    private let task: BGTask
    init(_ task: BGTask) { self.task = task }
    func complete(_ success: Bool) { task.setTaskCompleted(success: success) }
}
#endif

/// Starts the cloud sync with the app's environment objects and runs a pass
/// each time the app comes forward.
private struct SomaCloudModifier: ViewModifier {
    let health: HealthDashboard
    let journal: JournalStore

    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .task { CloudSync.shared.attach(health: health, journal: journal) }
            .onChange(of: phase) { _, phase in
                switch phase {
                case .active: Task { await CloudSync.shared.syncNow() }
                case .background: CloudBackground.schedule()
                default: break
                }
            }
    }
}

extension View {
    /// The account's cloud sync, attached once at the root.
    func somaCloud(health: HealthDashboard, journal: JournalStore) -> some View {
        modifier(SomaCloudModifier(health: health, journal: journal))
    }
}
