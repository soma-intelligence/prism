//
//  SomaScoringEngine.swift
//  HealthScoring
//
//  The pipeline that turns daily series into scores. It replicates, in order,
//  what the previous app did across three places:
//
//    1. its snapshot finalize pass: personal baselines, autonomic spreads,
//       the personal sleep need, the daily TRIMP series and its normalizers;
//    2. its canonical per-day recipes: sleep score, strain, recovery, stress,
//       the recovery-scaled sleep charge, the energy ledger and sleep debt;
//    3. its today scalars: last night's score, today's recovery breakdown,
//       today's strain and stress, and the intraday energy bank.
//
//  The preferences the original read from settings are fixed here to their
//  defaults: a 60 day baseline window, an 8 h sleep goal, the balanced
//  recovery model, both strain sources on, no jet lag and no subjective
//  adjustment.
//

import Foundation

public enum SomaScoringEngine {
    /// Days of history the personal baselines average over.
    static let baselineDays = 60
    /// The sleep goal the personal need is pulled toward, hours.
    static let sleepGoalHours = 8.0
    static let recoveryModel: RealHealthMath.RecoveryModel = .balanced
    /// Trailing days a trend direction is read over.
    public static let trendWindow = 30

    /// Maximum heart rate from age (Tanaka: 208 minus 0.7 per year), rounded
    /// and held to 120...220 the way the original did.
    ///
    /// With no age on record the original read an age of zero, which gives
    /// 208. Kept, rather than inventing an age.
    public static func maxHeartRate(ageYears: Double?) -> Double {
        let tanaka = (208 - 0.7 * (ageYears ?? 0)).rounded()
        return Double(min(220, max(120, Int(tanaka))))
    }

    /// Last night as the sessionizer sees it, before anything is scored: what
    /// a reader needs to go and fetch the night's heart rate.
    public static func lastNight(from samples: [ScoringSleepSample], now: Date,
                                 calendar: Calendar = .current) -> ScoringNightWindow? {
        let sessions = recentSessions(lite(samples), now: now, calendar: calendar)
        return sessions.first { $0.kind == .night }.map { ScoringNightWindow(start: $0.start, end: $0.end) }
    }

    /// The whole computation.
    public static func compute(_ inputs: ScoringInputs) -> ScoringResult {
        Pipeline(inputs).run()
    }

    // MARK: - Sleep plumbing

    static func lite(_ samples: [ScoringSleepSample]) -> [SleepSampleLite] {
        samples.map {
            SleepSampleLite(stage: $0.stage, start: $0.start, end: $0.end,
                            source: $0.source, sourceName: $0.source)
        }
    }

    /// Sessions over the last 36 hours, the window the original read them in.
    static func recentSessions(_ lite: [SleepSampleLite], now: Date,
                               calendar: Calendar) -> [RealSleepSession] {
        let windowStart = calendar.date(byAdding: .hour, value: -36, to: now) ?? now
        let recent = lite.filter { $0.end > windowStart && $0.start < now }
        return SleepSessionizer.sessions(from: recent, now: now, windowStart: windowStart,
                                         calendar: calendar)
    }

    /// The daily sleep breakdown: every cluster attributed to its WAKE day,
    /// its asleep, REM and deep hours, the night's bed and wake clock hours
    /// (bed above 24 after midnight) and the day's nap hours. Index 0 is the
    /// first day of the window, the last index today.
    static func dailySleepBreakdown(_ lite: [SleepSampleLite], days: Int, now: Date,
                                    calendar: Calendar)
        -> (asleep: [Double?], rem: [Double?], deep: [Double?],
            bedHour: [Double?], wakeHour: [Double?], nap: [Double?]) {
        let today = calendar.startOfDay(for: now)
        let dayZero = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        var asleep: [Int: Double] = [:]
        var rem: [Int: Double] = [:]
        var deep: [Int: Double] = [:]
        var bed: [Int: Double] = [:]
        var wake: [Int: Double] = [:]
        var nap: [Int: Double] = [:]

        let clusters = SleepSessionizer.dedupedClusters(from: lite)
        var clustersByDay: [Int: [SleepCluster]] = [:]
        for cluster in clusters {
            let dayIndex = calendar.dateComponents([.day], from: dayZero, to: cluster.end).day ?? -1
            guard dayIndex >= 0, dayIndex < days else { continue }
            clustersByDay[dayIndex, default: []].append(cluster)
            asleep[dayIndex, default: 0] += Double(cluster.asleepSeconds) / 3600
            for segment in cluster.segments {
                let hours = Double(segment.seconds) / 3600
                if segment.stage == "rem" {
                    rem[dayIndex, default: 0] += hours
                } else if segment.stage == "deep" {
                    deep[dayIndex, default: 0] += hours
                }
            }
        }

        // Clock positions come from the NIGHT cluster only, never from a nap.
        for (dayIndex, dayClusters) in clustersByDay {
            guard let night = nightSpan(dayClusters, calendar: calendar) else { continue }
            let startHour = Double(calendar.component(.hour, from: night.start))
                + Double(calendar.component(.minute, from: night.start)) / 60
            let endHour = Double(calendar.component(.hour, from: night.end))
                + Double(calendar.component(.minute, from: night.end)) / 60
            bed[dayIndex] = startHour < 12 ? startHour + 24 : startHour
            wake[dayIndex] = endHour
            let napSeconds = dayClusters
                .filter { $0.start < night.start || $0.end > night.end }
                .reduce(0) { $0 + $1.asleepSeconds }
            if napSeconds > 0 { nap[dayIndex] = Double(napSeconds) / 3600 }
        }

        func series(_ source: [Int: Double], cap: Double?) -> [Double?] {
            (0..<days).map { index in
                source[index].map { value in cap.map { min($0, value) } ?? value }
            }
        }
        return (series(asleep, cap: 14), series(rem, cap: 6), series(deep, cap: 5),
                series(bed, cap: nil), series(wake, cap: nil), series(nap, cap: 8))
    }

    /// The night's span among one day's clusters, or nil when the day only
    /// holds naps. Clusters ending in the wake window merge into one night;
    /// otherwise the longest episode long enough to be a night wins.
    static func nightSpan(_ clusters: [SleepCluster],
                          calendar: Calendar) -> (start: Date, end: Date)? {
        guard !clusters.isEmpty else { return nil }
        let thresholds = SleepSessionizer.Thresholds()
        let inWakeWindow = clusters.filter {
            thresholds.wakeWindow.contains(calendar.component(.hour, from: $0.end))
        }
        if !inWakeWindow.isEmpty {
            guard let start = inWakeWindow.map(\.start).min(),
                  let end = inWakeWindow.map(\.end).max() else { return nil }
            return (start, end)
        }
        guard let longest = clusters.max(by: { $0.asleepSeconds < $1.asleepSeconds }),
              longest.asleepSeconds >= thresholds.minNightMinutes * 60 else { return nil }
        return (longest.start, longest.end)
    }

    // MARK: - Night timing (from the chronotype estimator)

    /// Sleep duration in hours for one night. `bedHour` may exceed 24.
    static func sleepDuration(bedHour: Double, wakeHour: Double) -> Double {
        let onset = bedHour >= 24 ? bedHour - 24 : bedHour
        var duration = wakeHour - onset
        if duration < 0 { duration += 24 }
        return duration
    }

    /// Mid-sleep clock hour for one night, in [0, 24).
    static func midSleepHour(bedHour: Double, wakeHour: Double) -> Double {
        let onset = bedHour >= 24 ? bedHour - 24 : bedHour
        return CircadianMath.wrap24(onset + sleepDuration(bedHour: bedHour, wakeHour: wakeHour) / 2)
    }

    /// Trailing nights the habitual mid-sleep is averaged over.
    static let habitualMidSleepWindow = 28
    /// Below this many prior nights there is no rhythm to be off.
    static let habitualMidSleepMinNights = 7

    /// How far each night's mid-sleep sat from the sleeper's own habitual
    /// mid-sleep (the circular mean of the nights BEFORE it), hours.
    static func nightMisalignment(bedHour: [Double?], wakeHour: [Double?]) -> [Double?] {
        let count = max(bedHour.count, wakeHour.count)
        guard count > 0 else { return [] }
        var mids = [Double?](repeating: nil, count: count)
        for index in 0..<count {
            guard let bed = index < bedHour.count ? bedHour[index] : nil,
                  let wake = index < wakeHour.count ? wakeHour[index] : nil else { continue }
            let duration = sleepDuration(bedHour: bed, wakeHour: wake)
            guard duration >= 2, duration <= 16 else { continue }
            mids[index] = midSleepHour(bedHour: bed, wakeHour: wake)
        }
        return (0..<count).map { index -> Double? in
            guard let today = mids[index] else { return nil }
            let prior = RealHealthMath.trailingValues(
                mids, before: index, limit: habitualMidSleepWindow,
                maxLookback: RealHealthMath.baselineLookbackDays)
            guard prior.count >= habitualMidSleepMinNights,
                  let habitual = CircadianMath.circularMeanHours(prior) else { return nil }
            return CircadianMath.circularDistanceHours(today, habitual)
        }
    }

    // MARK: - Heart rate zones

    /// Seconds in each heart rate zone (by share of maximum heart rate). Each
    /// reading holds until the next one, at most five minutes, one minute for
    /// the last.
    static func zoneSeconds(samples: [(date: Date, bpm: Double, next: Date?)],
                            maxHR: Double, includeZoneZero: Bool) -> [Int] {
        var buckets = Array(repeating: 0, count: includeZoneZero ? 6 : 5)
        for sample in samples {
            let span: TimeInterval
            if let next = sample.next {
                span = min(300, next.timeIntervalSince(sample.date))
            } else {
                span = 60
            }
            let ratio = sample.bpm / maxHR
            let zone: Int
            if ratio < 0.5 { zone = 0 }
            else if ratio < 0.6 { zone = 1 }
            else if ratio < 0.7 { zone = 2 }
            else if ratio < 0.8 { zone = 3 }
            else if ratio < 0.9 { zone = 4 }
            else { zone = 5 }

            if includeZoneZero {
                buckets[zone] += Int(span)
            } else if zone > 0 {
                buckets[zone - 1] += Int(span)
            }
        }
        return buckets
    }

    // MARK: - Small helpers

    static func at(_ series: [Double?]?, _ index: Int) -> Double? {
        guard let series, index >= 0, index < series.count else { return nil }
        return series[index]
    }

    static func aligned(_ series: [Double?], _ count: Int) -> [Double?] {
        if series.count == count { return series }
        if series.count > count { return Array(series.suffix(count)) }
        return Array(repeating: nil, count: count - series.count) + series
    }

    static func trend(_ series: [Double?], key: String, openDay: Bool = false) -> ScoringTrend? {
        let window = Array(series.suffix(trendWindow))
        let tail = RealHealthMath.openDayTail(key: key, windowEndsToday: openDay)
        switch RealHealthMath.trendDirection(window, key: key, openDayTail: tail) {
        case .rising?: return .rising
        case .falling?: return .falling
        case .flat?: return .flat
        case nil: return nil
        }
    }
}

public extension ScoringResult {
    /// The direction of the last 30 days of a series, read the original way:
    /// the mean of the opening week against the closing week, with a dead
    /// band. Strain leaves out today, a day still being lived.
    var sleepTrend: ScoringTrend? { SomaScoringEngine.trend(sleepScore, key: "sleepScore") }
    var recoveryTrend: ScoringTrend? { SomaScoringEngine.trend(recovery, key: "recovery") }
    var strainTrend: ScoringTrend? { SomaScoringEngine.trend(strain, key: "strainPct", openDay: true) }
    var stressTrend: ScoringTrend? { SomaScoringEngine.trend(stress, key: "stress") }
    var energyTrend: ScoringTrend? { SomaScoringEngine.trend(energyEnd, key: "energy") }
    var sleepDebtTrend: ScoringTrend? { SomaScoringEngine.trend(sleepDebtHours, key: "bank") }
}

// MARK: - The pipeline

private struct Pipeline {
    let inputs: ScoringInputs
    let calendar: Calendar
    let now: Date
    let days: Int

    init(_ inputs: ScoringInputs) {
        self.inputs = inputs
        self.calendar = inputs.calendar
        self.now = inputs.now
        self.days = inputs.steps.count
    }

    func run() -> ScoringResult {
        let count = days
        let rhr = SomaScoringEngine.aligned(inputs.restingHeartRate, count)
        let hrv = SomaScoringEngine.aligned(inputs.heartRateVariability, count)
        let dayHR = SomaScoringEngine.aligned(inputs.dayHeartRate, count)
        let steps = inputs.steps
        let activeEnergy = SomaScoringEngine.aligned(inputs.activeEnergy, count)
        // A daily exercise total cannot exceed the 1440 minutes in a day: an
        // impossible value is a unit error upstream, dropped to a gap.
        let exerciseMin = SomaScoringEngine.aligned(inputs.exerciseMinutes, count)
            .map { value -> Double? in (value ?? 0) > 1440 ? nil : value }

        // Sleep.
        let lite = SomaScoringEngine.lite(inputs.sleepSamples)
        let breakdown = SomaScoringEngine.dailySleepBreakdown(lite, days: count, now: now,
                                                              calendar: calendar)
        let sleepHours = breakdown.asleep
        let sessions = SomaScoringEngine.recentSessions(lite, now: now, calendar: calendar)
        let night = sessions.first { $0.kind == .night }
        // The night that belongs to today: it ended today.
        let sleepToday = night.flatMap { calendar.isDate($0.end, inSameDayAs: now) ? $0 : nil }
        // Recovery may score from the last measured night while it is fresh.
        let readinessNight = sleepToday ?? night.flatMap {
            RealHealthMath.nightIsFreshForReadiness(wake: $0.end, now: now) ? $0 : nil
        }

        // Personal baselines, per-day causal.
        let baselineDays = SomaScoringEngine.baselineDays
        let rhrBaselineSeries = RealHealthMath.trailingMeanSeries(rhr, days: baselineDays)
        let hrvBaselineSeries = RealHealthMath.trailingMeanSeries(hrv, days: baselineDays)
        let latestRHR = inputs.latestRestingHeartRate
        let rhrBaselineToday = (rhrBaselineSeries.last ?? nil) ?? latestRHR
        let hrvBaselineToday = hrvBaselineSeries.last ?? nil

        // Autonomic spreads for the centered stress model.
        let hrvLogSpreadSeries = RealHealthMath.trailingRobustSpreadSeries(
            hrv, days: 60, floor: StressEngine.logHRVSpreadFloor, transform: { log(max(1, $0)) })
        let rhrSpreadSeries = RealHealthMath.trailingRobustSpreadSeries(
            rhr, days: 60, floor: StressEngine.rhrSpreadFloor)

        // Personalized sleep need: the 28-night mean pulled a quarter of the
        // way toward the goal, held to 6.5...9 h.
        let goal = min(9.0, max(6.5, SomaScoringEngine.sleepGoalHours))
        let goalSeconds = Int(goal * 3600)
        let mean28 = RealHealthMath.trailingMeanSeries(sleepHours, days: 28)
        let needSeries: [Int] = mean28.map { mean in
            guard let mean else { return goalSeconds }
            let need = mean + (goal - mean) * 0.25
            return Int(min(9.0, max(6.5, need)) * 3600)
        }
        let needToday = needSeries.last ?? goalSeconds

        // Daily TRIMP. History estimates the load from motion aggregates and
        // the day's mean heart rate; today uses its measured zones.
        let maxHR = SomaScoringEngine.maxHeartRate(ageYears: inputs.ageYears)
        var trimp: [Double?] = (0..<count).map { index in
            let restHR = rhr[index] ?? rhrBaselineToday
            let awakeHours = sleepHours[index].map { max(6, min(20, 24 - $0)) } ?? 16
            return RealHealthMath.estimatedTRIMP(
                exerciseMinutes: exerciseMin[index], steps: steps[index],
                activeKcal: activeEnergy[index], dayHR: dayHR[index], restHR: restHR,
                maxHR: maxHR, awakeHours: awakeHours, male: true)
        }
        let today0 = calendar.startOfDay(for: now)
        let todayHR = inputs.intradayHeartRate
            .filter { $0.start >= today0 && $0.start <= now }
            .sorted { $0.start < $1.start }
        let zoneInput: [(date: Date, bpm: Double, next: Date?)] = todayHR.indices.map { index in
            (todayHR[index].start, todayHR[index].value,
             index + 1 < todayHR.count ? todayHR[index + 1].start : nil)
        }
        let dayZones = SomaScoringEngine.zoneSeconds(samples: zoneInput, maxHR: maxHR,
                                                     includeZoneZero: true)
        let todayTrimp = RealHealthMath.todayTRIMP(
            dayZoneSeconds: dayZones, workoutZoneSeconds: Array(repeating: 0, count: 5),
            activeKcal: activeEnergy.last.flatMap { $0 } ?? 0, workoutKcal: 0,
            includeWorkouts: true, includeDaily: true)
        if count > 0 { trimp[count - 1] = todayTrimp }

        // Strain normalizers: the causal chronic load, and the causal 90 day
        // maximum as the fallback for thin histories.
        let trimp90MaxSeries = RealHealthMath.trailingMaxSeries(trimp, days: 90)
        let trimp90MaxToday = (trimp90MaxSeries.last ?? nil) ?? 0
        let ctlSeries = RealHealthMath.causalChronicDailyTRIMPSeries(trimp)

        var yesterdayStrain = 0
        if count > 1, let yesterday = trimp[count - 2] {
            yesterdayStrain = RealHealthMath.strainPercent(
                trimp: yesterday,
                trimp90Max: SomaScoringEngine.at(trimp90MaxSeries, count - 2) ?? trimp90MaxToday,
                chronicDailyTrimp: SomaScoringEngine.at(ctlSeries, count - 2))
        }

        // Per-day sleep score. Past nights carry no night heart rate in Soma,
        // so their dip term is left out; today's index uses last night's.
        let nightHypnograms = hypnogramsByDay(sessions: sessions, sleepHours: sleepHours)
        let age = inputs.ageYears.flatMap { $0 > 0 ? $0 : nil }
        let sleepScore: [Double?] = sleepHours.indices.map { index in
            guard let hours = sleepHours[index], hours > 0 else { return nil }
            let need = needSeries[index]
            let nightHR = index == count - 1 ? inputs.lastNightHeartRate : nil
            let dayRHR = rhr[index]
            if let hypnogram = nightHypnograms[index] {
                return RealHealthMath.sleepScore(hypnogram: hypnogram, needSeconds: need,
                                                 nightHR: nightHR, dayRHR: dayRHR,
                                                 ageYears: age).map(Double.init)
            }
            let rem = breakdown.rem[index].map { Int($0 * 3600) }
            let deep = breakdown.deep[index].map { Int($0 * 3600) }
            return RealHealthMath.sleepScore(asleepSeconds: Int(hours * 3600), needSeconds: need,
                                             remSeconds: rem, deepSeconds: deep,
                                             nightHR: nightHR, dayRHR: dayRHR,
                                             ageYears: age).map(Double.init)
        }

        // Per-day strain on the causal chronic scale.
        let strain: [Double?] = trimp.indices.map { index in
            guard let value = trimp[index] else { return nil }
            let tau90 = SomaScoringEngine.at(trimp90MaxSeries, index) ?? trimp90MaxToday
            return Double(RealHealthMath.strainPercent(
                trimp: value, trimp90Max: tau90,
                chronicDailyTrimp: SomaScoringEngine.at(ctlSeries, index)))
        }

        // Per-day recovery.
        let recovery: [Double?] = (0..<count).map { index in
            let h = hrv[index], r = rhr[index], s = sleepScore[index]
            if h == nil && r == nil && s == nil { return nil }
            let yesterday = index > 0 ? Int(strain[index - 1] ?? 0) : 0
            return Double(RealHealthMath.recovery(
                hrv: h,
                hrvBaseline: SomaScoringEngine.at(hrvBaselineSeries, index) ?? hrvBaselineToday,
                rhr: r,
                rhrBaseline: SomaScoringEngine.at(rhrBaselineSeries, index) ?? rhrBaselineToday,
                sleepScore: Int(s ?? 50), yesterdayStrain: yesterday,
                model: SomaScoringEngine.recoveryModel, jetLagResidualH: 0))
        }

        // Per-day stress: the centered autonomic model on causal baselines.
        let logHRV = hrv.compactMap { $0 }.map { log(max(1, $0)) }
        let hrvSpreadGlobal = StressEngine.robustSpread(Array(logHRV.suffix(60)),
                                                        floor: StressEngine.logHRVSpreadFloor)
        let rhrSpreadGlobal = StressEngine.robustSpread(Array(rhr.compactMap { $0 }.suffix(60)),
                                                        floor: StressEngine.rhrSpreadFloor)
        let stress: [Double?] = (0..<count).map { index in
            guard recovery[index] != nil else { return nil }
            let hrvBase = SomaScoringEngine.at(hrvBaselineSeries, index)
                ?? ((hrvBaselineToday ?? 0) > 0 ? hrvBaselineToday : nil)
            let rhrBase = SomaScoringEngine.at(rhrBaselineSeries, index)
                ?? ((rhrBaselineToday ?? 0) > 0 ? rhrBaselineToday : nil)
            return StressEngine.dailyValue(
                hrv: hrv[index],
                hrvBaseline: (hrvBase ?? 0) > 0 ? hrvBase : nil,
                hrvSpread: SomaScoringEngine.at(hrvLogSpreadSeries, index) ?? hrvSpreadGlobal,
                restingHR: rhr[index],
                restingHRBaseline: (rhrBase ?? 0) > 0 ? rhrBase : nil,
                rhrSpread: SomaScoringEngine.at(rhrSpreadSeries, index) ?? rhrSpreadGlobal)
        }

        // The night's charge, scaled by that night's recovery signals.
        let scaledSleep: [Double?] = sleepScore.indices.map { index in
            guard let score = sleepScore[index] else { return nil }
            let base = SomaScoringEngine.at(hrvBaselineSeries, index) ?? hrvBaselineToday
            let dayBase = (base ?? 0) > 0 ? base : nil
            let remFraction: Double? = {
                guard let rem = breakdown.rem[index], let slept = sleepHours[index], slept > 0 else { return nil }
                return min(1, max(0, rem / slept))
            }()
            let multiplier = VitalitySections.recoveryChargeMultiplier(
                hrv: hrv[index], hrvBaseline: dayBase, remFraction01: remFraction)
            return min(100, max(0, score * multiplier))
        }

        let ledger = RealHealthMath.energyLedger(
            sleepScores: scaledSleep, strains: strain, sleepHours: sleepHours,
            nightMisalignmentHours: SomaScoringEngine.nightMisalignment(
                bedHour: breakdown.bedHour, wakeHour: breakdown.wakeHour),
            dailyStress: stress, illnessDeviation: [])

        // Sleep debt: the accumulator over the 14 nights ending each day.
        let nights: [(asleep: Double?, need: Double?)] = (0..<count).map {
            (sleepHours[$0], Double(needSeries[$0]) / 3600)
        }
        let window = max(1, HealthStats.SleepDebt.windowNights)
        let sleepDebt: [Double?] = (0..<count).map { end in
            let start = max(0, end - window + 1)
            return HealthStats.SleepDebt.series(Array(nights[start...end])).last.flatMap { $0 }
        }

        // Today.
        let sleepScoreToday: Int? = sleepToday.flatMap { night in
            RealHealthMath.sleepScore(
                hypnogram: night.segments.map { ($0.stage, $0.seconds) },
                needSeconds: needToday,
                nightHR: inputs.lastNightHeartRate ?? latestRHR,
                dayRHR: max(1, rhrBaselineToday ?? 0),
                ageYears: age)
        }

        let hasTodayRawBucket = sleepToday != nil
            || (hrv.last ?? nil) != nil || (rhr.last ?? nil) != nil
        let hasOwnReadiness = readinessNight != nil || hasTodayRawBucket
        let recoveryToday: ScoringRecoveryBreakdown? = {
            guard hasOwnReadiness else { return nil }
            let breakdown = RealHealthMath.recoveryBreakdown(
                hrv: inputs.lastNightVariability ?? RealHealthMath.tailMean(hrv, days: 2),
                hrvBaseline: hrvBaselineToday,
                hrvSamples: hrv.suffix(baselineDays).compactMap { $0 }.count,
                rhr: latestRHR,
                rhrBaseline: rhrBaselineToday,
                rhrSamples: rhr.suffix(baselineDays).compactMap { $0 }.count,
                sleepScore: sleepScoreToday ?? 0,
                yesterdayStrain: yesterdayStrain,
                model: SomaScoringEngine.recoveryModel)
            return ScoringRecoveryBreakdown(
                score: breakdown.score, baseline: breakdown.baseline, rawTotal: breakdown.rawTotal,
                terms: breakdown.contributions.map {
                    ScoringRecoveryTerm(kind: ScoringRecoveryTerm.Kind(rawValue: $0.kind.rawValue) ?? .rest,
                                        points: $0.points, value: $0.value, baseline: $0.baseline)
                },
                missing: breakdown.missing.compactMap { ScoringRecoveryTerm.Kind(rawValue: $0.rawValue) })
        }()

        let strainPercentToday = RealHealthMath.strainPercent(
            trimp: todayTrimp, trimp90Max: trimp90MaxToday,
            chronicDailyTrimp: SomaScoringEngine.at(ctlSeries, count - 1))
        let strainMissing = RealHealthMath.strainMissing(
            score: strainPercentToday, steps: steps.last ?? nil,
            activeEnergy: activeEnergy.last ?? nil, exerciseMinutes: exerciseMin.last ?? nil)
        let strainToday: Int? = strainMissing ? nil : strainPercentToday
        let strainTarget = recoveryToday.map {
            RealHealthMath.strainTarget(recovery: $0.score,
                                        chronicDailyTrimp: SomaScoringEngine.at(ctlSeries, count - 1),
                                        trimp90Max: trimp90MaxToday)
        }

        let stressToday: Int? = hasTodayRawBucket
            ? stress.reversed().compactMap { $0 }.first.map { Int($0.rounded()) }
            : nil

        let energyToday: ScoringEnergyCurve? = {
            guard ledger.morning.contains(where: { $0 != nil }) else { return nil }
            return IntradayEnergy(
                now: now, calendar: calendar,
                night: sleepToday, naps: sessions.filter { $0.kind == .nap },
                morning: ledger.morning, end: ledger.end,
                strainToday: Double(strainToday ?? 0),
                heartRate: inputs.intradayHeartRate,
                activeEnergy: inputs.intradayActiveEnergy,
                restingBaseline: rhrBaselineToday ?? 0,
                maxHR: maxHR
            ).curve()
        }()

        return ScoringResult(
            days: count,
            sleepHours: sleepHours,
            sleepNeedHours: needSeries.map { Double($0) / 3600 },
            sleepScore: sleepScore,
            strain: strain,
            recovery: recovery,
            stress: stress,
            energyMorning: ledger.morning,
            energyEnd: ledger.end,
            sleepDebtHours: sleepDebt,
            hrvBaseline: hrvBaselineSeries,
            restingHeartRateBaseline: rhrBaselineSeries,
            trimp: trimp,
            sleepScoreToday: sleepScoreToday,
            recoveryToday: recoveryToday,
            strainToday: strainToday,
            strainTargetToday: strainTarget,
            stressToday: stressToday,
            energyToday: energyToday,
            sleepDebtHoursToday: sleepDebt.last(where: { $0 != nil }) ?? nil,
            sleepNeedHoursToday: Double(needToday) / 3600,
            lastNight: night.map { ScoringNightWindow(start: $0.start, end: $0.end) },
            nightsRecorded: sleepHours.compactMap { $0 }.filter { $0 > 0 }.count,
            variabilityDays: hrv.suffix(baselineDays).compactMap { $0 }.count,
            restingDays: rhr.suffix(baselineDays).compactMap { $0 }.count,
            remHours: breakdown.rem,
            deepHours: breakdown.deep,
            bedHour: breakdown.bedHour,
            wakeHour: breakdown.wakeHour,
            sleepPartsToday: sleepToday.map { night in
                ScoringSleepPart.parts(
                    hypnogram: night.segments.map { ($0.stage, $0.seconds) },
                    needSeconds: needToday,
                    nightHR: inputs.lastNightHeartRate ?? latestRHR,
                    dayRHR: max(1, rhrBaselineToday ?? 0),
                    ageYears: age)
            } ?? [],
            lastNightStages: sleepToday.map { ScoringStageRun.runs(of: $0) } ?? []
        )
    }

    /// Recorded night hypnograms keyed by the day they woke on, kept only when
    /// the session's asleep time agrees with that day's sleep hours within 15%.
    func hypnogramsByDay(sessions: [RealSleepSession],
                         sleepHours: [Double?]) -> [Int: [(stage: String, seconds: Int)]] {
        let today = calendar.startOfDay(for: now)
        var out: [Int: [(stage: String, seconds: Int)]] = [:]
        for session in sessions where session.kind == .night && !session.segments.isEmpty {
            let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: session.end),
                                               to: today).day ?? -1
            let index = days - 1 - back
            guard back >= 0, index >= 0, index < sleepHours.count,
                  let recordedHours = sleepHours[index], recordedHours > 0 else { continue }
            let asleep = session.asleepSeconds
            guard asleep > 0 else { continue }
            let recorded = recordedHours * 3600
            guard abs(Double(asleep) - recorded) / recorded <= 0.15 else { continue }
            out[index] = session.segments.map { ($0.stage, $0.seconds) }
        }
        return out
    }
}
