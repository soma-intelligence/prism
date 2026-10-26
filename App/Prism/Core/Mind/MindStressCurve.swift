//
//  MindStressCurve.swift
//  Prism
//
//  One day of stress, half hour by half hour, and the episodes in it.
//
//  The curve is the measured intraday stress: heart rate above resting, over
//  the span from resting to a ceiling, on 0 to 100. Workouts and the forty
//  minutes after them are effort rather than stress, and sleep is a slow heart
//  rather than a calm one, so both are gaps. The episodes are runs of medium
//  or higher in the awake, still, elapsed day, each tied to the calendar event
//  that overlaps it most.
//
//  The axis is local midnight, 48 buckets of 30 minutes, so bucket k is the
//  same clock slot on every day and two days compare slot for slot.
//

import Foundation
import HealthExportCore

/// A calendar event reduced to what Mind reads: a title, its window, who it
/// is with and the series it repeats in. The notes and the place are never
/// read, and the names never leave the device.
nonisolated struct MindCalendarEvent: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var calendarTitle: String
    var start: Date
    var end: Date
    /// The other people invited, by name, the person themself left out.
    /// Rooms and resources are not people and are dropped at the source.
    var attendees: [String] = []
    /// Shared by every occurrence of a repeating event, nil for a one off.
    /// Groups a series even when someone renames one occurrence.
    var seriesID: String? = nil

    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// One day of stress on the midnight axis.
nonisolated struct MindStressDayCurve: Equatable, Sendable {
    static let bucketMinutes = 30
    static let buckets = 48

    /// The start of the day.
    var day: Date
    /// ``buckets`` values, 0 to 100, nil where nothing was read or the bucket
    /// is sleep, a workout or still to come.
    var samples: [Double?]
    /// Buckets that fell in sleep.
    var sleepBuckets: Set<Int> = []
    /// Buckets covered by a workout or its recovery tail.
    var workoutBuckets: Set<Int> = []

    func isUsable(_ index: Int) -> Bool {
        index >= 0 && index < samples.count && samples[index] != nil
            && !sleepBuckets.contains(index) && !workoutBuckets.contains(index)
    }

    var usableCount: Int { samples.indices.filter(isUsable).count }

    /// The value in a bucket, when it is usable.
    func value(_ index: Int) -> Double? { isUsable(index) ? samples[index] : nil }

    /// The start of bucket `index`.
    func date(ofBucket index: Int) -> Date {
        day.addingTimeInterval(Double(index * Self.bucketMinutes) * 60)
    }

    /// The bucket a moment falls in, clamped to the day.
    func bucket(of date: Date) -> Int {
        let index = Int(date.timeIntervalSince(day) / Double(Self.bucketMinutes * 60))
        return min(max(index, 0), Self.buckets - 1)
    }

    /// The buckets a window touches: the start rounds down and the end up,
    /// so a meeting from 9:10 to 9:50 touches the 9:00 and 9:30 buckets.
    func buckets(from start: Date, to end: Date) -> Range<Int> {
        let perBucket = Double(Self.bucketMinutes * 60)
        let lower = max(0, Int((start.timeIntervalSince(day) / perBucket).rounded(.down)))
        let upper = min(Self.buckets, Int((end.timeIntervalSince(day) / perBucket).rounded(.up)))
        return lower..<max(lower, upper)
    }
}

/// Builds a day's curve from Health's samples.
nonisolated enum MindStressCurve {
    /// What a heart rate past its effort keeps from it.
    static let recoveryTail: TimeInterval = 40 * 60
    /// The ceiling of the scale sits at least this far above resting.
    static let minimumSpan: Double = 30
    /// The share of the maximum heart rate the ceiling sits at.
    static let ceilingShare = 0.72
    /// A maximum heart rate for a person whose age Soma does not know.
    static let defaultMaximum: Double = 190

    /// - Parameters:
    ///   - heartRate: the day's heart rate samples.
    ///   - resting: the resting rate the day is read against. Nil gives an
    ///     empty curve: stress above resting needs a resting rate.
    ///   - workouts: workouts overlapping the day.
    ///   - asleep: spans the person was asleep, from `PulseNights`.
    static func make(
        day: Date,
        now: Date,
        heartRate: [HealthReading],
        resting: Double?,
        maximum: Double? = nil,
        workouts: [HealthReading],
        asleep: [Range<Date>]
    ) -> MindStressDayCurve {
        var curve = MindStressDayCurve(day: day, samples: Array(repeating: nil, count: MindStressDayCurve.buckets))
        let span = Double(MindStressDayCurve.bucketMinutes * 60)
        for index in 0..<MindStressDayCurve.buckets {
            let start = day.addingTimeInterval(Double(index) * span)
            let end = start.addingTimeInterval(span)
            let middle = start.addingTimeInterval(span / 2)
            if workouts.contains(where: { $0.start < end && $0.end.addingTimeInterval(recoveryTail) > start }) {
                curve.workoutBuckets.insert(index)
            }
            if asleep.contains(where: { $0.contains(middle) }) {
                curve.sleepBuckets.insert(index)
            }
        }
        guard let resting else { return curve }
        let ceiling = max(resting + minimumSpan, (maximum ?? defaultMaximum) * ceilingShare)

        var sums = Array(repeating: (0.0, 0), count: MindStressDayCurve.buckets)
        for reading in heartRate where reading.start >= day && reading.start < now {
            let index = Int(reading.start.timeIntervalSince(day) / span)
            guard index >= 0, index < MindStressDayCurve.buckets else { continue }
            sums[index].0 += reading.value
            sums[index].1 += 1
        }
        var raw: [Double?] = sums.map { $0.1 > 0 ? $0.0 / Double($0.1) : nil }
        raw = raw.map { bpm in
            bpm.map { min(100, max(2, ($0 - resting) / max(1, ceiling - resting) * 100)) }
        }
        curve.samples = smoothed(raw)
        return curve
    }

    /// Three point smoothing over measured neighbours only: a gap stays a gap
    /// and never pulls its neighbours down.
    static func smoothed(_ values: [Double?]) -> [Double?] {
        values.indices.map { index in
            guard let centre = values[index] else { return nil }
            var total = centre
            var count = 1.0
            for neighbour in [index - 1, index + 1] where values.indices.contains(neighbour) {
                if let value = values[neighbour] { total += value; count += 1 }
            }
            return total / count
        }
    }
}

/// The 0 to 100 scale in four words. The cuts are
/// aligned with Garmin's: rest under 26, low under 51, medium under 76.
nonisolated enum MindStressBand: Int, CaseIterable, Sendable {
    case rest, low, medium, high

    init(_ value: Double) {
        switch value {
        case ..<26: self = .rest
        case ..<51: self = .low
        case ..<76: self = .medium
        default: self = .high
        }
    }

    var title: String {
        switch self {
        case .rest: "Calm"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .rest: 0...25
        case .low: 26...50
        case .medium: 51...75
        case .high: 76...100
        }
    }
}

/// The Stress Radar: the episodes of one day, and when to pause.
nonisolated enum MindStressRadar {
    /// Medium or higher is elevated.
    static let elevated: Double = 51
    /// Awake, still buckets a day needs before it is read.
    static let minimumCovered = 4

    struct Episode: Equatable, Sendable, Identifiable {
        /// The first bucket, stable across two reads of the same day.
        var id: Int { startBucket }
        var startBucket: Int
        /// Exclusive.
        var endBucket: Int
        /// The bucket holding the peak; the earliest on a tie.
        var peakBucket: Int
        var peak: Double
        var mean: Double
        /// The overlapping event's title, when one explains it.
        var trigger: String?

        var minutes: Int { (endBucket - startBucket) * MindStressDayCurve.bucketMinutes }
    }

    struct Reading: Equatable, Sendable {
        var episodes: [Episode]
        var peak: Double
        var mean: Double
        /// Awake, still minutes spent at medium or higher.
        var elevatedMinutes: Int
        /// Where to pause: the onset of the day's worst episode.
        var pauseBucket: Int?
        var covered: Int

        /// The worst episode, when there is one.
        var worst: Episode? { episodes.max { $0.peak < $1.peak } }
    }

    /// Nil when too little of the awake day was read.
    static func reading(_ curve: MindStressDayCurve, events: [MindCalendarEvent]) -> Reading? {
        let usable = curve.samples.indices.filter(curve.isUsable)
        guard usable.count >= minimumCovered else { return nil }
        let values = usable.compactMap { curve.samples[$0] }

        var episodes: [Episode] = []
        var runStart: Int?
        func close(_ end: Int) {
            guard let start = runStart else { return }
            let slice = (start..<end).compactMap { curve.samples[$0] }
            let peak = slice.max() ?? 0
            let offset = slice.firstIndex(of: peak) ?? 0
            let window = curve.date(ofBucket: start)..<curve.date(ofBucket: end)
            episodes.append(Episode(
                startBucket: start,
                endBucket: end,
                peakBucket: start + offset,
                peak: peak,
                mean: slice.reduce(0, +) / Double(max(slice.count, 1)),
                trigger: bestTrigger(window, events: events)
            ))
            runStart = nil
        }
        for index in 0..<curve.samples.count {
            if curve.isUsable(index), let value = curve.samples[index], value >= elevated {
                if runStart == nil { runStart = index }
            } else {
                close(index)
            }
        }
        close(curve.samples.count)

        let worst = episodes.max { $0.peak < $1.peak }
        return Reading(
            episodes: episodes,
            peak: values.max() ?? 0,
            mean: values.reduce(0, +) / Double(values.count),
            elevatedMinutes: values.filter { $0 >= elevated }.count * MindStressDayCurve.bucketMinutes,
            pauseBucket: worst?.startBucket,
            covered: usable.count
        )
    }

    /// The event with the greatest overlap onto the window, or nil.
    static func bestTrigger(_ window: Range<Date>, events: [MindCalendarEvent]) -> String? {
        var best: (String, TimeInterval)?
        for event in events {
            let overlap = min(window.upperBound, event.end).timeIntervalSince(max(window.lowerBound, event.start))
            if overlap > 0, overlap > (best?.1 ?? 0) { best = (event.title, overlap) }
        }
        return best?.0
    }

    /// The median of the days' means: the usual stress level.
    static func usual(_ days: [MindStressDayCurve]) -> Double? {
        MindUsual.percentile(days.compactMap { reading($0, events: []).map(\.mean) }, 0.5)
    }

    /// The middle half of every usable bucket across the days: the usual
    /// range, from the 25th to the 75th percentile.
    static func usualRange(_ days: [MindStressDayCurve]) -> ClosedRange<Double>? {
        let values = days.flatMap { day in day.samples.indices.compactMap(day.value) }
        guard values.count >= 12,
              let low = MindUsual.percentile(values, 0.25),
              let high = MindUsual.percentile(values, 0.75) else { return nil }
        return low...high
    }
}
