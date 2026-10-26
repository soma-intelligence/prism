//
//  MetricRoute.swift
//  Prism
//

import SwiftUI

/// The fitness and metric pages: steps, ECG, heart rhythm, mobility, mouth and teeth, sound, territory, activity summary, cardio load, heart rate recovery, training.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`.
///
/// The training menu and the cardio load explainer are sheets, opened by the
/// page that offers them, so they are not routes.
enum MetricRoute: Hashable {
    /// Steps today against usual, week by week, and the month so far.
    case steps
    /// The latest ECG recording, what it means, and the ones before it.
    case ecg
    /// AFib History week by week, what it means, and the way to the ECG.
    case afibBurden
    /// Irregular rhythm, high and low heart rate notifications, by date.
    case rhythmEvents
    /// Walking steadiness, its notifications, falls, gait and balance work.
    case mobility
    /// Thirty days of brushing, the Journal's floss and gums, and the next
    /// dental visit.
    case oral
    /// The sound around you, day by day, against the 80 dB line.
    case environmentalSound
    /// Headphone levels and the share of a safe week they used.
    case headphoneAudio
    /// Where a month of walks and runs went, on a map.
    case territory
    /// Thirty days of sessions by type, the Move ring and recent sessions.
    case activitySummary
    /// Daily strain against the target band.
    case strainPerformance
    /// Seven day load against the productive band.
    case cardioLoad
    /// What a week of cardio trained, zone by zone.
    case cardioFocus
    /// The one minute drop after each workout.
    case heartRateRecovery
    /// Which muscle groups a month of sessions loaded.
    case muscleWork
    /// A routine, read before it is started.
    case sessionPreview(String)

    @ViewBuilder
    var page: some View {
        switch self {
        case .steps: StepsPage()
        case .ecg: ECGPage()
        case .afibBurden: AFibBurdenPage()
        case .rhythmEvents: RhythmEventsPage()
        case .mobility: MobilityPage()
        case .oral: OralHealthPage()
        case .environmentalSound: SoundExposurePage(kind: .environment)
        case .headphoneAudio: SoundExposurePage(kind: .headphones)
        case .territory: TerritoryPage()
        case .activitySummary: ActivitySummaryPage()
        case .strainPerformance: StrainPerformancePage()
        case .cardioLoad: CardioLoadPage()
        case .cardioFocus: CardioFocusPage()
        case .heartRateRecovery: HeartRateRecoveryPage()
        case .muscleWork: MuscleWorkPage()
        case .sessionPreview(let id): SessionPreviewPage(routineID: id)
        }
    }
}
