//
//  EnvironmentWeek.swift
//  Prism
//

import Foundation
import HealthExportCore

/// The last seven days around you, today included: daylight against its
/// target, the days the sound around you reached 80 dB, how much of the
/// WHO's weekly headphone allowance was used, the UV and the air, and
/// today's pollen.
///
/// Daylight, sound, headphones and UV come from Apple Health
/// (``EnvironmentInputs``); the air, the UV when Health holds none, and the
/// pollen from Open-Meteo (``EnvironmentConditions``). Each figure is nil
/// when nothing was recorded, which the card draws as a dash, never as zero.
/// Informative only: nothing here is a diagnosis.
nonisolated struct EnvironmentWeek: Equatable, Codable, Sendable {
    /// Seven days of minutes in daylight, oldest first and today last, nil
    /// where nothing was recorded.
    var daylightMinutes: [Double?]
    /// Days that reached the bottom of ``daylightTarget``.
    var daylightDaysReached: Int
    /// The week's minutes in daylight, nil when no day recorded any.
    var daylightTotal: Double?
    /// Days whose loudest reading around you reached ``loudLevel``.
    var loudDays: Int?
    /// The share of the WHO's weekly headphone allowance used, 1 for all of
    /// it. Over 1 is over the allowance.
    var headphoneDoseShare: Double?
    /// The week's daily UV peaks added up.
    var uvTotal: Double?
    /// Days whose highest US AQI was over ``unhealthyAir``, and the highest.
    var unhealthyAirDays: Int?
    var airPeak: Double?
    /// Today's strongest pollen, nil without a forecast for where you are.
    var pollenPeak: PollenPeak?

    static let days = 7

    /// Minutes in daylight a day aims for. 30 is the day outside the report
    /// already counts (``EnvironmentReport/outsideMinutes``); 120 is the two
    /// hours outdoors a day that school trials against myopia set as their
    /// goal. More than that is fine: the band marks a goal, not a limit.
    static let daylightTarget: ClosedRange<Double> = 30...120

    /// A loud day: 80 dBA around you, the level Apple's Noise app warns at
    /// and the reference level of the WHO's safe listening standard.
    static let loudLevel: Double = 80

    /// WHO-ITU H.870 (2019), safe listening for adults: 1.6 Pa²h a week,
    /// which is 80 dBA for 40 hours. The dose is energy, so every 3 dB more
    /// halves the time.
    static let headphoneReference: Double = 80
    static let headphoneWeekHours: Double = 40

    /// US EPA: over 100 the air is unhealthy for sensitive groups.
    static let unhealthyAir: Double = 100

    /// Folds `inputs` into one week ending on the day of `now`, then lays
    /// `outside` over it. Several reads fold together, one per day as a
    /// test writes them; the lens passes the one it made.
    static func make(
        inputs: [EnvironmentInputs],
        outside: EnvironmentConditions? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> EnvironmentWeek {
        let today = calendar.startOfDay(for: now)
        let days = (0..<Self.days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let start = days.first ?? today

        // Daylight: the per day totals Health worked out, today from its
        // stretches outside when the total is not in yet.
        var byDay: [Date: Double] = [:]
        for input in inputs {
            byDay.merge(input.daylightByDay) { max($0, $1) }
        }
        let todaySpans = unique(inputs.flatMap(\.daylightToday)).filter { $0.start >= today }.map(\.value)
        let minutes = days.map { day in
            day == today ? (byDay[today] ?? (todaySpans.isEmpty ? nil : todaySpans.reduce(0, +))) : byDay[day]
        }
        let recorded = minutes.compactMap { $0 }

        // Sound around you, by the day each reading started.
        let sound = unique(inputs.flatMap(\.sound)).filter { $0.start >= start && $0.start <= now }
        let loudest = Dictionary(grouping: sound) { calendar.startOfDay(for: $0.start) }
            .compactMapValues { $0.map(\.value).max() }

        // Headphones: each reading's hours weighed by its energy against
        // 80 dBA, over the 40 hours the week allows.
        let headphones = unique(inputs.flatMap(\.headphones)).filter { $0.start >= start && $0.start <= now }
        let dose = headphones.reduce(0) { sum, reading in
            let hours = max(0, reading.end.timeIntervalSince(reading.start)) / 3600
            return sum + hours * pow(10, (reading.value - headphoneReference) / 10)
        }

        // UV: each day's highest index.
        let uv = unique(inputs.flatMap(\.uv)).filter { $0.start >= start && $0.start <= now }
        let uvPeaks = Dictionary(grouping: uv) { calendar.startOfDay(for: $0.start) }
            .compactMapValues { $0.map(\.value).max() }

        let week = EnvironmentWeek(
            daylightMinutes: minutes,
            daylightDaysReached: recorded.count { $0 >= daylightTarget.lowerBound },
            daylightTotal: recorded.isEmpty ? nil : recorded.reduce(0, +),
            loudDays: sound.isEmpty ? nil : loudest.values.count { $0 >= loudLevel },
            headphoneDoseShare: headphones.isEmpty ? nil : dose / headphoneWeekHours,
            uvTotal: uvPeaks.isEmpty ? nil : uvPeaks.values.reduce(0, +),
            unhealthyAirDays: nil,
            airPeak: nil,
            pollenPeak: nil
        )
        return week.laying(outside)
    }

    /// The week with the weather where you are laid in: the air of the last
    /// seven days, the forecast's UV when Health holds none, and today's
    /// pollen. Nil conditions leave those figures nil.
    func laying(_ outside: EnvironmentConditions?) -> EnvironmentWeek {
        var week = self
        let air = (outside?.aqiDays ?? []).suffix(Self.days).compactMap { $0 }
        week.unhealthyAirDays = air.isEmpty ? nil : air.count { $0 > Self.unhealthyAir }
        week.airPeak = air.max()
        if week.uvTotal == nil {
            let forecast = (outside?.uvDays ?? []).suffix(Self.days).compactMap { $0 }
            week.uvTotal = forecast.isEmpty ? nil : forecast.reduce(0, +)
        }
        week.pollenPeak = outside?.pollen.flatMap(PollenPeak.strongest)
        return week
    }

    /// An empty week, for a lens that has read nothing yet.
    static func empty(now: Date, calendar: Calendar = .current) -> EnvironmentWeek {
        make(inputs: [], now: now, calendar: calendar)
    }

    /// Two reads of one span hold the same samples once.
    private static func unique(_ readings: [HealthReading]) -> [HealthReading] {
        var seen: Set<String> = []
        return readings.filter { seen.insert("\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)|\($0.value)").inserted }
    }
}

// MARK: - Pollen

/// The six pollens Open-Meteo forecasts (CAMS, Europe only), in grains per
/// cubic metre.
nonisolated enum PollenKind: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case grass, birch, ragweed, alder, mugwort, olive

    /// Which of the National Allergy Bureau's scales it is read on.
    enum Group { case tree, grass, weed }

    var group: Group {
        switch self {
        case .birch, .alder, .olive: .tree
        case .grass: .grass
        case .ragweed, .mugwort: .weed
        }
    }

    var title: String {
        switch self {
        case .grass: "Grass"
        case .birch: "Birch"
        case .ragweed: "Ragweed"
        case .alder: "Alder"
        case .mugwort: "Mugwort"
        case .olive: "Olive"
        }
    }

    /// The service's hourly field.
    var field: String { "\(rawValue)_pollen" }
}

/// A pollen count as a level, on the steps the AAAAI's National Allergy
/// Bureau publishes for each group, in grains per cubic metre.
nonisolated enum PollenLevel: Int, Comparable, Codable, Sendable {
    case none, low, moderate, high, veryHigh

    static func < (a: PollenLevel, b: PollenLevel) -> Bool { a.rawValue < b.rawValue }

    /// The counts where low, moderate, high and very high begin. NAB: trees
    /// 1, 15, 90, 1500; grass 1, 5, 20, 200; weeds 1, 10, 50, 500.
    static func steps(_ group: PollenKind.Group) -> [Double] {
        switch group {
        case .tree: [1, 15, 90, 1500]
        case .grass: [1, 5, 20, 200]
        case .weed: [1, 10, 50, 500]
        }
    }

    static func level(_ kind: PollenKind, grains: Double) -> PollenLevel {
        let reached = steps(kind.group).count { grains >= $0 }
        return PollenLevel(rawValue: reached) ?? .veryHigh
    }

    var word: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        case .veryHigh: "Very high"
        }
    }
}

/// Today's strongest pollen: its kind, its count and its level.
nonisolated struct PollenPeak: Equatable, Codable, Sendable {
    var kind: PollenKind
    var grains: Double
    var level: PollenLevel

    /// The kind at the highest level; between two at one level, the one
    /// furthest towards its own high step.
    static func strongest(_ counts: [PollenKind: Double]) -> PollenPeak? {
        counts
            .map { PollenPeak(kind: $0.key, grains: $0.value, level: PollenLevel.level($0.key, grains: $0.value)) }
            .max { a, b in
                if a.level != b.level { return a.level < b.level }
                if a.reach != b.reach { return a.reach < b.reach }
                return a.kind.rawValue > b.kind.rawValue
            }
    }

    /// The count as a share of its kind's high step.
    private var reach: Double { grains / PollenLevel.steps(kind.group)[2] }
}
