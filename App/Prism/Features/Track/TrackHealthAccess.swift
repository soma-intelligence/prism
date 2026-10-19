//
//  TrackHealthAccess.swift
//  Prism
//

import Foundation
import HealthExportCore
#if canImport(HealthKit)
import HealthKit
#endif

/// What the "From Apple Health, as it comes" rows say about each source.
///
/// Health never tells an app whether a read was allowed: a refusal looks the
/// same as an empty store, on purpose. So a row says "On" only when data has
/// actually arrived, "Not asked" when Health reports the question was never
/// put, and "In Health" otherwise, which is where the answer lives.
struct TrackHealthAccess: Equatable, Sendable {
    var stateOfMind = Status.inHealth
    var mindful = Status.inHealth
    var medications = Status.inHealth

    enum Status: Equatable, Sendable {
        case on
        case notAsked
        case inHealth

        var text: String {
            switch self {
            case .on: "On"
            case .notAsked: "Not asked"
            case .inHealth: "In Health"
            }
        }
    }

    /// Reads the statuses. `source` is nil where Health is unavailable or
    /// swapped out for the empty store, and then every row says "In Health".
    static func read(from source: (any HealthSampleSource)?, now: Date, calendar: Calendar) async -> TrackHealthAccess {
        var access = TrackHealthAccess()
        guard let source else { return access }

        if let mindful = HealthMetricCatalog.metric(for: TrackInputs.Metric.mindful) {
            let start = calendar.date(byAdding: .day, value: -60, to: now) ?? now
            let found = (try? await source.samples(mindful, from: start, to: now, limit: 1)) ?? []
            if !found.isEmpty { access.mindful = .on }
        }

#if canImport(HealthKit)
        if HKHealthStore.isHealthDataAvailable() {
            let store = HKHealthStore()
            if let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [HKObjectType.stateOfMindType()]),
               status == .shouldRequest {
                access.stateOfMind = .notAsked
            }
            if access.mindful != .on,
               let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [HKCategoryType(.mindfulSession)]),
               status == .shouldRequest {
                access.mindful = .notAsked
            }
        }
#endif
        return access
    }
}
