//
//  SomaWidgetsModifier.swift
//  Prism
//

import SwiftUI
import HealthKit
import HealthExportCore

/// Publishes the widget snapshot at the moments it can change: when the app
/// comes forward (after draining the widget's logged drinks), when the scores
/// or the latest readings land, and after a run of Track changes. iOS only:
/// the widgets ship there, and no other platform has the App Group.
private struct SomaWidgetsModifier: ViewModifier {
    let health: HealthDashboard

    @Environment(\.scenePhase) private var phase

    private var track: TrackLogStore { .shared }

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onChange(of: phase, initial: true) { _, phase in
                guard phase == .active else { return }
                WidgetPublisher.shared.attach(health: health)
                WidgetRefresh.attach(health: health)
                WidgetRefresh.schedule()
                WidgetPublisher.shared.drainAndPublish()
            }
            // Health observation starts only once access was granted.
            .onChange(of: health.status, initial: true) { _, status in
                guard status == .ready else { return }
                WidgetRefresh.observeHealth()
            }
            .onChange(of: health.scores) { WidgetPublisher.shared.publishFromApp() }
            .onChange(of: health.readings) { WidgetPublisher.shared.schedulePublish() }
            .onChange(of: track.drinks) { WidgetPublisher.shared.scheduleTrackPublish() }
            .onChange(of: track.meals) { WidgetPublisher.shared.scheduleTrackPublish() }
            .onChange(of: track.moods) { WidgetPublisher.shared.scheduleTrackPublish() }
        #else
        content
        #endif
    }
}

extension View {
    /// The home and lock screen widgets, kept current from the root.
    func somaWidgets(health: HealthDashboard) -> some View {
        modifier(SomaWidgetsModifier(health: health))
    }
}
