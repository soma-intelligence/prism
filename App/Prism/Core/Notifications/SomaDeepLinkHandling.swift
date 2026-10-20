//
//  SomaDeepLinkHandling.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

extension View {
    /// Where every deep link lands, and what keeps the notifications current:
    /// applied once, on the shell.
    func somaDeepLinks() -> some View {
        modifier(SomaDeepLinkHandling())
    }
}

/// Takes ``SomaDeepLinkRouter/pending`` and opens it: the tab it belongs to,
/// then the sheet that shows it. Also installs the notification delegate,
/// takes in what was delivered while Soma was closed, and re-plans the
/// reminders each time the app comes forward and each time Today is read.
private struct SomaDeepLinkHandling: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(HealthDashboard.self) private var health
    @Environment(\.scenePhase) private var phase
    @State private var links = SomaDeepLinkRouter.shared
    @State private var notifications = SomaNotifications.shared
    @State private var sheet: LinkSheet?
    @State private var homeSheet: HomeSheetRoute?

    /// A sheet a link opens over the shell.
    private enum LinkSheet: Identifiable {
        case sleep
        case vault(HealthMetric)
        case inbox
        case score(ScoreRoute)
        case fuel
        case track(TrackRoute)

        var id: String {
            switch self {
            case .sleep: "sleep"
            case .vault(let metric): "vault.\(metric.identifier)"
            case .inbox: "inbox"
            case .score(let route): "score.\(route)"
            case .fuel: "fuel"
            case .track(let route): "track.\(route)"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: links.pending, initial: true) { _, link in
                guard let link else { return }
                links.pending = nil
                open(link)
            }
            .onOpenURL { url in
                if let link = SomaDeepLink(url: url) { open(link) }
            }
            .task {
                SomaNotificationRouter.install()
                await notifications.syncDelivered()
                await notifications.apply()
            }
            .onChange(of: phase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await notifications.syncDelivered()
                    await notifications.apply()
                }
            }
            .onChange(of: health.today) { _, today in
                Task { await notifications.observe(today) }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .sleep:
                    NavigationStack { ScoreRoute.lastNight.page.journeyDestinations() }
                case .vault(let metric):
                    NavigationStack { VaultRoute.dataType(BodyDataType(metric)).page.journeyDestinations() }
                case .inbox:
                    NotificationCenterSheet()
                case .score(let route):
                    NavigationStack { route.page.journeyDestinations() }
                case .fuel:
                    NavigationStack { HomeRoute.nutrition.page.journeyDestinations() }
                case .track(let route):
                    NavigationStack { route.page.journeyDestinations() }
                        .environment(\.trackInSheet, true)
                }
            }
            .homeSheets($homeSheet)
    }

    private func open(_ link: SomaDeepLink) {
        switch link {
        case .checkIn:
            router.selection = "pulse"
            router.pulseSection = .today
            // The new check-in when it has something to ask, the quick one
            // otherwise: a reminder never opens onto nothing.
            if !CheckInPresenter.shared.present() { homeSheet = .checkIn }
        case .sleep:
            router.selection = "pulse"
            sheet = .sleep
        case .vaultMetric(let identifier):
            if let metric = HealthMetricCatalog.metric(for: identifier) { sheet = .vault(metric) }
        case .trends:
            router.selection = "pulse"
            router.pulseSection = .trends
        case .today:
            router.selection = "pulse"
            router.pulseSection = .today
        case .inbox:
            sheet = .inbox
        case .score(let kind):
            // The score pages are pushed on a tab's own stack, which the shell
            // does not hold a path for, so a widget tap opens the page in a
            // sheet with its own stack, like the Sleep link does.
            let route: ScoreRoute? = switch kind {
            case "sleep": .sleep
            case "recovery": .recovery
            case "strain": .strain
            case "stress": .stress
            default: nil
            }
            router.selection = "pulse"
            if let route { sheet = .score(route) }
        case .vitals:
            router.selection = "pulse"
            router.pulseSection = .today
        case .fuel:
            router.selection = "pulse"
            sheet = .fuel
        case .journal:
            router.selection = "track"
            router.trackSection = .journal
        case .trackMood:
            router.selection = "track"
            sheet = .track(.mood)
        case .trackMeal:
            router.selection = "track"
            sheet = .track(.food)
        case .captureStart:
            break
        }
    }
}
