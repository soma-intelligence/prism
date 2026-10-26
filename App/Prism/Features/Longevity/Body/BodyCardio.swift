//
//  BodyCardio.swift
//  Prism
//

import Foundation
import HealthExportCore
import SomaUI

/// What the Cardio part is built from.
struct BodyCardioInputs: Sendable, Equatable {
    var now: Date
    /// VO2 max over the last sixteen weeks.
    var vo2Max: [HealthReading] = []
    /// Resting heart rate over the last sixteen weeks.
    var restingHeartRate: [HealthReading] = []
    /// Heart rate recovery one minute after a workout, over sixteen weeks.
    var recovery: [HealthReading] = []
    /// Workouts over the last five weeks, each carrying its coded activity
    /// type: the week the zones cover and the four before it.
    var workouts: [HealthReading] = []
    /// Heart rate samples taken during those workouts.
    var workoutHeartRate: [HealthReading] = []
    /// Distance walked or run during the latest run or walk, in metres.
    var runDistance: Double?
    /// Age in whole years, from the date of birth in Health.
    var age: Int?

    static let metrics = [
        BodyMetric.vo2Max, BodyMetric.restingHeartRate, BodyMetric.heartRateRecovery,
        BodyMetric.heartRate, BodyMetric.distanceWalkingRunning, BodyMetric.workout, BodyMetric.dateOfBirth,
    ]

    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> BodyCardioInputs {
        let trendStart = calendar.date(byAdding: .day, value: -BodyMetric.trendLookbackDays, to: now) ?? now
        let workoutStart = calendar.date(byAdding: .day, value: -35, to: now) ?? now

        async let vo2 = BodyMetric.samples(BodyMetric.vo2Max, from: trendStart, to: now, in: source)
        async let resting = BodyMetric.samples(BodyMetric.restingHeartRate, from: trendStart, to: now, in: source)
        async let recovery = BodyMetric.samples(BodyMetric.heartRateRecovery, from: trendStart, to: now, in: source)
        async let workouts = BodyMetric.samples(BodyMetric.workout, from: workoutStart, to: now, in: source)
        async let age = BodyMetric.age(in: source)

        // Heart rate is read per workout rather than over five weeks, which
        // would pull every sample the watch took at rest as well.
        let readWorkouts = await workouts
        var heartRate: [HealthReading] = []
        for workout in readWorkouts {
            heartRate += await BodyMetric.samples(BodyMetric.heartRate, from: workout.start, to: workout.end, in: source)
        }

        var distance: Double?
        if let run = BodyCardio.latestRun(in: readWorkouts),
           let metric = HealthMetricCatalog.metric(for: BodyMetric.distanceWalkingRunning) {
            distance = (try? await source.total(metric, from: run.start, to: run.end))?.value
        }

        return BodyCardioInputs(
            now: now,
            vo2Max: await vo2,
            restingHeartRate: await resting,
            recovery: await recovery,
            workouts: readWorkouts,
            workoutHeartRate: heartRate,
            runDistance: distance,
            age: await age
        )
    }
}

/// The Cardio part's words and numbers.
struct BodyCardio: Equatable {
    var eyebrow: String?
    var headline: String
    var reason: String

    var vo2Max: String?
    var vo2Trend: SomaTrend?
    var restingHeartRate: String?
    var restingTrend: SomaTrend?
    var recovery: String?
    var recoveryTrend: SomaTrend?

    var zones: Zones
    var run: Run?

    /// Seven days of heart rate zones.
    struct Zones: Equatable {
        /// Minutes per zone, nil for all of them without an age or workouts.
        var minutes: [BodyMath.Zone: Double]?
        /// The usual weekly span for zone 2, in minutes.
        var usualZoneTwo: ClosedRange<Double>?
        var note: String

        var zoneTwo: String? { minutes.map { BodyCardio.minutes($0[.two] ?? 0) } }

        /// The longest a bar or the usual line reaches, so both share a scale.
        var scale: Double {
            let longest = minutes?.values.max() ?? 0
            return max(longest, usualZoneTwo?.upperBound ?? 0, 1)
        }

        func fraction(_ zone: BodyMath.Zone) -> Double? {
            minutes.map { ($0[zone] ?? 0) / scale }
        }

        func value(_ zone: BodyMath.Zone) -> String? {
            minutes.map { "\(BodyCardio.minutes($0[zone] ?? 0)) min" }
        }

        var usualFraction: ClosedRange<Double>? {
            usualZoneTwo.map { ($0.lowerBound / scale)...($0.upperBound / scale) }
        }
    }

    /// The latest run or walk.
    struct Run: Equatable {
        var title: String
        var distance: String?
        var duration: String
        var note: String
        /// Heart rate over the session, in order.
        var heartRate: [Double]
    }

    static let runTypes: Set<Int> = [37, 52]

    static func latestRun(in workouts: [HealthReading]) -> HealthReading? {
        workouts.filter { runTypes.contains($0.code) }.max { $0.start < $1.start }
    }

    static func minutes(_ value: Double) -> String { String(Int(value.rounded())) }

    static func make(from inputs: BodyCardioInputs, calendar: Calendar = .current, locale: Locale = .current) -> BodyCardio {
        let vo2 = BodyMath.change(inputs.vo2Max, now: inputs.now, calendar: calendar)
        let resting = BodyMath.change(inputs.restingHeartRate, now: inputs.now, calendar: calendar)
        let recovery = BodyMath.change(inputs.recovery, now: inputs.now, calendar: calendar)
        let maxHeartRate = BodyMath.maxHeartRate(age: inputs.age)

        let zones = makeZones(inputs, maxHeartRate: maxHeartRate)
        let run = makeRun(inputs, maxHeartRate: maxHeartRate, locale: locale)

        var page = BodyCardio(
            eyebrow: "Last eight weeks",
            headline: "Your heart, as your watch reads it.",
            reason: "Nothing to read yet. A brisk walk or a run with Apple Watch starts VO2 max, and workouts fill the zones below.",
            vo2Max: BodyMath.format(vo2?.latest, decimals: 0, locale: locale),
            vo2Trend: BodyMath.trend(vo2?.delta, tolerance: 0.5),
            restingHeartRate: BodyMath.format(resting?.latest, decimals: 0, locale: locale),
            restingTrend: BodyMath.trend(resting?.delta, tolerance: 1),
            recovery: BodyMath.format(recovery?.latest, decimals: 0, locale: locale),
            recoveryTrend: BodyMath.trend(recovery?.delta, tolerance: 1),
            zones: zones,
            run: run
        )

        if let vo2 {
            let now = page.vo2Max ?? ""
            let before = BodyMath.format(vo2.earlier, decimals: 0, locale: locale)
            switch (BodyMath.trend(vo2.delta, tolerance: 0.5), before) {
            case (.up, let before?):
                page.headline = "Your engine is growing."
                page.reason = "VO2 max rose from \(before) to \(now) in eight weeks."
            case (.down, let before?):
                page.headline = "Your engine eased off."
                page.reason = "VO2 max fell from \(before) to \(now) in eight weeks."
            case (nil, _?):
                page.headline = "Your engine is holding."
                page.reason = "VO2 max has held near \(now) for eight weeks."
            default:
                page.headline = "Your engine, as your watch reads it."
                page.reason = "VO2 max reads \(now). In eight weeks there is a trend to show."
            }
            if let minutes = zones.minutes, let usual = zones.usualZoneTwo, (minutes[.two] ?? 0) < usual.lowerBound {
                page.reason += " Zone 2 ran short this week, and that is where the next gain comes from."
            }
        } else if zones.minutes != nil {
            page.headline = "Your heart, as your workouts read it."
            page.reason = "No VO2 max yet. A brisk outdoor walk or run with Apple Watch records one."
        }

        return page
    }

    private static func makeZones(_ inputs: BodyCardioInputs, maxHeartRate: Double?) -> Zones {
        let weekAgo = inputs.now.addingTimeInterval(-7 * 24 * 60 * 60)
        let lastWeek = inputs.workouts.filter { $0.start >= weekAgo }

        guard let maxHeartRate else {
            return Zones(minutes: nil, usualZoneTwo: nil,
                         note: "Zones are cut from your age. Add your date of birth in Health and your workouts fill this.")
        }
        guard !lastWeek.isEmpty, !inputs.workoutHeartRate.isEmpty else {
            return Zones(minutes: nil, usualZoneTwo: nil,
                         note: "No workouts with heart rate in the last seven days. The next one fills this.")
        }

        let minutes = BodyMath.zoneMinutes(heartRate: inputs.workoutHeartRate, workouts: lastWeek, maxHeartRate: maxHeartRate)
        let usual = BodyMath.usualZoneTwo(heartRate: inputs.workoutHeartRate, workouts: inputs.workouts,
                                          maxHeartRate: maxHeartRate, now: inputs.now)
        let most = BodyMath.Zone.allCases.max { (minutes[$0] ?? 0) < (minutes[$1] ?? 0) }

        var note = ""
        if let usual {
            note = "Usual \(Self.minutes(usual.lowerBound)) to \(Self.minutes(usual.upperBound)) a week."
        }
        if let most, (minutes[most] ?? 0) > 0 {
            note += (note.isEmpty ? "" : " ") + "Most of your time sits in zone \(most.rawValue)."
        }
        return Zones(minutes: minutes, usualZoneTwo: usual, note: note)
    }

    private static func makeRun(_ inputs: BodyCardioInputs, maxHeartRate: Double?, locale: Locale) -> Run? {
        guard let workout = latestRun(in: inputs.workouts) else { return nil }
        let seconds = workout.end.timeIntervalSince(workout.start)
        let kilometres = inputs.runDistance.map { $0 / 1000 }
        let samples = inputs.workoutHeartRate
            .filter { $0.start >= workout.start && $0.start < workout.end }
            .sorted { $0.start < $1.start }

        var sentences: [String] = []
        if let kilometres, kilometres > 0.05 {
            sentences.append("Average \(BodyMath.clock(seconds / kilometres)) a km.")
        }
        if let maxHeartRate, !samples.isEmpty {
            let zones = BodyMath.zoneMinutes(heartRate: samples, workouts: [workout], maxHeartRate: maxHeartRate)
            let hard = zones.filter { $0.key.rawValue >= 3 }.values.reduce(0, +)
            sentences.append("\(minutes(hard)) minutes in zone 3 and above.")
        }
        if samples.isEmpty {
            sentences.append("No heart rate was recorded during it.")
        }

        return Run(
            title: workout.code == 37 ? "Run" : "Walk",
            distance: kilometres.flatMap { BodyMath.format($0, decimals: 1, locale: locale) },
            duration: BodyMath.clock(seconds),
            note: sentences.joined(separator: " "),
            heartRate: samples.map(\.value)
        )
    }
}

#if DEBUG
extension BodyCardio {
    static var preview: BodyCardio {
        let now = Date()
        func at(_ minutesAgo: Double) -> Date { now.addingTimeInterval(-minutesAgo * 60) }
        let run = HealthReading(metric: BodyMetric.workout, value: 37, unit: .none, start: at(120), end: at(67))
        let heart = stride(from: 0.0, to: 53, by: 1).map { minute in
            HealthReading(metric: BodyMetric.heartRate, value: 120 + minute * 0.8, unit: .countPerMinute,
                          start: run.start.addingTimeInterval(minute * 60), end: run.start.addingTimeInterval(minute * 60))
        }
        return make(from: BodyCardioInputs(
            now: now,
            vo2Max: [HealthReading(metric: BodyMetric.vo2Max, value: 41, unit: .none, start: at(60 * 24 * 60), end: at(60 * 24 * 60)),
                     HealthReading(metric: BodyMetric.vo2Max, value: 44, unit: .none, start: at(600), end: at(600))],
            workouts: [run],
            workoutHeartRate: heart,
            runDistance: 10_200,
            age: 46
        ))
    }
}
#endif
