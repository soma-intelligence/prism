//
//  ScoringTypes.swift
//  HealthScoring
//
//  The public face of the scoring engine: plain values in, plain values out.
//  Everything behind it (RealHealthMath, StressEngine, VitalitySections,
//  HealthStats, SleepSessionizer) stays internal, so the ported algorithms
//  keep their original shape and the app only ever sees these types.
//

import Foundation

/// One Apple Health sleep analysis sample, reduced to what the sessionizer
/// reads: the stage, the span and who recorded it.
public struct ScoringSleepSample: Sendable, Hashable {
    /// "awake", "rem", "core" or "deep".
    public let stage: String
    public let start: Date
    public let end: Date
    /// The recording source. Two trackers writing the same night are told
    /// apart by this, so only one of them counts.
    public let source: String

    public init(stage: String, start: Date, end: Date, source: String) {
        self.stage = stage
        self.start = start
        self.end = end
        self.source = source
    }

    /// A sample from its `HKCategoryValueSleepAnalysis` code, or nil for the
    /// in bed wrapper (code 0), which is not a stage.
    ///
    /// Awake is 2, deep 4 and REM 5; core (3) and the unspecified asleep
    /// value (1) both read as core, the way the original reader mapped them.
    public init?(code: Int, start: Date, end: Date, source: String?) {
        let stage: String
        switch code {
        case 0: return nil
        case 2: stage = "awake"
        case 4: stage = "deep"
        case 5: stage = "rem"
        default: stage = "core"
        }
        self.init(stage: stage, start: start, end: end, source: source ?? "")
    }
}

/// One timed quantity: a heart rate reading, or a slice of active energy.
public struct ScoringTimedValue: Sendable, Hashable {
    public let start: Date
    public let end: Date
    public let value: Double

    public init(start: Date, end: Date, value: Double) {
        self.start = start
        self.end = end
        self.value = value
    }
}

/// The night the engine treats as last night: where its window sits.
public struct ScoringNightWindow: Sendable, Hashable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Everything the engine needs, already read out of the store.
///
/// Every daily series runs oldest first and ends today, one entry a day, nil
/// where the store holds nothing. They are all aligned to `steps.count`.
public struct ScoringInputs: Sendable {
    public var now: Date
    public var calendar: Calendar

    /// Resting heart rate, the day's mean, bpm.
    public var restingHeartRate: [Double?]
    /// Heart rate variability (Apple SDNN), the day's mean, ms.
    public var heartRateVariability: [Double?]
    /// The day's mean heart rate over every reading, bpm.
    public var dayHeartRate: [Double?]
    public var steps: [Double?]
    /// Active energy, kcal.
    public var activeEnergy: [Double?]
    /// Apple exercise minutes.
    public var exerciseMinutes: [Double?]

    /// Sleep analysis samples covering the whole window, and the evening
    /// before its first day.
    public var sleepSamples: [ScoringSleepSample]

    /// Heart rate readings since last night's bedtime (or midnight), for the
    /// zones of today's load and the shape of today's energy.
    public var intradayHeartRate: [ScoringTimedValue]
    /// Active energy samples over the same span.
    public var intradayActiveEnergy: [ScoringTimedValue]

    /// Mean heart rate across last night, for the sleep score's dip term.
    public var lastNightHeartRate: Double?
    /// Mean HRV across last night, the first choice for today's recovery.
    public var lastNightVariability: Double?
    /// The most recent resting heart rate on record, whatever its day.
    public var latestRestingHeartRate: Double?

    /// Age in years, from the date of birth. Nil when Health has none.
    public var ageYears: Double?

    public init(
        now: Date,
        calendar: Calendar = .current,
        restingHeartRate: [Double?] = [],
        heartRateVariability: [Double?] = [],
        dayHeartRate: [Double?] = [],
        steps: [Double?] = [],
        activeEnergy: [Double?] = [],
        exerciseMinutes: [Double?] = [],
        sleepSamples: [ScoringSleepSample] = [],
        intradayHeartRate: [ScoringTimedValue] = [],
        intradayActiveEnergy: [ScoringTimedValue] = [],
        lastNightHeartRate: Double? = nil,
        lastNightVariability: Double? = nil,
        latestRestingHeartRate: Double? = nil,
        ageYears: Double? = nil
    ) {
        self.now = now
        self.calendar = calendar
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.dayHeartRate = dayHeartRate
        self.steps = steps
        self.activeEnergy = activeEnergy
        self.exerciseMinutes = exerciseMinutes
        self.sleepSamples = sleepSamples
        self.intradayHeartRate = intradayHeartRate
        self.intradayActiveEnergy = intradayActiveEnergy
        self.lastNightHeartRate = lastNightHeartRate
        self.lastNightVariability = lastNightVariability
        self.latestRestingHeartRate = latestRestingHeartRate
        self.ageYears = ageYears
    }
}

/// Which way a series has been travelling over its window.
public enum ScoringTrend: String, Sendable, Hashable {
    case rising
    case falling
    case flat
}

/// One signed term of today's recovery, with the numbers behind it.
public struct ScoringRecoveryTerm: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case hrv, rhr, sleep, rest
    }

    public let kind: Kind
    /// Signed points after shaping, confidence and the per-term cap.
    public let points: Double
    /// Today's reading (ms, bpm or a sleep score). Nil for the rest credit.
    public let value: Double?
    /// The personal baseline (ms or bpm). Nil for sleep and rest.
    public let baseline: Double?
}

/// Today's recovery, taken apart.
public struct ScoringRecoveryBreakdown: Sendable, Hashable {
    public let score: Int
    /// The neutral the terms are added to (50).
    public let baseline: Double
    /// The total before the soft knee and the clamp.
    public let rawTotal: Double
    public let terms: [ScoringRecoveryTerm]
    /// Signals with nothing recorded today: their term was skipped, not faked.
    public let missing: [ScoringRecoveryTerm.Kind]
}

/// Today's energy, half hour by half hour, ending now.
public struct ScoringEnergyCurve: Sendable, Hashable {
    /// Where the axis starts: last night's bedtime, or midnight.
    public let axisStart: Date
    /// Where it ends: the moment the curve was computed.
    public let endsAt: Date
    /// The level at `axisStart` and then at the end of each half hour lived.
    public let levels: [Double]
    /// The level now: the last point of `levels`.
    public let current: Double
    /// Whether the curve was rebuilt from measured half hours, or drawn
    /// between the ledger's anchors because no intraday energy was recorded.
    public let isMeasured: Bool

    /// Each level with the moment it describes.
    public var points: [(date: Date, level: Double)] {
        levels.enumerated().map { index, level in
            (min(endsAt, axisStart.addingTimeInterval(Double(index) * 1800)), level)
        }
    }

    public static func == (lhs: ScoringEnergyCurve, rhs: ScoringEnergyCurve) -> Bool {
        lhs.axisStart == rhs.axisStart && lhs.endsAt == rhs.endsAt && lhs.levels == rhs.levels
            && lhs.current == rhs.current && lhs.isMeasured == rhs.isMeasured
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(axisStart)
        hasher.combine(levels)
        hasher.combine(isMeasured)
    }
}

/// Everything the engine worked out. Raw engine output: the product's own
/// gates (how many nights before a score is shown) sit with the caller.
public struct ScoringResult: Sendable, Equatable {
    /// Days in every series below; the last entry is today.
    public let days: Int

    // Per day, oldest first.
    public let sleepHours: [Double?]
    public let sleepNeedHours: [Double?]
    public let sleepScore: [Double?]
    public let strain: [Double?]
    public let recovery: [Double?]
    public let stress: [Double?]
    public let energyMorning: [Double?]
    public let energyEnd: [Double?]
    public let sleepDebtHours: [Double?]
    public let hrvBaseline: [Double?]
    public let restingHeartRateBaseline: [Double?]
    public let trimp: [Double?]

    // Today.
    /// Last night's score, scored from its hypnogram. Nil when no night
    /// ended today.
    public let sleepScoreToday: Int?
    /// Today's recovery with its terms. Nil until today owns readiness data.
    public let recoveryToday: ScoringRecoveryBreakdown?
    /// Today's strain from today's zones and active energy. Nil when the day
    /// has recorded no movement at all yet.
    public let strainToday: Int?
    /// The strain band today's recovery supports.
    public let strainTargetToday: ClosedRange<Int>?
    /// Today's centered stress. Nil when today has no autonomic reading.
    public let stressToday: Int?
    /// The energy bank now, and the curve that led there. Nil before the
    /// ledger has seen a night.
    public let energyToday: ScoringEnergyCurve?
    /// Sleep debt at the last measured night, hours.
    public let sleepDebtHoursToday: Double?
    /// Tonight's personal sleep need, hours.
    public let sleepNeedHoursToday: Double

    /// Last night, when one was found.
    public let lastNight: ScoringNightWindow?

    // Evidence, for the caller's gates.
    /// Nights with any sleep recorded in the window.
    public let nightsRecorded: Int
    /// Days with an HRV reading in the baseline window.
    public let variabilityDays: Int
    /// Days with a resting heart rate in the baseline window.
    public let restingDays: Int

    // Detail, for the pages that explain a score. Defaulted so the struct
    // keeps its shape for anything built before they existed.
    /// REM and deep hours per night, attributed to the wake day.
    public var remHours: [Double?] = []
    public var deepHours: [Double?] = []
    /// Bed and wake clock hours per night (bed above 24 after midnight).
    public var bedHour: [Double?] = []
    public var wakeHour: [Double?] = []
    /// Last night's score taken apart. Empty when there is no score.
    public var sleepPartsToday: [ScoringSleepPart] = []
    /// Last night's stages in order, each with its clock span.
    public var lastNightStages: [ScoringStageRun] = []
}
