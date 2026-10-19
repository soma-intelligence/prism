//
//  ToolWeather.swift
//  Prism
//

import Foundation

/// The weather and air the sun and skin tools read.
///
/// The app has no weather source yet: there is no WeatherKit entitlement and no
/// location permission, so ``ToolWeather/current`` is nil and Sun Budget and
/// Skin Forecast show their dashes and say what fills them. When a source
/// lands (the one the Pulse scores use), it fills this value and both pages
/// light up with no other change.
nonisolated struct ToolWeather: Sendable, Equatable {
    var place: String
    var latitude: Double
    var longitude: Double
    var uvNow: Double?
    /// Today's forecast UV by hour.
    var hourlyUV: [SomaTools.ErythemalDoseEngine.UVSample]
    var uvPeak: Double?
    var aqi: Int?
    var temperatureC: Double?
    var humidityPercent: Double?
    var windKph: Double?

    /// Nothing reads the weather yet.
    static let current: ToolWeather? = nil
}
