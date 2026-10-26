//
//  ToolWeather.swift
//  Prism
//

import Foundation

/// The weather and air the sun and skin tools read.
///
/// The same read as the Environment lens: Open-Meteo for the place
/// ``EnvironmentLocation`` knows (``EnvironmentWeatherClient``), taken by
/// ``ToolsModel`` when the tools load. Without a place, or when the services
/// do not answer, ``ToolWeather/current`` is nil and Sun Budget and Skin
/// Forecast show their dashes and say what fills them.
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

    /// The last read, nil until a place and its weather are known.
    @MainActor static var current: ToolWeather? { ToolsModel.shared.weather }
}

nonisolated extension ToolWeather {
    /// Today's weather at a place, from the Environment lens's read: the UV
    /// now and the day's highest, the air, the heat and the wind. Open-Meteo
    /// gives no hourly UV here, so the sun tools draw the day from its peak.
    init(place: String, latitude: Double, longitude: Double, conditions: EnvironmentConditions) {
        self.init(
            place: place,
            latitude: latitude,
            longitude: longitude,
            uvNow: conditions.uv,
            hourlyUV: [],
            uvPeak: conditions.uvDays.last ?? nil,
            aqi: conditions.aqi.map { Int($0.rounded()) },
            temperatureC: conditions.temperature,
            humidityPercent: conditions.humidity,
            windKph: conditions.wind
        )
    }
}
