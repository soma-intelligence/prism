//
//  BodyBiomarkers.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// One reading the Body lens lists:
/// its latest value, the last thirty days as a line, where it sits, and what
/// that means (``Insight``).
struct BodyBiomarker: Identifiable, Equatable, Sendable, Codable {
    /// How the status under the name is worked out.
    enum Judgement: Sendable {
        /// Against a band: the healthy zone where the metric has one, else the
        /// person's rolling range (``MetricDetailMath/standing``), the same
        /// word the metric's page shows. Heart, breathing, oxygen.
        case usual
        /// As a direction: increasing, decreasing, stabilizing. Body
        /// composition, where higher or lower is not good or bad by itself.
        case direction
    }

    enum Status: Equatable, Sendable, Codable {
        case normal, above, below
        case increasing, decreasing, stabilizing
        case none
    }

    let id: String
    let title: String
    let unit: String
    /// The latest value, formatted, or nil when Health holds none.
    let value: String?
    /// One value per day, oldest first, nil on a day with no reading.
    var days: [Double?]
    let status: Status
    /// What the days mean: the usual band, the cue, how much it moved.
    var insight: Insight = .empty(.steady)
    /// The few words under the status. Nil when the status says it all.
    var cue: String?
    /// The band the status is read against, drawn behind the sparkline.
    var band: ClosedRange<Double>?
}

/// The readings the Body lens shows and how each is formatted.
enum BodyBiomarkerSpec: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
    // Heart and fitness tiles.
    case vo2Max, restingHeartRate, heartRateVariabilitySDNN, heartRateRecoveryOneMinute, walkingHeartRateAverage
    // Movement tiles.
    case stepCount, appleExerciseTime, activeEnergyBurned, walkingSpeed
    // Walking tiles: what the phone and the watch read off the way you walk.
    case appleWalkingSteadiness, walkingStepLength, walkingAsymmetryPercentage, walkingDoubleSupportPercentage,
         sixMinuteWalkTestDistance, stairAscentSpeed
    // Biomarker rows.
    case bodyMass, bodyFatPercentage, leanBodyMass, bodyMassIndex, bloodPressureSystolic, bloodGlucose,
         respiratoryRate, oxygenSaturation, appleSleepingWristTemperature

    /// The heart and fitness tiles, after fitness age.
    static let tiles: [BodyBiomarkerSpec] = [.vo2Max, .restingHeartRate, .heartRateVariabilitySDNN, .heartRateRecoveryOneMinute, .walkingHeartRateAverage]
    static let movement: [BodyBiomarkerSpec] = [.stepCount, .appleExerciseTime, .activeEnergyBurned, .walkingSpeed]
    static let walking: [BodyBiomarkerSpec] = [.appleWalkingSteadiness, .walkingStepLength, .walkingAsymmetryPercentage,
                                               .walkingDoubleSupportPercentage, .sixMinuteWalkTestDistance, .stairAscentSpeed]
    static let rows: [BodyBiomarkerSpec] = [.bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex, .bloodPressureSystolic, .bloodGlucose, .respiratoryRate, .oxygenSaturation, .appleSleepingWristTemperature]

    /// The readings the interpretation engine knows, which Today reads too.
    static var interpreted: [BodyBiomarkerSpec] { allCases.filter { $0.insight != nil } }

    var identifier: String {
        let raw = rawValue
        switch self {
        case .vo2Max: return "HKQuantityTypeIdentifierVO2Max"
        default: return "HKQuantityTypeIdentifier" + raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    var title: String {
        switch self {
        case .vo2Max: "VO2 max"
        case .restingHeartRate: "Resting heart rate"
        case .heartRateVariabilitySDNN: "HRV"
        case .heartRateRecoveryOneMinute: "Heart rate recovery"
        case .walkingSpeed: "Walking speed"
        case .stepCount: "Steps"
        case .walkingHeartRateAverage: "Walking heart rate"
        case .appleExerciseTime: "Exercise"
        case .activeEnergyBurned: "Active energy"
        case .appleWalkingSteadiness: "Steadiness"
        case .walkingStepLength: "Step length"
        case .walkingAsymmetryPercentage: "Asymmetry"
        case .walkingDoubleSupportPercentage: "Double support"
        case .sixMinuteWalkTestDistance: "Six minute walk"
        case .stairAscentSpeed: "Stair speed"
        case .bodyMass: "Weight"
        case .bodyFatPercentage: "Body fat"
        case .leanBodyMass: "Lean body mass"
        case .bodyMassIndex: "BMI"
        case .bloodPressureSystolic: "Blood pressure"
        case .bloodGlucose: "Blood glucose"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Blood oxygen"
        case .appleSleepingWristTemperature: "Wrist temperature"
        }
    }

    var unit: String {
        switch self {
        case .vo2Max: "ml/kg/min"
        case .restingHeartRate, .heartRateRecoveryOneMinute, .walkingHeartRateAverage: "bpm"
        case .appleExerciseTime: "min"
        case .activeEnergyBurned: "kcal"
        case .appleWalkingSteadiness, .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage: "%"
        case .walkingStepLength: "cm"
        case .sixMinuteWalkTestDistance: "m"
        case .stairAscentSpeed: "m/s"
        case .heartRateVariabilitySDNN: "ms"
        case .walkingSpeed: "km/h"
        case .stepCount: "steps"
        case .bodyMass, .leanBodyMass: "kg"
        case .bodyFatPercentage, .oxygenSaturation: "%"
        case .bodyMassIndex: ""
        case .bloodPressureSystolic: "mmHg"
        case .bloodGlucose: "mg/dL"
        case .respiratoryRate: "rpm"
        case .appleSleepingWristTemperature: "°C"
        }
    }

    var decimals: Int {
        switch self {
        case .bodyMass, .leanBodyMass, .bodyFatPercentage, .bodyMassIndex, .respiratoryRate, .walkingSpeed,
             .vo2Max, .oxygenSaturation:
            1
        case .appleSleepingWristTemperature, .stairAscentSpeed: 2
        default: 0
        }
    }

    /// Health's canonical value into what the row shows: a fraction into a
    /// percent, metres a second into km/h.
    func display(_ value: Double) -> Double {
        switch self {
        case .bodyFatPercentage, .oxygenSaturation, .appleWalkingSteadiness, .walkingAsymmetryPercentage,
             .walkingDoubleSupportPercentage: value * 100
        case .walkingSpeed: value * 3.6
        case .walkingStepLength: value * 100
        default: value
        }
    }

    var judgement: BodyBiomarker.Judgement {
        switch self {
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex, .vo2Max, .stepCount, .walkingSpeed,
             .appleExerciseTime, .activeEnergyBurned, .walkingStepLength, .sixMinuteWalkTestDistance, .stairAscentSpeed:
            .direction
        default: .usual
        }
    }

    /// Steps, exercise minutes and active energy add up over a day;
    /// everything else is a mean of the day.
    var sumsPerDay: Bool { [.stepCount, .appleExerciseTime, .activeEnergyBurned].contains(self) }

    /// Its category's hue, for its line: never ink alone.
    var hue: SomaHealthHue {
        if let insight { return insight.hue }
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return .other }
        return BodyCategory.containing(BodyDataType(metric))?.hue ?? .other
    }

    /// How the engine judges it: the one table's policy, the same the
    /// metric's page reads.
    var policy: InsightPolicy {
        insight?.policy ?? MetricProfile.of(identifier).policy
            ?? InsightPolicy(preference: .steady, minimumSpread: 0, trendStep: 0)
    }

    /// The metric the interpretation engine reads it as; nil for the
    /// walking and movement readings it does not rank.
    var insight: InsightMetric? {
        switch self {
        case .vo2Max: .vo2Max
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariabilitySDNN: .heartRateVariability
        case .heartRateRecoveryOneMinute: .heartRateRecovery
        case .walkingSpeed: .walkingSpeed
        case .stepCount: .steps
        case .bodyMass: .weight
        case .bodyFatPercentage: .bodyFat
        case .leanBodyMass: .leanMass
        case .bodyMassIndex: .bodyMassIndex
        case .bloodPressureSystolic: .bloodPressure
        case .bloodGlucose: .bloodGlucose
        case .respiratoryRate: .respiratoryRate
        case .oxygenSaturation: .bloodOxygen
        case .appleSleepingWristTemperature: .wristTemperature
        case .walkingHeartRateAverage, .appleExerciseTime, .activeEnergyBurned, .appleWalkingSteadiness, .walkingStepLength,
             .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage, .sixMinuteWalkTestDistance, .stairAscentSpeed:
            nil
        }
    }

    /// The spec a metric is read through, nil for sleep, which is read as
    /// nights rather than samples.
    init?(_ metric: InsightMetric) {
        guard let spec = Self.allCases.first(where: { $0.insight == metric }) else { return nil }
        self = spec
    }

    func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }
}

enum BodyBiomarkers {
    static let days = 30
    /// The usual is read over the days before the last week.
    static let lookback = 90

    static var metrics: [String] { BodyBiomarkerSpec.allCases.map(\.identifier) }

    /// Reads ninety days of every reading in `specs` at once.
    static func read(
        _ specs: [BodyBiomarkerSpec] = BodyBiomarkerSpec.allCases,
        from source: any HealthSampleSource,
        now: Date,
        calendar: Calendar
    ) async -> [BodyBiomarkerSpec: [HealthReading]] {
        let start = calendar.date(byAdding: .day, value: -lookback, to: calendar.startOfDay(for: now)) ?? now
        return await withTaskGroup(of: (BodyBiomarkerSpec, [HealthReading]).self) { group in
            for spec in specs {
                group.addTask { (spec, await read(spec, from: source, start: start, now: now, calendar: calendar)) }
            }
            var result: [BodyBiomarkerSpec: [HealthReading]] = [:]
            for await (spec, readings) in group { result[spec] = readings }
            return result
        }
    }

    /// How far back a sparse reading looks for something to draw: a weight
    /// or a blood pressure logged once a month still gets a line.
    static let sparseLookback = 365

    /// The markers whose month holds fewer than two readings, given a year
    /// of their days instead, so their row draws a line rather than nothing.
    static func filledSparse(
        _ markers: [BodyBiomarkerSpec: BodyBiomarker], from source: any HealthSampleSource, now: Date, calendar: Calendar
    ) async -> [BodyBiomarkerSpec: BodyBiomarker] {
        var result = markers
        let sparse = markers.filter { $0.value.days.compactMap { $0 }.count < 2 && $0.value.value != nil }.map(\.key)
        guard !sparse.isEmpty else { return result }
        let start = calendar.date(byAdding: .day, value: -sparseLookback, to: calendar.startOfDay(for: now)) ?? now
        await withTaskGroup(of: (BodyBiomarkerSpec, [Double?]).self) { group in
            for spec in sparse {
                group.addTask {
                    let readings = await read(spec, from: source, start: start, now: now, calendar: calendar)
                    return (spec, daily(spec, readings: readings, days: sparseLookback, now: now, calendar: calendar))
                }
            }
            for await (spec, days) in group where days.compactMap({ $0 }).count > (result[spec]?.days.compactMap { $0 }.count ?? 0) {
                result[spec]?.days = days
            }
        }
        return result
    }

    /// Reads ninety days of one reading.
    static func read(_ spec: BodyBiomarkerSpec, from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> [HealthReading] {
        let start = calendar.date(byAdding: .day, value: -lookback, to: calendar.startOfDay(for: now)) ?? now
        return await read(spec, from: source, start: start, now: now, calendar: calendar)
    }

    private static func read(_ spec: BodyBiomarkerSpec, from source: any HealthSampleSource, start: Date, now: Date, calendar: Calendar) async -> [HealthReading] {
        guard let metric = HealthMetricCatalog.metric(for: spec.identifier) else { return [] }
        if spec.sumsPerDay {
            return await dailyTotals(metric, from: start, to: now, calendar: calendar, in: source)
        }
        return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
    }

    /// One reading per day holding Health's own total for it, oldest first,
    /// with nothing for a day that has none.
    ///
    /// For a reading that adds up, such as steps: ninety days of raw samples
    /// from a phone and a watch run to tens of thousands, each one fetched and
    /// then bucketed on the main actor before a tile can draw, and summed as
    /// they come they count a step twice when both devices took it. Health's
    /// statistics merge the sources the way the Health app does, and the
    /// source reads every day in one query (one statistics collection on the
    /// real store) rather than one query a day.
    static func dailyTotals(
        _ metric: HealthMetric,
        from start: Date,
        to now: Date,
        calendar: Calendar,
        in source: any HealthSampleSource
    ) async -> [HealthReading] {
        let days = (try? await source.dailyTotals(metric, from: start, to: now, calendar: calendar)) ?? []
        return days.map { day in
            // Dated inside its own day, so the daily buckets file it there and
            // not under the midnight it ends on.
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day.start)) ?? now
            let end = min(next.addingTimeInterval(-1), now)
            return HealthReading(metric: day.metric, value: day.value, unit: day.unit, start: day.start, end: end)
        }
        .sorted { $0.end < $1.end }
    }

    static func make(_ spec: BodyBiomarkerSpec, readings: [HealthReading], now: Date, calendar: Calendar) -> BodyBiomarker {
        let all = daily(spec, readings: readings, days: lookback, now: now, calendar: calendar)
        let recent = Array(all.suffix(days))
        let latest = readings.max(by: { $0.end < $1.end }).map { spec.display($0.value) }
        let shownLatest = spec.sumsPerDay ? recent.last.flatMap { $0 } ?? recent.compactMap { $0 }.last : latest
        let insight = spec.insight.map { InsightEngine.interpret($0, days: all) }
            ?? InsightEngine.interpret(all, policy: spec.policy)
        let standing = MetricDetailMath.standing(all, profile: MetricProfile.of(spec.identifier))
        return BodyBiomarker(
            id: spec.rawValue,
            title: spec.title,
            unit: spec.unit,
            value: shownLatest.map(spec.format),
            days: recent,
            status: status(spec, all: all, insight: insight, latest: shownLatest),
            insight: insight,
            cue: shownLatest == nil ? nil : cue(spec, insight: insight),
            band: standing.band
        )
    }

    /// The engine's cue, except where the status already names the month's
    /// direction ("Increasing"): there the cue says by how much instead.
    static func cue(_ spec: BodyBiomarkerSpec, insight: Insight) -> String? {
        guard spec.judgement == .direction, insight.cueKind == .trend || insight.cueKind == nil else { return insight.cue }
        guard let change = insight.change, insight.direction == .rising || insight.direction == .falling else { return nil }
        let unit = spec.unit.isEmpty ? "" : " \(spec.unit)"
        return "\(change > 0 ? "Up" : "Down") \(spec.format(abs(change)))\(unit) in 30 days"
    }

    /// One value per calendar day over `days`, oldest first.
    static func daily(_ spec: BodyBiomarkerSpec, readings: [HealthReading], days: Int, now: Date, calendar: Calendar) -> [Double?] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Int: [Double]] = [:]
        for reading in readings {
            let day = calendar.startOfDay(for: reading.end)
            guard let offset = calendar.dateComponents([.day], from: day, to: today).day,
                  offset >= 0, offset < days else { continue }
            buckets[offset, default: []].append(spec.display(reading.value))
        }
        return (0..<days).reversed().map { offset in
            guard let values = buckets[offset], !values.isEmpty else { return nil }
            let total = values.reduce(0, +)
            return spec.sumsPerDay ? total : total / Double(values.count)
        }
    }

    static func status(_ spec: BodyBiomarkerSpec, all: [Double?], latest: Double?) -> BodyBiomarker.Status {
        let insight = spec.insight.map { InsightEngine.interpret($0, days: all) } ?? InsightEngine.interpret(all, policy: spec.policy)
        return status(spec, all: all, insight: insight, latest: latest)
    }

    /// The word under the name: where the latest reading sits against its
    /// band (as its page says it), or for body composition the month's
    /// direction.
    static func status(_ spec: BodyBiomarkerSpec, all: [Double?], insight: Insight, latest: Double?) -> BodyBiomarker.Status {
        guard latest != nil else { return .none }
        switch spec.judgement {
        case .usual:
            guard all.compactMap({ $0 }).count >= 3 else { return .none }
            switch MetricDetailMath.standing(all, profile: MetricProfile.of(spec.identifier)).status {
            case .normal: return .normal
            case .above: return .above
            case .below: return .below
            case .direction, .none: return .none
            }
        case .direction:
            switch insight.direction {
            case .rising: return .increasing
            case .falling: return .decreasing
            case .steady: return .stabilizing
            case nil: return .none
            }
        }
    }
}
