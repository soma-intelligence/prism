//
//  WidgetRefreshTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

#if os(iOS)
@MainActor
struct WidgetRefreshTests {
    @Test func permittedIdentifierDeclared() {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(ids?.contains(WidgetRefresh.taskID) == true)
    }

    @Test func refreshWithoutAccessDoesNothing() async {
        WidgetRefresh.detach()
        UserDefaults.standard.removeObject(forKey: WidgetRefresh.grantedKey)
        #expect(await WidgetRefresh.refresh() == false)
    }

    /// A wake while the phone is locked reads nothing: Health and the Track
    /// log are closed, and a read then would publish (and save) empty values.
    @Test func lockedWakeReadsNothing() async {
        let saved = WidgetRefresh.isProtectedDataAvailable
        WidgetRefresh.isProtectedDataAvailable = { false }
        defer {
            WidgetRefresh.isProtectedDataAvailable = saved
            WidgetRefresh.detach()
        }
        WidgetRefresh.attach(health: HealthDashboard(source: EmptyHealthSource()))
        #expect(await WidgetRefresh.refresh() == false)
    }

    /// A cold launch hands the app's own dashboard over before any Health
    /// wake can run, so a wake reuses it instead of building a second one.
    @Test func adoptedDashboardServesTheWake() async {
        WidgetRefresh.detach()
        UserDefaults.standard.removeObject(forKey: WidgetRefresh.grantedKey)
        defer { WidgetRefresh.detach() }
        let dashboard = HealthDashboard(source: EmptyHealthSource())
        WidgetRefresh.adopt(health: dashboard)
        #expect(WidgetRefresh.attached === dashboard)
        // Adopting never replaces a dashboard already attached.
        WidgetRefresh.adopt(health: HealthDashboard(source: EmptyHealthSource()))
        #expect(WidgetRefresh.attached === dashboard)
        #expect(await WidgetRefresh.refresh())
    }

    @Test func nextRunIsAnHourOut() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(WidgetRefresh.earliestBegin(now: now) == now.addingTimeInterval(3600))
    }
}
#endif
