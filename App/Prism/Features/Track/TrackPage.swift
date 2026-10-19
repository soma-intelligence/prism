//
//  TrackPage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The parts of the Track tab.
enum TrackSection: PageSection {
    case journal
    case rituals
    case customize

    var title: LocalizedStringResource {
        switch self {
        case .journal: "Journal"
        case .rituals: "Rituals"
        case .customize: "Customize"
        }
    }
}

/// The tab for what a person logs by hand: the day's journal, the rituals
/// they keep, and which entries the journal offers.
struct TrackPage: View {
    @Environment(AppRouter.self) private var router
    @Namespace private var zoom

    var body: some View {
        @Bindable var router = router

        NavigationStack {
            SomaPartSwitcher(selection: router.trackSection) { part in
                switch part {
                case .journal: TrackJournalView()
                case .rituals: TrackRitualsView()
                case .customize: TrackCustomizeView()
                }
            }
            .navigationDestination(for: PulseRoute.self) { route in
                route.page.zoomDestination(route)
            }
            .journeyDestinations()
            .tabPageChrome(title: "Track", section: $router.trackSection)
        }
        .environment(\.zoomNamespace, zoom)
#if DEBUG
        .onAppear {
            // `-track.section customize` opens a part directly, for screenshots.
            if let name = UserDefaults.standard.string(forKey: "track.section"),
               let section = TrackSection.allCases.first(where: { "\($0)" == name }) {
                router.trackSection = section
            }
        }
#endif
    }
}

#Preview("Track") {
    TrackPage()
        .environment(HealthDashboard())
        .environment(AppRouter())
        .environment(JournalStore(url: nil))
}
