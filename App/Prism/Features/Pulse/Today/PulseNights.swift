//
//  PulseNights.swift
//  Prism
//

import Foundation
import HealthExportCore

/// One night, put together from Health's sleep samples.
struct PulseNight: Equatable, Sendable {
    /// The day the night belongs to: the morning it ended on.
    var day: Date
    /// When the person got into bed, or fell asleep when nothing recorded bed.
    var bedtime: Date
    var fellAsleep: Date
    var woke: Date
    /// Time actually asleep, in seconds.
    var asleep: TimeInterval
    /// Deep sleep in seconds, or nil when no source recorded stages. A night
    /// recorded as plain "asleep" has no deep sleep to count, which is not the
    /// same as none.
    var deep: TimeInterval?
}

/// Turns sleep samples into nights.
///
/// Health keeps every source's samples side by side: a watch's stages, a
/// phone's time in bed, a third-party app's own night. Summing their lengths
/// counts the same hour twice, which is how a night of seven hours reads as
/// eleven. Here the asleep intervals are merged first, so an hour counts once
/// whoever recorded it.
enum PulseNights {
    /// `HKCategoryValueSleepAnalysis`: in bed.
    static let inBed = 0
    /// Every coded value that means asleep: unspecified, core, deep and REM.
    /// Unspecified is what older watches and most other apps write.
    static let asleepCodes: Set<Int> = [1, 3, 4, 5]
    /// The values only a source that records stages writes.
    static let stagedCodes: Set<Int> = [3, 4, 5]
    static let deepCode = 4

    /// Two stretches of sleep closer than this are one night woken in.
    static let joiningGap: TimeInterval = 60 * 60

    /// Nights, oldest first, one per day: the longest stretch of sleep that
    /// ended between six in the evening before and six in the evening of that
    /// day. A nap in the afternoon is a shorter stretch, and loses to the night.
    static func nights(from samples: [HealthReading], calendar: Calendar) -> [PulseNight] {
        let asleep = merged(samples.filter { asleepCodes.contains($0.code) })
        guard !asleep.isEmpty else { return [] }

        var stretches: [[Range<Date>]] = []
        for interval in asleep {
            if let last = stretches.last?.last,
               interval.lowerBound.timeIntervalSince(last.upperBound) <= joiningGap {
                stretches[stretches.count - 1].append(interval)
            } else {
                stretches.append([interval])
            }
        }

        let deep = merged(samples.filter { $0.code == deepCode })
        let staged = merged(samples.filter { stagedCodes.contains($0.code) })
        let bed = merged(samples.filter { $0.code == inBed })

        var longest: [Date: (span: Range<Date>, asleep: TimeInterval)] = [:]
        for stretch in stretches {
            guard let first = stretch.first, let last = stretch.last else { continue }
            let span = first.lowerBound..<last.upperBound
            let total = stretch.reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
            let day = sleepDay(endingAt: span.upperBound, calendar: calendar)
            if let current = longest[day], current.asleep >= total { continue }
            longest[day] = (span, total)
        }

        return longest.keys.sorted().compactMap { day in
            guard let night = longest[day] else { return nil }
            let span = night.span
            let isStaged = overlap(of: staged, with: span) > 0
            // Bed begins with the time-in-bed stretch that runs into sleep, and
            // no earlier than a few hours before it.
            let bedtime = bed
                .filter { $0.lowerBound <= span.lowerBound && $0.upperBound >= span.lowerBound.addingTimeInterval(-joiningGap) }
                .map(\.lowerBound)
                .filter { span.lowerBound.timeIntervalSince($0) < 4 * 60 * 60 }
                .min() ?? span.lowerBound
            return PulseNight(
                day: day,
                bedtime: bedtime,
                fellAsleep: span.lowerBound,
                woke: span.upperBound,
                asleep: night.asleep,
                deep: isStaged ? overlap(of: deep, with: span) : nil
            )
        }
    }

    /// The day a stretch of sleep belongs to: one ending before six in the
    /// evening is that day's night, one ending after is the next day's.
    static func sleepDay(endingAt end: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: end.addingTimeInterval(6 * 60 * 60))
    }

    /// The samples' spans, sorted, with overlapping and touching spans joined.
    static func merged(_ samples: [HealthReading]) -> [Range<Date>] {
        let spans = samples
            .filter { $0.end > $0.start }
            .map { $0.start..<$0.end }
            .sorted { $0.lowerBound < $1.lowerBound }
        var result: [Range<Date>] = []
        for span in spans {
            if let last = result.last, span.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// Seconds of `spans` that fall inside `window`.
    static func overlap(of spans: [Range<Date>], with window: Range<Date>) -> TimeInterval {
        spans.reduce(0) { total, span in
            let start = max(span.lowerBound, window.lowerBound)
            let end = min(span.upperBound, window.upperBound)
            return total + max(0, end.timeIntervalSince(start))
        }
    }
}
