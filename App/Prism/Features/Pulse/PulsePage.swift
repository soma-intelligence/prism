//
//  PulsePage.swift
//  Prism
//

import SwiftUI
import SomaUI

/// The parts of the Pulse tab.
enum PulseSection: PageSection {
    case today
    case trends
    case explore

    var title: LocalizedStringResource {
        switch self {
        case .today: "Today"
        case .trends: "Trends"
        case .explore: "Explore"
        }
    }
}

/// The home tab: how you are today, how that moves over time, and what there is
/// to read about it.
struct PulsePage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(AppRouter.self) private var router
    @Namespace private var zoom

    var body: some View {
        @Bindable var router = router

        NavigationStack {
            SomaPartSwitcher(selection: router.pulseSection) { part in
                switch part {
                case .today: PulseTodayView()
                case .trends: PulseTrendsView()
                case .explore: PulseExploreView()
                }
            }
            .navigationDestination(for: PulseRoute.self) { route in
                route.page.zoomDestination(route)
            }
            .journeyDestinations()
            .tabPageChrome(title: "Pulse", section: $router.pulseSection)
        }
        .environment(\.zoomNamespace, zoom)
        .task { await health.start() }
#if DEBUG
        .onAppear {
            // `-pulse.section trends` opens a part directly, for screenshots.
            if let name = UserDefaults.standard.string(forKey: "pulse.section"),
               let section = PulseSection.allCases.first(where: { "\($0)" == name }) {
                router.pulseSection = section
            }
        }
#endif
    }
}

#Preview("Pulse") {
    PulsePage()
        .environment(HealthDashboard())
        .environment(AppRouter())
        .environment(JournalStore(url: nil))
}
