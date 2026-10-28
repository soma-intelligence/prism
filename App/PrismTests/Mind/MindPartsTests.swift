//
//  MindPartsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

/// The Mind tab's arithmetic: streaks, hard and calm days, the stress
/// heatmap and what comes before a hard afternoon. A fixed calendar keeps the
/// days the same on every machine.
@Suite("Mind parts")
@MainActor
struct MindPartsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    /// Tuesday 29 September 2026 at `hour`:`minute`, or a day before or after.
    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func day(_ offset: Int) -> Date { calendar.startOfDay(for: at(12, day: offset)) }

    func peak(_ hour: Int, minutes: Double = 20, day offset: Int = 0) -> PulsePeak {
        let start = at(hour, day: offset)
        return PulsePeak(start: start, end: start.addingTimeInterval(minutes * 60), peak: 95, above: 35)
    }

    func reading(_ metric: String, _ value: Double, at date: Date, lasting seconds: TimeInterval = 60) -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .none, start: date, end: date.addingTimeInterval(seconds))
    }

    // MARK: - Streak

    @Test("A streak counts days in a row back from today")
    func streakFromToday() {
        let days: Set<Date> = [day(0), day(-1), day(-2), day(-4)]
        #expect(MindMath.streak(days, today: at(20), calendar: calendar) == 3)
    }

    @Test("Today without a ritual yet does not break the streak")
    func streakFromYesterday() {
        let days: Set<Date> = [day(-1), day(-2)]
        #expect(MindMath.streak(days, today: at(9), calendar: calendar) == 2)
    }

    @Test("A gap of two days ends the streak at zero")
    func streakBroken() {
        #expect(MindMath.streak([day(-2), day(-3)], today: at(9), calendar: calendar) == 0)
        #expect(MindMath.streak([], today: at(9), calendar: calendar) == 0)
    }

    @Test("Days given mid-afternoon still count as their day")
    func streakNormalizesTimes() {
        #expect(MindMath.streak([at(15), at(8, day: -1)], today: at(20), calendar: calendar) == 2)
    }

    // MARK: - Hard and calm days

    @Test("Two peaks make a hard day, none on a readable day makes a calm one")
    func hardAndCalm() {
        let hard = MindStressDay(day: day(0), peaks: [peak(10), peak(15)], isReadable: true)
        let one = MindStressDay(day: day(-1), peaks: [peak(15, day: -1)], isReadable: true)
        let calm = MindStressDay(day: day(-2), peaks: [], isReadable: true)
        let empty = MindStressDay(day: day(-3), peaks: [], isReadable: false)

        #expect(hard.isHard && !hard.isCalm)
        #expect(!one.isHard && !one.isCalm)
        #expect(calm.isCalm && !calm.isHard)
        #expect(!empty.isCalm, "a day with nothing to read is not calm, it is unknown")
    }

    @Test("A hard afternoon has a peak starting between 12:00 and 18:00")
    func afternoonPeak() {
        #expect(MindStressDay(day: day(0), peaks: [peak(12)], isReadable: true).hasAfternoonPeak(calendar: calendar))
        #expect(MindStressDay(day: day(0), peaks: [peak(17)], isReadable: true).hasAfternoonPeak(calendar: calendar))
        #expect(!MindStressDay(day: day(0), peaks: [peak(18)], isReadable: true).hasAfternoonPeak(calendar: calendar))
        #expect(!MindStressDay(day: day(0), peaks: [peak(9)], isReadable: true).hasAfternoonPeak(calendar: calendar))
    }

    @Test("A raised heart while still becomes a peak; the same heart on a walk does not")
    func stressDayFromSamples() {
        let heart = "HKQuantityTypeIdentifierHeartRate"
        let steps = "HKQuantityTypeIdentifierStepCount"
        var hr = (0..<20).map { reading(heart, 60, at: at(8, $0 * 3)) }
        hr += [reading(heart, 98, at: at(14)), reading(heart, 100, at: at(14, 6))]
        hr += [reading(heart, 110, at: at(17)), reading(heart, 112, at: at(17, 5))]
        let walking = [reading(steps, 600, at: at(16, 55), lasting: 15 * 60)]
        let morning = [reading(steps, 800, at: at(7), lasting: 20 * 60)]

        let result = MindStress.day(day(0), heartRate: hr, steps: walking + morning, resting: 60, workouts: [], calendar: calendar)
        #expect(result.isReadable)
        #expect(result.peaks.count == 1)
        #expect(result.peaks.first?.start == at(14))
    }

    @Test("Without a resting rate a day cannot be read")
    func stressDayNeedsResting() {
        let heart = "HKQuantityTypeIdentifierHeartRate"
        let hr = (0..<20).map { reading(heart, 90, at: at(9, $0 * 2)) }
        let steps = [reading("HKQuantityTypeIdentifierStepCount", 500, at: at(7))]
        let result = MindStress.day(day(0), heartRate: hr, steps: steps, resting: nil, workouts: [], calendar: calendar)
        #expect(!result.isReadable)
        #expect(result.peaks.isEmpty)
    }

    // MARK: - Heatmap

    @Test("Hours map to two hour blocks from 08:00, and nothing outside 08:00 to 22:00")
    func heatmapColumns() {
        #expect(MindHeatmap.column(ofHour: 7) == nil)
        #expect(MindHeatmap.column(ofHour: 8) == 0)
        #expect(MindHeatmap.column(ofHour: 9) == 0)
        #expect(MindHeatmap.column(ofHour: 14) == 3)
        #expect(MindHeatmap.column(ofHour: 21) == 6)
        #expect(MindHeatmap.column(ofHour: 22) == nil)
    }

    @Test("Monday is the first row")
    func heatmapRows() {
        // 29 September 2026 is a Tuesday.
        #expect(MindHeatmap.row(of: at(12), calendar: calendar) == 1)
        #expect(MindHeatmap.row(of: at(12, day: -1), calendar: calendar) == 0)
        #expect(MindHeatmap.row(of: at(12, day: -2), calendar: calendar) == 6)
    }

    @Test("Peak minutes add up by weekday and block, and the headline names the busiest")
    func heatmapBucketing() {
        let days = [
            MindStressDay(day: day(0), peaks: [peak(14, minutes: 30), peak(15, minutes: 10)], isReadable: true),
            MindStressDay(day: day(2), peaks: [peak(16, minutes: 30, day: 2)], isReadable: true),
            MindStressDay(day: day(-1), peaks: [peak(9, minutes: 5, day: -1), peak(23, minutes: 60, day: -1)], isReadable: true),
        ]
        let map = MindHeatmap.make(days, calendar: calendar)
        #expect(map.minutes[1][3] == 40, "Tuesday 14:00 to 16:00")
        #expect(map.minutes[3][4] == 30, "Thursday 16:00 to 18:00")
        #expect(map.minutes[0][0] == 5, "Monday 08:00 to 10:00")
        #expect(map.minutes.flatMap { $0 }.reduce(0, +) == 75, "the 23:00 peak falls outside the map")
        #expect(map.topRows == [1, 3])
        #expect(map.topPart == .afternoon)
    }

    @Test("An empty map names no day and no part")
    func heatmapEmpty() {
        let map = MindHeatmap.make([], calendar: calendar)
        #expect(map.isEmpty)
        #expect(map.topRows.isEmpty)
        #expect(map.topPart == nil)
    }

    // MARK: - What comes before

    @Test("Each thing counts the hard afternoons it came before")
    func precursors() {
        let afternoons = [day(0), day(-7), day(-14)]
        var journal = MindJournal()
        journal.tagsByDay[day(-1)] = ["late-meal"]
        journal.tagsByDay[day(-7)] = ["coffee-late"]
        journal.tagsByDay[day(-15)] = ["hard-training", "late-meal"]
        let result = MindInsights.precursors(
            before: afternoons,
            shortNights: [day(0), day(-14), day(-3)],
            hardTraining: [day(-8)],
            journal: journal,
            calendar: calendar
        )
        #expect(result.map(\.count) == [2, 2, 1, 2])
        #expect(result.map(\.title) == [
            "A night under seven hours",
            "A late dinner the night before",
            "Coffee after 14:00",
            "Hard training the day before",
        ])
    }

    @Test("Insights count hard, calm and short nights, and dash what cannot be read")
    func insightsCounts() {
        let stress = [
            MindStressDay(day: day(-1), peaks: [peak(13, day: -1), peak(15, day: -1)], isReadable: true),
            MindStressDay(day: day(-2), peaks: [], isReadable: true),
            MindStressDay(day: day(-3), peaks: [], isReadable: true),
            MindStressDay(day: day(-4), peaks: [], isReadable: false),
        ]
        let model = MindInsights.make(from: MindInputs(now: at(20)), stress: stress, journal: MindJournal(), calendar: calendar)
        #expect(model.hardDays == 1)
        #expect(model.calmDays == 2)
        #expect(model.shortNights == nil, "no sleep read is not zero short nights")
        #expect(model.hardAfternoons == 1)

        let empty = MindInsights.make(from: MindInputs(now: at(20)), stress: [], journal: MindJournal(), calendar: calendar)
        #expect(empty.hardDays == nil)
        #expect(empty.calmDays == nil)
        #expect(empty.peakDays == nil)
    }

    // MARK: - Rituals

    @Test("Breathing days lift evening HRV and the ritual says so")
    func breatheEffect() {
        let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        let mindful = "HKCategoryTypeIdentifierMindfulSession"
        var inputs = MindInputs(now: at(12))
        for offset in 1...10 {
            let breathed = offset <= 4
            inputs.heartRateVariability.append(reading(hrv, breathed ? 50 : 44, at: at(22, day: -offset)))
            if breathed {
                inputs.mindful.append(reading(mindful, 1, at: at(19, day: -offset), lasting: 10 * 60))
            }
        }
        let model = MindRituals.make(from: inputs, journal: MindJournal(), calendar: calendar)
        let breathe = model.rituals.first { $0.kind == .breathe }
        #expect(breathe?.value == "+6 ms")
        #expect(breathe?.detail == "HRV, 4 of 4 times")
        #expect(breathe?.title == "Breathe, 10 minutes")
        #expect(model.bestEffect == "+6")
        #expect(model.streak == 4, "four evenings in a row up to yesterday")
        #expect(model.tonight?.kind == .breathe)
    }

    @Test("Journal tags that behave like rituals join, with the reading that fits them")
    func tagRituals() {
        #expect(MindRituals.reading(forTag: "meditation", title: "Meditation") == .variability)
        #expect(MindRituals.reading(forTag: "sauna", title: "Sauna") == .deepSleep)
        #expect(MindRituals.reading(forTag: "custom-1", title: "Journal before bed") == .deepSleep)
        #expect(MindRituals.reading(forTag: "coffee-late", title: "Coffee after 14:00") == nil)
    }

    @Test("With nothing logged, the stats are dashes rather than zeros")
    func ritualsEmpty() {
        let model = MindRituals.make(from: MindInputs(now: at(12)), journal: MindJournal(), calendar: calendar)
        #expect(model.rituals.isEmpty)
        #expect(model.thisWeek == nil)
        #expect(model.streak == nil)
        #expect(model.bestEffect == nil)
    }

    @Test("An effect that rounds to zero is not presented as the best one")
    func ritualsRoundedZero() {
        let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        let mindful = "HKCategoryTypeIdentifierMindfulSession"
        var inputs = MindInputs(now: at(12))
        for offset in 1...10 {
            let breathed = offset <= 4
            inputs.heartRateVariability.append(reading(hrv, breathed ? 44.3 : 44, at: at(22, day: -offset)))
            if breathed {
                inputs.mindful.append(reading(mindful, 1, at: at(19, day: -offset), lasting: 10 * 60))
            }
        }
        let model = MindRituals.make(from: inputs, journal: MindJournal(), calendar: calendar)
        let breathe = model.rituals.first { $0.kind == .breathe }
        #expect(breathe?.signedDelta == "0", "the row still shows the measured move")
        #expect(breathe?.isClear == false)
        #expect(breathe?.isCost == false)
        #expect(model.bestEffect == nil, "no effect is not the best effect")
        #expect(model.tonight == nil)
        #expect(model.tonightDetail.hasPrefix("10 minutes of slow breathing"))
    }

    // MARK: - Breathing

    @Test("A breath is four seconds in and six out")
    func breathCycle() {
        #expect(MindBreatheSheet.breath(at: 0).isInhaling)
        #expect(MindBreatheSheet.breath(at: 3.9).isInhaling)
        #expect(!MindBreatheSheet.breath(at: 4.1).isInhaling)
        #expect(MindBreatheSheet.breath(at: 10).isInhaling)
        #expect(abs(MindBreatheSheet.breath(at: 4).scale - 1) < 0.001)
        #expect(abs(MindBreatheSheet.breath(at: 0).scale - MindBreatheSheet.emptyScale) < 0.001)
        #expect(MindBreatheSheet.clock(600) == "10:00")
        #expect(MindBreatheSheet.clock(59.2) == "1:00")
    }
}
