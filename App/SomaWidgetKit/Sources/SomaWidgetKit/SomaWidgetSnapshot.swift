import Foundation

/// Everything the widgets draw, written by the app and read by the extension.
/// Every field except `generatedAt` decodes with a default, so a file written by
/// an older build still decodes instead of blanking the widget.
public struct SomaWidgetSnapshot: Codable, Equatable, Sendable {
    public struct Score: Codable, Equatable, Sendable {
        public var value: Double?
        public var series7: [Double?]

        public init(value: Double? = nil, series7: [Double?] = []) {
            self.value = value
            self.series7 = series7
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decodeIfPresent(Double.self, forKey: .value)
            series7 = try c.decodeIfPresent([Double?].self, forKey: .series7) ?? []
        }
    }

    public struct Vital: Codable, Equatable, Sendable {
        public var value: Double?
        public var series7: [Double?]

        public init(value: Double? = nil, series7: [Double?] = []) {
            self.value = value
            self.series7 = series7
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decodeIfPresent(Double.self, forKey: .value)
            series7 = try c.decodeIfPresent([Double?].self, forKey: .series7) ?? []
        }
    }

    public struct EnergyPoint: Codable, Equatable, Sendable {
        public var date: Date
        public var level: Double

        public init(date: Date, level: Double) {
            self.date = date
            self.level = level
        }
    }

    /// Today's logged intake. `countedIDs` holds the inbox items already in the
    /// counts, so the widget and the app never count one item twice.
    public struct Tally: Codable, Equatable, Sendable {
        /// "yyyy-MM-dd", local calendar.
        public var day: String
        public var waterMl: Double
        public var caffeineMg: Double
        public var moods: Int
        public var meals: Int
        public var waterGoalMl: Double
        public var countedIDs: Set<UUID>

        public init(
            day: String,
            waterMl: Double = 0,
            caffeineMg: Double = 0,
            moods: Int = 0,
            meals: Int = 0,
            waterGoalMl: Double = 2000,
            countedIDs: Set<UUID> = []
        ) {
            self.day = day
            self.waterMl = waterMl
            self.caffeineMg = caffeineMg
            self.moods = moods
            self.meals = meals
            self.waterGoalMl = waterGoalMl
            self.countedIDs = countedIDs
        }

        public static func empty(day: String) -> Tally {
            Tally(day: day)
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
            waterMl = try c.decodeIfPresent(Double.self, forKey: .waterMl) ?? 0
            caffeineMg = try c.decodeIfPresent(Double.self, forKey: .caffeineMg) ?? 0
            moods = try c.decodeIfPresent(Int.self, forKey: .moods) ?? 0
            meals = try c.decodeIfPresent(Int.self, forKey: .meals) ?? 0
            waterGoalMl = try c.decodeIfPresent(Double.self, forKey: .waterGoalMl) ?? 2000
            countedIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .countedIDs) ?? []
        }
    }

    public var generatedAt: Date
    public var hasData: Bool
    /// All 0...100, like SomaScores.
    public var sleep: Score
    public var recovery: Score
    public var strain: Score
    public var stress: Score
    public var energyNow: Double?
    /// Bedtime to now.
    public var energyCurve: [EnergyPoint]
    /// Last night, for the curve's grey block.
    public var sleepBand: ClosedRange<Date>?
    public var restingHR: Vital
    public var hrv: Vital
    public var sleepHours: Vital
    /// Large Vitals only.
    public var hypnogram: [Stage]?
    public var burnedKcal: Double?
    public var eatenKcal: Double?
    public var tally: Tally

    public init(
        generatedAt: Date,
        hasData: Bool = false,
        sleep: Score = Score(),
        recovery: Score = Score(),
        strain: Score = Score(),
        stress: Score = Score(),
        energyNow: Double? = nil,
        energyCurve: [EnergyPoint] = [],
        sleepBand: ClosedRange<Date>? = nil,
        restingHR: Vital = Vital(),
        hrv: Vital = Vital(),
        sleepHours: Vital = Vital(),
        hypnogram: [Stage]? = nil,
        burnedKcal: Double? = nil,
        eatenKcal: Double? = nil,
        tally: Tally = .empty(day: "")
    ) {
        self.generatedAt = generatedAt
        self.hasData = hasData
        self.sleep = sleep
        self.recovery = recovery
        self.strain = strain
        self.stress = stress
        self.energyNow = energyNow
        self.energyCurve = energyCurve
        self.sleepBand = sleepBand
        self.restingHR = restingHR
        self.hrv = hrv
        self.sleepHours = sleepHours
        self.hypnogram = hypnogram
        self.burnedKcal = burnedKcal
        self.eatenKcal = eatenKcal
        self.tally = tally
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        hasData = try c.decodeIfPresent(Bool.self, forKey: .hasData) ?? false
        sleep = try c.decodeIfPresent(Score.self, forKey: .sleep) ?? Score()
        recovery = try c.decodeIfPresent(Score.self, forKey: .recovery) ?? Score()
        strain = try c.decodeIfPresent(Score.self, forKey: .strain) ?? Score()
        stress = try c.decodeIfPresent(Score.self, forKey: .stress) ?? Score()
        energyNow = try c.decodeIfPresent(Double.self, forKey: .energyNow)
        energyCurve = try c.decodeIfPresent([EnergyPoint].self, forKey: .energyCurve) ?? []
        // A malformed band (a reversed range) drops the band alone.
        sleepBand = (try? c.decodeIfPresent(ClosedRange<Date>.self, forKey: .sleepBand)) ?? nil
        restingHR = try c.decodeIfPresent(Vital.self, forKey: .restingHR) ?? Vital()
        hrv = try c.decodeIfPresent(Vital.self, forKey: .hrv) ?? Vital()
        sleepHours = try c.decodeIfPresent(Vital.self, forKey: .sleepHours) ?? Vital()
        hypnogram = try c.decodeIfPresent([Stage].self, forKey: .hypnogram)
        burnedKcal = try c.decodeIfPresent(Double.self, forKey: .burnedKcal)
        eatenKcal = try c.decodeIfPresent(Double.self, forKey: .eatenKcal)
        tally = try c.decodeIfPresent(Tally.self, forKey: .tally) ?? .empty(day: "")
    }
}

/// One stretch of a night's sleep, for the hypnogram.
public struct Stage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case awake, rem, core, deep }
    public var kind: Kind
    public var start: Date
    public var end: Date

    public init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}

public enum Freshness: Equatable, Sendable {
    case fresh
    case stale(hours: Int)
}

public extension SomaWidgetSnapshot {
    /// Stale when older than 12 hours.
    func freshness(now: Date) -> Freshness {
        let age = now.timeIntervalSince(generatedAt)
        guard age > 12 * 3600 else { return .fresh }
        return .stale(hours: Int(age / 3600))
    }
}

public extension SomaWidgetSnapshot {
    /// The one fixture for the widget gallery, previews and render review.
    ///
    /// Noon UTC on 2026-10-03: the night ran 21:00 to 05:00, and the energy
    /// curve runs from bedtime to noon, under the sleep block and after it.
    static let placeholder: SomaWidgetSnapshot = {
        // 2026-10-03T12:00:00Z.
        let now = Date(timeIntervalSince1970: 1_791_028_800)
        let bedtime = now.addingTimeInterval(-15 * 3600)
        let wake = now.addingTimeInterval(-7 * 3600)
        // Half hour points from bedtime to now: the bank fills through the
        // night to 80, then drains to 70 by noon, with a small swell every
        // five hours that is back to zero at both ends.
        let curve = (0...30).map { i in
            let hours = Double(i) / 2
            let trend = hours <= 8 ? 30 + 50 * hours / 8 : 80 - 10 * (hours - 8) / 7
            let swell = 3 * sin(2 * .pi * hours / 5)
            return EnergyPoint(date: bedtime.addingTimeInterval(hours * 3600), level: trend + swell)
        }
        // Five cycles through the night, in minutes from bedtime; they add up
        // to the eight hours of the band.
        let cycle: [(Stage.Kind, Double)] = [
            (.awake, 10), (.core, 40), (.deep, 50), (.core, 20), (.rem, 15),
            (.core, 35), (.deep, 40), (.core, 20), (.rem, 25),
            (.awake, 5), (.core, 45), (.deep, 20), (.core, 20), (.rem, 35),
            (.core, 50), (.rem, 40), (.awake, 10),
        ]
        var stages: [Stage] = []
        var cursor = bedtime
        for (kind, minutes) in cycle {
            let end = cursor.addingTimeInterval(minutes * 60)
            stages.append(Stage(kind: kind, start: cursor, end: end))
            cursor = end
        }
        let series: [Double?] = [70, 74, 68, 77, 80, 76, 82]
        return SomaWidgetSnapshot(
            generatedAt: now,
            hasData: true,
            sleep: Score(value: 80, series7: series),
            recovery: Score(value: 82, series7: series),
            strain: Score(value: 54, series7: [40, 52, 61, 48, 57, 66, 54]),
            stress: Score(value: 39, series7: [45, 41, 50, 38, 36, 42, 39]),
            energyNow: 70,
            energyCurve: curve,
            sleepBand: bedtime...wake,
            restingHR: Vital(value: 52, series7: [54, 53, 53, 52, 52, 51, 52]),
            hrv: Vital(value: 64, series7: [58, 61, 60, 63, 66, 62, 64]),
            sleepHours: Vital(value: 7.2, series7: [6.8, 7.4, 7.0, 7.6, 6.9, 7.3, 7.2]),
            hypnogram: stages,
            burnedKcal: 2310,
            eatenKcal: 1980,
            tally: Tally(day: "2026-10-03", waterMl: 1250)
        )
    }()
}
