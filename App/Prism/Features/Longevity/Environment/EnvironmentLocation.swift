//
//  EnvironmentLocation.swift
//  Prism
//

import Foundation
import CoreLocation
import MapKit
import Observation

/// Where you are, for the Environment lens: the device's own position for
/// the map, the same place rounded to about a kilometre for everything that
/// asks a service, and its name.
///
/// Only the map reads ``exact``, and the map draws on the device. The name
/// lookup sends the rounded place, and the weather client rounds it again to
/// a tenth of a degree, so what leaves the device is what it always was.
///
/// Uses the Location answer the app already has. When Location was never
/// asked, the lens shows one button that asks for it in context, the first
/// time only; a refusal is never asked again here. Without the device's own
/// place, the city picked on the Weather page stands in. Names come from
/// Apple's reverse geocoder and are kept on the device by rounded place, so
/// a place is named once.
@MainActor
@Observable
final class EnvironmentLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum Access: Equatable {
        case notAsked
        case denied
        case allowed
    }

    static let shared = EnvironmentLocation()

    private(set) var access: Access
    private(set) var place: EnvironmentSun.Place?
    /// The device's own position, unrounded, for drawing on the map only.
    /// Nil when the place is the Weather city or Location is off.
    private(set) var exact: EnvironmentSun.Place?
    /// Whether ``place`` is the device's own rather than the Weather city.
    private(set) var isHere = false

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        access = Self.access(manager.authorizationStatus)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Asks for Location while in use. Only when it was never asked.
    func request() {
        guard access == .notAsked else { return }
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let next = Self.access(manager.authorizationStatus)
        guard next != access else { return }
        access = next
        Task { await refresh() }
    }

    /// Reads the place again: the device's when allowed, else the city.
    func refresh() async {
        if access == .allowed, let here = await fix() {
            isHere = true
            let named = await named(Self.rounded(here.latitude, here.longitude))
            place = named
            exact = EnvironmentSun.Place(latitude: here.latitude, longitude: here.longitude, name: named.name)
            return
        }
        isHere = false
        exact = nil
        if let city = SleepPlaceStore.shared.weatherCity {
            place = EnvironmentSun.Place(latitude: city.latitude, longitude: city.longitude, name: city.name)
        } else {
            place = nil
        }
    }

    private static func access(_ status: CLAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: .notAsked
        case .denied, .restricted: .denied
        default: .allowed
        }
    }

    /// One fix, as the device gives it: the last known one, or the first
    /// update within a few seconds. Rounded by the caller before it is used
    /// for anything but the map.
    private func fix() async -> EnvironmentSun.Place? {
        if let known = manager.location {
            return EnvironmentSun.Place(latitude: known.coordinate.latitude, longitude: known.coordinate.longitude)
        }
        let fix: (Double, Double)? = await withTaskGroup(of: (Double, Double)?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.default) {
                        if let location = update.location {
                            return (location.coordinate.latitude, location.coordinate.longitude)
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return fix.map { EnvironmentSun.Place(latitude: $0.0, longitude: $0.1) }
    }

    nonisolated static func rounded(_ latitude: Double, _ longitude: Double) -> EnvironmentSun.Place {
        let coarse = CoarseCoordinate.rounded(latitude: latitude, longitude: longitude)
        return EnvironmentSun.Place(latitude: coarse.latitude, longitude: coarse.longitude)
    }

    // MARK: Names

    /// The rounded place with its name: the city it is in. Never the name of
    /// whatever building sits at the rounded point, which can be a kilometre
    /// from where you are.
    private func named(_ place: EnvironmentSun.Place) async -> EnvironmentSun.Place {
        var place = place
        let key = String(format: "environment.city.%.2f,%.2f", place.latitude, place.longitude)
        if let cached = UserDefaults.standard.string(forKey: key) {
            place.name = cached
            return place
        }
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return place }
        let name = item.addressRepresentations?.cityName
        if let name { UserDefaults.standard.set(name, forKey: key) }
        place.name = name
        return place
    }
}
