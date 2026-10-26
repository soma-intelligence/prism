//
//  ScoreDetails.swift
//  HealthScoring
//
//  What the score pages read beyond the scores themselves: a score taken
//  apart, last night's stages on a clock, the night heart rate dip, a
//  personal usual band, the stress line through the day, and the nights
//  as windows. Plain values in, plain values out, like the rest of the
//  engine's public face.
//

import Foundation

// MARK: - The sleep score, taken apart

/// One component of a night's sleep score.
///
/// `share` is the component's weight after the zero-and-renormalize step, so
/// the shares of one night sum to 100, and `points` is what it earned out of
/// its share. The points sum to the score (before rounding).
public struct ScoringSleepPart: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, CaseIterable, Codable {
        case duration, efficiency, deep, rem, continuity, dip
    }

    public let kind: Kind
    /// The relative weight the formula gives this component (40, 15, ...).
    public let weight: Double
    /// Its share of 100 once the missing components are dropped.
    public let share: Double
    /// 0 to 1: how much of its share it earned.
    public let credit: Double

    public var points: Double { share * credit }

    /// The parts of a night scored from its hypnogram, exactly as
    /// `sleepScore(hypnogram:...)` scores it. Empty when the night has no
    /// asleep time.
    static func parts(hypnogram: [(stage: String, seconds: Int)],
                      needSeconds: Int,
                      nightHR: Double?,
                      dayRHR: Double?,
                      ageYears: Double?) -> [ScoringSleepPart] {
        guard let terms = RealHealthMath.sleepScoreTerms(hypnogram: hypnogram, needSeconds: needSeconds,
                                                         nightHR: nightHR, dayRHR: dayRHR,
                                                         ageYears: ageYears) else { return [] }
        let total = terms.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        return terms.compactMap { term in
            Kind(rawValue: term.kind).map {
                ScoringSleepPart(kind: $0, weight: term.weight, share: term.weight / total * 100,
                                 credit: min(1, max(0, term.value)))
            }
        }
    }
}

// MARK: - Last night on a clock

/// One run of a single sleep stage with where it sat on the clock.
public struct ScoringStageRun: Sendable, Hashable, Codable {
    /// "awake", "rem", "core" or "deep".
    public let stage: String
    public let start: Date
    public let end: Date

    public init(stage: String, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }

    /// A session's segments laid end to end from its start, held inside its
    /// span.
    static func runs(of session: RealSleepSession) -> [ScoringStageRun] {
        var cursor = session.start
        var out: [ScoringStageRun] = []
        for segment in session.segments where segment.seconds > 0 {
            let end = min(session.end, cursor.addingTimeInterval(TimeInterval(segment.seconds)))
            guard end > cursor else { break }
            out.append(ScoringStageRun(stage: segment.stage, start: cursor, end: end))
            cursor = end
        }
        return out
    }
}

public extension SomaScoringEngine {
    /// The night that ended on each day of the window, oldest first, ending
    /// today; nil for a day with no night (a day of naps only is nil too).
    static func nightWindows(from samples: [ScoringSleepSample], days: Int, now: Date,
                             calendar: Calendar = .current) -> [ScoringNightWindow?] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let dayZero = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        var byDay: [Int: [SleepCluster]] = [:]
        for cluster in SleepSessionizer.dedupedClusters(from: lite(samples)) {
            let index = calendar.dateComponents([.day], from: dayZero, to: cluster.end).day ?? -1
            guard index >= 0, index < days else { continue }
            byDay[index, default: []].append(cluster)
        }
        return (0..<days).map { index in
            byDay[index].flatMap { nightSpan($0, calendar: calendar) }
                .map { ScoringNightWindow(start: $0.start, end: $0.end) }
        }
    }
}

// MARK: - The night heart rate dip

/// How far the sleeping heart rate fell below the resting baseline.
///
/// `dip = (resting - mean sleeping) / resting * 100`, from at least ten
/// usable beats; a thinner night is no reading rather than a two sample mean.
public struct ScoringNightDip: Sendable, Hashable {
    /// The dipping convention: under 5 percent flat, 5 to 10 shallow, 10 to
    /// 20 healthy, over 20 deep.
    public enum Band: String, Sendable, Hashable, CaseIterable {
        case flat, shallow, healthy, deep

        public init(percent: Double) {
            switch percent {
            case ..<5: self = .flat
            case 5..<10: self = .shallow
            case 10..<20: self = .healthy
            default: self = .deep
            }
        }

        /// The band's span in percent, open ended at both extremes.
        public var range: (low: Double?, high: Double?) {
            switch self {
            case .flat: (nil, 5)
            case .shallow: (5, 10)
            case .healthy: (10, 20)
            case .deep: (20, nil)
            }
        }
    }

    public static let minimumBeats = 10

    public let percent: Double
    public let meanSleepingHR: Double
    public let restingHR: Double
    public let beats: Int
    /// The lowest reading of the night and when it came.
    public let lowest: Double
    public let lowestAt: Date

    public var band: Band { Band(percent: percent) }

    /// The dip of one night, or nil below ``minimumBeats`` or without a
    /// usable resting baseline.
    public static func reading(samples: [ScoringTimedValue], restingHR: Double?) -> ScoringNightDip? {
        let beats = samples.filter { $0.value.isFinite && $0.value > 0 }
        guard beats.count >= minimumBeats, let restingHR, restingHR > 0,
              let low = beats.min(by: { $0.value < $1.value }) else { return nil }
        let mean = beats.reduce(0) { $0 + $1.value } / Double(beats.count)
        return ScoringNightDip(percent: (restingHR - mean) / restingHR * 100, meanSleepingHR: mean,
                               restingHR: restingHR, beats: beats.count,
                               lowest: low.value, lowestAt: low.start)
    }

    /// The dip from a night's mean heart rate alone, for history nights read
    /// as one average.
    public static func percent(meanSleepingHR: Double?, restingHR: Double?) -> Double? {
        guard let mean = meanSleepingHR, mean > 0, let restingHR, restingHR > 0 else { return nil }
        return (restingHR - mean) / restingHR * 100
    }
}

// MARK: - A personal usual band

/// Where a signal usually sits for this person: the median of their own
/// recent values with one robust spread either side.
public struct ScoringUsual: Sendable, Hashable {
    public let center: Double
    public let low: Double
    public let high: Double
    public let count: Int

    public init(center: Double, low: Double, high: Double, count: Int) {
        self.center = center
        self.low = low
        self.high = high
        self.count = count
    }

    /// Spread floors, in each signal's unit, so a flat stretch of history
    /// cannot draw a band too thin to leave.
    public enum Floor {
        public static let hrvMilliseconds = HealthStats.SpreadFloor.hrvMilliseconds
        public static let restingHR = HealthStats.SpreadFloor.restingHR
        public static let respiratoryRate = HealthStats.SpreadFloor.respiratoryRate
        public static let wristTemperature = HealthStats.SpreadFloor.wristTemperature
        public static let sleepHours = HealthStats.SpreadFloor.sleepHours
        public static let scorePoints = HealthStats.SpreadFloor.scorePoints
    }

    /// Seven values before a band is drawn: the engine's reliable tier.
    public static let minimumCount = HealthStats.DataGate.reliable.nights

    /// The usual band of `values`, or nil below ``minimumCount``.
    public static func of(_ values: [Double?], spreadFloor: Double) -> ScoringUsual? {
        let clean = values.compactMap { $0 }.filter(\.isFinite)
        guard clean.count >= minimumCount,
              let baseline = HealthStats.baseline(clean, spreadFloor: spreadFloor) else { return nil }
        return ScoringUsual(center: baseline.center, low: baseline.center - baseline.spread,
                            high: baseline.center + baseline.spread, count: baseline.count)
    }

    public func contains(_ value: Double) -> Bool { value >= low && value <= high }
}

// MARK: - Stress through the day

/// One half hour of the stress line.
public struct ScoringStressPoint: Sendable, Hashable {
    public let start: Date
    /// 0 to 100.
    public let value: Double
}

public enum ScoringIntradayStress {
    /// Half hour buckets.
    public static let bucketMinutes = 30

    /// The stress line from midnight to now: each half hour's mean heart
    /// rate against rest, with the day's HRV deficit as its floor (the acute
    /// model). A half hour with no reading, or one that falls inside sleep or
    /// a workout, is left out rather than scored: sleep is not stress, and a
    /// run raises the heart for a reason the score does not count.
    public static func line(heartRate: [ScoringTimedValue],
                            dayStart: Date,
                            now: Date,
                            excluded: [ScoringNightWindow],
                            hrv: Double?,
                            hrvBaseline: Double?,
                            restingHR: Double?,
                            maxHR: Double) -> [ScoringStressPoint] {
        let span = TimeInterval(bucketMinutes * 60)
        let count = max(0, Int(ceil(now.timeIntervalSince(dayStart) / span)))
        guard count > 0 else { return [] }
        var sums = Array(repeating: 0.0, count: count)
        var counts = Array(repeating: 0, count: count)
        for reading in heartRate where reading.start >= dayStart && reading.start <= now {
            let index = Int(reading.start.timeIntervalSince(dayStart) / span)
            guard index >= 0, index < count, reading.value > 0 else { continue }
            sums[index] += reading.value
            counts[index] += 1
        }
        var inputs = VitalityInputs(now: now, bucketMinutes: bucketMinutes)
        inputs.hrv = hrv
        inputs.hrvBaseline = hrvBaseline
        inputs.restingHR = restingHR
        inputs.maxHR = maxHR
        return (0..<count).compactMap { index in
            guard counts[index] > 0 else { return nil }
            let start = dayStart.addingTimeInterval(Double(index) * span)
            let middle = start.addingTimeInterval(span / 2)
            guard !excluded.contains(where: { middle >= $0.start && middle <= $0.end }) else { return nil }
            let mean = sums[index] / Double(counts[index])
            return ScoringStressPoint(start: start,
                                      value: StressEngine.instantaneous(hr: mean, inputs: inputs))
        }
    }
}
