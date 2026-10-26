//
//  SomaCloudModifier.swift
//  Prism
//

import SwiftUI

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
