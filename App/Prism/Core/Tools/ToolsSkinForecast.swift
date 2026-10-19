//
//  ToolsSkinForecast.swift
//  Prism
//
//  Daily skin comfort index (0 to 100) from the day's environmental
//  conditions. High UV, poor air quality, drying wind and out of band
//  temperature all stress the skin barrier; the index is 100 minus a
//  weighted distance from a comfortable environment, and the "top lever"
//  names the single condition dragging it down the most today.
//
//  No knowledge of weather clients or UI. All inputs are passed in as plain
//  optional numbers (no I/O), the types are pure and Sendable. When the
//  weather source is missing entirely, `reading(for:)` returns nil and the
//  page shows its empty state.
//
//  IMPORTANT: this is a WELLNESS ESTIMATE, not a diagnosis. Real skin
//  reactivity is personal (phototype, existing conditions, products,
//  humidity, pollen). v1 uses population default comfort zones over four
//  environmental drivers (UV, US AQI, wind, temperature). Humidity is carried
//  on the environment for display but is NOT scored in v1, exactly as in the
//  original model; personalizing the thresholds per user over logged skin
//  symptoms is a deliberate later step.
//
//  Model shape:
//    Each available driver yields a 0...1 penalty measuring how far it sits
//    beyond its comfort threshold. The penalties are combined as a
//    weight-normalized average over ONLY the drivers that are present, so a
//    missing driver neither inflates nor deflates the score. The index is
//    100 * (1 - deficit); the top lever is the present driver with the
//    largest weighted penalty above a small floor.
//
//  Citations for the environmental skin link:
//    Engebretsen et al., 2016, Br J Dermatol (humidity and barrier)
//    Wollenberg et al., 2018, Allergy (environmental triggers)
//

import Foundation

extension SomaTools {

    /// The environmental drivers behind the index, in the order they are
    /// scored. The engine deals only in the abstract feature; the page maps
    /// each to its label, icon and action line.
    nonisolated enum SkinFeature: String, Sendable, CaseIterable, Equatable, Identifiable {
        case uv
        case airQuality
        case wind
        case temperature

        var id: String { rawValue }
    }

    /// Interpretation bands for the 0 to 100 index. Communicated in WORDS with
    /// one accent colour (one vocabulary, not a second colour scale).
    nonisolated enum SkinBand: String, Sendable, Equatable, CaseIterable {
        case calm       // >= 80: barrier friendly day
        case mild       // 60..<80: minor stressors
        case reactive   // 40..<60: notable stress, worth a countermeasure
        case high       // < 40: harsh day for the skin

        init(index: Int) {
            switch index {
            case 80...:     self = .calm
            case 60..<80:   self = .mild
            case 40..<60:   self = .reactive
            default:        self = .high
            }
        }

        /// The index range each band covers, for the scale behind the page's
        /// info button ("80-100" and so on). Highest band first.
        var range: ClosedRange<Int> {
            switch self {
            case .calm:     return 80...100
            case .mild:     return 60...79
            case .reactive: return 40...59
            case .high:     return 0...39
            }
        }

        /// The lowest index still called calm, where a trend chart draws its
        /// dashed reference. Read from the band itself rather than typed as 80,
        /// so a boundary moved here moves the line too.
        static var calmThreshold: Int {
            (0...100).first { SkinBand(index: $0) == .calm } ?? 80
        }
    }

    /// The environmental snapshot fed to the engine. Every field is optional
    /// because a weather source may return any subset (or nothing); the engine
    /// scores over whatever is present and reports empty only when nothing is.
    nonisolated struct SkinEnvironment: Sendable, Equatable {
        var uvIndex: Double?
        var aqi: Int?
        var windKph: Double?
        var temperatureC: Double?
        /// Relative humidity in percent. Carried for display only; not scored
        /// in v1 (see the file header).
        var humidityPercent: Double?

        init(uvIndex: Double? = nil,
             aqi: Int? = nil,
             windKph: Double? = nil,
             temperatureC: Double? = nil,
             humidityPercent: Double? = nil) {
            self.uvIndex = uvIndex
            self.aqi = aqi
            self.windKph = windKph
            self.temperatureC = temperatureC
            self.humidityPercent = humidityPercent
        }

        /// True when no driver the engine scores is present, which is the
        /// page's empty state.
        var hasNoScoredDriver: Bool {
            SkinForecastEngine.reading(for: self) == nil
        }
    }

    /// One day's fully derived reading. Pure value type: every surface renders
    /// it identically, and the math is verifiable on fixtures.
    nonisolated struct SkinForecastReading: Sendable, Equatable {
        /// 0 (harsh) to 100 (calm). Already rounded to a whole score.
        let index: Int
        /// 0...1 combined deficit that produced the index (index = 100*(1-deficit)).
        let deficit: Double
        /// The single driver dragging the index down the most today, if any is
        /// meaningfully beyond comfort. nil on a comfortable day.
        let topLever: SkinFeature?
        /// The environment that produced this reading, so the page can show the
        /// contributing values without recomputing.
        let environment: SkinEnvironment

        var band: SkinBand { SkinBand(index: index) }

        /// One row per driver, in `SkinFeature` order, for the page's rails.
        var drivers: [SkinForecastEngine.Driver] {
            SkinForecastEngine.drivers(for: self)
        }
    }

    nonisolated enum SkinForecastEngine {

        // MARK: - Comfort thresholds (population defaults, v1)

        /// UV index at or below which the sun poses no barrier stress.
        static let uvComfortMax: Double = 3
        /// UV index at which the UV penalty saturates.
        static let uvHarsh: Double = 10

        /// US AQI at or below which air quality is "good".
        static let aqiComfortMax: Double = 50
        /// US AQI at which the air quality penalty saturates.
        static let aqiHarsh: Double = 200

        /// Wind (km/h) at or below which there is no meaningful drying.
        static let windComfortMax: Double = 15
        /// Wind (km/h) at which the wind penalty saturates.
        static let windHarsh: Double = 45

        /// Comfortable temperature band (C). Below the low end the air is cold
        /// and drying; above the high end heat and sweat irritate.
        static let tempComfortLow: Double = 16
        static let tempComfortHigh: Double = 24
        /// Temperature (C) at each end where the penalty saturates.
        static let tempColdHarsh: Double = -5
        static let tempHotHarsh: Double = 35

        /// Relative weights of the drivers. UV and air quality carry the most
        /// weight for barrier and oxidative stress; wind and temperature follow.
        static let weightUV: Double = 0.30
        static let weightAQI: Double = 0.25
        static let weightWind: Double = 0.20
        static let weightTemperature: Double = 0.25

        /// A weighted penalty below this contributes no actionable lever.
        static let leverFloor: Double = 0.05

        /// Weight of one driver in the index.
        static func weight(_ feature: SkinFeature) -> Double {
            switch feature {
            case .uv:          return weightUV
            case .airQuality:  return weightAQI
            case .wind:        return weightWind
            case .temperature: return weightTemperature
            }
        }

        /// The comfortable range of a driver (no penalty inside it) and the
        /// harsh point(s) where the penalty saturates, for the page's "usual
        /// range" line. Temperature is a band, the others a ceiling from zero.
        nonisolated struct ComfortZone: Equatable, Sendable {
            let comfort: ClosedRange<Double>
            /// Saturation below the band (temperature only).
            let harshLow: Double?
            /// Saturation above the band.
            let harshHigh: Double
            let unit: String
        }

        static func comfortZone(_ feature: SkinFeature) -> ComfortZone {
            switch feature {
            case .uv:
                return ComfortZone(comfort: 0...uvComfortMax, harshLow: nil,
                                   harshHigh: uvHarsh, unit: "UV")
            case .airQuality:
                return ComfortZone(comfort: 0...aqiComfortMax, harshLow: nil,
                                   harshHigh: aqiHarsh, unit: "AQI")
            case .wind:
                return ComfortZone(comfort: 0...windComfortMax, harshLow: nil,
                                   harshHigh: windHarsh, unit: "km/h")
            case .temperature:
                return ComfortZone(comfort: tempComfortLow...tempComfortHigh,
                                   harshLow: tempColdHarsh, harshHigh: tempHotHarsh,
                                   unit: "\u{00B0}C")
            }
        }

        // MARK: - Per-driver penalties (0...1)

        /// Penalty from the UV index. Zero at or below the comfort ceiling,
        /// ramping linearly to 1 at the harsh point.
        static func uvPenalty(_ uv: Double) -> Double {
            ramp(uv, from: uvComfortMax, to: uvHarsh)
        }

        /// Penalty from US AQI. Zero for "good" air, ramping to 1 at the harsh point.
        static func aqiPenalty(_ aqi: Double) -> Double {
            ramp(aqi, from: aqiComfortMax, to: aqiHarsh)
        }

        /// Penalty from wind. Zero for calm air, ramping to 1 at the harsh point.
        static func windPenalty(_ wind: Double) -> Double {
            ramp(wind, from: windComfortMax, to: windHarsh)
        }

        /// Penalty from temperature. Zero inside the comfort band; outside it,
        /// the distance beyond the nearer edge ramps to 1 at that end's harsh
        /// point. Cold and hot are symmetric in intent, asymmetric in span.
        static func temperaturePenalty(_ temp: Double) -> Double {
            if temp < tempComfortLow {
                return ramp(tempComfortLow - temp, from: 0, to: tempComfortLow - tempColdHarsh)
            }
            if temp > tempComfortHigh {
                return ramp(temp - tempComfortHigh, from: 0, to: tempHotHarsh - tempComfortHigh)
            }
            return 0
        }

        /// The penalty of one driver in `environment`, nil when that driver is
        /// missing or non-finite. The same ramps the index uses, so the page's
        /// rails and the score cannot disagree.
        static func penalty(_ feature: SkinFeature, in environment: SkinEnvironment) -> Double? {
            switch feature {
            case .uv:
                guard let uv = environment.uvIndex, uv.isFinite else { return nil }
                return uvPenalty(uv)
            case .airQuality:
                guard let aqi = environment.aqi else { return nil }
                return aqiPenalty(Double(aqi))
            case .wind:
                guard let wind = environment.windKph, wind.isFinite else { return nil }
                return windPenalty(wind)
            case .temperature:
                guard let temp = environment.temperatureC, temp.isFinite else { return nil }
                return temperaturePenalty(temp)
            }
        }

        /// The raw value of one driver, nil when missing.
        static func value(_ feature: SkinFeature, in environment: SkinEnvironment) -> Double? {
            switch feature {
            case .uv:          return environment.uvIndex.flatMap { $0.isFinite ? $0 : nil }
            case .airQuality:  return environment.aqi.map(Double.init)
            case .wind:        return environment.windKph.flatMap { $0.isFinite ? $0 : nil }
            case .temperature: return environment.temperatureC.flatMap { $0.isFinite ? $0 : nil }
            }
        }

        // MARK: - Index

        /// Combine the present drivers into a reading. Returns nil only when the
        /// environment carries no usable driver at all (fully empty), so the
        /// page can show an honest empty state rather than a fabricated score.
        static func reading(for environment: SkinEnvironment) -> SkinForecastReading? {
            var weightedPenalties: [(feature: SkinFeature, weighted: Double)] = []
            var totalWeight = 0.0
            var totalWeighted = 0.0

            for feature in SkinFeature.allCases {
                guard let penalty = penalty(feature, in: environment) else { continue }
                let clamped = min(max(penalty, 0), 1)
                let weight = weight(feature)
                let weighted = clamped * weight
                weightedPenalties.append((feature, weighted))
                totalWeight += weight
                totalWeighted += weighted
            }

            guard totalWeight > 0 else { return nil }

            let deficit = totalWeighted / totalWeight
            let index = Int((100 * (1 - deficit)).rounded())
            let clampedIndex = min(max(index, 0), 100)

            let topLever = weightedPenalties
                .filter { $0.weighted > leverFloor }
                .max { $0.weighted < $1.weighted }?
                .feature

            return SkinForecastReading(index: clampedIndex,
                                       deficit: deficit,
                                       topLever: topLever,
                                       environment: environment)
        }

        /// Plain numbers entry point for a weather source that may return any
        /// subset. nil when nothing scored is present (empty state).
        static func reading(uvIndex: Double?,
                            aqi: Int?,
                            windKph: Double?,
                            temperatureC: Double?,
                            humidityPercent: Double? = nil) -> SkinForecastReading? {
            reading(for: SkinEnvironment(uvIndex: uvIndex, aqi: aqi, windKph: windKph,
                                         temperatureC: temperatureC,
                                         humidityPercent: humidityPercent))
        }

        // MARK: - Driver rows

        /// One driver, resolved for display: the rail's fraction, the measured
        /// value, and whether it is today's top lever (the one row that carries
        /// an action line).
        nonisolated struct Driver: Equatable, Sendable, Identifiable {
            let feature: SkinFeature
            /// 0 at or under comfort, 1 at the harsh point, nil when the driver
            /// is missing today. nil draws an empty rail: an unknown reading and
            /// a reading at comfort must not look the same.
            let penalty: Double?
            /// The measured value, nil when missing.
            let value: Double?
            let isTopLever: Bool

            var id: String { feature.rawValue }
        }

        static func drivers(for reading: SkinForecastReading) -> [Driver] {
            SkinFeature.allCases.map { feature in
                Driver(feature: feature,
                       penalty: penalty(feature, in: reading.environment),
                       value: value(feature, in: reading.environment),
                       isTopLever: reading.topLever == feature)
            }
        }

        // MARK: - Helpers

        /// Linear 0...1 ramp: 0 at or below `from`, 1 at or above `to`. Guards a
        /// degenerate span (`to <= from`) by returning 0 below the point and 1
        /// at or above it.
        private static func ramp(_ value: Double, from: Double, to: Double) -> Double {
            guard to > from else { return value >= to ? 1 : 0 }
            return min(max((value - from) / (to - from), 0), 1)
        }
    }
}
