//
//  SomaPreviewSamples+Environment.swift
//  SomaUIPreviewSupport
//

import Foundation
import SomaUI

/// A day outside for the Environment gauges in the gallery: minutes in
/// daylight against a usual band, the sun most of the way across its day, a UV
/// index, two sound levels and a temperature range.
public extension SomaPreviewSamples {
    static let daylightMinutes: Double = 48
    static let daylightUsual: ClosedRange<Double> = 40...85
    /// Today's sunrise and sunset, and a moment most of the way across.
    static var sunrise: Date { Calendar.current.startOfDay(for: .now).addingTimeInterval(7 * 3_600 + 5 * 60) }
    static var sunset: Date { Calendar.current.startOfDay(for: .now).addingTimeInterval(18 * 3_600 + 48 * 60) }
    static var sunNow: Date { Calendar.current.startOfDay(for: .now).addingTimeInterval(14 * 3_600 + 20 * 60) }
    static let uvIndex: Double = 6
    static let soundAround: Double = 64
    static let soundHeadphones: Double = 83
    static let temperatureNow: Double = 18
    static let temperatureRange: ClosedRange<Double> = 12...21
    /// Thirty nights slept: most at home, a few at a friend's across town.
    static let sleepHeat: [SomaHeatPoint] = [
        SomaHeatPoint(id: "home", latitude: 37.4443, longitude: -122.1598, weight: 1),
        SomaHeatPoint(id: "home.2", latitude: 37.4445, longitude: -122.1601, weight: 0.45),
        SomaHeatPoint(id: "friend", latitude: 37.4468, longitude: -122.1552, weight: 0.2),
    ]
}
