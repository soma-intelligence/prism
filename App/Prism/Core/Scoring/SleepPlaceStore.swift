//
//  SleepPlaceStore.swift
//  Prism
//

import Foundation
import Observation
#if os(iOS) || os(visionOS)
import UIKit
#endif

/// Where each night was slept, the bedroom as the person describes it, and
/// the city the Weather page shows.
///
/// The places saved here were set by hand, from a search or from where the
/// device was when it was set, at that exact spot, and a place set by hand is
/// never replaced. Nights ``SleepPlaceFinder`` found at a place the person
/// named stand in where no place was set by hand (``detected``, held in
/// memory, never saved here). Kept on the device as one JSON file in
/// Application Support, beside the Journal, readable once the phone has been
/// unlocked after a restart, since a sleep visit reads it from a locked
/// phone.
@MainActor
@Observable
final class SleepPlaceStore {
    /// A named place: a city from the search, with where it is.
    struct Place: Codable, Hashable, Identifiable, Sendable {
        var id: String { name + "|" + String(format: "%.3f,%.3f", latitude, longitude) }
        var name: String
        var latitude: Double
        var longitude: Double
    }

    /// The bedroom as the person describes it. Nil fields were never set.
    struct Bedroom: Codable, Equatable, Sendable {
        /// Degrees Celsius.
        var temperature: Double?
        var isDark: Bool?
    }

    private struct Stored: Codable {
        var nights: [String: Place] = [:]
        var bedroom = Bedroom()
        var weatherCity: Place?
    }

    /// Keyed by the stamp of the day the night ended on, `yyyy-MM-dd`.
    private(set) var nights: [String: Place]
    var bedroom: Bedroom { didSet { save() } }
    var weatherCity: Place? { didSet { save() } }
    /// Nights found at a named place, by the same day stamps; set by
    /// ``SleepPlaceFinder``, never saved here.
    var detected: [String: Place] = [:]

    private let url: URL?
    private let calendar: Calendar
    /// The file is there but did not read (protected data before the first
    /// unlock): nothing is saved over it until it reads and merges.
    @ObservationIgnored private(set) var isHoldingUnread = false
    @ObservationIgnored private var readableObserver: (any NSObjectProtocol)?
    /// True while the initializer fills the settings, whose observers would
    /// otherwise write the file straight back (or, after a failed read,
    /// write an empty state over it).
    @ObservationIgnored private var isStarting = true

    static let shared = SleepPlaceStore()

    /// - Parameter url: nil keeps it in memory only, for previews and tests.
    init(url: URL? = SleepPlaceStore.defaultURL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        let read = SomaFileStorage.read(Stored.self, at: url)
        if case .loaded(let stored) = read {
            nights = stored.nights
            bedroom = stored.bedroom
            weatherCity = stored.weatherCity
        } else {
            nights = [:]
            bedroom = Bedroom()
            weatherCity = nil
        }
        isStarting = false
        if case .unreadable = read { holdUntilReadable() }
        if case .loaded = read { SomaFileStorage.allowBackgroundReads(at: url) }
    }

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

    /// After a failed read, reads the file again. On success it loads, what
    /// was set meanwhile wins, and saving resumes.
    func reloadIfUnread() {
        guard isHoldingUnread else { return }
        let stored: Stored
        switch SomaFileStorage.read(Stored.self, at: url) {
        case .unreadable: return
        case .missing: stored = Stored()
        case .loaded(let value): stored = value
        }
        // Still holding, so the settings' own saves wait for the one below.
        let pending = (nights: nights, bedroom: bedroom, weatherCity: weatherCity)
        nights = stored.nights.merging(pending.nights) { _, new in new }
        bedroom = Bedroom(temperature: pending.bedroom.temperature ?? stored.bedroom.temperature,
                          isDark: pending.bedroom.isDark ?? stored.bedroom.isDark)
        weatherCity = pending.weatherCity ?? stored.weatherCity
        isHoldingUnread = false
        if let readableObserver { NotificationCenter.default.removeObserver(readableObserver) }
        readableObserver = nil
        save()
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "sleep-places.json")
    }

    /// The place set by hand for the night, else the one found.
    func place(forNightEnding date: Date) -> Place? {
        let key = stamp(date)
        return nights[key] ?? detected[key]
    }

    func isSetByHand(forNightEnding date: Date) -> Bool {
        nights[stamp(date)] != nil
    }

    func setPlace(_ place: Place?, forNightEnding date: Date) {
        setPlace(place, stamp: stamp(date))
    }

    func setPlace(_ place: Place?, stamp: String) {
        nights[stamp] = place
        save()
    }

    /// Forgets every night, the bedroom and the Weather city, file and all,
    /// for "Delete my data".
    func erase() {
        nights = [:]
        detected = [:]
        bedroom = Bedroom()
        weatherCity = nil
        // The two settings above wrote the file again on their way out.
        if let url { try? FileManager.default.removeItem(at: url) }
        isHoldingUnread = false
    }

    /// The places slept in, most recent first, each once.
    var recentPlaces: [Place] {
        var seen: Set<Place> = []
        return nights.sorted { $0.key > $1.key }.map(\.value).filter { seen.insert($0).inserted }
    }

    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func save() {
        guard let url, !isHoldingUnread, !isStarting else { return }
        let stored = Stored(nights: nights, bedroom: bedroom, weatherCity: weatherCity)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.backgroundReadableAtomicOptions)
        } catch {
            // Kept in memory; the next change tries the write again.
        }
    }
}
