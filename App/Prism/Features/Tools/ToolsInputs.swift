//
//  ToolsInputs.swift
//  Prism
//

import Foundation
import HealthExportCore
import HealthScoring

/// One night of sleep, attributed to the day it ended on.
nonisolated struct ToolNight: Sendable, Equatable {
    /// Midnight of the day the night ended on.
    var wakeDay: Date
    var bed: Date
    var wake: Date
    /// Hours of sleep, awake stretches left out.
    var asleep: Double
    var deep: Double
    var rem: Double
    var core: Double
    var awake: Double
    /// The stages of the night from the one source kept, oldest first, for
    /// the hypnogram.
    var stages: [ScoringSleepSample]

    /// Bed as a decimal clock hour against the wake day's midnight, past 24 for
    /// an onset after midnight (a 01:00 onset is 25): the encoding the
    /// circadian engines read.
    func bedHour(calendar: Calendar) -> Double {
        bed.timeIntervalSince(calendar.startOfDay(for: wake)) / 3600 + 24
    }

    func wakeHour(calendar: Calendar) -> Double {
        wake.timeIntervalSince(calendar.startOfDay(for: wake)) / 3600
    }
}

/// What the tool pages read out of Apple Health, all at once.
///
/// Everything here is read with the store's own queries through
/// `HealthSampleSource`; a read that fails is left empty and the page shows
/// its dash. Nothing sensitive is asked for: no cycle, no reproductive health.
nonisolated struct ToolsInputs: Sendable, Equatable {
    var now: Date
    /// Oldest first, one per wake day at most.
    var nights: [ToolNight] = []
    /// Caffeine entries over the last 30 days, in mg.
    var caffeine: [HealthReading] = []
    /// Minutes in daylight today, or nil when the watch recorded none.
    var daylightToday: Double?
    /// Workouts over the last twelve weeks. `value` is the activity type code.
    var workouts: [HealthReading] = []
    var vo2Max: [HealthReading] = []
    var restingHeartRate: [HealthReading] = []
    /// Heart rate variability (SDNN) over the last six months.
    var heartRateVariability: [HealthReading] = []
    var respiratoryRate: [HealthReading] = []
    var leanMass: HealthReading?
    var ageYears: Double?

    enum Metric {
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
        static let caffeine = "HKQuantityTypeIdentifierDietaryCaffeine"
        static let daylight = "HKQuantityTypeIdentifierTimeInDaylight"
        static let workout = "HKWorkoutTypeIdentifier"
        static let vo2Max = "HKQuantityTypeIdentifierVO2Max"
        static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
        static let heartRateVariability = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"
        static let leanMass = "HKQuantityTypeIdentifierLeanBodyMass"
        static let dateOfBirth = "HKCharacteristicTypeIdentifierDateOfBirth"
    }

    static let metrics = [
        Metric.sleep, Metric.caffeine, Metric.daylight, Metric.workout, Metric.vo2Max,
        Metric.restingHeartRate, Metric.heartRateVariability, Metric.respiratoryRate, Metric.leanMass, Metric.dateOfBirth,
    ]

    /// Workout activity codes that count as strength work
    /// (`HKWorkoutActivityType`: functional 20, traditional 50, core 59).
    static let strengthCodes: Set<Int> = [20, 50, 59]

    /// Days of sleep read: twelve weeks, enough for the circadian engines'
    /// eight week window and the social jetlag history.
    static let nightDays = 84

    var hasNights: Bool { !nights.isEmpty }

    /// Readings averaged per day, oldest first, days without one left out:
    /// the longitudinal series the aging model reads.
    static func dailyMeans(_ readings: [HealthReading], through end: Date? = nil, calendar: Calendar) -> [Double] {
        var sums: [Date: (Double, Int)] = [:]
        for reading in readings where end.map({ reading.start <= $0 }) ?? true {
            let day = calendar.startOfDay(for: reading.start)
            let current = sums[day] ?? (0, 0)
            sums[day] = (current.0 + reading.value, current.1 + 1)
        }
        return sums.keys.sorted().compactMap { sums[$0].map { $0.0 / Double($0.1) } }
    }

    /// The latest night, if it ended today or yesterday.
    func lastNight(calendar: Calendar) -> ToolNight? {
        guard let last = nights.last else { return nil }
        let today = calendar.startOfDay(for: now)
        let age = calendar.dateComponents([.day], from: last.wakeDay, to: today).day ?? 99
        return age <= 1 ? last : nil
    }

    /// Bed and wake hours, one per day for the last `days` days, oldest first,
    /// the last being today; nil where no night ended that day.
    func series(days: Int, calendar: Calendar) -> (bed: [Double?], wake: [Double?]) {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: ToolNight] = [:]
        for night in nights { byDay[night.wakeDay] = night }
        var bed: [Double?] = [], wake: [Double?] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let night = byDay[day]
            bed.append(night?.bedHour(calendar: calendar))
            wake.append(night?.wakeHour(calendar: calendar))
        }
        return (bed, wake)
    }

    // MARK: - Reading

    @concurrent
    static func read(from source: any HealthSampleSource, now: Date, calendar: Calendar) async -> ToolsInputs {
        let today = calendar.startOfDay(for: now)
        func back(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today) ?? today }

        @Sendable func samples(_ identifier: String, from start: Date) async -> [HealthReading] {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return [] }
            return (try? await source.samples(metric, from: start, to: now, limit: 0)) ?? []
        }
        @Sendable func latest(_ identifier: String) async -> HealthReading? {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
            return try? await source.latest(metric)
        }
        @Sendable func total(_ identifier: String, from start: Date) async -> Double? {
            guard let metric = HealthMetricCatalog.metric(for: identifier) else { return nil }
            return (try? await source.total(metric, from: start, to: now))?.value
        }

        let sleepFrom = calendar.date(byAdding: .hour, value: -18, to: back(nightDays)) ?? back(nightDays)
        async let sleep = samples(Metric.sleep, from: sleepFrom)
        async let caffeine = samples(Metric.caffeine, from: back(30))
        async let daylight = total(Metric.daylight, from: today)
        async let workouts = samples(Metric.workout, from: back(84))
        async let vo2 = samples(Metric.vo2Max, from: back(182))
        async let resting = samples(Metric.restingHeartRate, from: back(182))
        async let variability = samples(Metric.heartRateVariability, from: back(182))
        async let breathing = samples(Metric.respiratoryRate, from: back(30))
        async let lean = latest(Metric.leanMass)
        async let birth = latest(Metric.dateOfBirth)

        let stages = await sleep.compactMap {
            ScoringSleepSample(code: Int($0.value), start: $0.start, end: $0.end, source: $0.source)
        }
        return ToolsInputs(
            now: now,
            nights: nights(from: stages, calendar: calendar),
            caffeine: await caffeine,
            daylightToday: await daylight,
            workouts: await workouts,
            vo2Max: await vo2,
            restingHeartRate: await resting,
            heartRateVariability: await variability,
            respiratoryRate: await breathing,
            leanMass: await lean,
            ageYears: await birth?.value
        )
    }

    /// Sleep stages grouped into nights.
    ///
    /// The asleep stretches of every source are merged into sessions where
    /// they sit less than an hour apart; a session of three hours or more is a
    /// night, and a day keeps its longest. Stage totals come from the one
    /// source that recorded the most sleep inside the session, so a watch and a
    /// phone writing the same night count it once.
    static func nights(from samples: [ScoringSleepSample], calendar: Calendar) -> [ToolNight] {
        let asleep = samples.filter { $0.stage != "awake" }.sorted { $0.start < $1.start }
        var sessions: [(start: Date, end: Date)] = []
        for sample in asleep {
            if let last = sessions.last, sample.start.timeIntervalSince(last.end) < 3600 {
                sessions[sessions.count - 1].end = max(last.end, sample.end)
            } else {
                sessions.append((sample.start, sample.end))
            }
        }

        var byDay: [Date: ToolNight] = [:]
        for session in sessions where session.end.timeIntervalSince(session.start) >= 3 * 3600 {
            let inside = samples.filter { $0.start >= session.start.addingTimeInterval(-3600) && $0.end <= session.end.addingTimeInterval(3600) }
            var bySource: [String: Double] = [:]
            for sample in inside where sample.stage != "awake" {
                bySource[sample.source, default: 0] += sample.end.timeIntervalSince(sample.start)
            }
            guard let kept = bySource.max(by: { $0.value < $1.value })?.key else { continue }
            let own = inside.filter { $0.source == kept }.sorted { $0.start < $1.start }
            func hours(_ stage: String) -> Double {
                own.filter { $0.stage == stage }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
            }
            let night = ToolNight(
                wakeDay: calendar.startOfDay(for: session.end),
                bed: session.start,
                wake: session.end,
                asleep: hours("deep") + hours("rem") + hours("core"),
                deep: hours("deep"),
                rem: hours("rem"),
                core: hours("core"),
                awake: hours("awake"),
                stages: own
            )
            if let existing = byDay[night.wakeDay], existing.asleep >= night.asleep { continue }
            byDay[night.wakeDay] = night
        }
        return byDay.values.sorted { $0.wakeDay < $1.wakeDay }
    }
}
