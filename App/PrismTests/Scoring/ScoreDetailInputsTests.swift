//
//  ScoreDetailInputsTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import HealthScoring
@testable import Prism

/// The score pages read Health through one call that names the parts a page
/// needs. Each part is a set of reads laid onto thirty days or onto the
/// nights; what is checked here is that each lands on the right day, that a
/// day or a night without a reading stays empty rather than zero, and that a
/// store that refuses every read leaves the page with dashes, not a crash.
@Suite("Score detail inputs")
struct ScoreDetailInputsTests {
    typealias Metric = ScoreDetailInputs.Metric

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// 3 October 2026 at the given time, `day` days from it.
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    var now: Date { at(15) }

    func read(_ parts: Set<ScoreDetailInputs.Part>, _ readings: [HealthReading], fails: Bool = false) async -> ScoreDetailInputs {
        await ScoreDetailInputs.read(parts, from: ScriptedHealthSource(readings, fails: fails), now: now, calendar: calendar)
    }

    /// Last night: in bed at 22:40, asleep from 23:00 to 07:00.
    var lastNight: [HealthReading] {
        [
            .test(Metric.sleep, 0, from: at(22, 40, day: -1), to: at(7, 5)),
            .test(Metric.sleep, 3, from: at(23, day: -1), to: at(7)),
        ]
    }

    // MARK: What a page asks for

    @Test("Sleep is always asked for, and each part adds only its own metrics")
    func metricsPerPart() {
        #expect(ScoreDetailInputs.metrics(for: []) == [Metric.sleep])
        #expect(ScoreDetailInputs.metrics(for: [.sound]) == [Metric.sound, Metric.sleep].sorted())

        let today = Set(ScoreDetailInputs.metrics(for: [.today]))
        #expect(today.isSuperset(of: [Metric.heartRate, Metric.steps, Metric.activeEnergy, Metric.standHour,
                                      Metric.workout, Metric.dateOfBirth]))

        let all = ScoreDetailInputs.metrics(for: Set(ScoreDetailInputs.Part.allCases))
        #expect(all == all.sorted())
        #expect(Set(all).count == all.count)
    }

    @Test("Every metric a page can ask for is one the Health catalog knows")
    func metricsAreInTheCatalog() {
        for identifier in ScoreDetailInputs.metrics(for: Set(ScoreDetailInputs.Part.allCases)) {
            #expect(HealthMetricCatalog.metric(for: identifier) != nil, "\(identifier) is not in the catalog")
        }
    }

    @Test("Readings are averaged per night, and a night with none, or no night, is a gap")
    func byNight() {
        let nights: [ScoringNightWindow?] = [
            ScoringNightWindow(start: at(23, day: -2), end: at(7, day: -1)),
            nil,
            ScoringNightWindow(start: at(23, day: -1), end: at(7)),
        ]
        let readings: [HealthReading] = [
            .test(Metric.respiratory, 14, at: at(1, day: -1)),
            .test(Metric.respiratory, 16, at: at(4, day: -1)),
            .test(Metric.respiratory, 30, at: at(12, day: -1)),
        ]
        #expect(ScoreDetailInputs.byNight(readings, nights: nights) == [15, nil, nil])
    }

    // MARK: Reading

    @Test("Last night is found, with the time its tracker says bed began")
    func nights() async {
        let inputs = await read([.nights], lastNight)
        #expect(inputs.nights.count == ScoreDetailInputs.days)
        #expect(inputs.recordedNights.count == 1)
        let last = inputs.nights.last ?? nil
        #expect(last != nil)
        #expect((last?.start ?? .distantFuture) <= at(23, 30, day: -1))
        #expect((last?.end ?? .distantPast) >= at(6, 30))
        #expect(inputs.inBedStart == at(22, 40, day: -1))
    }

    @Test("The night's heart rate is its mean, and its beats come in time order")
    func nightHeart() async {
        let beats: [HealthReading] = [
            .test(Metric.heartRate, 55, at: at(5)),
            .test(Metric.heartRate, 60, at: at(23, 30, day: -1)),
            .test(Metric.heartRate, 50, at: at(2)),
            .test(Metric.restingHeartRate, 52, at: at(8)),
        ]
        let inputs = await read([.nightHeart], lastNight + beats)
        #expect(inputs.nightHeartRate.last == 55)
        #expect(inputs.lastNightBeats.map(\.value) == [60, 50, 55])
        #expect(inputs.resting.last == 52)
    }

    @Test("HRV and resting heart rate land on the day they were measured, other days empty")
    func heart() async {
        let readings: [HealthReading] = [
            .test(Metric.hrv, 40, at: at(7)),
            .test(Metric.hrv, 50, at: at(12)),
            .test(Metric.hrv, 62, at: at(7, day: -2)),
            .test(Metric.restingHeartRate, 54, at: at(7)),
        ]
        let inputs = await read([.heart], readings)
        #expect(inputs.hrv.count == ScoreDetailInputs.days)
        #expect(inputs.hrv.last == 45)
        #expect(inputs.hrv[ScoreDetailInputs.days - 3] == 62)
        #expect(inputs.hrv[ScoreDetailInputs.days - 2] == nil)
        #expect(inputs.resting.last == 54)
    }

    @Test("Today counts steps and energy since midnight, the hours stood, and the week's workouts in order")
    func today() async {
        let readings: [HealthReading] = [
            .test(Metric.steps, 2_000, at: at(21, day: -1)),
            .test(Metric.steps, 3_000, at: at(8)),
            .test(Metric.steps, 4_500, at: at(12)),
            .test(Metric.activeEnergy, 180, at: at(9)),
            .test(Metric.activeEnergy, 220, at: at(13)),
            .test(Metric.standHour, 0, at: at(9)),
            .test(Metric.standHour, 0, at: at(10)),
            .test(Metric.standHour, 1, at: at(11)),
            .test(Metric.heartRate, 88, at: at(14)),
            .test(Metric.heartRate, 72, at: at(9)),
            .test(Metric.workout, 37, from: at(18, day: -1), to: at(19, day: -1)),
            .test(Metric.workout, 13, from: at(7, day: -3), to: at(8, day: -3)),
            .test(Metric.workout, 37, from: at(7, day: -9), to: at(8, day: -9)),
            .test(Metric.dateOfBirth, 35, at: at(0, day: -400)),
        ]
        let inputs = await read([.today], readings)
        #expect(inputs.steps == 7_500)
        #expect(inputs.activeEnergy == 400)
        #expect(inputs.standHours == 2)
        #expect(inputs.todayHeartRate.map(\.value) == [72, 88])
        #expect(inputs.workouts.map(\.start) == [at(7, day: -3), at(18, day: -1)])
        #expect(inputs.age == 35)
    }

    @Test("A day without stand hours reads as unknown, not as zero hours")
    func noStandHours() async {
        let inputs = await read([.today], [.test(Metric.steps, 1_000, at: at(9))])
        #expect(inputs.standHours == nil)
        #expect(inputs.activeEnergy == nil)
    }

    @Test("A store that refuses every read leaves every series empty")
    func refusedStore() async {
        let inputs = await read(Set(ScoreDetailInputs.Part.allCases), lastNight, fails: true)
        #expect(inputs.recordedNights.isEmpty)
        #expect(inputs.inBedStart == nil)
        #expect(inputs.hrv.allSatisfy { $0 == nil })
        #expect(inputs.respiratory.allSatisfy { $0 == nil })
        #expect(inputs.nightSound.allSatisfy { $0 == nil })
        #expect(inputs.todayHeartRate.isEmpty)
        #expect(inputs.workouts.isEmpty)
        #expect(inputs.steps == nil)
        #expect(inputs.standHours == nil)
        #expect(inputs.age == nil)
    }

    @Test("Last night's vitals are its own readings in time order, oxygen in percent, nothing from the day")
    func nightVitals() async {
        let readings = lastNight + [
            .test(Metric.oxygen, 0.95, at: at(3)),
            .test(Metric.oxygen, 0.97, at: at(1)),
            .test(Metric.oxygen, 0.99, at: at(12)),
            .test(Metric.respiratory, 14, at: at(2)),
            .test(Metric.sound, 34, at: at(4)),
        ]
        let inputs = await read([.nightVitals], readings)
        #expect(inputs.lastNightVitals.oxygen.map { $0.value.rounded() } == [97, 95])
        #expect(inputs.lastNightVitals.breathing.map(\.value) == [14])
        #expect(inputs.lastNightVitals.sound.map(\.value) == [34])
        #expect(inputs.lastNightVitals.hrv.isEmpty)
    }

    @Test("Without the vitals part nothing is read through the night")
    func noNightVitals() async {
        let inputs = await read([.nights], lastNight + [.test(Metric.oxygen, 0.95, at: at(3))])
        #expect(inputs.lastNightVitals == ScoreDetailInputs.NightVitals())
    }
}
