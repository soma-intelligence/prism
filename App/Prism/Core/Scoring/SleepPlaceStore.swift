//
//  SleepPlaceStore.swift
//  Prism
//

import Foundation
import Observation

/// Where each night was slept, the bedroom as the person describes it, and
/// the city the Weather page shows.
///
/// Soma reads no location of its own, so every place here was set by hand,
/// and a place set by hand is never replaced. Kept on the device as one JSON
/// file in Application Support, beside the Journal.
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

    private let url: URL?
    private let calendar: Calendar

    static let shared = SleepPlaceStore()

    /// - Parameter url: nil keeps it in memory only, for previews and tests.
    init(url: URL? = SleepPlaceStore.defaultURL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            nights = stored.nights
            bedroom = stored.bedroom
            weatherCity = stored.weatherCity
        } else {
            nights = [:]
            bedroom = Bedroom()
            weatherCity = nil
        }
    }

    nonisolated static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "sleep-places.json")
    }

    func place(forNightEnding date: Date) -> Place? {
        nights[stamp(date)]
    }

    func setPlace(_ place: Place?, forNightEnding date: Date) {
        nights[stamp(date)] = place
        save()
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
        guard let url else { return }
        let stored = Stored(nights: nights, bedroom: bedroom, weatherCity: weatherCity)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: SomaFileStorage.protectedAtomicOptions)
        } catch {
            // Kept in memory; the next change tries the write again.
        }
    }
}
