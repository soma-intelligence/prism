//
//  ToolWeatherTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Sun Budget and Skin Forecast read the weather the Environment lens reads.
/// What crosses over is held here: the day's UV peak is today's, the air is
/// a whole index, and a value the services left out stays a dash rather
/// than turning into zero.
@Suite("Tool weather")
@MainActor
struct ToolWeatherTests {
    @Test("Today's conditions cross over to the tools, the UV peak taken from today")
    func fromConditions() {
        var conditions = EnvironmentConditions()
        conditions.uv = 3.2
        conditions.uvDays = [5.5, nil, 4.1]
        conditions.aqi = 37.6
        conditions.temperature = 17.4
        conditions.humidity = 61
        conditions.wind = 14.4

        let weather = ToolWeather(place: "Lyon", latitude: 45.8, longitude: 4.8, conditions: conditions)
        #expect(weather.place == "Lyon")
        #expect(weather.latitude == 45.8)
        #expect(weather.longitude == 4.8)
        #expect(weather.uvNow == 3.2)
        #expect(weather.uvPeak == 4.1)
        #expect(weather.aqi == 38)
        #expect(weather.temperatureC == 17.4)
        #expect(weather.humidityPercent == 61)
        #expect(weather.windKph == 14.4)
        #expect(weather.hourlyUV.isEmpty)
    }

    @Test("A value the services left out stays unknown, today's UV peak included")
    func gaps() {
        var conditions = EnvironmentConditions()
        conditions.uvDays = [5.5, nil]
        let weather = ToolWeather(place: "Lyon", latitude: 45.8, longitude: 4.8, conditions: conditions)
        #expect(weather.uvNow == nil)
        #expect(weather.uvPeak == nil)
        #expect(weather.aqi == nil)
        #expect(weather.temperatureC == nil)
        #expect(weather.windKph == nil)
    }
}
