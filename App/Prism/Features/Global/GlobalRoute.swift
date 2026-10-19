//
//  GlobalRoute.swift
//  Prism
//

import SwiftUI

/// The app wide pages: health records, the calendar, activity status and its
/// legend, and the Share studio.
///
/// Registered on every tab's stack by `journeyDestinations()`, so a link
/// anywhere in the app can push one of these with `NavigationLink(value:)`
/// or a `TileLink`. Each case maps to its page in `page`. The calendar, the
/// status picker and the studio are sheets in the design; the views that open
/// them present `page` inside ``GlobalSheet``.
enum GlobalRoute: Hashable, Identifiable {
    case healthRecords
    case calendar
    case activityStatus
    case activityLegend
    case shareStudio

    var id: Self { self }

    @ViewBuilder
    var page: some View {
        switch self {
        case .healthRecords:
            HealthRecordsPage()
        case .calendar:
            CalendarPage()
        case .activityStatus:
            ActivityStatusPage()
        case .activityLegend:
            ActivityStatusLegendPage()
        case .shareStudio:
            ShareStudioPage()
        }
    }
}
