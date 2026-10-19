//
//  TrackRoute.swift
//  Prism
//

import SwiftUI

/// The logging pages Track opens: fasting, the body's measures, drinks and
/// intake, food, doses, the evening, the mood and the morning's rating.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. The same pages open as sheets from Track's "Add to today"
/// chips through `trackEntrySheet(item:)`, which gives them a Cancel.
enum TrackRoute: Hashable, Identifiable {
    /// A fast drawn on a 24 hour clock.
    case fasting
    /// A weight on the turning scale.
    case weight
    /// A height against the ruler, then the waist.
    case height
    /// What to know before the camera scan.
    case cameraScan
    /// The evening: how the day went, what was taken, what happened tonight.
    case evening
    /// How the day felt: the orb, seven stops, words and what had a hand in
    /// it. Sets the Journal's feeling for the day.
    case mood
    /// The same, for right now.
    case moodNow
    /// A drink poured into the glass.
    case drink(TrackDrink)
    /// The day's glass and the caffeine still on board.
    case intake
    /// A timed practice: cold plunge, sauna, meditation.
    case practice(TrackPractice)
    /// How the night felt on waking, as a moon.
    case wake
    /// A meal as a ring in proportion.
    case food
    /// A dose of a supplement on the plan, or a new one when nil.
    case dose(UUID?)

    var id: Self { self }

    @ViewBuilder
    var page: some View {
        switch self {
        case .fasting: TrackFastingView()
        case .weight: TrackWeightView()
        case .height: TrackHeightView()
        case .cameraScan: TrackCameraScanIntro()
        case .evening: TrackEveningView()
        case .mood: TrackMoodView(scope: .today)
        case .moodNow: TrackMoodView(scope: .now)
        case .drink(let drink): TrackWaterView(initial: drink)
        case .intake: TrackIntakeView()
        case .practice(let practice): TrackPracticeView(practice: practice)
        case .wake: TrackWakeView()
        case .food: TrackFoodView()
        case .dose(let id): TrackDoseView(supplementID: id)
        }
    }
}
