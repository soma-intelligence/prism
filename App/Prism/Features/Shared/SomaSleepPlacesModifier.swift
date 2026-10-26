//
//  SomaSleepPlacesModifier.swift
//  Prism
//

import SwiftUI
import HealthScoring

/// Hands the recorder each moment the app comes forward, with last night's
/// window, and again when the scores land with a window the first pass did
/// not have yet.
private struct SomaSleepPlacesModifier: ViewModifier {
    let health: HealthDashboard

    @Environment(\.scenePhase) private var phase

    private var lastNight: DateInterval? {
        guard let night = health.scores?.detail.lastNight, night.start <= night.end else { return nil }
        return DateInterval(start: night.start, end: night.end)
    }

    func body(content: Content) -> some View {
        if SleepPlaceRecorder.isSupported {
            content
                .onChange(of: phase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    SleepPlaceRecorder.shared.appBecameActive(lastNight: lastNight)
                }
                .onChange(of: health.scores?.detail.lastNight) {
                    guard phase == .active else { return }
                    SleepPlaceRecorder.shared.appBecameActive(lastNight: lastNight)
                }
        } else {
            content
        }
    }
}

extension View {
    /// Detection of where each night was slept, when the person turned it on.
    func somaSleepPlaces(health: HealthDashboard) -> some View {
        modifier(SomaSleepPlacesModifier(health: health))
    }
}
