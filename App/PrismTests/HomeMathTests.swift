//
//  HomeMathTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The pages Today opens are arithmetic over readings: a marker against its
/// usual, last night in stages, stand hours, the cycle, a meal's rise and a
/// workout's effort.
@Suite("Pulse home math")
struct HomeMathTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func reading(_ metric: String, _ value: Double, _ start: Date, _ end: Date? = nil) -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .none, start: start, end: end ?? start.addingTimeInterval(60))
    }

    // MARK: Marker

    @Test("A marker reads its latest day against the month before it")
    func marker() {
        var readings: [HealthReading] = []
        for offset in 1...30 {
            readings.append(reading("rhr", offset.isMultiple(of: 2) ? 52 : 56, at(7, day: -offset)))
        }
        readings.append(reading("rhr", 57, at(7)))
        let series = HomeMarkerSeries.make(readings, days: 30, today: at(12), calendar: calendar)
        #expect(series.latest == 57)
        #expect(series.usual == 54)
        #expect(series.band == 52...56)
        #expect(series.days.count == 30)
        #expect(series.days.last == 57)
        #expect(series.changes.map(\.days) == [3, 7, 14, 30, 90])
        #expect(series.changes.last?.change == nil)
    }

    @Test("A marker with nothing recorded is all dashes")
    func markerEmpty() {
        let series = HomeMarkerSeries.make([], days: 30, today: at(12), calendar: calendar)
        #expect(series.latest == nil)
        #expect(series.usual == nil)
        #expect(series.days.allSatisfy { $0 == nil })
        #expect(HomeMarkerSeries.direction(nil, step: 0.5) == "-")
        #expect(HomeMarkerSeries.direction(1.3, step: 0.5) == "Rising")
        #expect(HomeMarkerSeries.direction(0.2, step: 0.5) == "Steady")
    }

    // MARK: Night

    @Test("Last night splits into stages, wakings and the time to fall asleep")
    func night() {
        let sleep = "HKCategoryTypeIdentifierSleepAnalysis"
        let samples = [
            reading(sleep, 0, at(23, 40, day: -1), at(7, 15)),
            reading(sleep, 3, at(23, 51, day: -1), at(0, 30)),
            reading(sleep, 4, at(0, 30), at(1, 30)),
            reading(sleep, 3, at(1, 30), at(3, 26)),
            reading(sleep, 2, at(3, 26), at(3, 36)),
            reading(sleep, 5, at(3, 36), at(5, 0)),
            reading(sleep, 3, at(5, 0), at(7, 13)),
        ]
        let night = HomeNightStages.make(samples, now: at(18), calendar: calendar)
        #expect(night != nil)
        #expect(abs((night?.totals[.deep] ?? 0) - 3600) < 1)
        #expect(abs((night?.totals[.rem] ?? 0) - 84 * 60) < 1)
        #expect(night?.wakings == [at(3, 26)])
        #expect(abs((night?.latency ?? 0) - 11 * 60) < 1)
        #expect(night?.isStaged == true)
    }

    @Test("No sleep ending today, no night")
    func noNight() {
        #expect(HomeNightStages.make([], now: at(18), calendar: calendar) == nil)
    }

    // MARK: Stand

    @Test("Stand hours: stood, missed, the hour running, and the ones still open")
    func stand() {
        let stand = "HKCategoryTypeIdentifierAppleStandHour"
        let samples = [
            reading(stand, 0, at(9)),
            reading(stand, 1, at(14)),
            reading(stand, 0, at(15)),
        ]
        let hours = HomeStandHour.day(samples, now: at(18, 2), calendar: calendar)
        #expect(hours.count == 24)
        #expect(hours[9] == .stood)
        #expect(hours[14] == .missed)
        #expect(hours[15] == .stood)
        #expect(hours[18] == .now)
        #expect(hours[20] == .open)
        #expect(hours.filter { $0 == .stood }.count == 2)
    }

    // MARK: Cycle

    @Test("Periods, their lengths, today's day and phase, and the next start")
    func cycle() {
        var flow: [Date] = []
        for start in [-85, -57, -28] {
            for day in 0..<5 { flow.append(at(8, day: start + day)) }
        }
        let cycle = HomeCycle.make(flowDays: flow, today: at(12), calendar: calendar)
        #expect(cycle?.starts.count == 3)
        #expect(cycle?.lengths == [28, 29])
        #expect(cycle?.length == 29)
        #expect(cycle?.day == 29)
        #expect(cycle?.phase == .luteal)
        #expect(cycle?.nextStart == calendar.startOfDay(for: at(12, day: 1)))
    }

    @Test("One period only: the day, but no length and no phase")
    func cycleShort() {
        let flow = (0..<4).map { at(8, day: -16 + $0) }
        let cycle = HomeCycle.make(flowDays: flow, today: at(12), calendar: calendar)
        #expect(cycle?.day == 17)
        #expect(cycle?.length == nil)
        #expect(cycle?.phase == nil)
        #expect(HomeCycle.make(flowDays: [], today: at(12), calendar: calendar) == nil)
    }

    // MARK: Meals

    @Test("A meal's rise is the peak over the half hour before it")
    func mealResponse() {
        let glucose = "HKQuantityTypeIdentifierBloodGlucose"
        let lunch = at(12, 48)
        let readings = [
            reading(glucose, 92, at(12, 30)),
            reading(glucose, 94, at(12, 45)),
            reading(glucose, 120, at(13, 15)),
            reading(glucose, 141, at(13, 35)),
            reading(glucose, 110, at(14, 5)),
            reading(glucose, 96, at(14, 33)),
        ]
        let response = HomeMealResponse.make(meal: lunch, glucose: readings)
        #expect(response?.rise == 48)
        #expect(response?.peakAt == at(13, 35))
        #expect(abs((response?.backToBaseline ?? 0) - 105 * 60) < 1)
        #expect(HomeMealResponse.make(meal: lunch, glucose: Array(readings.suffix(3))) == nil)
    }

    // MARK: Effort

    @Test("Soma's read of an effort follows the heart's share of its maximum")
    func effort() {
        #expect(HomeEffortMath.somaRead(averageHeartRate: 125, age: 46) == 6)
        #expect(HomeEffortMath.somaRead(averageHeartRate: 80, age: 46) == 1)
        #expect(HomeEffortMath.somaRead(averageHeartRate: nil, age: 46) == nil)
        #expect(HomeEffortMath.word(7) == "Hard")
    }

    @Test("The week's load is rating times minutes over seven days")
    func load() {
        let efforts = [
            HomeEffort(workoutStart: at(17), minutes: 45, rating: 7),
            HomeEffort(workoutStart: at(7, day: -3), minutes: 30, rating: 3),
            HomeEffort(workoutStart: at(7, day: -9), minutes: 60, rating: 5),
        ]
        #expect(HomeEffortMath.weekLoad(efforts, now: at(18), calendar: calendar) == 405)
        #expect(HomeEffortMath.weekLoad([], now: at(18), calendar: calendar) == nil)
    }

    // MARK: Log

    @Test("Track's log keeps a day's water and caffeine for Pulse, and a missing day is nil")
    @MainActor
    func log() {
        let log = TrackLogStore(url: nil, calendar: calendar)
        #expect(log.waterMl(on: at(12)) == nil)
        #expect(log.caffeineMg(on: at(12)) == nil)
        log.addDrink(.water, ml: 250, at: at(9))
        log.addDrink(.water, ml: 250, at: at(11))
        log.addDrink(.water, ml: 500, at: at(9, day: -1))
        log.addDrink(.coffee, ml: 250, caffeineMg: 95, at: at(8))
        #expect(log.caffeineMg(on: at(12)) == 95)
        #expect(log.lastCaffeine(on: at(12)) == at(8))
        log.removeLastDrink(on: at(12)) { $0.drink == .water }
        #expect(log.drinks(on: at(12)).filter { $0.drink == .water }.count == 1)
        log.removeLastDrink(on: at(12)) { $0.caffeineMg > 0 }
        #expect(log.caffeineMg(on: at(12)) == nil)
        log.setWakeFeel(9, on: at(8))
        #expect(log.wakeFeel(on: at(20)) == 5)
        #expect(log.wakeRating(on: at(20)) == 10)
        log.setWakeRating(5, on: at(8))
        #expect(log.wakeFeel(on: at(20)) == 3)
    }
}
