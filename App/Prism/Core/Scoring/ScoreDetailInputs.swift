//
//  ScoreDetailInputs.swift
//  Prism
//

import Foundation
import HealthExportCore
import HealthScoring

/// What the score pages read from Apple Health beyond ``SomaScores``: the
/// nights as windows, each night's heart rate, breathing, wrist temperature
/// and sound, today's heart rate and workouts, and a month of HRV and resting
/// heart rate to draw a usual band from.
///
/// A page names the parts it needs, and only those are read. Every series is
/// thirty days, oldest first, ending today, nil where the store holds
/// nothing: a night without a reading is a gap, never a zero.
nonisolated struct ScoreDetailInputs: Sendable, Equatable {
    /// What a page can ask for.
    enum Part: Sendable, Hashable, CaseIterable {
        /// Nights as windows, from the sleep samples.
        case nights
        /// Daily HRV and resting heart rate.
        case heart
        /// Each night's mean heart rate, and last night's beats.
        case nightHeart
        /// Each night's breathing rate and wrist temperature.
        case breathing
        /// Each night's mean sound level.
        case sound
        /// Today's heart rate, workouts, steps, energy and stand hours.
        case today
        /// Heart rate recovery one minute after exercise.
        case heartRecovery
    }

    /// Days in every series.
    static let days = 30

    var now: Date
    var nights: [ScoringNightWindow?] = []
    /// When last night's time in bed began, where a tracker wrote it.
    var inBedStart: Date?
    var hrv: [Double?] = []
    var resting: [Double?] = []
    var nightHeartRate: [Double?] = []
    var lastNightBeats: [ScoringTimedValue] = []
    var respiratory: [Double?] = []
    var wristTemperature: [Double?] = []
    var nightSound: [Double?] = []
    var todayHeartRate: [ScoringTimedValue] = []
    /// Workouts over the last seven days: the activity code and the span.
    var workouts: [HealthReading] = []
    var steps: Double?
    var activeEnergy: Double?
    var standHours: Int?
    var heartRecovery: [Double?] = []
    var age: Double?

    enum Metric {
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
        static let heartRate = "HKQuantityTypeIdentifierHeartRate"
        static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
        static let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let respiratory = "HKQuantityTypeIdentifierRespiratoryRate"
        static let wristTemperature = "HKQuantityTypeIdentifierAppleSleepingWristTemperature"
        static let sound = "HKQuantityTypeIdentifierEnvironmentalAudioExposure"
        static let steps = "HKQuantityTypeIdentifierStepCount"
        static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
        static let standHour = "HKCategoryTypeIdentifierAppleStandHour"
        static let workout = "HKWorkoutTypeIdentifier"
        static let heartRecovery = "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
        static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
    }

    /// The metrics to ask for before reading `parts`.
    static func metrics(for parts: Set<Part>) -> [String] {
        var out: Set<String> = [Metric.sleep]
        for part in parts {
            switch part {
            case .nights: break
            case .heart: out.formUnion([Metric.hrv, Metric.restingHeartRate])
            case .nightHeart: out.formUnion([Metric.heartRate, Metric.restingHeartRate])
            case .breathing: out.formUnion([Metric.respiratory, Metric.wristTemperature])
            case .sound: out.insert(Metric.sound)
            case .today:
                out.formUnion([Metric.heartRate, Metric.steps, Metric.activeEnergy, Metric.standHour,
                               Metric.workout, Metric.dateOfBirth])
            case .heartRecovery: out.insert(Metric.heartRecovery)
            }
        }
        return out.sorted()
    }

    /// Nights with a night in them, oldest first.
    var recordedNights: [ScoringNightWindow] { nights.compactMap { $0 } }

    /// Reads `parts` from `source`. A read that fails leaves its series
    /// empty, and the page renders its dash.
    @concurrent
    static func read(_ parts: Set<Part>, from source: any HealthSampleSource, now: Date,
                     calendar: Calendar) async -> ScoreDetailInputs {
        var inputs = ScoreDetailInputs(now: now)
        let starts = SomaScoresReader.dayStarts(days: days, now: now, calendar: calendar)
        guard let first = starts.first else { return inputs }

        @Sendable func samples(_ identifier: String, from start: Date, to end: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: end, limit: 0)) ?? []
        }
        @Sendable func average(_ identifier: String, _ window: ScoringNightWindow?) async -> Double? {
            guard let window, let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
            return (try? await source.average(metric, from: window.start, to: window.end))?.value
        }

        // Nights come first: most of the rest is read over them.
        let sleepFrom = calendar.date(byAdding: .hour, value: -18, to: first) ?? first
        let sleepReadings = await samples(Metric.sleep, from: sleepFrom, to: now)
        let sleepSamples = sleepReadings.compactMap {
            ScoringSleepSample(code: Int($0.value), start: $0.start, end: $0.end, source: $0.source)
        }
        inputs.nights = SomaScoringEngine.nightWindows(from: sleepSamples, days: days, now: now, calendar: calendar)
        if let last = inputs.nights.last ?? nil {
            // The in bed wrapper (code 0) is what a tracker writes when the
            // person got into bed, before the first stage.
            inputs.inBedStart = sleepReadings
                .filter { Int($0.value) == 0 && $0.end > last.start.addingTimeInterval(-3 * 3600) && $0.start <= last.start }
                .map(\.start).min()
        }
        let nights = inputs.nights

        if parts.contains(.heart) {
            async let hrv = samples(Metric.hrv, from: first, to: now)
            async let resting = samples(Metric.restingHeartRate, from: first, to: now)
            inputs.hrv = SomaScoresReader.dailyMeans(await hrv, dayStarts: starts, calendar: calendar)
            inputs.resting = SomaScoresReader.dailyMeans(await resting, dayStarts: starts, calendar: calendar)
        }

        if parts.contains(.nightHeart) {
            inputs.nightHeartRate = await perNight(nights) { await average(Metric.heartRate, $0) }
            if let last = nights.last ?? nil {
                inputs.lastNightBeats = await samples(Metric.heartRate, from: last.start, to: last.end)
                    .map { ScoringTimedValue(start: $0.start, end: $0.end, value: $0.value) }
                    .sorted { $0.start < $1.start }
            }
            if !parts.contains(.heart) {
                let resting = await samples(Metric.restingHeartRate, from: first, to: now)
                inputs.resting = SomaScoresReader.dailyMeans(resting, dayStarts: starts, calendar: calendar)
            }
        }

        if parts.contains(.breathing) {
            async let breathing = samples(Metric.respiratory, from: sleepFrom, to: now)
            async let temperature = samples(Metric.wristTemperature, from: sleepFrom, to: now)
            inputs.respiratory = byNight(await breathing, nights: nights)
            inputs.wristTemperature = byNight(await temperature, nights: nights)
        }

        if parts.contains(.sound) {
            inputs.nightSound = await perNight(nights) { await average(Metric.sound, $0) }
        }

        if parts.contains(.today) {
            let today = calendar.startOfDay(for: now)
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            async let heartRate = samples(Metric.heartRate, from: today, to: now)
            async let workouts = samples(Metric.workout, from: weekAgo, to: now)
            async let stand = samples(Metric.standHour, from: today, to: now)
            async let birth = latest(Metric.dateOfBirth, in: source)
            if let metric = HealthMetricCatalog.metric(for: Metric.steps) {
                inputs.steps = (try? await source.total(metric, from: today, to: now))?.value
            }
            if let metric = HealthMetricCatalog.metric(for: Metric.activeEnergy) {
                inputs.activeEnergy = (try? await source.total(metric, from: today, to: now))?.value
            }
            inputs.todayHeartRate = await heartRate
                .map { ScoringTimedValue(start: $0.start, end: $0.end, value: $0.value) }
                .sorted { $0.start < $1.start }
            inputs.workouts = await workouts.sorted { $0.start < $1.start }
            // HKCategoryValueAppleStandHour: 0 stood, 1 idle.
            let hours = await stand
            inputs.standHours = hours.isEmpty ? nil : hours.filter { Int($0.value) == 0 }.count
            inputs.age = await birth
        }

        if parts.contains(.heartRecovery) {
            let readings = await samples(Metric.heartRecovery, from: first, to: now)
            inputs.heartRecovery = SomaScoresReader.dailyMeans(readings, dayStarts: starts, calendar: calendar)
        }

        return inputs
    }

    // MARK: - Pieces

    private static func latest(_ identifier: String, in source: any HealthSampleSource) async -> Double? {
        guard let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
        return (try? await source.latest(metric))?.value
    }

    /// One read per night, a few in flight at once.
    private static func perNight(_ nights: [ScoringNightWindow?],
                                 _ read: @escaping @Sendable (ScoringNightWindow?) async -> Double?) async -> [Double?] {
        var out = [Double?](repeating: nil, count: nights.count)
        await withTaskGroup(of: (Int, Double?).self) { group in
            var next = 0
            func add() {
                guard next < nights.count else { return }
                let index = next
                let night = nights[index]
                next += 1
                group.addTask { (index, night == nil ? nil : await read(night)) }
            }
            for _ in 0..<6 { add() }
            for await (index, value) in group {
                out[index] = value
                add()
            }
        }
        return out
    }

    /// Readings averaged per night: a reading belongs to the night whose
    /// window holds it.
    static func byNight(_ readings: [HealthReading], nights: [ScoringNightWindow?]) -> [Double?] {
        nights.map { night in
            guard let night else { return nil }
            let inside = readings.filter { $0.start >= night.start && $0.start <= night.end }.map(\.value)
            return inside.isEmpty ? nil : inside.reduce(0, +) / Double(inside.count)
        }
    }
}
