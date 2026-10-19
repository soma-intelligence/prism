//
//  EmptyHealthSource.swift
//  Prism
//

import Foundation
import HealthExportCore
import HealthExportHealthKit

/// A Health store that holds nothing and asks nothing.
///
/// What the app reads when it is launched with `-health.empty YES`, which the
/// UI tests pass. On a simulator that has never answered it, Health's
/// permission sheet covers the app, and on iOS 27 that sheet belongs to
/// Health's own view service: XCUITest cannot reach its buttons, and it does
/// not swipe away. Every test that taps something would fail on a fresh
/// simulator, in CI, and on xcodebuild's parallel clones. A source that never
/// asks never puts the sheet up.
///
/// It reports itself available and hands back nothing, so the pages come up
/// ready with a dash in every value, as they do over the Simulator's empty
/// store. Unavailable would draw the state meant for a Mac instead, which is
/// not the page a test sets out to drive.
struct EmptyHealthSource: HealthSampleSource {
    var isAvailable: Bool { true }

    /// Asks nothing: no sheet, and nothing added to what the app has asked
    /// Health for.
    func requestAuthorization(for metrics: [HealthMetric]) async throws {}

    func latest(_ metric: HealthMetric) async throws -> HealthReading? { nil }

    func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }

    func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? { nil }

    func samples(_ metric: HealthMetric, from: Date, to: Date, limit: Int) async throws -> [HealthReading] { [] }
}

extension HealthDashboard {
    /// The defaults key behind `-health.empty YES`.
    static let emptyLaunchKey = "health.empty"

    /// What the app's one dashboard reads: Apple Health, or the empty store
    /// when the app was launched with `-health.empty YES`.
    ///
    /// A launch argument lands in the argument domain of `UserDefaults`, which
    /// is read ahead of the app's own and never written back, so the switch
    /// holds for that launch alone. Nothing in the app sets the key.
    static func launchSource(defaults: UserDefaults = .standard) -> any HealthSampleSource {
#if DEBUG && targetEnvironment(simulator)
        // A made up year of every metric, for looking at the pages on a
        // simulator: `-health.fixture YES`. Never compiled for a device, so
        // invented readings cannot reach a real phone.
        if defaults.bool(forKey: FixtureHealthSource.launchKey) { return FixtureHealthSource() }
#endif
        return defaults.bool(forKey: emptyLaunchKey) ? EmptyHealthSource() : HealthKitSampleSource()
    }
}
