//
//  MindSignals.swift
//  Prism
//
//  Each signal Mind reads, today against its usual: the rows of "What moved
//  it" on the Mind page and "What moves it" on the HRV page.
//

import Foundation
import HealthExportCore

struct MindSignals: Equatable, Sendable {
    var hrv: MindSignalRow
    var resting: MindSignalRow
    var breathing: MindSignalRow
    var peaks: MindSignalRow
    var sleep: MindSignalRow

    /// Daily HRV (mean) keyed by day, the usual range and the median.
    var hrvByDay: [Date: Double]
    var hrvUsual: ClosedRange<Double>?
    var hrvBaseline: Double?
    var hrvToday: Double?
    var hrvLastNight: Double?

    static func make(
        heartRateVariability: [HealthReading],
        restingHeartRate: [HealthReading],
        respiratory: [HealthReading],
        sleep: [HealthReading],
        peaks: [PulsePeak],
        now: Date,
        calendar: Calendar,
        words: PulseWording
    ) -> MindSignals {
        let today = calendar.startOfDay(for: now)

        // HRV: today's mean against the middle half of the days before.
        let hrvByDay = MindUsual.daily(heartRateVariability, calendar: calendar, reduce: MindUsual.mean)
        let hrvPast = hrvByDay.filter { $0.key < today }.map(\.value)
        let hrvUsual = MindUsual.range(hrvPast)
        let hrvBaseline = hrvPast.count >= MindUsual.minimumDays ? EffectMath.median(hrvPast) : nil
        let hrvToday = hrvByDay[today]
        let evenings = MindDaily.eveningVariability(heartRateVariability, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let hrvLastNight = evenings[yesterday]

        // Resting heart rate: the latest against the usual.
        let restingByDay = MindUsual.daily(restingHeartRate, calendar: calendar, reduce: { MindUsual.percentile($0, 0.5) })
        let restingUsual = MindUsual.range(restingByDay.filter { $0.key < today }.map(\.value))
        let restingNow = restingByDay[today] ?? restingByDay[yesterday]

        // Breathing overnight: the respiratory rate recorded asleep.
        let nightly = nightlyBreathing(respiratory, calendar: calendar)
        let breathingUsual = MindUsual.range(nightly.filter { $0.key < today }.map(\.value))
        let breathingNow = nightly[today]

        // Sleep: last night's time asleep against the usual night.
        let nights = PulseNights.nights(from: sleep, calendar: calendar)
        let lastNight = nights.first { calendar.isDate($0.day, inSameDayAs: today) }
        let sleepUsual = MindUsual.range(nights.filter { $0.day < today }.map { $0.asleep / 3600 })

        func range(_ usual: ClosedRange<Double>?, decimals: Int = 0, clock: Bool = false) -> String? {
            guard let usual else { return nil }
            if clock {
                return "usual \(words.clock(usual.lowerBound * 3600)) to \(words.clock(usual.upperBound * 3600))"
            }
            let format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(decimals))) }
            return "usual \(format(usual.lowerBound)) to \(format(usual.upperBound))"
        }

        let peakTimes = peaks.map { words.time($0.start) }
        let peakHours = peaks.map { Double(calendar.component(.hour, from: $0.start)) + Double(calendar.component(.minute, from: $0.start)) / 60 }

        return MindSignals(
            hrv: MindSignalRow(
                kind: .hrv, title: "HRV", detail: range(hrvUsual),
                value: hrvToday.map { "\(words.whole($0)) ms" },
                isCost: MindUsual.place(hrvToday, in: hrvUsual) == .under,
                number: hrvToday, usual: hrvUsual
            ),
            resting: MindSignalRow(
                kind: .resting, title: "Resting heart rate", detail: range(restingUsual),
                value: restingNow.map { "\(words.whole($0)) bpm" },
                isCost: MindUsual.place(restingNow, in: restingUsual) == .over,
                number: restingNow, usual: restingUsual
            ),
            breathing: MindSignalRow(
                kind: .breathing, title: "Breathing, overnight", detail: range(breathingUsual, decimals: 1),
                value: breathingNow.map { $0.formatted(.number.precision(.fractionLength(1))) + " /min" },
                isCost: MindUsual.place(breathingNow, in: breathingUsual) == .over,
                number: breathingNow, usual: breathingUsual
            ),
            peaks: MindSignalRow(
                kind: .peaks, title: "Stress peaks",
                detail: peakTimes.isEmpty ? "none so far today" : words.list(peakTimes),
                value: "\(peaks.count)",
                isCost: peaks.count >= MindStress.hardDayPeaks,
                number: nil, usual: nil, marks: peakHours
            ),
            sleep: MindSignalRow(
                kind: .sleep, title: "Sleep", detail: range(sleepUsual, clock: true),
                value: lastNight.map { words.clock($0.asleep) },
                isCost: MindUsual.place(lastNight.map { $0.asleep / 3600 }, in: sleepUsual) == .under,
                number: lastNight.map { $0.asleep / 3600 }, usual: sleepUsual
            ),
            hrvByDay: hrvByDay,
            hrvUsual: hrvUsual,
            hrvBaseline: hrvBaseline,
            hrvToday: hrvToday,
            hrvLastNight: hrvLastNight
        )
    }

    /// The breathing rate of each night, keyed by the morning it ended on:
    /// readings from 22:00 to 08:00, one taken before midnight counted with
    /// the next morning. The Breathing row and the check-in's streak both
    /// read nights this one way.
    static func nightlyBreathing(_ respiratory: [HealthReading], calendar: Calendar) -> [Date: Double] {
        var byMorning: [Date: [Double]] = [:]
        for reading in respiratory {
            let hour = calendar.component(.hour, from: reading.start)
            let day = calendar.startOfDay(for: reading.start)
            let morning: Date? = if hour < 8 {
                day
            } else if hour >= 22 {
                calendar.date(byAdding: .day, value: 1, to: day)
            } else {
                nil
            }
            if let morning { byMorning[morning, default: []].append(reading.value) }
        }
        return byMorning.compactMapValues(MindUsual.mean)
    }

    /// Breathing ran over its usual range this many nights in a row, ending
    /// last night: the check-in asks about it from three.
    static func fastBreathingNights(_ respiratory: [HealthReading], now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        let night = nightlyBreathing(respiratory, calendar: calendar)
        guard let usual = MindUsual.range(night.filter { $0.key < calendar.date(byAdding: .day, value: -3, to: today) ?? today }.map(\.value)) else { return 0 }
        var count = 0
        var day = today
        while let value = night[day], value > usual.upperBound {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

/// The Mind score in words.
enum MindScoreWords {
    static func word(_ score: Int?) -> String {
        guard let score else { return "Not read yet" }
        switch score {
        case 70...: return "At ease"
        case 50..<70: return "Working hard"
        default: return "Under strain"
        }
    }

    static func headline(_ score: Int?) -> String {
        guard let score else { return "Mind reads your HRV and your pulse at rest." }
        switch score {
        case 70...: return "HRV high and pulse low for you: a calm reading."
        case 50..<70: return "HRV and pulse close to your usual."
        default: return "HRV low or pulse high for you: a strained reading."
        }
    }

    /// Today against the mean of the seven days before.
    static func againstLastWeek(_ series: [Double?]) -> Double? {
        guard let today = series.last ?? nil else { return nil }
        let week = series.dropLast().suffix(7).compactMap { $0 }
        guard week.count >= 3, let mean = MindUsual.mean(week) else { return nil }
        return today - mean
    }
}
