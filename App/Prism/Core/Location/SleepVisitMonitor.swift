//
//  SleepVisitMonitor.swift
//  Prism
//

import Foundation
import CoreLocation
import Observation

/// Core Location's visits, for Sleep places: where the phone stayed and
/// when it came and went, handed to ``SleepPlaceFinder``.
///
/// Visits need Location set to Always: the phone notes a stay with little
/// battery, and wakes the app for it in the background, with no background
/// mode. Without Always nothing is monitored and Sleep places falls back to
/// nights set by hand. Always is asked only from the Sleep places sheet,
/// after it says why. iPhone only: the Mac and the headset never ask.
@MainActor
@Observable
final class SleepVisitMonitor: NSObject {
    enum Access: Equatable {
        /// This device cannot monitor visits.
        case unavailable
        case notAsked
        /// While using the app only: visits need more.
        case whileUsing
        case always
        case denied
    }

    static let shared = SleepVisitMonitor()

    private(set) var access: Access = .unavailable

    /// Whether Always was asked once already: the system shows that
    /// question one time, after which only Settings can change it.
    var askedAlways: Bool {
        get { UserDefaults.standard.bool(forKey: "sleepPlaces.askedAlways") }
        set { UserDefaults.standard.set(newValue, forKey: "sleepPlaces.askedAlways") }
    }

#if os(iOS)
    @ObservationIgnored private let manager = CLLocationManager()
#endif

    override init() {
        super.init()
#if os(iOS)
        manager.delegate = self
        access = Self.access(manager.authorizationStatus)
#endif
    }

    /// Called at launch, so a visit that wakes the app in the background
    /// finds its delegate. Monitors only with Always.
    func start() {
#if os(iOS)
        access = Self.access(manager.authorizationStatus)
        if access == .always {
            manager.startMonitoringVisits()
        } else {
            manager.stopMonitoringVisits()
        }
#endif
    }

    /// Asks for Always, once.
    func requestAlways() {
#if os(iOS)
        askedAlways = true
        manager.requestAlwaysAuthorization()
#endif
    }

#if os(iOS)
    private static func access(_ status: CLAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse: .whileUsing
        case .authorizedAlways: .always
        default: .denied
        }
    }
#endif
}

#if os(iOS)
extension SleepVisitMonitor: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        start()
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        SleepPlaceFinder.shared.record(SleepVisit(
            arrival: visit.arrivalDate == .distantPast ? nil : visit.arrivalDate,
            departure: visit.departureDate == .distantFuture ? nil : visit.departureDate,
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            accuracy: visit.horizontalAccuracy
        ))
    }
}
#endif
