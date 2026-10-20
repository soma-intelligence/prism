//
//  BodyLensRead.swift
//  Prism
//

import Foundation
import HealthExportCore

/// Everything the Body lens draws from Health: the three numbers at its head
/// and every reading's tile or row.
struct BodyLensRead: Sendable {
    var inputs: BodyOverviewInputs
    var markers: [BodyBiomarkerSpec: BodyBiomarker]
}

/// The Body lens's last read, kept a minute as ``HealthDashboard/start()``
/// keeps its own: the lens's `.task` runs again on every lens and tab switch,
/// and reading ninety days of two dozen readings each time holds the page
/// that has just appeared behind the store. A pull to refresh reads afresh.
@MainActor
final class BodyLensCache {
    static let shared = BodyLensCache()
    /// How long a read stands.
    static let lifetime: TimeInterval = 60

    private var stored: (dashboard: ObjectIdentifier, read: BodyLensRead, at: Date)?

    /// The last read, while it stands, for a first frame that already has
    /// its numbers.
    func fresh(for health: HealthDashboard, now: Date = .now) -> BodyLensRead? {
        guard let stored, stored.dashboard == ObjectIdentifier(health),
              now.timeIntervalSince(stored.at) < Self.lifetime else { return nil }
        return stored.read
    }

    /// The read: the kept one while it stands, else a new one. Nil when
    /// Health is unavailable or the person refused it.
    func read(health: HealthDashboard, force: Bool = false, now: Date = .now,
              calendar: Calendar = .current) async -> BodyLensRead? {
        if !force, let kept = fresh(for: health, now: now) { return kept }
        guard let source = await health.prepare(BodyOverviewInputs.metrics + BodyBiomarkers.metrics) else { return nil }
        async let overview = BodyOverviewInputs.read(from: source, now: now, calendar: calendar)
        async let readings = BodyBiomarkers.read(from: source, now: now, calendar: calendar)
        let inputs = await overview
        let all = await readings
        var markers: [BodyBiomarkerSpec: BodyBiomarker] = [:]
        for spec in BodyBiomarkerSpec.allCases {
            markers[spec] = BodyBiomarkers.make(spec, readings: all[spec] ?? [], now: now, calendar: calendar)
        }
        let read = BodyLensRead(inputs: inputs, markers: markers)
        stored = (ObjectIdentifier(health), read, now)
        return read
    }
}
