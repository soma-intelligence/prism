//
//  ToolsSolarTimes.swift
//  Prism
//
//  Sunrise and sunset from latitude, longitude and date, using the "Almanac
//  for Computers" solar equations. No external API required.
//
//  One implementation only. Two copies of this algorithm once drifted apart,
//  each anchoring its result to the wrong day in a
//  different direction (Tokyo's sunrise came out after its own sunset).
//
//  On anchoring, which is the subtle half of the algorithm: step 7b yields a
//  UTC CLOCK TIME in [0, 24), never an instant. Everything before it is
//  defined modulo 24 h (RA is folded into [0, 24), and the -0.06571 t term
//  grows without bound), so the unfolded value carries no day information
//  whatsoever. The day has to be reattached afterwards, from the location.
//
//  Also here: `SolarDayAxis`, the solar day seen as an axis (0 at sunrise,
//  1 at sunset), which the Sun Budget arc places its sun and burn pip on.
//

import Foundation

extension SomaTools {

    nonisolated enum SolarTimes {

        /// Official sunrise and sunset for the civil day of `date`, as absolute
        /// instants. The returned pair is always ordered: `sunset` is the first
        /// sunset after `sunrise`. Render them with a local formatter to get
        /// local clock times.
        ///
        /// Returns nil when the sun does not rise or set that day (polar day or
        /// polar night), and when the coordinate is outside the domain. nil
        /// therefore means "no event OR bad input"; validate coordinates at the
        /// call site if you need to tell those two apart.
        ///
        /// `date` is read for its civil day only, in `calendar`. The two clock
        /// times are placed on the civil day of the LOCATION, which is not always
        /// the same UTC day: east of Greenwich a sunrise can fall on the previous
        /// UTC day (Tokyo), far west a sunset can fall on the next one (Hawaii).
        static func sunriseSunset(date: Date,
                                  latitude: Double,
                                  longitude: Double,
                                  calendar: Calendar = .current) -> (sunrise: Date, sunset: Date)? {
            guard latitude.isFinite, longitude.isFinite,
                  latitude >= -90, latitude <= 90,
                  longitude >= -180, longitude <= 180,
                  let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date),
                  let midnightUTC = utcMidnight(ofCivilDayOf: date, calendar: calendar)
            else { return nil }

            let N = Double(dayOfYear)
            let lngHour = longitude / 15.0

            guard let sunriseUT = calculateEvent(dayOfYear: N, latitude: latitude, lngHour: lngHour, isSunrise: true),
                  let sunsetUT = calculateEvent(dayOfYear: N, latitude: latitude, lngHour: lngHour, isSunrise: false)
            else { return nil }

            // The sunrise carries the day for the pair. Anchoring the sunset on
            // its own clock time would invert the two within a few minutes of the
            // polar-day threshold, where the sunset clock time wraps past midnight
            // while the sunrise clock time has not.
            let sunrise = midnightUTC.addingTimeInterval(
                (sunriseUT + dayShiftHours(utHours: sunriseUT, lngHour: lngHour)) * 3600)
            let dayLength = ensureRange(sunsetUT - sunriseUT, max: 24.0)

            return (sunrise, sunrise.addingTimeInterval(dayLength * 3600))
        }

        // MARK: - Helpers

        /// Steps 2 to 7b: the UTC clock time of the event, in [0, 24).
        private static func calculateEvent(dayOfYear N: Double, latitude: Double,
                                           lngHour: Double, isSunrise: Bool) -> Double? {
            let tBase = isSunrise ? 6.0 : 18.0
            let t = N + ((tBase - lngHour) / 24.0)

            let M = (0.9856 * t) - 3.289

            let radM = M * .pi / 180.0
            var L = M + (1.916 * sin(radM)) + (0.020 * sin(2 * radM)) + 282.634
            L = ensureRange(L, max: 360.0)

            let radL = L * .pi / 180.0
            var RA = atan(0.91764 * tan(radL)) * 180.0 / .pi
            RA = ensureRange(RA, max: 360.0)

            let lQuadrant = (floor(L / 90.0)) * 90.0
            let raQuadrant = (floor(RA / 90.0)) * 90.0
            RA = RA + (lQuadrant - raQuadrant)
            RA = RA / 15.0

            let sinDec = 0.39782 * sin(radL)
            let cosDec = cos(asin(sinDec))

            let zenith = 90.8333
            let radZenith = zenith * .pi / 180.0
            let radLat = latitude * .pi / 180.0

            let cosH = (cos(radZenith) - (sinDec * sin(radLat))) / (cosDec * cos(radLat))

            // Written as the accepted range rather than as its negation: NaN fails
            // BOTH `cosH > 1` and `cosH < -1`, so the rejecting form let a
            // non-finite input through and produced a non-finite Date.
            guard cosH >= -1, cosH <= 1 else { return nil }

            let hRad = acos(cosH)
            let hDeg = hRad * 180.0 / .pi
            let H = isSunrise ? (360.0 - hDeg) : hDeg

            let T = (H / 15.0) + RA - (0.06571 * t) - 6.622

            // Step 7b.
            return ensureRange(T - lngHour, max: 24.0)
        }

        /// Whether a UTC clock time belongs to the day before or after the anchor.
        ///
        /// The event sits near 6 h (sunrise) or 18 h (sunset) of LOCAL MEAN SOLAR
        /// time, which is `utHours + lngHour`. When that value leaves [0, 24) the
        /// event's UTC day is the neighbouring one. Longitude, not the device
        /// timezone, is what decides: the calculator knows where the sun is, not
        /// which political timezone the spot observes.
        private static func dayShiftHours(utHours: Double, lngHour: Double) -> Double {
            let localSolar = utHours + lngHour
            if localSolar >= 24 { return -24 }
            if localSolar < 0 { return 24 }
            return 0
        }

        private static func ensureRange(_ value: Double, max: Double) -> Double {
            var v = value
            while v < 0 { v += max }
            while v >= max { v -= max }
            return v
        }

        /// Midnight UTC of the civil day `date` falls on, read in `calendar`. Only
        /// an anchor to count hours from, never a displayed instant.
        private static func utcMidnight(ofCivilDayOf date: Date, calendar: Calendar) -> Date? {
            let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
            let localComponents = calendar.dateComponents([.year, .month, .day], from: date)

            var utcComponents = DateComponents()
            utcComponents.year = localComponents.year
            utcComponents.month = localComponents.month
            utcComponents.day = localComponents.day
            utcComponents.hour = 0
            utcComponents.minute = 0
            utcComponents.second = 0
            utcComponents.timeZone = utc

            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = utc
            return utcCalendar.date(from: utcComponents)
        }
    }

    /// The solar day seen as an AXIS: 0 at sunrise, 1 at sunset. Nothing else.
    ///
    /// What the axis REFUSES to answer matters as much as what it computes.
    /// Before sunrise, after sunset, and wherever there is no sunrise/sunset
    /// pair at all (polar day and night), it returns nil. An axis that clamped
    /// to 0 or 1 there would place a sun on a horizon where it is not.
    nonisolated struct SolarDayAxis: Equatable, Sendable {
        let sunrise: Date
        let sunset: Date

        /// nil when there is no day to walk: a bound is missing (polar
        /// latitudes, or the location never resolved), or the bounds are out of
        /// order. The failure is in the INITIALIZER, so an axis that exists is
        /// always walkable and `progress` never divides by a zero span.
        init?(sunrise: Date?, sunset: Date?) {
            guard let sunrise, let sunset, sunset > sunrise else { return nil }
            self.sunrise = sunrise
            self.sunset = sunset
        }

        /// Day length in seconds. Strictly positive by construction.
        var span: TimeInterval { sunset.timeIntervalSince(sunrise) }

        /// Where `date` falls on the axis: 0 at sunrise, 1 at sunset, nil outside.
        ///
        /// The bounds are INCLUDED: the sunrise instant is a point of the axis,
        /// otherwise a dial opened exactly at sunrise would flicker between its
        /// arc and its fallback.
        func progress(at date: Date) -> Double? {
            let elapsed = date.timeIntervalSince(sunrise)
            guard elapsed >= 0, elapsed <= span else { return nil }
            return elapsed / span
        }
    }
}
