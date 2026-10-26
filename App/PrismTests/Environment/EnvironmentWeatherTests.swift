//
//  EnvironmentWeatherTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The weather comes from Open-Meteo's forecast and air quality services. What
/// leaves the phone is a place rounded to about ten kilometres and the list of
/// fields wanted, nothing else; what comes back is read field by field, a
/// missing value staying a gap rather than a zero.
@Suite("Environment weather")
@MainActor
struct EnvironmentWeatherTests {
    typealias Client = EnvironmentWeatherClient

    func object(_ json: String) throws -> [String: Any] {
        try #require(Client.object(Data(json.utf8)))
    }

    /// Two days at a place two hours ahead of UTC, the last one partly empty.
    let forecast = #"""
    {
      "utc_offset_seconds": 7200,
      "current": {"temperature_2m": 17.4, "relative_humidity_2m": 61, "wind_speed_10m": 14.4, "uv_index": 3.2, "weather_code": 61, "is_day": 1},
      "daily": {
        "time": ["2026-10-02", "2026-10-03"],
        "temperature_2m_max": [19.1, 18.0],
        "temperature_2m_min": [9.5, null],
        "uv_index_max": [null, 4.1],
        "sunrise": ["2026-10-02T07:51", "2026-10-03T07:52"],
        "sunset": ["2026-10-02T19:28", "2026-10-03T19:26"]
      },
      "hourly": {"time": ["2026-10-02T22:00", "2026-10-02T23:00", "2026-10-03T00:00"], "temperature_2m": [12.0, null, 11.0]}
    }
    """#

    let air = #"""
    {
      "current": {"us_aqi": 38},
      "hourly": {
        "time": ["2026-10-02T00:00", "2026-10-02T12:00", "2026-10-03T00:00", "2026-10-03T01:00", "2026-10-04T00:00"],
        "us_aqi": [20, 55, null, 31, null]
      }
    }
    """#

    /// A wall clock time in October 2026 at a place two hours ahead of UTC.
    func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: DateComponents(year: 2026, month: 10, day: day))!
        return midnight.addingTimeInterval(Double((hour - 2) * 3600 + minute * 60))
    }

    /// Decimal values come back through JSONSerialization, so they are held
    /// to a hair rather than to the last bit.
    func close(_ value: Double?, _ expected: Double) -> Bool {
        value.map { abs($0 - expected) < 1e-9 } ?? false
    }

    @Test("Only the rounded place and the fields wanted go out")
    func requests() throws {
        let forecastURL = try #require(Client.forecastURL(latitude: 48.9, longitude: 2.4))
        let airURL = try #require(Client.airURL(latitude: 48.9, longitude: 2.4))
        for url in [forecastURL, airURL] {
            let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(parts.scheme == "https")
            let names = Set((parts.queryItems ?? []).map(\.name))
            #expect(names.isSubset(of: ["latitude", "longitude", "current", "daily", "hourly", "past_days", "forecast_days", "timezone"]))
            #expect(parts.queryItems?.first { $0.name == "latitude" }?.value == "48.9")
            #expect(parts.queryItems?.first { $0.name == "longitude" }?.value == "2.4")
        }
        #expect(forecastURL.host() == "api.open-meteo.com")
        #expect(airURL.host() == "air-quality-api.open-meteo.com")
    }

    @Test("The forecast's current values, daily series and hourly temperatures read across, gaps kept")
    func forecastParsing() throws {
        let answer = try object(forecast)
        let conditions = Client.parse(forecast: answer, air: nil)
        #expect(close(conditions.temperature, 17.4))
        #expect(conditions.humidity == 61)
        #expect(close(conditions.wind, 14.4))
        #expect(close(conditions.uv, 3.2))
        #expect(conditions.weatherCode == 61)
        #expect(conditions.isDay == true)
        #expect(conditions.highDays.count == 2)
        #expect(close(conditions.highDays.first ?? nil, 19.1))
        #expect(conditions.uvDays.count == 2)
        #expect(conditions.uvDays.first == .some(nil))
        #expect(close(conditions.uvDays.last ?? nil, 4.1))
        #expect(conditions.high == 18.0)
        #expect(conditions.low == nil)
        #expect(conditions.sunrise == local(3, 7, 52))
        #expect(conditions.sunset == local(3, 19, 26))
        #expect(conditions.hourly == [local(2, 22): 12.0, local(3, 0): 11.0])
        #expect(conditions.aqi == nil)
        #expect(conditions.symbol == "cloud.rain.fill")
    }

    @Test("Air quality keeps each day's worst hour, in day order, a day without one left a gap")
    func airParsing() throws {
        let answer = try object(air)
        let conditions = Client.parse(forecast: nil, air: answer)
        #expect(conditions.aqi == 38)
        #expect(conditions.aqiDays == [55, 31, nil])
        #expect(conditions.temperature == nil)
    }

    @Test("No answer from either service is no conditions at all")
    func nothing() {
        #expect(Client.parse(forecast: nil, air: nil) == EnvironmentConditions())
        #expect(Client.object(Data("not json".utf8)) == nil)
        #expect(Client.object(nil) == nil)
    }

    @Test("A night's outdoor temperature is the mean of its hours, the half hour before it included")
    func nightMean() throws {
        let answer = try object(forecast)
        let conditions = Client.parse(forecast: answer, air: nil)
        #expect(conditions.mean(from: local(2, 22, 20), to: local(3, 6)) == 11.5)
        #expect(conditions.mean(from: local(3, 1), to: local(3, 6)) == nil)
    }

    @Test("The sky's symbol follows the WMO code, by day and by night")
    func symbols() {
        #expect(EnvironmentConditions(weatherCode: 0, isDay: true).symbol == "sun.max.fill")
        #expect(EnvironmentConditions(weatherCode: 0, isDay: false).symbol == "moon.stars.fill")
        #expect(EnvironmentConditions(weatherCode: 45).symbol == "cloud.fog.fill")
        #expect(EnvironmentConditions(weatherCode: 73).symbol == "cloud.snow.fill")
        #expect(EnvironmentConditions(weatherCode: 96).symbol == "cloud.bolt.rain.fill")
        #expect(EnvironmentConditions().symbol == "cloud.sun.fill")
    }
}
