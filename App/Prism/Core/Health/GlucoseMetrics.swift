//
//  GlucoseMetrics.swift
//  Prism
//
//  A continuous glucose monitor's readings, read the way the international
//  consensus on time in range reads them (Battelino et al., Diabetes Care
//  2019;42:1593): the share of readings in 70 to 180 mg/dL, under 70 and
//  under 54, over 180 and over 250; the mean; GMI (Bergenstal et al.,
//  Diabetes Care 2018;41:2275); the coefficient of variation; the hourly
//  profile of a fortnight; and what each meal logged in Track did over the
//  two hours after it.
//
//  Health stores glucose in mg/dL. The unit a person chose in Settings is
//  applied when a number is shown, never to the arithmetic, so a share or a
//  GMI cannot move with the setting.
//

import Foundation
import HealthExportCore

// MARK: - Units

extension GlucoseUnit {
    /// mg/dL in one mmol/L of glucose: its molar mass, 180.16 g/mol, over ten.
    nonisolated static let milligramsPerMillimole = 18.016

    /// A value read in mg/dL, in this unit.
    nonisolated func value(milligrams: Double) -> Double {
        self == .milligrams ? milligrams : milligrams / Self.milligramsPerMillimole
    }

    /// A value read in mg/dL, written in this unit: whole mg/dL, mmol/L to
    /// one decimal. A dash when there is nothing.
    nonisolated func text(milligrams: Double?) -> String {
        guard let milligrams else { return "-" }
        let value = value(milligrams: milligrams)
        return value.formatted(.number.precision(.fractionLength(self == .milligrams ? 0 : 1)).grouping(.never))
    }

    /// A value with its unit: "70 mg/dL", "3.9 mmol/L".
    nonisolated func label(milligrams: Double) -> String {
        "\(text(milligrams: milligrams)) \(title)"
    }
}

// MARK: - The consensus ranges

/// The thresholds the consensus draws, in mg/dL. Its targets for most adults
/// with diabetes: more than 70 % in range, under 4 % below 70, under 1 %
/// below 54, under 25 % above 180, under 5 % above 250, a CV of 36 % or less.
nonisolated enum GlucoseRange {
    static let low = 70.0
    /// Level 2 hypoglycaemia: clinically significant, whatever the symptoms.
    static let veryLow = 54.0
    static let high = 180.0
    static let veryHigh = 250.0

    static let targetInRange = 0.70
    static let targetBelow70 = 0.04
    static let targetBelow54 = 0.01
    static let targetAbove180 = 0.25
    static let targetCV = 36.0
}

// MARK: - A meal

/// What glucose did over the two hours after a meal logged in Track. Values
/// in mg/dL; the page writes them in the person's unit.
nonisolated struct MealResponse: Equatable, Identifiable, Sendable {
    var id: UUID { mealID }
    var mealID: UUID
    var name: String
    var meal: TrackMeal
    var date: Date
    /// The mean of the readings in the half hour before the meal.
    var baseline: Double
    /// The highest reading in the two hours after it.
    var peak: Double
    var rise: Double { max(0, peak - baseline) }
    /// Minutes from the meal to the peak.
    var peakMinutes: Double
    /// Minutes from the meal until a reading after the peak came back within
    /// 5 mg/dL of the baseline. Nil when it had not inside the two hours.
    var returnMinutes: Double?

    /// The window a meal is read over.
    static let window: TimeInterval = 2 * 3600
    static let lead: TimeInterval = 30 * 60
    static let settled = 5.0

    /// The response to one meal, or nil without a reading in the half hour
    /// before it and two in the two hours after: half a trace is not a peak.
    static func make(_ entry: TrackMealEntry, sorted samples: [HealthReading]) -> MealResponse? {
        let time = entry.date
        let before = samples.filter { $0.start >= time.addingTimeInterval(-lead) && $0.start <= time }
        let after = samples.filter { $0.start > time && $0.start <= time.addingTimeInterval(window) }
        guard !before.isEmpty, after.count >= 2, let peak = after.max(by: { $0.value < $1.value }) else { return nil }
        let baseline = before.map(\.value).reduce(0, +) / Double(before.count)
        let back = after.first { $0.start > peak.start && $0.value - baseline <= settled }
        return MealResponse(
            mealID: entry.id, name: entry.name, meal: entry.meal, date: time,
            baseline: baseline, peak: peak.value,
            peakMinutes: peak.start.timeIntervalSince(time) / 60,
            returnMinutes: back.map { $0.start.timeIntervalSince(time) / 60 }
        )
    }
}

// MARK: - The hourly profile

/// One hour of the ambulatory profile: where the fortnight's readings at that
/// hour sat, from the 10th to the 90th percentile, in mg/dL.
nonisolated struct GlucoseProfileHour: Equatable, Sendable {
    var hour: Int
    var p10: Double
    var p25: Double
    var median: Double
    var p75: Double
    var p90: Double
}

// MARK: - The summary

/// A fortnight of glucose, read once for the page. Shares are 0 to 1; every
/// value is nil when it cannot be read honestly, and the time shares, the
/// mean, GMI, the variation and the profile are only read off a monitor's
/// trace: three finger sticks a day say nothing about the hours between.
nonisolated struct GlucoseSummary: Equatable, Sendable {
    var unit: GlucoseUnit
    /// True when more than 70 % of the readings sit in a continuous trace.
    var isContinuous: Bool
    var readingCount: Int
    /// Days between the first reading and the last.
    var daysCovered: Double

    var timeInRange: Double?
    var timeBelow70: Double?
    var timeBelow54: Double?
    var timeAbove180: Double?
    var timeAbove250: Double?
    var averageMilligrams: Double?
    /// Glucose management indicator, in percent: an HbA1c estimated from the mean.
    var gmi: Double?
    /// Coefficient of variation, in percent.
    var cv: Double?
    var profile: [GlucoseProfileHour]
    var meals: [MealResponse]
    /// What to do about a reading under 54 mg/dL. Shown above every number,
    /// and set from any reading, a finger stick's too.
    var urgentNote: String?

    /// The mean in the person's unit.
    var average: Double? { averageMilligrams.map { unit.value(milligrams: $0) } }

    /// Two readings this close sit in one trace: a 5 minute sensor, or a
    /// 15 minute one with a reading lost.
    static let traceGap: TimeInterval = 20 * 60
    /// The share of readings that have to sit in a trace for the page to read
    /// them as a monitor's.
    static let continuousShare = 0.7
    /// An hour of a 5 minute sensor: fewer readings are not yet a trace.
    static let minimumTrace = 12
    /// How old a reading under 54 can be and still be "now".
    static let recent: TimeInterval = 30 * 60

    static func make(
        samples: [HealthReading],
        meals: [TrackMealEntry],
        unit: GlucoseUnit,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GlucoseSummary {
        let sorted = samples.filter { $0.value > 0 }.sorted { $0.start < $1.start }
        let values = sorted.map(\.value)
        let continuous = isContinuous(sorted)
        let span = (sorted.last?.start.timeIntervalSince(sorted.first?.start ?? now) ?? 0) / 86_400
        var summary = GlucoseSummary(
            unit: unit, isContinuous: continuous, readingCount: sorted.count, daysCovered: span,
            profile: [], meals: [], urgentNote: urgentNote(sorted, unit: unit, now: now)
        )
        guard continuous else { return summary }

        let count = Double(values.count)
        func share(_ test: (Double) -> Bool) -> Double { Double(values.filter(test).count) / count }
        summary.timeInRange = share { $0 >= GlucoseRange.low && $0 <= GlucoseRange.high }
        summary.timeBelow70 = share { $0 < GlucoseRange.low }
        summary.timeBelow54 = share { $0 < GlucoseRange.veryLow }
        summary.timeAbove180 = share { $0 > GlucoseRange.high }
        summary.timeAbove250 = share { $0 > GlucoseRange.veryHigh }

        let mean = values.reduce(0, +) / count
        summary.averageMilligrams = mean
        // GMI (%) = 3.31 + 0.02392 x mean glucose in mg/dL (Bergenstal 2018).
        summary.gmi = 3.31 + 0.02392 * mean
        if values.count >= 2 {
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (count - 1)
            summary.cv = variance.squareRoot() / mean * 100
        }
        summary.profile = profile(sorted, calendar: calendar)
        summary.meals = meals
            .filter { $0.date <= now }
            .sorted { $0.date > $1.date }
            .compactMap { MealResponse.make($0, sorted: sorted) }
        return summary
    }

    /// More than 70 % of the readings have a neighbour within 20 minutes.
    static func isContinuous(_ sorted: [HealthReading]) -> Bool {
        guard sorted.count >= minimumTrace else { return false }
        var linked = 0
        for index in sorted.indices {
            let previous = index > 0 ? sorted[index].start.timeIntervalSince(sorted[index - 1].start) : .infinity
            let next = index < sorted.count - 1 ? sorted[index + 1].start.timeIntervalSince(sorted[index].start) : .infinity
            if min(previous, next) <= traceGap { linked += 1 }
        }
        return Double(linked) / Double(sorted.count) > continuousShare
    }

    /// The percentiles of each clock hour, for the hours that have readings.
    static func profile(_ sorted: [HealthReading], calendar: Calendar) -> [GlucoseProfileHour] {
        Dictionary(grouping: sorted, by: { calendar.component(.hour, from: $0.start) })
            .compactMap { hour, readings -> GlucoseProfileHour? in
                let values = readings.map(\.value).sorted()
                guard values.count >= 3 else { return nil }
                return GlucoseProfileHour(
                    hour: hour,
                    p10: percentile(values, 0.10), p25: percentile(values, 0.25), median: percentile(values, 0.50),
                    p75: percentile(values, 0.75), p90: percentile(values, 0.90)
                )
            }
            .sorted { $0.hour < $1.hour }
    }

    /// Linear interpolation between the closest ranks of sorted values.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let rank = p * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down))
        let high = min(low + 1, sorted.count - 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (rank - Double(low))
    }

    /// The note a reading under 54 mg/dL brings. When the latest reading is
    /// that low and minutes old, what to do now comes first: the rule of 15
    /// of the ADA's Standards of Care (2025, section 6). Informative, never a
    /// diagnosis: a doctor reads a pattern of lows.
    static func urgentNote(_ sorted: [HealthReading], unit: GlucoseUnit, now: Date) -> String? {
        let lows = sorted.filter { $0.value < GlucoseRange.veryLow }
        guard !lows.isEmpty else { return nil }
        let threshold = unit.label(milligrams: GlucoseRange.veryLow)
        if let latest = sorted.last, latest.value < GlucoseRange.veryLow, now.timeIntervalSince(latest.start) <= recent {
            return "Your latest reading is under \(threshold). Take 15 g of fast sugar, juice or glucose tablets, and check again in 15 minutes. If you feel confused or faint, or it does not come up, call emergency services."
        }
        let times = lows.count == 1 ? "Once in these days" : "\(lows.count) readings in these days"
        return "\(times) glucose fell under \(threshold), a low that matters whatever you felt. Talk to your doctor about it, sooner if it happens again."
    }
}

// MARK: - The Body tile

/// The Glucose tile on the Body lens: the fortnight's time in range and the
/// last seven days of it, one bar a day. Only a monitor's trace makes one;
/// finger sticks and an empty store leave the tile out.
nonisolated struct GlucoseTile: Equatable, Sendable {
    /// The fortnight's share in 70 to 180 mg/dL, 0 to 1.
    var timeInRange: Double?
    /// Each of the last seven days in range, in percent, today last. Nil
    /// for a day with no readings.
    var days: [Double?]
    var latest: Date?

    static func make(samples: [HealthReading], now: Date = .now, calendar: Calendar = .current) -> GlucoseTile? {
        let sorted = samples.filter { $0.value > 0 && $0.start <= now }.sorted { $0.start < $1.start }
        guard GlucoseSummary.isContinuous(sorted) else { return nil }
        func inRange(_ readings: [HealthReading]) -> Double? {
            guard !readings.isEmpty else { return nil }
            let inside = readings.filter { $0.value >= GlucoseRange.low && $0.value <= GlucoseRange.high }.count
            return Double(inside) / Double(readings.count)
        }
        let byDay = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.start) }
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().map { back -> Double? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return inRange(byDay[day] ?? []).map { $0 * 100 }
        }
        return GlucoseTile(timeInRange: inRange(sorted), days: days, latest: sorted.last?.start)
    }
}
