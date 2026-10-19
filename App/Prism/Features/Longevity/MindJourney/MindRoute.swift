//
//  MindRoute.swift
//  Prism
//

import SwiftUI

/// The Mind lens's deeper pages: the Mind score, insights, what habits do to
/// recovery and sleep, meetings, HRV, the inner map, the stress radar and the
/// mood forecast.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`.
enum MindRoute: Hashable {
    /// Mind · detail: the score and what moved it.
    case detail
    /// Insights · last 60 days: when stress peaks and what comes before.
    case insights
    /// Insights · Recovery and Sleep: what habits do to each.
    case habits(MindHabitLens)
    /// Meeting stress: today's meetings against the usual.
    case meetings
    /// Metric · HRV.
    case hrv
    /// The inner map: feelings by week, felt against measured, what pulls.
    case innerMap
    /// Stress Radar: today's episodes and where stress rises.
    case stressRadar
    /// Mood forecast: the day ahead.
    case moodForecast

    @ViewBuilder
    var page: some View {
        switch self {
        case .detail: MindDetailPage()
        case .insights: MindInsightsPage()
        case .habits(let lens): MindHabitsPage(lens: lens)
        case .meetings: MindMeetingsPage()
        case .hrv: MindHRVPage()
        case .innerMap: MindInnerMapPage()
        case .stressRadar: MindStressRadarPage()
        case .moodForecast: MindMoodForecastPage()
        }
    }
}
