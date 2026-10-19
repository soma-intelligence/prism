//
//  TerritoryNamesTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// What the Territory page sends to Apple's reverse geocoder: the middle of a
/// place, rounded to 0.01 degree (about a kilometre) before it leaves the
/// device. The exact middle stays on the page for the map.
@Suite("Territory place lookups")
struct TerritoryNamesTests {

    @Test("The coordinate handed to the geocoder is rounded to 0.01 degree")
    func lookupIsRounded() {
        let middle = Territory.Point(latitude: 37.774929, longitude: -122.419416, altitude: 12.5)
        let sent = TerritoryNames.lookupCoordinate(for: middle)
        #expect(sent.latitude == 37.77)
        #expect(sent.longitude == -122.42)
    }

    @Test("Rounding goes to the nearest step, either side of zero")
    func nearestStep() {
        let sent = TerritoryNames.lookupCoordinate(for: Territory.Point(latitude: -33.8688, longitude: 151.2093))
        #expect(sent.latitude == -33.87)
        #expect(sent.longitude == 151.21)
    }

    @Test("Two middles inside the same step ask the same question")
    func sameStepSameLookup() {
        let a = TerritoryNames.lookupCoordinate(for: Territory.Point(latitude: 48.8561, longitude: 2.3522))
        let b = TerritoryNames.lookupCoordinate(for: Territory.Point(latitude: 48.8584, longitude: 2.3499))
        #expect(a.latitude == b.latitude)
        #expect(a.longitude == b.longitude)
    }

    @Test("The shared rule is the same one the Environment lens uses")
    func sharedRule() {
        #expect(CoarseCoordinate.degrees(51.50739) == 51.51)
        #expect(CoarseCoordinate.step == 0.01)
        #expect(CoarseCoordinate.degrees(0.5) == 0.5)
        #expect(CoarseCoordinate.degrees(0.014) == 0.01)
    }
}
