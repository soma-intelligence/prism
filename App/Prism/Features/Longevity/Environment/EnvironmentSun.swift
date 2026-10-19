//
//  EnvironmentSun.swift
//  Prism
//

import Foundation

/// Sunrise and sunset worked out on the device, from a coarse place and the
/// date alone: no forecast service, nothing leaves the phone.
///
/// The place comes from ``EnvironmentLocation``, rounded to a tenth of a
/// degree. Without one, the sun's path is drawn with a dash at each end.
nonisolated enum EnvironmentSun {
    /// A rounded place: about eleven kilometres, enough for the sun.
    struct Place: Sendable, Equatable {
        var latitude: Double
        var longitude: Double
        /// The city's name when the place came from the Weather page.
        var name: String?
    }

    /// The sun's day at one place.
    struct Day: Sendable, Equatable {
        var rise: Date
        var set: Date

        /// The share of daylight gone by at `now`: under 0 before sunrise,
        /// over 1 after sunset.
        func progress(at now: Date) -> Double {
            let length = set.timeIntervalSince(rise)
            guard length > 0 else { return 0 }
            return now.timeIntervalSince(rise) / length
        }
    }

    /// The sunrise and sunset of the local day holding `date`, by the NOAA
    /// almanac method (accurate to a minute or two). Nil in a polar day or
    /// night, when the sun does not cross the horizon.
    static func day(for date: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) -> Day? {
        guard let rise = crossing(rising: true, date: date, latitude: latitude, longitude: longitude, calendar: calendar),
              let set = crossing(rising: false, date: date, latitude: latitude, longitude: longitude, calendar: calendar),
              set > rise else { return nil }
        return Day(rise: rise, set: set)
    }

    private static func crossing(rising: Bool, date: Date, latitude: Double, longitude: Double, calendar: Calendar) -> Date? {
        let radians = Double.pi / 180
        let localStart = calendar.startOfDay(for: date)
        guard let localEnd = calendar.date(byAdding: .day, value: 1, to: localStart),
              let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let utcMidnight = utc.date(from: parts) else { return nil }

        let hourAngle = longitude / 15
        let t = Double(dayOfYear) + ((rising ? 6 : 18) - hourAngle) / 24
        let anomaly = 0.9856 * t - 3.289
        var trueLongitude = anomaly + 1.916 * sin(anomaly * radians) + 0.020 * sin(2 * anomaly * radians) + 282.634
        trueLongitude = trueLongitude.truncatingRemainder(dividingBy: 360)
        if trueLongitude < 0 { trueLongitude += 360 }
        var ascension = atan(0.91764 * tan(trueLongitude * radians)) / radians
        ascension = ascension.truncatingRemainder(dividingBy: 360)
        if ascension < 0 { ascension += 360 }
        ascension += (floor(trueLongitude / 90) * 90) - (floor(ascension / 90) * 90)
        ascension /= 15

        let sinDeclination = 0.39782 * sin(trueLongitude * radians)
        let cosDeclination = cos(asin(sinDeclination))
        let zenith = 90.833
        let cosHour = (cos(zenith * radians) - sinDeclination * sin(latitude * radians))
            / (cosDeclination * cos(latitude * radians))
        guard (-1...1).contains(cosHour) else { return nil }
        var hour = acos(cosHour) / radians
        if rising { hour = 360 - hour }
        hour /= 15

        let localMean = hour + ascension - 0.06571 * t - 6.622
        var universal = (localMean - hourAngle).truncatingRemainder(dividingBy: 24)
        if universal < 0 { universal += 24 }

        var result = utcMidnight.addingTimeInterval(universal * 3600)
        while result < localStart { result = result.addingTimeInterval(86_400) }
        while result >= localEnd { result = result.addingTimeInterval(-86_400) }
        return result
    }
}
