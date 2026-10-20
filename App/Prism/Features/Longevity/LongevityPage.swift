//
//  LongevityPage.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// The lenses of the Longevity tab.
enum LongevitySection: PageSection {
    case body
    case mind
    case environment

    var title: LocalizedStringResource {
        switch self {
        case .body: "Body"
        case .mind: "Mind"
        case .environment: "Environment"
        }
    }
}

/// Months and years rather than the day: the body, the mind and what surrounds
/// you, each read over the long run.
///
/// The day lives on Pulse and what you log lives on Track. This tab holds the
/// slow readings: what your wearables read, the lab results you add, and
/// the environment, which carries no score because it describes what
/// surrounds you rather than you.
struct LongevityPage: View {
    @Environment(HealthDashboard.self) private var health
    @Environment(AppRouter.self) private var router
    @Namespace private var zoom

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.longevityPath) {
            SomaPartSwitcher(selection: router.longevitySection) { part in
                switch part {
                case .body: LongevityBodyView()
                case .mind: LongevityMindView()
                case .environment: LongevityEnvironmentView()
                }
            }
            .navigationDestination(for: LongevityRoute.self) { route in
                Group {
                    switch route {
                    case .cardio: BodyCardioPage()
                    case .strength: BodyStrengthPage()
                    }
                }
                .zoomDestination(route)
            }
            .navigationDestination(for: PulseRoute.self) { route in
                route.page.zoomDestination(route)
            }
            .journeyDestinations()
            .tabPageChrome(title: "Longevity", section: $router.longevitySection)
        }
        .environment(\.zoomNamespace, zoom)
        .task { await health.start() }
#if DEBUG
        .onAppear {
            // `-longevity.section mind` opens a lens directly, for screenshots.
            if let name = UserDefaults.standard.string(forKey: "longevity.section"),
               let section = LongevitySection.allCases.first(where: { "\($0)" == name }) {
                router.longevitySection = section
            }
            // `-longevity.metric HKQuantityTypeIdentifierStepCount` (or a score's
            // identifier) opens a metric's page over the lens, for screenshots.
            if let identifier = UserDefaults.standard.string(forKey: "longevity.metric"), router.longevityPath.isEmpty {
                if let metric = HealthMetricCatalog.metric(for: identifier) {
                    router.longevityPath.append(VaultRoute.dataType(BodyDataType(metric)))
                } else if let score = ScoreMetric.allCases.first(where: { $0.identifier == identifier }) {
                    router.longevityPath.append(VaultRoute.score(score))
                }
            }
        }
#endif
    }
}

#Preview("Longevity") {
    LongevityPage()
        .environment(HealthDashboard())
        .environment(AppRouter())
        .environment(JournalStore(url: nil))
}
