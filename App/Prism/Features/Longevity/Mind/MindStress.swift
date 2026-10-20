//
//  MindStress.swift
//  Prism
//

import Foundation
import HealthExportCore

/// One day read for stress: its peaks, and whether it could be read at all.
struct MindStressDay: Equatable, Sendable {
    /// The start of the day.
    var day: Date
    /// Heart rate raised well above resting while still, as ``PulseSignals``
    /// finds it on the Today page.
    var peaks: [PulsePeak]
    /// Whether the day held a resting rate, steps and enough heart readings to
    /// tell a calm day from an empty one.
    var isReadable: Bool

    /// Two peaks or more.
    var isHard: Bool { peaks.count >= MindStress.hardDayPeaks }
    /// Read, and no peak at all.
    var isCalm: Bool { isReadable && peaks.isEmpty }

    /// Whether a peak started in the afternoon, 12:00 to 18:00.
    func hasAfternoonPeak(calendar: Calendar) -> Bool {
        peaks.contains { MindStress.afternoon.contains(calendar.component(.hour, from: $0.start)) }
    }
}

/// The Mind tab's rules for stress, shared by Inner space and Insights.
///
/// Health has no stress reading. The same sign the Today page uses stands in:
/// a heart well above its resting rate with no steps and no workout around it.
enum MindStress {
    /// Peaks that make a day hard.
    static let hardDayPeaks = 2
    /// The hours that count as the afternoon.
    static let afternoon = 12..<18
    /// Heart readings a day needs before its lack of peaks means calm.
    static let readableHeartReadings = 12

    /// Reduces one day's samples to its peaks.
    static func day(
        _ day: Date,
        heartRate: [HealthReading],
        steps: [HealthReading],
        resting: Double?,
        workouts: [HealthReading],
        calendar: Calendar
    ) -> MindStressDay {
        let stepsTotal = steps.reduce(0) { $0 + $1.value }
        let read = PulseSignals.workouts(workouts, steps: [:], heartRate: [], age: nil)
        let peaks = PulseSignals.peaks(
            heartRate: heartRate,
            since: day,
            resting: resting,
            steps: steps,
            stepsToday: stepsTotal,
            workouts: read
        )
        let readable = resting != nil && stepsTotal > 0 && heartRate.count >= readableHeartReadings
        return MindStressDay(day: day, peaks: peaks, isReadable: readable)
    }

    /// The resting rate a day is measured against: that day's own reading,
    /// else the median of the week before it.
    static func resting(on day: Date, from readings: [HealthReading], calendar: Calendar) -> Double? {
        let own = readings.filter { calendar.isDate($0.start, inSameDayAs: day) }.map(\.value)
        if let median = PulseSignals.median(own) { return median }
        let weekBefore = calendar.date(byAdding: .day, value: -7, to: day) ?? day
        return PulseSignals.median(readings.filter { $0.start >= weekBefore && $0.start < day }.map(\.value))
    }
}

/// When stress peaks: minutes of peak by weekday and by two hour block,
/// from 08:00 to 22:00.
struct MindHeatmap: Equatable, Sendable, Codable {
    static let firstHour = 8
    static let blockHours = 2
    static let columns = 7

    /// Seven rows, Monday first, each with ``columns`` blocks of minutes.
    var minutes: [[Double]]

    var highest: Double { minutes.flatMap { $0 }.max() ?? 0 }
    var isEmpty: Bool { highest <= 0 }

    /// The block a clock hour falls in, or nil outside the map.
    static func column(ofHour hour: Int) -> Int? {
        guard hour >= firstHour else { return nil }
        let column = (hour - firstHour) / blockHours
        return column < columns ? column : nil
    }

    /// Monday is row 0.
    static func row(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func make(_ days: [MindStressDay], calendar: Calendar) -> MindHeatmap {
        var minutes = Array(repeating: Array(repeating: 0.0, count: columns), count: 7)
        for day in days {
            for peak in day.peaks {
                guard let column = column(ofHour: calendar.component(.hour, from: peak.start)) else { continue }
                let length = max(1, peak.end.timeIntervalSince(peak.start) / 60)
                minutes[row(of: peak.start, calendar: calendar)][column] += length
            }
        }
        return MindHeatmap(minutes: minutes)
    }

    /// The weekdays that carry the most, at most two, in week order: every
    /// row within a quarter of the busiest.
    var topRows: [Int] {
        let totals = minutes.map { $0.reduce(0, +) }
        guard let most = totals.max(), most > 0 else { return [] }
        let close = totals.indices.filter { totals[$0] >= most * 0.75 }
        return Array(close.sorted { totals[$0] > totals[$1] }.prefix(2)).sorted()
    }

    enum Part: Equatable, Sendable { case morning, afternoon, evening }

    /// The part of the day that carries the most.
    var topPart: Part? {
        var sums: [Part: Double] = [:]
        for column in 0..<Self.columns {
            let hour = Self.firstHour + column * Self.blockHours
            let part: Part = hour < 12 ? .morning : (hour < 18 ? .afternoon : .evening)
            sums[part, default: 0] += minutes.reduce(0) { $0 + $1[column] }
        }
        guard let best = sums.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
        return best.key
    }
}
