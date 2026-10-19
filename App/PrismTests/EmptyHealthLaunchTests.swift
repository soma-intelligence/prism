//
//  EmptyHealthLaunchTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import HealthExportHealthKit
@testable import Prism

/// `-health.empty YES` is how a UI test keeps Health's permission sheet off
/// the app: Apple Health is swapped for a store that asks nothing and holds
/// nothing, and every page comes up ready with a dash for each value.
@Suite("Empty Health launch")
@MainActor
struct EmptyHealthLaunchTests {

    /// Runs `body` against a defaults domain of its own, removed afterwards,
    /// so nothing here reaches the app's own settings or the next run.
    private func withDefaults<T>(empty: Bool?, _ body: (UserDefaults) throws -> T) throws -> T {
        let name = "PrismTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        if let empty { defaults.set(empty, forKey: HealthDashboard.emptyLaunchKey) }
        return try body(defaults)
    }

    @Test("Launched with the argument, the app reads the empty store")
    func argumentSwapsTheSource() throws {
        let source = try withDefaults(empty: true) { HealthDashboard.launchSource(defaults: $0) }
        #expect(source is EmptyHealthSource)
    }

    @Test("Launched without it, or with NO, the app reads Apple Health")
    func withoutTheArgumentHealthKitStays() throws {
        let absent = try withDefaults(empty: nil) { HealthDashboard.launchSource(defaults: $0) }
        let refused = try withDefaults(empty: false) { HealthDashboard.launchSource(defaults: $0) }
        #expect(absent is HealthKitSampleSource)
        #expect(refused is HealthKitSampleSource)
    }

    @Test("The pages come up ready, with a dash for every value")
    func pagesComeUpReadyAndEmpty() async {
        let dashboard = HealthDashboard(source: EmptyHealthSource())

        await dashboard.start()

        #expect(dashboard.status == .ready)
        for metric in HealthDashboard.displayed {
            #expect(dashboard.value(metric.identifier) == nil)
            #expect(dashboard.minutes(metric.identifier) == nil)
            #expect(dashboard.rowValue(for: metric) == "-")
        }
    }
}
