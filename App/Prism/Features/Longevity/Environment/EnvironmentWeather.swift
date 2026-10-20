//
//  EnvironmentWeather.swift
//  Prism
//

import Foundation

/// The weather where you are, from Open-Meteo's free forecast and air
/// quality services: no key, no account, only a place rounded to about ten
/// kilometres leaves the device.
///
/// The app has no WeatherKit capability, so this is the weather source
/// (owner, 2026-10-03). Thirty days back come with today, so the detail
/// sheets can chart temperature, UV and air quality, and the Sleep card can
/// read the outdoor temperature of last night.
nonisolated struct EnvironmentConditions: Sendable, Equatable, Codable {
    var temperature: Double?
    var humidity: Double?
    var uv: Double?
    var aqi: Double?
    var weatherCode: Int?
    var isDay: Bool?
    var low: Double?
    var high: Double?
    var sunrise: Date?
    var sunset: Date?
    /// Thirty one days, oldest first and today last: the day's high, its
    /// highest UV and its highest US AQI.
    var highDays: [Double?] = []
    var uvDays: [Double?] = []
    var aqiDays: [Double?] = []
    /// Every hour's temperature, for the outdoor temperature over a night.
    var hourly: [Date: Double] = [:]

    /// The mean outdoor temperature over a stretch, a night say.
    func mean(from start: Date, to end: Date) -> Double? {
        let values = hourly.filter { $0.key >= start.addingTimeInterval(-1800) && $0.key <= end }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The sky as a symbol, from the WMO weather code.
    var symbol: String {
        let day = isDay ?? true
        switch weatherCode ?? -1 {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

/// Reads and keeps the conditions, place by place, for thirty minutes.
actor EnvironmentWeatherClient {
    static let shared = EnvironmentWeatherClient()

    static let freshFor: TimeInterval = 30 * 60
    private var cache: [String: (read: Date, value: EnvironmentConditions)] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Nil when both services fail; a field the services leave out stays nil.
    func conditions(latitude: Double, longitude: Double, now: Date = Date()) async -> EnvironmentConditions? {
        let lat = (latitude * 10).rounded() / 10
        let lon = (longitude * 10).rounded() / 10
        let key = "\(lat),\(lon)"
        if let hit = cache[key], now.timeIntervalSince(hit.read) < Self.freshFor { return hit.value }

        let session = session
        async let forecast = Self.fetch(Self.forecastURL(latitude: lat, longitude: lon), session: session)
        async let air = Self.fetch(Self.airURL(latitude: lat, longitude: lon), session: session)
        let (weather, quality) = await (forecast, air)
        guard weather != nil || quality != nil else { return cache[key]?.value }
        let value = Self.parse(forecast: Self.object(weather), air: Self.object(quality))
        cache[key] = (now, value)
        return value
    }

    private static func fetch(_ url: URL?, session: URLSession) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    static func object(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Requests

    static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,uv_index,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,uv_index_max,sunrise,sunset"),
            URLQueryItem(name: "hourly", value: "temperature_2m"),
            URLQueryItem(name: "past_days", value: "30"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return parts?.url
    }

    static func airURL(latitude: Double, longitude: Double) -> URL? {
        var parts = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi"),
            URLQueryItem(name: "hourly", value: "us_aqi"),
            URLQueryItem(name: "past_days", value: "30"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return parts?.url
    }

    // MARK: Parsing

    /// Reads both answers. Times come as local wall clock ("2026-10-03T07:05")
    /// with the place's offset beside them.
    static func parse(forecast: [String: Any]?, air: [String: Any]?) -> EnvironmentConditions {
        var result = EnvironmentConditions()

        if let forecast {
            let clock = clockParser(offset: forecast["utc_offset_seconds"] as? Int ?? 0)
            let current = forecast["current"] as? [String: Any] ?? [:]
            result.temperature = number(current["temperature_2m"])
            result.humidity = number(current["relative_humidity_2m"])
            result.uv = number(current["uv_index"])
            result.weatherCode = number(current["weather_code"]).map { Int($0) }
            result.isDay = number(current["is_day"]).map { $0 > 0 }

            let daily = forecast["daily"] as? [String: Any] ?? [:]
            let highs = series(daily["temperature_2m_max"])
            let lows = series(daily["temperature_2m_min"])
            result.highDays = highs
            result.uvDays = series(daily["uv_index_max"])
            result.high = highs.last ?? nil
            result.low = lows.last ?? nil
            result.sunrise = (daily["sunrise"] as? [String])?.last.flatMap(clock)
            result.sunset = (daily["sunset"] as? [String])?.last.flatMap(clock)

            let hourly = forecast["hourly"] as? [String: Any] ?? [:]
            let times = (hourly["time"] as? [String] ?? []).map(clock)
            let temperatures = series(hourly["temperature_2m"])
            for (time, value) in zip(times, temperatures) {
                if let time, let value { result.hourly[time] = value }
            }
        }

        if let air {
            result.aqi = number((air["current"] as? [String: Any])?["us_aqi"])
            let hourly = air["hourly"] as? [String: Any] ?? [:]
            let values = series(hourly["us_aqi"])
            var byDay: [String: Double] = [:]
            var order: [String] = []
            for (time, value) in zip(hourly["time"] as? [String] ?? [], values) {
                let day = String(time.prefix(10))
                if byDay[day] == nil, !order.contains(day) { order.append(day) }
                if let value { byDay[day] = max(byDay[day] ?? 0, value) }
            }
            result.aqiDays = order.map { byDay[$0] }
        }
        return result
    }

    private static func number(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }

    private static func series(_ any: Any?) -> [Double?] {
        (any as? [Any])?.map { number($0) } ?? []
    }

    private static func clockParser(offset: Int) -> (String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: offset)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return { formatter.date(from: $0) }
    }
}
