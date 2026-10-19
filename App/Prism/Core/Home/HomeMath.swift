//
//  HomeMath.swift
//  Prism
//
//  The arithmetic behind the pages Pulse's Today opens: a marker against its
//  usual, last night's stages, the day's stand hours, the cycle, the rise
//  after a meal, and a workout's effort. Plain functions over readings, so
//  each is tested without a Health store.
//

import Foundation
import HealthExportCore

// MARK: - A marker against its usual

/// One marker's days: a value per day, the usual band, and how it moved.
struct HomeMarkerSeries: Equatable, Sendable {
    struct Change: Equatable, Sendable, Identifiable {
        var id: Int { days }
        var days: Int
        /// The last seven days' mean against the seven days that ended
        /// `days` ago. Nil without enough readings on both sides.
        var change: Double?
    }

    /// One value per day, oldest first, nil on a day with none.
    var days: [Double?]
    var latest: Double?
    /// The median of the thirty days before the latest.
    var usual: Double?
    /// The middle half of those thirty days.
    var band: ClosedRange<Double>?
    var changes: [Change]

    static let periods = [3, 7, 14, 30, 90]

    /// Builds the series for the `count` days ending on `today`.
    ///
    /// - Parameter aggregate: how a day's readings become one value: the
    ///   median for a resting rate, the mean for HRV.
    static func make(
        _ readings: [HealthReading],
        days count: Int,
        today: Date,
        calendar: Calendar,
        aggregate: ([Double]) -> Double? = PulseSignals.median
    ) -> HomeMarkerSeries {
        let start = calendar.startOfDay(for: today)
        var byDay: [Date: [Double]] = [:]
        for reading in readings {
            byDay[calendar.startOfDay(for: reading.start), default: []].append(reading.value)
        }
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: start) ?? start }
        func value(_ offset: Int) -> Double? { byDay[day(offset)].flatMap(aggregate) }

        let span = max(count, 97)
        let all = (0..<span).reversed().map { value($0) }
        let shown = Array(all.suffix(count))
        let latestOffset = (0..<3).first { value($0) != nil }
        let latest = latestOffset.flatMap(value)

        let earlier = (1...30).compactMap { offset in value((latestOffset ?? 0) + offset) }
        var usual: Double?
        var band: ClosedRange<Double>?
        if earlier.count >= 5 {
            usual = PulseSignals.median(earlier)
            if let low = PulseSignals.percentile(earlier, 0.25), let high = PulseSignals.percentile(earlier, 0.75) {
                band = low...max(low, high)
            }
        }

        func mean(_ offsets: ClosedRange<Int>) -> Double? {
            let found = offsets.compactMap(value)
            return found.count >= 3 ? found.reduce(0, +) / Double(found.count) : nil
        }
        let recent = mean(0...6)
        let changes = periods.map { period -> Change in
            guard let recent, let before = mean(period...(period + 6)) else { return Change(days: period, change: nil) }
            return Change(days: period, change: recent - before)
        }

        return HomeMarkerSeries(days: shown, latest: latest, usual: usual, band: band, changes: changes)
    }

    /// How a change reads: rising, falling or steady, against a step that
    /// counts as moving for this marker.
    static func direction(_ change: Double?, step: Double) -> String {
        guard let change else { return "-" }
        if change >= step { return "Rising" }
        if change <= -step { return "Falling" }
        return "Steady"
    }
}

// MARK: - Last night

/// Last night's sleep in stages.
struct HomeNightStages: Equatable, Sendable {
    enum Stage: Int, CaseIterable, Sendable {
        case awake = 2, rem = 5, core = 3, deep = 4, asleep = 1

        var title: String {
            switch self {
            case .awake: "Awake"
            case .rem: "REM"
            case .core: "Core"
            case .deep: "Deep"
            case .asleep: "Asleep"
            }
        }

        /// The row the hypnogram draws it on, top first.
        var row: Int {
            switch self {
            case .awake: 0
            case .rem: 1
            case .core, .asleep: 2
            case .deep: 3
            }
        }
    }

    struct Segment: Equatable, Sendable {
        var stage: Stage
        var start: Date
        var end: Date
    }

    var night: PulseNight
    var segments: [Segment]
    /// Seconds in each stage.
    var totals: [Stage: TimeInterval]
    /// Times awake inside the night, and when.
    var wakings: [Date]
    /// Minutes from bed to sleep, when bed was recorded.
    var latency: TimeInterval?

    var isStaged: Bool { totals[.deep] != nil || totals[.rem] != nil || totals[.core] != nil }

    /// Last night, or nil when the store holds no sleep ending today.
    static func make(_ samples: [HealthReading], now: Date, calendar: Calendar) -> HomeNightStages? {
        let today = calendar.startOfDay(for: now)
        guard let night = PulseNights.nights(from: samples, calendar: calendar)
            .last(where: { $0.day == today && $0.woke <= now }) else { return nil }

        let window = night.fellAsleep..<night.woke
        var segments: [Segment] = []
        var totals: [Stage: TimeInterval] = [:]
        for stage in Stage.allCases {
            let spans = PulseNights.merged(samples.filter { Int($0.value) == stage.rawValue })
                .compactMap { span -> Range<Date>? in
                    let start = max(span.lowerBound, window.lowerBound)
                    let end = min(span.upperBound, window.upperBound)
                    return start < end ? start..<end : nil
                }
            guard !spans.isEmpty else { continue }
            totals[stage] = spans.reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
            segments += spans.map { Segment(stage: stage, start: $0.lowerBound, end: $0.upperBound) }
        }
        // A night recorded without stages is one plain "asleep"; with stages,
        // the unspecified samples double the staged ones and are dropped.
        if totals[.deep] != nil || totals[.core] != nil || totals[.rem] != nil {
            segments.removeAll { $0.stage == .asleep }
            totals[.asleep] = nil
        }
        segments.sort { $0.start < $1.start }

        // A waking is an awake stretch of three minutes or more.
        let wakings = segments
            .filter { $0.stage == .awake && $0.end.timeIntervalSince($0.start) >= 3 * 60 }
            .map(\.start)

        let latency = night.bedtime < night.fellAsleep ? night.fellAsleep.timeIntervalSince(night.bedtime) : nil
        return HomeNightStages(night: night, segments: segments, totals: totals, wakings: wakings, latency: latency)
    }
}

// MARK: - Stand hours

/// The day hour by hour, as Apple Watch counts stand hours.
enum HomeStandHour: Equatable, Sendable {
    case stood, missed, now, open

    /// `HKCategoryValueAppleStandHour`: 0 is stood, 1 is idle.
    static func day(_ samples: [HealthReading], now: Date, calendar: Calendar) -> [HomeStandHour] {
        let today = calendar.startOfDay(for: now)
        let nowHour = calendar.component(.hour, from: now)
        var stood = Set<Int>()
        var idle = Set<Int>()
        for sample in samples where calendar.startOfDay(for: sample.start) == today {
            let hour = calendar.component(.hour, from: sample.start)
            if Int(sample.value) == 0 { stood.insert(hour) } else { idle.insert(hour) }
        }
        return (0..<24).map { hour in
            if stood.contains(hour) { return .stood }
            if hour == nowHour { return .now }
            if hour > nowHour { return .open }
            return idle.contains(hour) ? .missed : .open
        }
    }
}

// MARK: - The cycle

/// Where the person is in their cycle, from the flow Health holds.
struct HomeCycle: Equatable, Sendable {
    enum Phase: String, Sendable {
        case menstrual, follicular, ovulatory, luteal

        var title: String {
            switch self {
            case .menstrual: "Menstrual"
            case .follicular: "Follicular"
            case .ovulatory: "Ovulatory"
            case .luteal: "Luteal"
            }
        }
    }

    /// The first day of each period, oldest first.
    var starts: [Date]
    /// Day of the cycle today, 1 on the first day of the last period.
    var day: Int
    /// The median of the recent cycle lengths: nil until two periods are on
    /// record.
    var length: Int?
    var phase: Phase?
    var nextStart: Date?
    /// The lengths of the cycles on record, most recent last.
    var lengths: [Int]

    /// Two days of flow further apart than this start a new period.
    static let gapDays = 10

    /// The cycle for `flowDays`, the days Health recorded any flow on, or nil
    /// when none is on record.
    static func make(flowDays: [Date], today: Date, calendar: Calendar) -> HomeCycle? {
        let days = Set(flowDays.map { calendar.startOfDay(for: $0) }).sorted()
        guard !days.isEmpty else { return nil }
        let start = calendar.startOfDay(for: today)

        var starts: [Date] = []
        var previous: Date?
        for day in days where day <= start {
            if let previous, let gap = calendar.dateComponents([.day], from: previous, to: day).day, gap < gapDays {
                // Still the same period.
            } else {
                starts.append(day)
            }
            previous = day
        }
        guard let last = starts.last,
              let elapsed = calendar.dateComponents([.day], from: last, to: start).day else { return nil }

        let lengths = zip(starts, starts.dropFirst()).compactMap { pair -> Int? in
            guard let days = calendar.dateComponents([.day], from: pair.0, to: pair.1).day,
                  (15...60).contains(days) else { return nil }
            return days
        }
        let length = lengths.isEmpty ? nil : PulseSignals.median(lengths.suffix(6).map(Double.init)).map { Int($0.rounded()) }
        let day = elapsed + 1

        var phase: Phase?
        if let length {
            // Ovulation sits about fourteen days before the next period.
            let ovulation = length - 14
            let periodDays = days.filter { $0 >= last }.count
            switch day {
            case ...max(periodDays, 1): phase = .menstrual
            case ..<(ovulation - 1): phase = .follicular
            case (ovulation - 1)...(ovulation + 1): phase = .ovulatory
            default: phase = .luteal
            }
        }
        let nextStart = length.flatMap { calendar.date(byAdding: .day, value: $0, to: last) }
        return HomeCycle(starts: starts, day: day, length: length, phase: phase, nextStart: nextStart, lengths: lengths)
    }
}

// MARK: - After a meal

/// How far blood glucose rose after a meal.
struct HomeMealResponse: Equatable, Sendable {
    /// Peak above the level before the meal, in mg/dL.
    var rise: Double
    var peakAt: Date
    /// Minutes until glucose came back within 5 mg/dL of the level before,
    /// nil when it had not by the last reading.
    var backToBaseline: TimeInterval?
    /// Readings after the meal, as minutes from it and mg/dL above baseline.
    var curve: [(minutes: Double, above: Double)]

    static func == (lhs: HomeMealResponse, rhs: HomeMealResponse) -> Bool {
        lhs.rise == rhs.rise && lhs.peakAt == rhs.peakAt && lhs.backToBaseline == rhs.backToBaseline
            && lhs.curve.map(\.minutes) == rhs.curve.map(\.minutes) && lhs.curve.map(\.above) == rhs.curve.map(\.above)
    }

    /// The response to a meal eaten at `time`, or nil without a reading in the
    /// half hour before it and two in the three hours after.
    static func make(meal time: Date, glucose: [HealthReading]) -> HomeMealResponse? {
        let before = glucose.filter { $0.start >= time.addingTimeInterval(-30 * 60) && $0.start <= time }
        let after = glucose.filter { $0.start > time && $0.start <= time.addingTimeInterval(3 * 60 * 60) }
            .sorted { $0.start < $1.start }
        guard !before.isEmpty, after.count >= 2 else { return nil }
        let baseline = before.map(\.value).reduce(0, +) / Double(before.count)
        guard let peak = after.max(by: { $0.value < $1.value }) else { return nil }
        let back = after.first { $0.start > peak.start && $0.value - baseline <= 5 }
        return HomeMealResponse(
            rise: max(0, peak.value - baseline),
            peakAt: peak.start,
            backToBaseline: back.map { $0.start.timeIntervalSince(time) },
            curve: after.map { ($0.start.timeIntervalSince(time) / 60, $0.value - baseline) }
        )
    }
}

// MARK: - A workout's effort

enum HomeEffortMath {
    /// Soma's own read of a workout on the CR10 scale, from how hard the heart
    /// worked: the average rate as a share of the age-predicted maximum, mapped
    /// onto the zones (50 percent easy, 90 percent all out).
    static func somaRead(averageHeartRate: Double?, age: Int?) -> Int? {
        guard let average = averageHeartRate, let age, age > 0 else { return nil }
        let share = average / Double(220 - age)
        let rating = ((share - 0.5) / 0.4 * 9 + 1).rounded()
        return Int(min(10, max(1, rating)))
    }

    /// Foster's session load: the rating times the minutes, summed over the
    /// seven days ending on `now`.
    static func weekLoad(_ efforts: [HomeEffort], now: Date, calendar: Calendar) -> Int? {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let week = efforts.filter { $0.workoutStart >= start && $0.workoutStart <= now }
        guard !week.isEmpty else { return nil }
        return Int(week.reduce(0) { $0 + Double($1.rating) * $1.minutes }.rounded())
    }

    /// The word for a CR10 rating.
    static func word(_ rating: Int) -> String {
        switch rating {
        case ...2: "Easy"
        case 3...4: "Moderate"
        case 5...6: "Somewhat hard"
        case 7...8: "Hard"
        case 9: "Very hard"
        default: "All out"
        }
    }
}
