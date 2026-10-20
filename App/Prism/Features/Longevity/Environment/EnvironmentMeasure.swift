//
//  EnvironmentMeasure.swift
//  Prism
//

import SwiftUI
import SomaUI
import HealthExportCore

/// One thing the Environment lens measures, with everything a card and its
/// detail sheet need to draw it: the scale it is coloured on, the limit it is
/// read against, its last thirty days and the word for where it stands.
enum EnvironmentMeasure: String, Identifiable, CaseIterable {
    case daylight
    case uv
    case air
    case temperature
    case sound
    case headphones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight: "Daylight"
        case .uv: "UV index"
        case .air: "Air quality"
        case .temperature: "Temperature"
        case .sound: "Around you"
        case .headphones: "Headphones"
        }
    }

    var unit: String {
        switch self {
        case .daylight: "min"
        case .uv: ""
        case .air: "AQI"
        case .temperature: "°C"
        case .sound, .headphones: "dB"
        }
    }

    var symbol: String {
        switch self {
        case .daylight: "sun.max.fill"
        case .uv: "sun.max.trianglebadge.exclamationmark.fill"
        case .air: "aqi.medium"
        case .temperature: "thermometer.medium"
        case .sound: "ear.fill"
        case .headphones: "headphones"
        }
    }

    var scale: SomaDataScale {
        switch self {
        case .daylight: .daylight
        case .uv: .uvIndex
        case .air: .airQuality
        case .temperature: .temperature
        case .sound, .headphones: .soundLevel
        }
    }

    var barStyle: SomaScaleBar.Style {
        switch self {
        case .daylight, .sound, .headphones: .level
        case .uv, .air, .temperature: .scale
        }
    }

    /// The line a level is read against: Apple's 80 dB for headphones held
    /// over a week, and 70 dB around you, where the WHO starts counting harm
    /// over a day.
    var limit: Double? {
        switch self {
        case .sound: 70
        case .headphones: EnvironmentReport.headphoneLimit
        default: nil
        }
    }

    /// The numbers written under the scale bar.
    var ticks: [Double] {
        switch self {
        case .daylight: [0, 30, 60, 120]
        case .uv: [0, 3, 6, 8, 11]
        case .air: [0, 50, 100, 150, 200, 300]
        case .temperature: [-10, 0, 10, 20, 30, 40]
        case .sound: [30, 70, 100]
        case .headphones: [30, 80, 100]
        }
    }

    /// The Apple Health type behind it, for the Vault; nil where Health
    /// holds none.
    var identifier: String? {
        switch self {
        case .daylight: EnvironmentInputs.Metric.daylight
        case .uv: EnvironmentInputs.Metric.uv
        case .sound: EnvironmentInputs.Metric.sound
        case .headphones: EnvironmentInputs.Metric.headphones
        case .air, .temperature: nil
        }
    }

    var metric: HealthMetric? { identifier.flatMap(HealthMetricCatalog.metric(for:)) }

    /// The headline value: today, or the week for headphones.
    func current(_ report: EnvironmentReport) -> Double? {
        switch self {
        case .daylight: report.daylight
        case .uv: report.uvNow ?? report.outside?.uv
        case .sound: report.sound
        case .headphones: report.headphones
        case .air: report.outside?.aqi
        case .temperature: report.outside?.temperature
        }
    }

    /// Thirty days, oldest first.
    func days(_ report: EnvironmentReport) -> [Double?] {
        switch self {
        case .daylight: report.daylightDays
        case .uv: report.uvDays.contains { $0 != nil } ? report.uvDays : Array((report.outside?.uvDays ?? []).suffix(30))
        case .sound: report.soundDays
        case .headphones: report.headphoneDays
        case .air: Array((report.outside?.aqiDays ?? []).suffix(30))
        case .temperature: Array((report.outside?.highDays ?? []).suffix(30))
        }
    }

    /// The usual band, where there is one.
    func band(_ report: EnvironmentReport) -> ClosedRange<Double>? {
        switch self {
        case .daylight: report.daylightUsual
        case .sound: report.soundUsual
        default: nil
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .uv: value.formatted(.number.precision(.fractionLength(0...1)))
        default: "\(Int(value.rounded()))"
        }
    }

    /// Where a value stands, in a word or two, and its colour.
    func status(_ value: Double?, report: EnvironmentReport, colors: SomaColors) -> (word: String, color: Color)? {
        guard let value else { return nil }
        switch self {
        case .daylight:
            guard let usual = report.daylightUsual else { return nil }
            if value < usual.lowerBound { return ("Below usual", colors.statusOut.color) }
            if value > usual.upperBound { return ("Above usual", colors.statusNormal.color) }
            return ("Usual", colors.statusNormal.color)
        case .uv:
            let word = switch value {
            case ..<3: "Low"
            case ..<6: "Moderate"
            case ..<8: "High"
            case ..<11: "Very high"
            default: "Extreme"
            }
            return (word, scale.value(at: value).color)
        case .air:
            let word = switch value {
            case ...50: "Good"
            case ...100: "Moderate"
            case ...150: "Sensitive groups"
            case ...200: "Unhealthy"
            case ...300: "Very unhealthy"
            default: "Hazardous"
            }
            return (word, scale.value(at: value).color)
        case .temperature:
            let word = switch value {
            case ..<5: "Cold"
            case ..<15: "Cool"
            case ..<24: "Mild"
            case ..<30: "Warm"
            default: "Hot"
            }
            return (word, scale.value(at: value).color)
        case .sound, .headphones:
            let line = limit ?? 80
            if value >= line + 5 { return ("Too loud", colors.statusAlert.color) }
            if value >= line { return ("Over limit", colors.statusOut.color) }
            return ("Safe", colors.statusNormal.color)
        }
    }
}

/// The sun's day where you are, worked out on the device.
struct EnvironmentSky: Equatable {
    var now: Date
    var day: EnvironmentSun.Day?
    var place: EnvironmentSun.Place?

    func rise(_ words: PulseWording) -> String? { day.map { words.time($0.rise) } }
    func set(_ words: PulseWording) -> String? { day.map { words.time($0.set) } }

    static func make(now: Date, place: EnvironmentSun.Place?, calendar: Calendar = .current) -> EnvironmentSky {
        EnvironmentSky(
            now: now,
            day: place.flatMap { EnvironmentSun.day(for: now, latitude: $0.latitude, longitude: $0.longitude, calendar: calendar) },
            place: place
        )
    }
}

/// The bedroom as the Sleep environment sheet keeps it, read for the card.
struct EnvironmentBedroom: Equatable {
    /// The outdoor temperature over last night, where you slept.
    var outdoor: Double?
    /// Last night's average sound, in dBA.
    var noise: Double?
    /// Degrees Celsius, as the person set it.
    var temperature: Double?
    var isDark: Bool?
    /// Where last night was slept, as set by hand.
    var place: String?
}

/// One place slept in over the last thirty days, for the Sleep places map.
struct EnvironmentSleepPlace: Identifiable, Equatable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var nights: Int
    /// The average sleep score of those nights.
    var score: Double?
    var isLastNight: Bool

    /// Groups thirty nights by place. `scores` runs oldest first and ends
    /// today, as ``SomaScores`` keeps them.
    @MainActor
    static func make(store: SleepPlaceStore, scores: [Double?], now: Date, calendar: Calendar = .current) -> [EnvironmentSleepPlace] {
        let today = calendar.startOfDay(for: now)
        let byNight = Array(scores.reversed())
        var groups: [String: (place: SleepPlaceStore.Place, scores: [Double])] = [:]
        var nights: [String: Int] = [:]
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let place = store.place(forNightEnding: day) else { continue }
            nights[place.id, default: 0] += 1
            var group = groups[place.id] ?? (place, [])
            if byNight.indices.contains(offset), let score = byNight[offset] { group.scores.append(score) }
            groups[place.id] = group
        }
        let last = store.place(forNightEnding: today)?.id
        return groups.map { id, group in
            EnvironmentSleepPlace(
                id: id, name: group.place.name,
                latitude: group.place.latitude, longitude: group.place.longitude,
                nights: nights[id] ?? 0,
                score: group.scores.isEmpty ? nil : group.scores.reduce(0, +) / Double(group.scores.count),
                isLastNight: id == last
            )
        }
        .sorted { $0.nights > $1.nights }
    }
}
