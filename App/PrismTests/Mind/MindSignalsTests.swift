//
//  MindSignalsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// Each row of "What moved it" reads one signal today against the middle
/// half of the person's own days before it. What is held here is that each
/// signal lands on the right day (a breath at 23:00 belongs to the night that
/// ends the next morning), that the cost points the right way for each one
/// (HRV and sleep cost when low, the heart and the breath when high), and
/// that under five days of history no usual is claimed.
@Suite("Mind signals")
@MainActor
struct MindSignalsTests {
    enum Metric {
        static let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        static let resting = "HKQuantityTypeIdentifierRestingHeartRate"
        static let respiratory = "HKQuantityTypeIdentifierRespiratoryRate"
        static let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
    }

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    var words: PulseWording { PulseWording(calendar: calendar, locale: Locale(identifier: "en_GB")) }

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    var now: Date { at(15) }

    /// Five days of HRV with a usual of 45 to 55 ms and a median of 50, then
    /// a low 30 this morning. Yesterday has an evening reading of 56.
    var hrv: [HealthReading] {
        [
            .test(Metric.hrv, 40, at: at(7, day: -5)),
            .test(Metric.hrv, 45, at: at(7, day: -4)),
            .test(Metric.hrv, 50, at: at(7, day: -3)),
            .test(Metric.hrv, 60, at: at(7, day: -2)),
            .test(Metric.hrv, 54, at: at(7, day: -1)),
            .test(Metric.hrv, 56, at: at(22, day: -1)),
            .test(Metric.hrv, 30, at: at(7)),
        ]
    }

    /// Resting heart rate with a usual of 52 to 56, nothing yet today.
    var resting: [HealthReading] {
        let values: [Double] = [50, 52, 54, 56, 58]
        return values.enumerated().map { index, value in
            HealthReading.test(Metric.resting, value, at: at(8, day: index - 5))
        }
    }

    /// Breathing at 03:00 on the five nights before, usual 14.5 to 15.5, then
    /// last night 18 at 23:00 and 17 at 03:00, and a daytime 30 to leave out.
    var respiratory: [HealthReading] {
        let values: [Double] = [14, 14.5, 15, 15.5, 16]
        let before = values.enumerated().map { index, value in
            HealthReading.test(Metric.respiratory, value, at: at(3, day: index - 5))
        }
        let lastNight: [HealthReading] = [
            .test(Metric.respiratory, 18, at: at(23, day: -1)),
            .test(Metric.respiratory, 17, at: at(3)),
            .test(Metric.respiratory, 30, at: at(12)),
        ]
        return before + lastNight
    }

    /// Five nights of 7 to 9 hours asleep from 23:00, usual 7:30 to 8:30,
    /// then six hours last night.
    var sleep: [HealthReading] {
        let hours: [Double] = [7, 7.5, 8, 8.5, 9]
        let past = hours.enumerated().map { index, asleep in
            HealthReading.test(Metric.sleep, 1, from: at(23, day: index - 6), to: at(23, day: index - 6).addingTimeInterval(asleep * 3600))
        }
        return past + [.test(Metric.sleep, 1, from: at(23, day: -1), to: at(5))]
    }

    func peak(_ hour: Int, _ minute: Int) -> PulsePeak {
        PulsePeak(start: at(hour, minute), end: at(hour, minute + 10), peak: 120, above: 50)
    }

    func make(
        hrv: [HealthReading] = [], resting: [HealthReading] = [], respiratory: [HealthReading] = [],
        sleep: [HealthReading] = [], peaks: [PulsePeak] = []
    ) -> MindSignals {
        MindSignals.make(heartRateVariability: hrv, restingHeartRate: resting, respiratory: respiratory,
                         sleep: sleep, peaks: peaks, now: now, calendar: calendar, words: words)
    }

    // MARK: The rows

    @Test("A low HRV today costs, against a usual and a baseline taken from the days before")
    func hrvRow() {
        let signals = make(hrv: hrv)
        #expect(signals.hrvUsual == 45...55)
        #expect(signals.hrvBaseline == 50)
        #expect(signals.hrvToday == 30)
        #expect(signals.hrv.value == "30 ms")
        #expect(signals.hrv.detail == "usual 45 to 55")
        #expect(signals.hrv.isCost)
        #expect(signals.hrv.number == 30)
    }

    @Test("Last night's HRV is the evening before and the small hours after it")
    func hrvLastNight() {
        #expect(make(hrv: hrv).hrvLastNight == 43)
    }

    @Test("Resting heart rate falls back to yesterday before today is measured, and a high one costs")
    func restingRow() {
        let row = make(resting: resting).resting
        #expect(row.number == 58)
        #expect(row.value == "58 bpm")
        #expect(row.usual == 52...56)
        #expect(row.isCost)
    }

    @Test("A breath at 23:00 belongs to the night that ends the next morning, and a daytime one is left out")
    func breathingRow() {
        let row = make(respiratory: respiratory).breathing
        #expect(row.number == 17.5)
        #expect(row.usual == 14.5...15.5)
        #expect(row.isCost)
    }

    @Test("Last night's sleep is read against the usual night, and a short one costs")
    func sleepRow() {
        let row = make(sleep: sleep).sleep
        #expect(row.number == 6)
        #expect(row.value == "6:00")
        #expect(row.usual == 7.5...8.5)
        #expect(row.detail == "usual 7:30 to 8:30")
        #expect(row.isCost)
    }

    @Test("Two stress peaks make a hard day, and each one is a tick at its clock hour")
    func peaksRow() {
        let first = peak(10, 15)
        let second = peak(14, 40)
        let row = make(peaks: [first, second]).peaks
        #expect(row.value == "2")
        #expect(row.isCost)
        #expect(row.marks == [10.25, 14 + 40.0 / 60])
        #expect(row.detail == "\(words.time(first.start)) and \(words.time(second.start))")

        let one = make(peaks: [first]).peaks
        #expect(one.value == "1")
        #expect(!one.isCost)
    }

    @Test("With nothing recorded every row is a dash and nothing reads as a cost")
    func nothingRecorded() {
        let signals = make()
        for row in [signals.hrv, signals.resting, signals.breathing, signals.sleep] {
            #expect(row.value == nil, "\(row.kind)")
            #expect(row.usual == nil, "\(row.kind)")
            #expect(row.detail == nil, "\(row.kind)")
            #expect(!row.isCost, "\(row.kind)")
        }
        #expect(signals.peaks.value == "0")
        #expect(signals.peaks.detail == "none so far today")
        #expect(!signals.peaks.isCost)
        #expect(signals.hrvBaseline == nil)
        #expect(signals.hrvLastNight == nil)
    }

    @Test("Four days of history claim no usual and no baseline, so a low day costs nothing yet")
    func tooLittleHistory() {
        let signals = make(hrv: hrv.filter { $0.start >= at(0, day: -4) })
        #expect(signals.hrvUsual == nil)
        #expect(signals.hrvBaseline == nil)
        #expect(signals.hrvToday == 30)
        #expect(signals.hrv.detail == nil)
        #expect(!signals.hrv.isCost)
    }

    // MARK: Fast breathing

    /// Seven nights, four to ten days back, with a usual of 14.5 to 15.5, then
    /// the three nights before last night and last night itself.
    func breathing(lastNights: [Double?]) -> [HealthReading] {
        let values: [Double] = [14, 14, 15, 15, 15, 16, 16]
        var readings = values.enumerated().map { index, value in
            HealthReading.test(Metric.respiratory, value, at: at(3, day: index - 10))
        }
        for (index, value) in lastNights.enumerated() {
            if let value { readings.append(.test(Metric.respiratory, value, at: at(3, day: index - 3))) }
        }
        readings.append(.test(Metric.respiratory, 40, at: at(12)))
        return readings
    }

    @Test("Nights over the usual are counted back from last night until one is not")
    func fastBreathingNights() {
        let readings = breathing(lastNights: [15, 17, 17.5, 18])
        #expect(MindSignals.fastBreathingNights(readings, now: now, calendar: calendar) == 3)
    }

    @Test("A breath at 23:00 counts with the next morning, as on the Breathing row")
    func lateEveningCountsWithTheMorning() {
        var readings = breathing(lastNights: [15, 17, 17.5, nil])
        #expect(MindSignals.fastBreathingNights(readings, now: now, calendar: calendar) == 0)
        readings.append(.test(Metric.respiratory, 18, at: at(23, day: -1)))
        #expect(MindSignals.fastBreathingNights(readings, now: now, calendar: calendar) == 3)
    }

    @Test("A night is keyed by its morning across the spring clock change")
    func springForward() {
        // In Paris, clocks went forward at 02:00 on 29 March 2026.
        let evening = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 23, minute: 30))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let nights = MindSignals.nightlyBreathing([.test(Metric.respiratory, 16, at: evening)], calendar: calendar)
        #expect(nights == [morning: 16])
    }

    @Test("A morning without a reading counts no fast nights, however fast the ones before it")
    func noReadingThisMorning() {
        let readings = breathing(lastNights: [17, 17, 17.5, nil])
        #expect(MindSignals.fastBreathingNights(readings, now: now, calendar: calendar) == 0)
    }

    @Test("Under five nights of history before the last three, nothing is counted")
    func fastBreathingNeedsHistory() {
        let readings = breathing(lastNights: [17, 17, 17.5, 18]).filter { $0.start >= at(0, day: -7) }
        #expect(MindSignals.fastBreathingNights(readings, now: now, calendar: calendar) == 0)
    }
}
