//
//  SleepPlaceFinder.swift
//  Prism
//

import Foundation
import Observation
import SomaUI
#if os(iOS) || os(visionOS)
import UIKit
#endif

/// Finds where each night was slept, on the device: the visits Core Location
/// reports (``SleepVisitMonitor``, with Location set to Always) matched to
/// the nights Apple Health holds, together with the nights set by hand in
/// ``SleepPlaceStore``. Gathers them into places, keeps what the person said
/// about each (a name, or forget it) and draws their heat.
///
/// Everything stays in one file in Application Support, encrypted until the
/// first unlock after a restart (a visit wakes the app while the phone is
/// locked, so the file has to read then): sixty days of visits, the nights found from them, and
/// the decisions. Nothing here leaves the device or goes into the export.
/// A place's heat: every warm spot near it, and its own, which the map
/// frames.
struct SleepPlaceHeat: Equatable {
    var points: [SomaHeatPoint] = []
    var framing: [SomaHeatPoint] = []
}

@MainActor
@Observable
final class SleepPlaceFinder {
    private struct Stored: Codable {
        var visits: [SleepVisit] = []
        var found: [String: SleepSpot] = [:]
        var decisions: [SleepPlaceDecision] = []
    }

    /// How long visits and found nights are kept.
    static let keptDays = 60

    private(set) var visits: [SleepVisit]
    /// Nights found from the visits, keyed by the day each ended on.
    private(set) var found: [String: SleepSpot]
    private(set) var decisions: [SleepPlaceDecision]

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let manual: SleepPlaceStore
    @ObservationIgnored private let calendar: Calendar
    /// The file is there but did not read (protected data before the first
    /// unlock): nothing is saved over it, new visits wait in memory, and the
    /// file is read again and merged once it opens.
    @ObservationIgnored private(set) var isHoldingUnread = false
    @ObservationIgnored private var readableObserver: (any NSObjectProtocol)?

    static let shared = SleepPlaceFinder()

    /// - Parameter url: nil keeps it in memory only, for previews and tests.
    init(url: URL? = SleepPlaceFinder.defaultURL, manual: SleepPlaceStore = .shared, calendar: Calendar = .current) {
        self.url = url
        self.manual = manual
        self.calendar = calendar
        var stored: Stored?
        var unread = false
        switch SomaFileStorage.read(Stored.self, at: url) {
        case .loaded(let value):
            stored = value
            SomaFileStorage.allowBackgroundReads(at: url)
        case .unreadable: unread = true
        case .missing: break
        }
        visits = stored?.visits ?? []
        found = stored?.found ?? [:]
        decisions = stored?.decisions ?? []
#if DEBUG
        if url != nil, !unread, Self.usesFixture, visits.isEmpty { visits = Self.fixtureVisits(now: Date(), calendar: calendar) }
#endif
        if unread { holdUntilReadable() }
        publish()
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "sleep-visits.json")
    }

    // MARK: What it shows

    /// Every night with a place: set by hand first, else found.
    var spots: [SleepSpot] {
        var out = found
        for (night, place) in manual.nights {
            out[night] = SleepSpot(night: night, latitude: place.latitude, longitude: place.longitude,
                                   hours: found[night]?.hours ?? 8, name: place.name)
        }
        return Array(out.values)
    }

    /// The places, most nights first.
    var places: [SleepPlaceCluster] {
        SleepPlaceDetection.clusters(spots: spots, decisions: decisions)
    }

    /// The first place slept in more than once that has no name yet.
    var pending: SleepPlaceCluster? {
        places.first { !$0.isConfirmed && $0.nights.count >= 2 }
    }

    /// The heat round `place` (the main place when nil): its nights and the
    /// nights near enough to share its map, framed on the place itself.
    func heat(around place: SleepPlaceCluster? = nil) -> SleepPlaceHeat {
        let spots = spots
        guard let place = place ?? places.first else { return SleepPlaceHeat() }
        let points = SleepPlaceDetection.heat(spots: SleepPlaceDetection.near(place, spots: spots))
        let own = Set(SleepPlaceDetection.heat(spots: SleepPlaceDetection.near(place, spots: spots,
                                                                                within: SleepPlaceDetection.placeRadius)).map(\.id))
        return SleepPlaceHeat(points: points, framing: points.filter { own.contains($0.id) })
    }

    // MARK: Changes

    /// A visit from Core Location, or one made up for the simulator.
    func record(_ visit: SleepVisit) {
        merge(visit)
        prune(now: Date())
        save()
    }

    /// Adds a visit, or completes the same stay seen before.
    private func merge(_ visit: SleepVisit) {
        if let index = visits.firstIndex(where: {
            $0.arrival == visit.arrival && SleepPlaceDetection.distance(($0.latitude, $0.longitude), (visit.latitude, visit.longitude)) < 1
        }) {
            // The same stay again, now with its departure.
            visits[index] = visit
        } else {
            visits.append(visit)
        }
    }

    /// Matches the visits to the nights Health holds, oldest first.
    func refresh(nights: [DateInterval], now: Date = Date()) {
        let read = SleepPlaceDetection.attribute(visits: visits, nights: nights, stamp: manual.stamp)
        // A night found before keeps its place when its visits have aged out.
        found.merge(read) { _, new in new }
        prune(now: now)
        save()
        publish()
    }

    /// Names a place (and so confirms it): "Home" or the person's own word.
    func name(_ place: SleepPlaceCluster, _ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let id = place.decision, let index = decisions.firstIndex(where: { $0.id == id }) {
            decisions[index].name = name
        } else {
            decisions.append(SleepPlaceDecision(id: UUID(), latitude: place.latitude, longitude: place.longitude, name: name))
        }
        save()
        publish()
    }

    /// Forgets a place: its visits, the nights found there and the nights
    /// set there by hand go. Only its spot is kept, so it is not found again.
    func forget(_ place: SleepPlaceCluster) {
        let here = (place.latitude, place.longitude)
        let near: (Double, Double) -> Bool = {
            SleepPlaceDetection.distance(here, ($0, $1)) <= SleepPlaceDetection.placeRadius
        }
        visits.removeAll { near($0.latitude, $0.longitude) }
        found = found.filter { !near($0.value.latitude, $0.value.longitude) }
        for night in place.nights where manual.nights[night].map({ near($0.latitude, $0.longitude) }) == true {
            manual.setPlace(nil, stamp: night)
        }
        decisions.removeAll { $0.id == place.decision }
        decisions.append(SleepPlaceDecision(id: UUID(), latitude: place.latitude, longitude: place.longitude, isForgotten: true))
        save()
        publish()
    }

    /// Forgets everything, file and all, for "Delete my data": the visits,
    /// the nights found from them and every decision, forgotten spots
    /// included.
    func erase() {
        visits = []
        found = [:]
        decisions = []
        if let url { try? FileManager.default.removeItem(at: url) }
        isHoldingUnread = false
        publish()
    }

    /// Hands the named nights found here to ``SleepPlaceStore``, so the
    /// bedroom card and last night's weather read them like nights set by
    /// hand.
    private func publish() {
        var named: [String: SleepPlaceStore.Place] = [:]
        for place in places {
            guard let name = place.name else { continue }
            for night in place.nights where found[night] != nil {
                named[night] = SleepPlaceStore.Place(name: name, latitude: place.latitude, longitude: place.longitude)
            }
        }
        manual.detected = named
    }

    private func prune(now: Date) {
        guard let edge = calendar.date(byAdding: .day, value: -Self.keptDays, to: now) else { return }
        visits.removeAll { ($0.departure ?? $0.arrival ?? now) < edge }
        let oldest = manual.stamp(edge)
        found = found.filter { $0.key >= oldest }
    }

    // MARK: A file that did not read

    /// Blocks saving, and reads again once protected data opens.
    private func holdUntilReadable() {
        isHoldingUnread = true
#if os(iOS) || os(visionOS)
        guard readableObserver == nil else { return }
        readableObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfUnread() }
        }
#endif
    }

    /// After a failed read, reads the file again. On success what it holds
    /// loads, the visits and decisions made meanwhile are laid on top, and
    /// saving resumes.
    func reloadIfUnread() {
        guard isHoldingUnread else { return }
        let stored: Stored
        switch SomaFileStorage.read(Stored.self, at: url) {
        case .unreadable: return
        case .missing: stored = Stored()
        case .loaded(let value): stored = value
        }
        let pending = (visits: visits, found: found, decisions: decisions)
        visits = stored.visits
        found = stored.found
        decisions = stored.decisions
        for visit in pending.visits { merge(visit) }
        found.merge(pending.found) { _, new in new }
        let known = Set(decisions.map(\.id))
        decisions += pending.decisions.filter { !known.contains($0.id) }
        isHoldingUnread = false
        if let readableObserver { NotificationCenter.default.removeObserver(readableObserver) }
        readableObserver = nil
        prune(now: Date())
        save()
        publish()
    }

    private func save() {
        guard let url, !isHoldingUnread else { return }
        let stored = Stored(visits: visits, found: found, decisions: decisions)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.backgroundReadableAtomicOptions)
        } catch {
            // Kept in memory; the next change tries the write again.
        }
    }

#if DEBUG
    /// `-sleepPlaces.fixture YES`: thirty evenings of made up visits round
    /// the simulator's spot, since the simulator reports no visits. Most
    /// nights at one flat, a few at a friend's a kilometre and a half away.
    static var usesFixture: Bool { UserDefaults.standard.bool(forKey: "sleepPlaces.fixture") }

    static func fixtureVisits(now: Date, calendar: Calendar) -> [SleepVisit] {
        let today = calendar.startOfDay(for: now)
        return (1...30).compactMap { back -> SleepVisit? in
            guard let evening = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let away = back % 9 == 4 || back % 9 == 5
            let wobble = Double((back * 37) % 11 - 5) * 0.000_02
            return SleepVisit(arrival: evening.addingTimeInterval(19.5 * 3_600),
                              departure: evening.addingTimeInterval(32.5 * 3_600),
                              latitude: (away ? 37.4502 : 37.4443) + wobble,
                              longitude: (away ? -122.1462 : -122.1598) - wobble,
                              accuracy: 35)
        }
    }
#endif
}
