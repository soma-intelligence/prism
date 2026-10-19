//
//  ToolsSolarElevation.swift
//  Prism
//
//  Deterministic solar elevation (altitude) angle for any instant and
//  location, via the standard NOAA solar-position algorithm. No network,
//  no I/O: pass in the date and coordinate and get degrees back. Sibling of
//  `SolarTimes` (sunrise and sunset); this file answers the finer question
//  "how high is the sun right now", which the vitamin D model needs as its
//  UVB proxy and the Sun Budget day curve needs to shape the UV over the day.
//

import Foundation

extension SomaTools {

    nonisolated enum SolarElevation {

        /// Solar elevation angle in degrees for `date` at (`latitude`,
        /// `longitude`). Positive above the horizon, negative below it (so a
        /// caller can tell civil twilight from full night). Longitude is
        /// positive east. Uses the NOAA general solar-position equations
        /// (fractional year, equation of time, declination, hour angle) applied
        /// in UTC, so the passed `calendar` only supplies the gregorian frame.
        static func elevationDegrees(date: Date,
                                     latitude: Double,
                                     longitude: Double,
                                     calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {

            // Decompose the absolute instant in UTC. NOAA math is defined in
            // universal time; the longitude term below carries the location back
            // to local (true) solar time, so no timezone offset is needed here.
            var cal = calendar
            cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt

            guard let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) else {
                // Gregorian ordinality never fails in practice; treat an
                // unresolvable date as fully below the horizon.
                return -90.0
            }
            let daysInYear = Double(cal.range(of: .day, in: .year, for: date)?.count ?? 365)

            let comps = cal.dateComponents([.hour, .minute, .second], from: date)
            let hour = Double(comps.hour ?? 0)
            let minute = Double(comps.minute ?? 0)
            let second = Double(comps.second ?? 0)

            let deg2rad = Double.pi / 180.0
            let rad2deg = 180.0 / Double.pi

            // Fractional year gamma (radians): where we are around the orbit,
            // with the hour term centering noon.
            let gamma = (2.0 * Double.pi / daysInYear)
                * (Double(dayOfYear) - 1.0 + (hour - 12.0) / 24.0)

            // Equation of time (minutes): the sundial versus clock correction.
            let eqTime = 229.18 * (0.000075
                + 0.001868 * cos(gamma)
                - 0.032077 * sin(gamma)
                - 0.014615 * cos(2.0 * gamma)
                - 0.040849 * sin(2.0 * gamma))

            // Solar declination (radians): the sun's latitude on the celestial
            // sphere.
            let decl = 0.006918
                - 0.399912 * cos(gamma)
                + 0.070257 * sin(gamma)
                - 0.006758 * cos(2.0 * gamma)
                + 0.000907 * sin(2.0 * gamma)
                - 0.002697 * cos(3.0 * gamma)
                + 0.001480 * sin(3.0 * gamma)

            // True solar time in minutes (timezone offset is 0 in UTC).
            let timeOffset = eqTime + 4.0 * longitude
            let trueSolarTime = hour * 60.0 + minute + second / 60.0 + timeOffset

            // Hour angle (degrees): 0 at local solar noon, +/-180 at midnight.
            let hourAngleDeg = (trueSolarTime / 4.0) - 180.0
            let hourAngle = hourAngleDeg * deg2rad

            let latRad = latitude * deg2rad

            // sin(elevation) = sin(lat)sin(dec) + cos(lat)cos(dec)cos(H)
            var sinElev = sin(latRad) * sin(decl)
                + cos(latRad) * cos(decl) * cos(hourAngle)
            // Guard against tiny floating drift outside asin's domain.
            sinElev = min(1.0, max(-1.0, sinElev))

            return asin(sinElev) * rad2deg
        }
    }
}
