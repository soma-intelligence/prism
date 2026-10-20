//
//  HomeRoute.swift
//  Prism
//

import SwiftUI

/// The pages Pulse's Today opens beyond the scores: next move, timeline, nutrition, cycle, the medical card.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`.
enum HomeRoute: Hashable {
    /// The move behind the orb, why, and the other doors.
    case nextMove
    /// The day hour by hour, and what is still to come.
    case timeline
    /// Today's meals against the usual, and the rise after each.
    case nutrition
    /// Where the person is in their cycle, and what the phase moves.
    case cycle
    /// Date of birth, blood type and what an emergency needs.
    case medicalCard

    @ViewBuilder
    var page: some View {
        switch self {
        case .nextMove: HomeNextMovePage()
        case .timeline: HomeTimelinePage()
        case .nutrition: HomeNutritionPage()
        case .cycle: HomeCyclePage()
        case .medicalCard: HomeMedicalCardPage()
        }
    }
}

/// The sheets Today and its pages open over themselves.
enum HomeSheetRoute: Identifiable, Hashable {
    case notifications
    case quickAdd
    case lastNight
    case marker(HomeMarker)
    case mood
    case editToday
    case allCategories
    case stand
    case foodLog
    case checkIn
    case effort
    case breathe
    case walk(minutes: Int)

    var id: String {
        switch self {
        case .notifications: "notifications"
        case .quickAdd: "quickAdd"
        case .lastNight: "lastNight"
        case .marker(let marker): "marker.\(marker.rawValue)"
        case .mood: "mood"
        case .editToday: "editToday"
        case .allCategories: "allCategories"
        case .stand: "stand"
        case .foodLog: "foodLog"
        case .checkIn: "checkIn"
        case .effort: "effort"
        case .breathe: "breathe"
        case .walk(let minutes): "walk.\(minutes)"
        }
    }

    /// Whether it takes the whole screen rather than a sheet.
    var isCover: Bool {
        if case .walk = self { return true }
        return false
    }

    @ViewBuilder
    var sheet: some View {
        switch self {
        case .notifications: NotificationCenterSheet()
        case .quickAdd: HomeQuickAddSheet()
        // The same page the night card pushes, in a stack of its own.
        case .lastNight: NavigationStack { LastNightPage().journeyDestinations() }
        case .marker(let marker): HomeMarkerSheet(initial: marker)
        case .mood: NavigationStack { TrackMoodView() }
        case .editToday: HomeEditTodaySheet()
        case .allCategories: HomeAllCategoriesSheet()
        case .stand: HomeStandSheet()
        case .foodLog: NavigationStack { TrackFoodView() }
        case .checkIn: HomeCheckInSheet()
        case .effort: HomeEffortSheet()
        case .breathe: MindBreatheSheet()
        case .walk(let minutes): HomeWalkLiveView(targetMinutes: minutes)
        }
    }
}

extension View {
    /// Presents a ``HomeSheetRoute``: a sheet, or the whole screen for a walk
    /// on a phone.
    func homeSheets(_ route: Binding<HomeSheetRoute?>) -> some View {
        modifier(HomeSheetPresenter(route: route))
    }
}

private struct HomeSheetPresenter: ViewModifier {
    @Binding var route: HomeSheetRoute?

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .sheet(item: sheetBinding) { $0.sheet }
            .fullScreenCover(item: coverBinding) { $0.sheet }
#else
        content
            .sheet(item: $route) { $0.sheet }
#endif
    }

    private var sheetBinding: Binding<HomeSheetRoute?> {
        Binding(
            get: { route.flatMap { $0.isCover ? nil : $0 } },
            set: { if $0 == nil, route?.isCover != true { route = nil } }
        )
    }

    private var coverBinding: Binding<HomeSheetRoute?> {
        Binding(
            get: { route.flatMap { $0.isCover ? $0 : nil } },
            set: { if $0 == nil, route?.isCover == true { route = nil } }
        )
    }
}
