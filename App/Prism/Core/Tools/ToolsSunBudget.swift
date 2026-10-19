//
//  ToolsSunBudget.swift
//  Prism
//
//  Sun Budget over `ErythemalDoseEngine`: from the UV index and the sun's
//  real elevation at the user's location, how long today's sun would take to
//  burn the user's Fitzpatrick skin, and how far an SPF pushes that out. The
//  floor to that ceiling, the minutes of sun for vitamin D, comes from
//  `VitaminDEngine` on the SAME conditions: both are bounds of one question,
//  how long to stay out today.
//
//  The environmental half (`SunBudget.Conditions`) is built from plain numbers
//  a weather source may or may not provide: a current UV index, the location,
//  the instant, and optionally a day's hourly UV or only its peak. The
//  personal half (Fitzpatrick type, SPF) is applied by `SunBudget.Reading`,
//  so changing a picker recomputes without refetching anything. When there
//  is no weather source at all, the page never builds a reading and shows its
//  empty state.
//
//  Everything here is a WELLNESS estimate, not medical advice and not a
//  measured dose.
//

import Foundation

extension SomaTools {

    nonisolated enum SunBudget {

        // MARK: - Inputs

        /// SPF options the picker offers. Raw value is the protection factor
        /// used as a linear multiplier on tolerated dose (bare skin = 1). The
        /// unprotected case is named `bare`, not `none`, so it never collides
        /// with `Optional.none` at a call site.
        nonisolated enum SPF: Double, CaseIterable, Identifiable, Sendable {
            case bare = 1
            case spf15 = 15
            case spf30 = 30
            case spf50 = 50

            var id: Double { rawValue }

            var label: String {
                switch self {
                case .bare:  return "None"
                case .spf15: return "SPF 15"
                case .spf30: return "SPF 30"
                case .spf50: return "SPF 50"
                }
            }
        }

        /// The environmental half of the estimate, resolved once per open and
        /// held while the pickers recompute the rest. Kept separate from skin
        /// type and SPF so changing a picker never triggers a refetch.
        nonisolated struct Conditions: Equatable, Sendable {
            let uv: Double
            let solarElevationDeg: Double
            /// Today's UV curve, oldest first. Empty when neither a forecast nor
            /// a peak was available, which drops everything back to the flat
            /// model rather than to a blank screen.
            var hourly: [ErythemalDoseEngine.UVSample] = []
            /// Today's solar day at the coordinate. nil is a real answer, not a
            /// failure: polar day and polar night have no sunrise/sunset pair,
            /// and the surfaces fall back to their flat visual there.
            var sunrise: Date?
            var sunset: Date?

            init(uv: Double,
                 solarElevationDeg: Double,
                 hourly: [ErythemalDoseEngine.UVSample] = [],
                 sunrise: Date? = nil,
                 sunset: Date? = nil) {
                self.uv = uv
                self.solarElevationDeg = solarElevationDeg
                self.hourly = hourly
                self.sunrise = sunrise
                self.sunset = sunset
            }

            var solarDay: SolarDayAxis? { SolarDayAxis(sunrise: sunrise, sunset: sunset) }
        }

        /// Builds the conditions from plain numbers. The sun angle and the solar
        /// day are pure arithmetic from the coordinate, so they cost no round
        /// trip. The day's curve comes from `hourlyUV` when the source has a
        /// forecast, otherwise from `peakUV` shaped by the sun's path
        /// (`estimatedHourlyUV`), otherwise it stays empty (flat model).
        ///
        /// `uvIndex` nil falls back to the curve's value at `date`, then to 0.
        /// Returns nil when there is no UV information at all (no current UV,
        /// no forecast, no peak): the page's empty state.
        static func conditions(uvIndex: Double?,
                               latitude: Double,
                               longitude: Double,
                               date: Date,
                               hourlyUV: [ErythemalDoseEngine.UVSample] = [],
                               peakUV: Double? = nil,
                               calendar: Calendar = .current) -> Conditions? {
            guard latitude.isFinite, longitude.isFinite else { return nil }
            let elevation = SolarElevation.elevationDegrees(date: date,
                                                            latitude: latitude,
                                                            longitude: longitude)
            let solar = SolarTimes.sunriseSunset(date: date, latitude: latitude,
                                                 longitude: longitude, calendar: calendar)

            var hourly = hourlyUV.sorted { $0.date < $1.date }
            if hourly.count < 2, let peakUV, peakUV.isFinite {
                hourly = estimatedHourlyUV(peakUV: peakUV, latitude: latitude,
                                           longitude: longitude, day: date, calendar: calendar)
            }
            if hourly.count < 2 { hourly = [] }

            let current: Double
            if let uvIndex, uvIndex.isFinite {
                current = max(0, uvIndex)
            } else if let interpolated = uv(at: date, on: hourly) {
                current = interpolated
            } else {
                return nil
            }

            return Conditions(uv: current,
                              solarElevationDeg: elevation,
                              hourly: hourly,
                              sunrise: solar?.sunrise,
                              sunset: solar?.sunset)
        }

        // MARK: - UV curve from a peak

        /// Exponent of the clear sky UV index against the sine of the solar
        /// elevation. The erythemal UV index falls off faster than the plain
        /// solar beam as the sun drops, because the UVB path through ozone
        /// lengthens; empirical fits put it near cos(SZA)^2 to cos(SZA)^2.5.
        /// Added in Soma (the original page always had an hourly forecast), so
        /// treat the shape as an approximation.
        static let uvElevationExponent: Double = 2.2

        /// The day's UV curve when a weather source only gives the day's peak
        /// UV: every `stepMinutes` across the civil day of `day`, UV follows the
        /// sun's elevation, scaled so the highest sample equals `peakUV`. Zero
        /// with the sun at or below the horizon. Empty when the sun never rises
        /// (polar night) or the peak is not positive.
        static func estimatedHourlyUV(peakUV: Double,
                                      latitude: Double,
                                      longitude: Double,
                                      day: Date,
                                      stepMinutes: Int = 60,
                                      calendar: Calendar = .current) -> [ErythemalDoseEngine.UVSample] {
            guard peakUV > 0, peakUV.isFinite, stepMinutes > 0 else { return [] }
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

            var instants: [Date] = []
            var cursor = start
            while cursor <= end {
                instants.append(cursor)
                cursor = cursor.addingTimeInterval(Double(stepMinutes) * 60)
            }

            let shapes = instants.map { instant -> Double in
                let elevation = SolarElevation.elevationDegrees(date: instant,
                                                                latitude: latitude,
                                                                longitude: longitude)
                guard elevation > 0 else { return 0 }
                return pow(sin(elevation * .pi / 180), uvElevationExponent)
            }
            guard let top = shapes.max(), top > 0 else { return [] }
            return zip(instants, shapes).map { instant, shape in
                ErythemalDoseEngine.UVSample(date: instant, uv: peakUV * shape / top)
            }
        }

        /// The UV at `date` on a curve, interpolated linearly between samples.
        /// nil outside the curve or when it has fewer than two points.
        static func uv(at date: Date, on hourly: [ErythemalDoseEngine.UVSample]) -> Double? {
            let samples = hourly.sorted { $0.date < $1.date }
            guard samples.count > 1, let first = samples.first, let last = samples.last,
                  date >= first.date, date <= last.date else { return nil }
            for (index, sample) in samples.enumerated().dropLast() {
                let next = samples[index + 1]
                guard date <= next.date else { continue }
                let span = next.date.timeIntervalSince(sample.date)
                guard span > 0 else { return next.uv }
                let t = date.timeIntervalSince(sample.date) / span
                return sample.uv + (next.uv - sample.uv) * t
            }
            return last.uv
        }

        // MARK: - Outcome and band

        /// What the day holds for this skin under this SPF. Three cases, not
        /// two: a countdown, a day that runs out before the dose does, and a sun
        /// that is not up. Collapsing the middle one into "no risk" is how an
        /// old screen told someone at 09:00 they had hours of margin.
        nonisolated enum Outcome: Equatable, Sendable {
            case burns(minutes: Double)
            case outlastsDay
            case noRiskNow

            var minutes: Double? {
                if case .burns(let minutes) = self { return minutes }
                return nil
            }
        }

        /// Urgency bands on the burn time, so the headline reads as a prompt
        /// ("cover up soon") not just a number. The band is a word; the accent
        /// colour stays constant.
        nonisolated enum Band: Equatable, Sendable {
            case noRisk, high, moderate, low

            /// Band cut points in minutes: under 20 is high, under 45 moderate.
            static let highBelowMinutes: Double = 20
            static let moderateBelowMinutes: Double = 45

            init(bareMinutes: Double?) {
                guard let minutes = bareMinutes else { self = .noRisk; return }
                switch minutes {
                case ..<Band.highBelowMinutes:     self = .high
                case ..<Band.moderateBelowMinutes: self = .moderate
                default:                           self = .low
                }
            }

            var label: String {
                switch self {
                case .noRisk:   return "No risk"
                case .high:     return "Cover up soon"
                case .moderate: return "Watch the clock"
                case .low:      return "Plenty of time"
                }
            }
        }

        // MARK: - Reading

        /// The burn estimate for one set of conditions plus one skin type and
        /// SPF. Fully derived from its inputs, so the views stay previewable and
        /// the math stays verifiable on fixtures.
        nonisolated struct Reading: Equatable, Sendable {
            let uv: Double
            let solarElevationDeg: Double
            let fitzpatrick: Fitzpatrick
            let spf: SPF
            /// Minutes of bare skin sun before erythema at the current UV (flat
            /// model), nil when there is no burn risk right now.
            let bareMinutes: Double?
            /// Minutes under the selected SPF; nil for the same reason.
            let protectedMinutes: Double?

            /// Today's UV curve, kept on the reading so the chart and the
            /// headline are read off ONE series. Empty when the curve never
            /// arrived, which drops everything below back to the flat model.
            let hourly: [ErythemalDoseEngine.UVSample]
            /// The instant the reading is anchored to. Passed in rather than taken
            /// from the clock inside, so equality stays stable and fixtures can
            /// pin it.
            let now: Date
            /// Where the tolerated dose lands under the selected SPF, walking the
            /// curve forward. nil either because there is no curve or because the
            /// day runs out first; `outcome` tells those apart.
            let burnInstant: Date?
            let bareBurnInstant: Date?

            /// Today's solar day. nil at polar latitudes and before the location
            /// resolves, which keeps `horizonProgress` as the documented fallback.
            let solarDay: SolarDayAxis?

            init(conditions: Conditions,
                 fitzpatrick: Fitzpatrick,
                 spf: SPF = .bare,
                 now: Date) {
                uv = conditions.uv
                solarElevationDeg = conditions.solarElevationDeg
                self.fitzpatrick = fitzpatrick
                self.spf = spf
                bareMinutes = ErythemalDoseEngine.minutesToBurn(
                    uvIndex: conditions.uv, fitzpatrick: fitzpatrick, spf: 1)
                protectedMinutes = ErythemalDoseEngine.minutesToBurn(
                    uvIndex: conditions.uv, fitzpatrick: fitzpatrick, spf: spf.rawValue)
                hourly = conditions.hourly
                solarDay = conditions.solarDay
                self.now = now
                burnInstant = ErythemalDoseEngine.burnInstant(
                    from: now, hourly: conditions.hourly, fitzpatrick: fitzpatrick, spf: spf.rawValue)
                bareBurnInstant = ErythemalDoseEngine.burnInstant(
                    from: now, hourly: conditions.hourly, fitzpatrick: fitzpatrick, spf: 1)
            }

            /// Flat model band on bare skin. Prefer `bareBand` on any surface
            /// that also shows the curve.
            var band: Band { Band(bareMinutes: bareMinutes) }

            /// Two points are enough to integrate between; one is just a reading.
            var usesForecast: Bool { hourly.count > 1 }

            /// What the page says, under the selected SPF.
            var outcome: Outcome {
                Self.outcome(usesForecast: usesForecast, uv: uv, now: now,
                             flatMinutes: protectedMinutes, instant: burnInstant)
            }

            /// The same question with nothing on the skin, so the SPF row can
            /// state what the sunscreen is actually buying.
            var bareOutcome: Outcome {
                Self.outcome(usesForecast: usesForecast, uv: uv, now: now,
                             flatMinutes: bareMinutes, instant: bareBurnInstant)
            }

            private static func outcome(usesForecast: Bool, uv: Double, now: Date,
                                        flatMinutes: Double?, instant: Date?) -> Outcome {
                guard usesForecast else {
                    return flatMinutes.map { .burns(minutes: $0) } ?? .noRiskNow
                }
                if let instant {
                    return .burns(minutes: max(0, instant.timeIntervalSince(now) / 60))
                }
                return uv > 0 ? .outlastsDay : .noRiskNow
            }

            /// The band the page shows follows the SPF, so picking SPF 50 moves
            /// the word as well as the number.
            var selectedBand: Band {
                switch outcome {
                case .burns(let minutes): return Band(bareMinutes: minutes)
                case .outlastsDay, .noRiskNow: return .noRisk
                }
            }

            /// The bare skin band read off the SAME walk as `bareOutcome`, for
            /// surfaces without a picker. `band` reads the flat model; at 09:00
            /// the two can disagree by hours.
            var bareBand: Band {
                switch bareOutcome {
                case .burns(let minutes): return Band(bareMinutes: minutes)
                case .outlastsDay, .noRiskNow: return .noRisk
                }
            }

            /// What the sunscreen buys over bare skin, in minutes. nil unless
            /// both the protected and the bare outcome are countdowns (the page
            /// then prints its hint or the "outlasts the day" line instead).
            var spfGainMinutes: Double? {
                guard spf != .bare,
                      case .burns(let protectedMinutes) = outcome,
                      case .burns(let bareMinutes) = bareOutcome else { return nil }
                return max(0, protectedMinutes - bareMinutes)
            }

            /// The highest point of the day's curve.
            var dayPeak: ErythemalDoseEngine.UVSample? {
                hourly.max { $0.uv < $1.uv }
            }

            /// "Time to burn at the peak": the flat model at the day's highest
            /// UV under the selected SPF, the shortest countdown the day can
            /// produce. nil without a curve or with a zero peak.
            var minutesToBurnAtPeak: Double? {
                guard let peak = dayPeak else { return nil }
                return ErythemalDoseEngine.minutesToBurn(uvIndex: peak.uv,
                                                         fitzpatrick: fitzpatrick,
                                                         spf: spf.rawValue)
            }

            /// The daylight slice of the curve, one sample of margin on each
            /// side. Charting the full 24 hours would spend three quarters of the
            /// plot on a flat zero.
            var daylight: [ErythemalDoseEngine.UVSample] {
                guard let first = hourly.firstIndex(where: { $0.uv > 0.05 }),
                      let last = hourly.lastIndex(where: { $0.uv > 0.05 }),
                      last > first else { return hourly }
                return Array(hourly[max(0, first - 1)...min(hourly.count - 1, last + 1)])
            }

            /// Visual margin for the compact horizon. Ninety minutes or more
            /// fills the arc; a very short estimate still keeps a visible sliver
            /// so the state never reads as missing data. No current burn risk is
            /// the full, calm horizon rather than an empty warning gauge.
            var horizonProgress: Double {
                guard let bareMinutes else { return 1 }
                return min(max(bareMinutes / Self.horizonFullMinutes, 0.08), 1)
            }

            /// The minutes that fill the margin arc.
            static let horizonFullMinutes: Double = 90

            /// Band cut points placed on the margin arc (20 and 45 of 90 min).
            static var horizonMarks: [Double] {
                [Band.highBelowMinutes / horizonFullMinutes,
                 Band.moderateBelowMinutes / horizonFullMinutes]
            }

            /// Where `date` sits on the solar day: 0 at sunrise, 1 at sunset,
            /// nil outside it.
            func dayProgress(at date: Date) -> Double? {
                solarDay?.progress(at: date)
            }

            /// The bare skin burn instant placed on the solar day axis, so the
            /// pip and the sun are read against one scale. nil when nothing burns
            /// today, and when the instant falls past sunset (the day runs out
            /// before the dose does, which has no place on the trajectory).
            var burnFraction: Double? {
                guard let bareBurnInstant else { return nil }
                return dayProgress(at: bareBurnInstant)
            }

            /// Vitamin D on the same conditions and skin type, bare skin fraction
            /// defaulted to face, forearms and hands.
            func vitaminD(exposedSkinFraction: Double = VitaminDEstimate.defaultExposedSkinFraction,
                          goalIU: Double = VitaminDEstimate.defaultGoalIU) -> VitaminDEngine.Synthesis {
                VitaminDEngine.synthesis(uvIndex: uv,
                                         solarElevationDeg: solarElevationDeg,
                                         fitzpatrick: fitzpatrick,
                                         exposedSkinFraction: exposedSkinFraction,
                                         goalIU: goalIU)
            }
        }

        /// Every SPF option's outcome for one set of conditions, in picker order.
        static func whatIf(conditions: Conditions,
                           fitzpatrick: Fitzpatrick,
                           now: Date) -> [(spf: SPF, outcome: Outcome)] {
            SPF.allCases.map { spf in
                (spf, Reading(conditions: conditions, fitzpatrick: fitzpatrick,
                              spf: spf, now: now).outcome)
            }
        }

        // MARK: - Day chart geometry

        /// Clock hour as a decimal (13:30 is 13.5), in `calendar`'s time zone.
        static func decimalHour(_ date: Date, calendar: Calendar = .current) -> Double {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        }

        /// The x window of the day chart in decimal hours, from the daylight
        /// slice, at least half an hour wide. nil when there is no curve to draw
        /// (the page then shows its plain hero).
        static func chartWindow(for reading: Reading,
                                calendar: Calendar = .current) -> (startHour: Double, endHour: Double)? {
            let daylight = reading.daylight
            guard daylight.count > 1, let first = daylight.first, let last = daylight.last else { return nil }
            let startHour = decimalHour(first.date, calendar: calendar)
            let endHour = max(startHour + 0.5, decimalHour(last.date, calendar: calendar))
            return (startHour, endHour)
        }

        /// Where an instant falls across the chart window, as a 0...1 fraction
        /// (unclamped: the caller decides whether to draw out of range).
        static func chartFraction(_ date: Date, startHour: Double, endHour: Double,
                                  calendar: Calendar = .current) -> Double {
            let span = max(0.001, endHour - startHour)
            return (decimalHour(date, calendar: calendar) - startHour) / span
        }

        /// The two pins on the curve: where you are (only when now falls inside
        /// the window), and where the budget runs out under the selected SPF.
        nonisolated struct ChartMarkers: Equatable, Sendable {
            let now: Double?
            let burn: Double?
        }

        static func chartMarkers(for reading: Reading,
                                 startHour: Double, endHour: Double,
                                 calendar: Calendar = .current) -> ChartMarkers {
            let nowHour = decimalHour(reading.now, calendar: calendar)
            let now = (nowHour >= startHour && nowHour <= endHour)
                ? chartFraction(reading.now, startHour: startHour, endHour: endHour, calendar: calendar)
                : nil
            let burn = reading.burnInstant.map {
                chartFraction($0, startHour: startHour, endHour: endHour, calendar: calendar)
            }
            return ChartMarkers(now: now, burn: burn)
        }

        // MARK: - Duration display

        /// A duration split for display: minutes under 90, hours with one
        /// decimal beyond, so a dim UV estimate does not print 300 in a "min"
        /// field. The burn and the vitamin D readings break at the same place.
        nonisolated struct Duration: Equatable, Sendable {
            nonisolated enum Unit: Sendable { case minutes, hours }
            let value: String
            let unit: Unit

            var unitLabel: String { unit == .minutes ? "min" : "hr" }
        }

        static func duration(_ minutes: Double) -> Duration {
            if minutes < 90 {
                return Duration(value: String(Int(minutes.rounded())), unit: .minutes)
            }
            return Duration(value: String(format: "%.1f", minutes / 60), unit: .hours)
        }
    }
}
