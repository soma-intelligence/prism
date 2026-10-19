//
//  CoarseCoordinate.swift
//  Prism
//

import Foundation

/// The one rule for how precisely a place may leave the device.
///
/// Anything that asks Apple to name a place, or keys a stored name by place,
/// goes through ``degrees(_:)`` first: 0.01 degree is about a kilometre, which
/// names a neighbourhood and nothing finer. The map on screen may keep exact
/// fixes; only what is sent out is rounded.
nonisolated enum CoarseCoordinate {
    /// One step of the grid, in degrees.
    static let step = 0.01
    /// Grid cells per degree, derived from ``step``. Rounding multiplies,
    /// rounds and divides by this whole number: dividing by it is exact to the
    /// nearest double, so the result is the same value as the literal (51.51),
    /// where multiplying by ``step`` can land a hair away.
    private static let cellsPerDegree = (1 / step).rounded()

    /// A latitude or longitude rounded to the grid.
    static func degrees(_ value: Double) -> Double {
        (value * cellsPerDegree).rounded() / cellsPerDegree
    }

    /// A pair of coordinates rounded to the grid.
    static func rounded(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
        (degrees(latitude), degrees(longitude))
    }
}
