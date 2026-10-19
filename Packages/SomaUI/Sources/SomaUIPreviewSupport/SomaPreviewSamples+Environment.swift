//
//  SomaPreviewSamples+Environment.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

/// A day outside for the Environment gauges in the gallery: minutes in
/// daylight against a usual band, the sun most of the way across, a UV
/// index, two sound levels and a temperature range.
public extension SomaPreviewSamples {
    static let daylightMinutes: Double = 48
    static let daylightUsual: ClosedRange<Double> = 40...85
    /// The share of daylight gone by, with its sunrise and sunset.
    static let sunProgress: Double = 0.62
    static let sunrise = "07:05"
    static let sunset = "18:48"
    static let uvIndex: Double = 6
    static let soundAround: Double = 64
    static let soundHeadphones: Double = 83
    static let temperatureNow: Double = 18
    static let temperatureRange: ClosedRange<Double> = 12...21
}
