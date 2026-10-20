//
//  SomaHeatMapTests.swift
//  SomaUITests
//

import Testing
import Foundation
@testable import SomaUI

@Suite("Heat map")
struct SomaHeatMapTests {
    @Test("No spot frames nothing; one spot frames the least span round it")
    func oneSpot() {
        #expect(SomaHeatGeometry.region([], minimumSpan: 700) == nil)
        let one = SomaHeatGeometry.region([SomaHeatPoint(id: "a", latitude: 37.44, longitude: -122.16, weight: 1)], minimumSpan: 700)
        #expect(one?.latitude == 37.44)
        #expect(one?.longitude == -122.16)
        #expect(one?.span == 700)
    }

    @Test("Spots far apart are all framed, with room round them")
    func farApart() throws {
        let region = try #require(SomaHeatGeometry.region([
            SomaHeatPoint(id: "a", latitude: 37.40, longitude: -122.16, weight: 1),
            SomaHeatPoint(id: "b", latitude: 37.50, longitude: -122.16, weight: 0.5),
        ], minimumSpan: 700))
        #expect(abs(region.latitude - 37.45) < 0.000_1)
        // A tenth of a degree north to south is about 11 km.
        #expect(region.span > 11_000 * 1.5)
        #expect(region.span < 11_200 * 1.7)
    }

    @Test("A busier spot glows wider and denser, rings narrowing to the middle")
    func rings() {
        let busy = SomaHeatGeometry.rings(weight: 1, radius: 70, layers: 14, opacity: 0.06)
        let quiet = SomaHeatGeometry.rings(weight: 0.1, radius: 70, layers: 14, opacity: 0.06)
        #expect(busy.count == 14)
        #expect(busy[0].radius == 70)
        #expect(busy[0].radius > quiet[0].radius)
        #expect(busy[0].opacity > quiet[0].opacity)
        #expect(zip(busy, busy.dropFirst()).allSatisfy { $0.radius > $1.radius })
        #expect(SomaHeatGeometry.rings(weight: 1, radius: 70, layers: 0, opacity: 0.09).isEmpty)
    }

    @Test("Weights are held to 0...1, and the busiest spot is the warmest tone")
    func weights() {
        #expect(SomaHeatPoint(id: "a", latitude: 0, longitude: 0, weight: 3).weight == 1)
        #expect(SomaHeatPoint(id: "a", latitude: 0, longitude: 0, weight: -1).weight == 0)
        #expect(SomaHeatGeometry.tone(weight: 1) == SomaEnergyRamp.calm.value(at: 0))
    }
}
