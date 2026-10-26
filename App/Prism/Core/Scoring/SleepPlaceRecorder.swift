//
//  SleepPlaceRecorder.swift
//  Prism
//

import Foundation
import CoreLocation
import MapKit
import Observation
import SwiftUI
import HealthScoring

/// Notes where the phone spent the night, down to the street, so sleep can be
/// compared place by place without anyone typing a place in.
///
/// Off until the person turns it on. Two ways in, depending on the Location
/// answer:
///
/// - Always: the system's visit monitoring. iOS reports each stay with its
///   arrival and departure, and relaunches the app for it when Soma is closed,
///   so a stay that held the night is that night's place even if Soma is never
///   opened. Visits cost almost no battery: the system already tracks them.
/// - While in use: one precise fix when Soma comes forward in the morning,
///   given to the night that just ended. Opening the app in bed is the common
///   case, and that is where the phone slept.
///
/// The coordinates are kept as the fix gave them, never rounded: precise is
/// the point here, unlike the Environment lens. A fix within a short walk of a
/// place already detected takes that place, so one home stays one place rather
/// than a cloud of addresses a few metres apart. A night set by hand is never
/// touched (``SleepPlaceStore/setAutomatic(_:forNightEnding:)`` refuses it).
///
/// iPhone only: visits do not exist on visionOS, and the place a Mac sat in
/// overnight says nothing about where its owner slept.
@MainActor
@Observable
final class SleepPlaceRecorder: NSObject {
    enum Access: Equatable {
        case notAsked
        case denied
        case whenInUse
        case always
    }

    static let enabledKey = "sleepPlace.automatic"
    /// Whether the Always question was put. iOS shows it once; after that the
    /// only way to Always is the Settings app.
    static let askedAlwaysKey = "sleepPlace.askedAlways"
    private static let nightStartKey = "sleepPlace.lastNight.start"
    private static let nightEndKey = "sleepPlace.lastNight.end"

    static let shared = SleepPlaceRecorder()

    static var isSupported: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private(set) var isOn: Bool
    private(set) var access: Access
    /// False when Precise Location is off for Soma: a reduced fix is several
    /// kilometres wide and names a district, not a street, so nothing is kept.
    private(set) var isPrecise: Bool
    /// Stored as well as kept in the defaults so the page redraws when the
    /// question was put and the answer left Location as it was.
    private var askedAlways: Bool

    @ObservationIgnored private let store: SleepPlaceStore
    @ObservationIgnored private let defaults: UserDefaults
    #if os(iOS)
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var fixNight: Date?
    @ObservationIgnored private var fixTimeout: Task<Void, Never>?
    @ObservationIgnored private var renamed: Set<String> = []
    #endif

    init(store: SleepPlaceStore = .shared, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        isOn = defaults.bool(forKey: Self.enabledKey)
        access = .notAsked
        isPrecise = true
        askedAlways = defaults.bool(forKey: Self.askedAlwaysKey)
        super.init()
        #if os(iOS)
        manager.delegate = self
        readAuthorization()
        #endif
    }

    /// Called once from the app's launch. A visit relaunches Soma in the
    /// background with no window, and the system hands the visit to whichever
    /// manager is listening, so the listening starts here rather than in a
    /// view. Previews and the test host never start it.
    static func launch() {
        guard isSupported else { return }
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              environment["XCTestConfigurationFilePath"] == nil,
              UserDefaults.standard.bool(forKey: enabledKey) else { return }
        shared.resume()
    }

    // MARK: Switch

    /// Turns detection on or off. On asks for Location while in use the first
    /// time; the Always offer is a separate step the person takes.
    func setOn(_ on: Bool) {
        guard Self.isSupported else { return }
        isOn = on
        defaults.set(on, forKey: Self.enabledKey)
        #if os(iOS)
        if on {
            if access == .notAsked { manager.requestWhenInUseAuthorization() }
            resume()
        } else {
            manager.stopMonitoringVisits()
            endFix()
        }
        #endif
    }

    /// Whether the Always question can still be put in the app. Once asked,
    /// the answer can only change in Settings.
    var canAskAlways: Bool {
        access == .whenInUse && !askedAlways
    }

    func requestAlways() {
        #if os(iOS)
        guard canAskAlways else { return }
        askedAlways = true
        defaults.set(true, forKey: Self.askedAlwaysKey)
        manager.requestAlwaysAuthorization()
        #endif
    }

    // MARK: The app comes forward

    /// The app came forward: remember last night's window for a later visit,
    /// and in the morning take one fix for the night that just ended.
    func appBecameActive(lastNight: DateInterval?, now: Date = Date()) {
        if let lastNight { remember(lastNight) }
        #if os(iOS)
        guard isOn, access == .whenInUse || access == .always, isPrecise else { return }
        nameUnnamedNights(now: now)
        guard let night = Self.morningNight(now: now, lastNight: lastNight ?? rememberedNight(), calendar: .current),
              store.place(forNightEnding: night) == nil else { return }
        beginFix(for: night)
        #endif
    }

    private func remember(_ night: DateInterval) {
        defaults.set(night.start.timeIntervalSinceReferenceDate, forKey: Self.nightStartKey)
        defaults.set(night.end.timeIntervalSinceReferenceDate, forKey: Self.nightEndKey)
    }

    /// The last window the scores gave, kept so a visit that relaunches the
    /// app in the background (before any Health read) still knows the night.
    private func rememberedNight() -> DateInterval? {
        let start = defaults.double(forKey: Self.nightStartKey)
        let end = defaults.double(forKey: Self.nightEndKey)
        guard start > 0, end > start else { return nil }
        return DateInterval(start: Date(timeIntervalSinceReferenceDate: start), end: Date(timeIntervalSinceReferenceDate: end))
    }

    // MARK: Recording

    /// Gives a fix to a night: the nearby detected place when there is one,
    /// else the fix named by the geocoder.
    private func record(latitude: Double, longitude: Double, forNightEnding night: Date) async {
        if let current = store.place(forNightEnding: night), !current.wasDetected { return }
        let known = store.recentPlaces.filter(\.wasDetected)
        if let near = Self.nearest(latitude: latitude, longitude: longitude, among: known) {
            store.setAutomatic(near, forNightEnding: night)
            return
        }
        let place = await Self.named(latitude: latitude, longitude: longitude)
        store.setAutomatic(place, forNightEnding: night)
    }

    /// A fix taken offline is kept under its coordinates; the next time the
    /// app comes forward it gets its street, once per place a session.
    private func nameUnnamedNights(now: Date) {
        #if os(iOS)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for back in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let place = store.place(forNightEnding: day),
                  place.wasDetected, place.address == nil,
                  renamed.insert(place.id).inserted else { continue }
            Task { [weak self] in
                let named = await Self.named(latitude: place.latitude, longitude: place.longitude)
                guard named.address != nil, let self else { return }
                // The night may have been set by hand while the name was asked.
                guard self.store.place(forNightEnding: day) == place else { return }
                self.store.setAutomatic(named, forNightEnding: day)
            }
        }
        #endif
    }

    // MARK: Naming

    /// The street and city for a coordinate, from Apple's reverse geocoder,
    /// with the full address on one line. Offline or unnamed, the place keeps
    /// its coordinates as its name and no address.
    static func named(latitude: Double, longitude: Double) async -> SleepPlaceStore.Place {
        var place = SleepPlaceStore.Place(name: coordinateName(latitude: latitude, longitude: longitude),
                                          latitude: latitude, longitude: longitude, isAutomatic: true)
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let items = try? await request.mapItems,
              let item = items.first else { return place }
        let lines = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: false)
        let street = lines?.split(whereSeparator: \.isNewline).first.map(String.init)
        if let name = label(street: street, city: item.addressRepresentations?.cityName, fallback: item.name) {
            place.name = name
        }
        place.address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? item.address?.fullAddress
        return place
    }

    /// "12 Rue des Lilas, Lyon": the street line and the city. The street
    /// alone when the city is missing or already in it, the city alone when
    /// there is no street, else the map item's own name.
    nonisolated static func label(street: String?, city: String?, fallback: String?) -> String? {
        let street = street?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        switch (street, city) {
        case let (street?, city?) where street.localizedCaseInsensitiveContains(city): return street
        case let (street?, city?): return "\(street), \(city)"
        case let (street?, nil): return street
        case let (nil, city?): return city
        default: return fallback?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
    }

    nonisolated static func coordinateName(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    // MARK: Rules, pure for the tests

    /// A fix this accurate puts the phone in one building: 65 m is what a
    /// phone indoors on Wi-Fi reports, and anything wider can be next door.
    nonisolated static let fixAccuracy: Double = 65
    /// Visits are reported coarser than a live fix, and a stay is already a
    /// strong signal, so they get a wider bound.
    nonisolated static let visitAccuracy: Double = 200
    /// Two fixes this close are the same home.
    nonisolated static let samePlaceDistance: Double = 120

    /// Whether a live fix is precise and fresh enough to name the night. A
    /// negative accuracy is the system saying the fix is invalid, and a fix
    /// older than two minutes is a cached one from somewhere else.
    nonisolated static func accepts(accuracy: Double, age: TimeInterval) -> Bool {
        accuracy >= 0 && accuracy <= fixAccuracy && age.isFinite && age <= 120
    }

    nonisolated static func acceptsVisit(accuracy: Double) -> Bool {
        accuracy >= 0 && accuracy <= visitAccuracy
    }

    /// The detected place within ``samePlaceDistance`` of a fix, the nearest
    /// when several are.
    nonisolated static func nearest(latitude: Double, longitude: Double,
                                    among places: [SleepPlaceStore.Place]) -> SleepPlaceStore.Place? {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        let here = CLLocation(latitude: latitude, longitude: longitude)
        return places
            .map { ($0, here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.1.isFinite && $0.1 <= samePlaceDistance }
            .min { $0.1 < $1.1 }?.0
    }

    /// The night a morning opening belongs to, as the day it ended on, or nil
    /// outside the morning.
    ///
    /// With last night's window, the morning runs from waking to four hours
    /// after; a window that ended more than a day ago describes an older
    /// night and is ignored. Without one, the morning is 04:00 to 12:00.
    nonisolated static func morningNight(now: Date, lastNight: DateInterval?, calendar: Calendar) -> Date? {
        if let night = lastNight {
            let since = now.timeIntervalSince(night.end)
            if since >= 0, since <= 4 * 3600 { return calendar.startOfDay(for: night.end) }
            if since >= 0, since < 24 * 3600 { return nil }
        }
        let hour = calendar.component(.hour, from: now)
        return (4..<12).contains(hour) ? calendar.startOfDay(for: now) : nil
    }

    /// The nights a stay held, each as the day it ended on.
    ///
    /// A stay holds a night when it covers at least half of it, so leaving a
    /// friend's at one in the morning does not make it the night's place.
    /// The night is last night's window when the scores have it, and for every
    /// other night the core of the night, 02:00 to 05:00 local. An open
    /// arrival or departure (`distantPast`, `distantFuture`) is clipped to the
    /// last week and to now, and a stay still going counts only the part
    /// already lived.
    nonisolated static func nights(heldByArrival arrival: Date, departure: Date, lastNight: DateInterval?,
                                   now: Date, calendar: Calendar) -> [Date] {
        let from = max(arrival, now.addingTimeInterval(-7 * 24 * 3600))
        let to = min(departure, now)
        guard from < to else { return [] }
        var held: Set<Date> = []
        let windowDay = lastNight.map { calendar.startOfDay(for: $0.end) }
        if let night = lastNight, covers(from: from, to: to, night.start, night.end) {
            held.insert(calendar.startOfDay(for: night.end))
        }
        var day = calendar.startOfDay(for: from)
        while day <= to {
            if day != windowDay,
               let start = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: day),
               let end = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: day),
               covers(from: from, to: to, start, end) {
                held.insert(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return held.sorted()
    }

    /// Whether `from...to` overlaps at least half of `start...end`.
    nonisolated private static func covers(from: Date, to: Date, _ start: Date, _ end: Date) -> Bool {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return false }
        let overlap = min(to, end).timeIntervalSince(max(from, start))
        return overlap >= length / 2
    }
}

#if os(iOS)
extension SleepPlaceRecorder: @preconcurrency CLLocationManagerDelegate {
    private func readAuthorization() {
        access = switch manager.authorizationStatus {
        case .notDetermined: .notAsked
        case .denied, .restricted: .denied
        case .authorizedAlways: .always
        default: .whenInUse
        }
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
    }

    /// Starts what the current answer allows. Visits need Always; without it
    /// the morning fix is all there is.
    fileprivate func resume() {
        guard isOn else { return }
        if access == .always {
            manager.startMonitoringVisits()
        } else {
            manager.stopMonitoringVisits()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        readAuthorization()
        resume()
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard isOn, isPrecise, Self.acceptsVisit(accuracy: visit.horizontalAccuracy) else { return }
        let coordinate = visit.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let nights = Self.nights(heldByArrival: visit.arrivalDate, departure: visit.departureDate,
                                 lastNight: rememberedNight(), now: Date(), calendar: .current)
        guard !nights.isEmpty else { return }
        Task { [weak self] in
            for night in nights {
                await self?.record(latitude: coordinate.latitude, longitude: coordinate.longitude, forNightEnding: night)
            }
        }
    }

    // MARK: The morning fix

    private func beginFix(for night: Date) {
        guard fixNight == nil else { return }
        fixNight = night
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.startUpdatingLocation()
        // Eight seconds is long enough for GPS or Wi-Fi to settle indoors and
        // short enough not to hold the radio for a fix that will not come.
        fixTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.endFix()
        }
    }

    fileprivate func endFix() {
        fixTimeout?.cancel()
        fixTimeout = nil
        fixNight = nil
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let night = fixNight else { return }
        let now = Date()
        let good = locations
            .filter { Self.accepts(accuracy: $0.horizontalAccuracy, age: now.timeIntervalSince($0.timestamp)) }
            .min { $0.horizontalAccuracy < $1.horizontalAccuracy }
        guard let good, CLLocationCoordinate2DIsValid(good.coordinate) else { return }
        endFix()
        let coordinate = good.coordinate
        Task { [weak self] in
            await self?.record(latitude: coordinate.latitude, longitude: coordinate.longitude, forNightEnding: night)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Not knowing yet is the normal start of a fix; anything else ends it.
        if (error as? CLError)?.code == .locationUnknown { return }
        if fixNight != nil { endFix() }
    }
}
#else
extension SleepPlaceRecorder {
    fileprivate func resume() {}
    fileprivate func endFix() {}
}
#endif

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
