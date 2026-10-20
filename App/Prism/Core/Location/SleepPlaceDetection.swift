//
//  SleepPlaceDetection.swift
//  Prism
//

import Foundation
import SomaUI

/// Somewhere the phone stayed, as Core Location reported it: where, how
/// sure, and when it came and went (nil when Core Location could not say).
nonisolated struct SleepVisit: Codable, Equatable, Sendable {
    var arrival: Date?
    var departure: Date?
    var latitude: Double
    var longitude: Double
    /// Metres.
    var accuracy: Double
}

/// Where one night was slept: found from the visits, or set by hand.
nonisolated struct SleepSpot: Codable, Equatable, Sendable {
    /// The day the night ended on, `yyyy-MM-dd`, as ``SleepPlaceStore`` keys it.
    var night: String
    var latitude: Double
    var longitude: Double
    /// Hours of the night spent there.
    var hours: Double
    /// Set by hand: the place's name as the person picked it.
    var name: String? = nil

    var isByHand: Bool { name != nil }
}

/// What the person said about a place: its name, or to forget it. Matched
/// to the nights around its spot, so it holds as new nights come in.
nonisolated struct SleepPlaceDecision: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var name: String?
    var isForgotten = false
}

/// One place slept in: the nights there, where they centre, and its name
/// when the person gave one.
nonisolated struct SleepPlaceCluster: Identifiable, Equatable, Sendable {
    var id: String
    var latitude: Double
    var longitude: Double
    /// The nights slept there, most recent first.
    var nights: [String]
    var hours: Double
    /// The person's name for it: from a decision, or the place set by hand.
    var name: String?
    /// The decision it answers to, if any.
    var decision: UUID?

    /// Named by the person, so nothing more to ask.
    var isConfirmed: Bool { name != nil }
}

/// The on device sums behind Sleep places: which visit each night was slept
/// at, which nights share a place, and the heat of all of them. Pure, so the
/// rules are tested without Core Location.
nonisolated enum SleepPlaceDetection {
    /// Nights closer than this (metres) are one place.
    static let placeRadius = 150.0
    /// Visits less sure than this (metres) are left out.
    static let usableAccuracy = 250.0
    /// A visit holds a night when it covers at least this share of it.
    static let nightShare = 0.5
    /// The heat map's cell, in metres: nights in one cell warm one spot.
    static let heatCell = 25.0
    /// Places further than this (metres) from the main one are left off
    /// its map, so the map stays close enough to read the street.
    static let nearby = 3_000.0

    static let metresPerDegree = 111_320.0

    /// Metres between two spots, flat Earth: right to well within a city.
    static func distance(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let north = (a.0 - b.0) * metresPerDegree
        let east = (a.1 - b.1) * metresPerDegree * cos((a.0 + b.0) / 2 * .pi / 180)
        return (north * north + east * east).squareRoot()
    }

    /// Each night's place: the visit that covers most of it, if it covers
    /// at least half. Keyed by the day the night ended on.
    static func attribute(visits: [SleepVisit], nights: [DateInterval], stamp: (Date) -> String) -> [String: SleepSpot] {
        var out: [String: SleepSpot] = [:]
        let usable = visits.filter { $0.accuracy >= 0 && $0.accuracy <= usableAccuracy }
        for night in nights where night.duration > 0 {
            var best: (visit: SleepVisit, overlap: TimeInterval)?
            for visit in usable {
                let start = max(night.start, visit.arrival ?? .distantPast)
                let end = min(night.end, visit.departure ?? .distantFuture)
                let overlap = end.timeIntervalSince(start)
                if overlap > (best?.overlap ?? 0) { best = (visit, overlap) }
            }
            guard let best, best.overlap >= night.duration * nightShare else { continue }
            let key = stamp(night.end)
            // Two sleeps ending the same day (a nap after a night): the
            // longer stay names the day.
            if let kept = out[key], kept.hours * 3_600 >= best.overlap { continue }
            out[key] = SleepSpot(night: key, latitude: best.visit.latitude, longitude: best.visit.longitude,
                                 hours: best.overlap / 3_600)
        }
        return out
    }

    /// The spots as places: nights near a decision belong to it (a
    /// forgotten one drops them), the rest gather round each other. Most
    /// nights first.
    static func clusters(spots: [SleepSpot], decisions: [SleepPlaceDecision]) -> [SleepPlaceCluster] {
        struct Group {
            var id: String
            var decision: SleepPlaceDecision?
            var spots: [SleepSpot] = []
            var anchor: (Double, Double)
        }
        var groups: [Group] = decisions.filter { !$0.isForgotten }.map {
            Group(id: $0.id.uuidString, decision: $0, anchor: ($0.latitude, $0.longitude))
        }
        let forgotten = decisions.filter(\.isForgotten)
        for spot in spots.sorted(by: { $0.night < $1.night }) {
            let here = (spot.latitude, spot.longitude)
            if forgotten.contains(where: { distance(($0.latitude, $0.longitude), here) <= placeRadius }) { continue }
            let nearest = groups.indices
                .map { ($0, distance(groups[$0].anchor, here)) }
                .filter { $0.1 <= placeRadius }
                .min { $0.1 < $1.1 }?.0
            if let nearest {
                groups[nearest].spots.append(spot)
                if groups[nearest].decision == nil { groups[nearest].anchor = centre(groups[nearest].spots) }
            } else {
                groups.append(Group(id: String(format: "new|%.4f,%.4f", spot.latitude, spot.longitude), spots: [spot], anchor: here))
            }
        }
        return groups.compactMap { group -> SleepPlaceCluster? in
            guard !group.spots.isEmpty else { return nil }
            let middle = centre(group.spots)
            return SleepPlaceCluster(
                id: group.id,
                latitude: middle.0, longitude: middle.1,
                nights: group.spots.map(\.night).sorted(by: >),
                hours: group.spots.reduce(0) { $0 + $1.hours },
                name: group.decision?.name ?? handName(group.spots),
                decision: group.decision?.id
            )
        }
        .sorted { ($0.nights.count, $0.nights.first ?? "") > ($1.nights.count, $1.nights.first ?? "") }
    }

    /// The heat: every spot's hours summed in cells of ``heatCell``, each
    /// cell at the hours weighted middle of its nights, the busiest at 1.
    static func heat(spots: [SleepSpot], cell: Double = heatCell) -> [SomaHeatPoint] {
        // Each cell's east west size is read at its own latitude band (a
        // tenth of a degree), so a spot lands in the same cell whatever
        // other spots it is summed with.
        var cells: [String: (hours: Double, latitude: Double, longitude: Double)] = [:]
        for spot in spots where spot.hours > 0 {
            let row = Int((spot.latitude * metresPerDegree / cell).rounded(.down))
            let band = (spot.latitude * 10).rounded() / 10
            let column = Int((spot.longitude * metresPerDegree * cos(band * .pi / 180) / cell).rounded(.down))
            let key = "\(row),\(column)"
            var sum = cells[key] ?? (0, 0, 0)
            sum.hours += spot.hours
            sum.latitude += spot.latitude * spot.hours
            sum.longitude += spot.longitude * spot.hours
            cells[key] = sum
        }
        let most = cells.values.map(\.hours).max() ?? 0
        guard most > 0 else { return [] }
        return cells.map { key, sum in
            SomaHeatPoint(id: key, latitude: sum.latitude / sum.hours, longitude: sum.longitude / sum.hours,
                          weight: sum.hours / most)
        }
        .sorted { $0.weight > $1.weight }
    }

    /// The spots near enough to `place` to share its map.
    static func near(_ place: SleepPlaceCluster, spots: [SleepSpot], within reach: Double = nearby) -> [SleepSpot] {
        spots.filter { distance((place.latitude, place.longitude), ($0.latitude, $0.longitude)) <= reach }
    }

    private static func centre(_ spots: [SleepSpot]) -> (Double, Double) {
        let hours = spots.reduce(0) { $0 + max($1.hours, 0.01) }
        let latitude = spots.reduce(0) { $0 + $1.latitude * max($1.hours, 0.01) } / hours
        let longitude = spots.reduce(0) { $0 + $1.longitude * max($1.hours, 0.01) } / hours
        return (latitude, longitude)
    }

    /// The name set by hand most often among a place's nights.
    private static func handName(_ spots: [SleepSpot]) -> String? {
        let counts = Dictionary(grouping: spots.compactMap(\.name), by: { $0 }).mapValues(\.count)
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }
}
