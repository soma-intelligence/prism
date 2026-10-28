//
//  TrackLogTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// Track's logging arithmetic: fasting, the caffeine model, adherence to a
/// rhythm, the glass, and the store that keeps it all.
@Suite("Track log")
struct TrackLogTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Fasting

    @Test("A fast is read from its start: elapsed, fraction and what is left")
    func fastDerivesFromStart() {
        let fast = TrackFast(start: date(9, 16, 20), objectiveHours: 14)
        let now = date(9, 17, 3)
        #expect(fast.elapsed(at: now) == 7 * 3600)
        #expect(fast.fraction(at: now) == 0.5)
        #expect(fast.remaining(at: now) == 7.0 * 3600)
        #expect(fast.goalEnd == date(9, 17, 10))
        #expect(TrackFast(start: now, objectiveHours: nil).fraction(at: now) == nil)
        #expect(fast.elapsed(at: date(9, 16, 19)) == 0)
    }

    @Test("A start at an hour already past by more than half an hour is tomorrow's")
    func nextStartRollsOver() {
        let now = date(9, 16, 18, 2)
        #expect(TrackFasting.nextStart(at: 20, from: now, calendar: calendar) == date(9, 16, 20))
        #expect(TrackFasting.nextStart(at: 18, from: now, calendar: calendar) == date(9, 16, 18))
        #expect(TrackFasting.nextStart(at: 8, from: now, calendar: calendar) == date(9, 17, 8))
    }

    @Test("Hours snap to the quarter and wrap round the clock")
    func snapping() {
        #expect(TrackFasting.snapped(20.1) == 20)
        #expect(TrackFasting.snapped(23.9) == 0)
        #expect(TrackFasting.snapped(-0.5) == 23.5)
    }

    @Test("The part of a fast inside the sleep window counts across midnight")
    func overlapWithSleepWindow() {
        // 20:00 for 14 hours against 23:15 to 07:00: 7h 45m.
        let seconds = TrackFasting.overlap(start: date(9, 16, 20), hours: 14, window: (23.25, 7), calendar: calendar)
        #expect(seconds == (7 * 60 + 45) * 60)
        let english = Locale(identifier: "en_US")
        #expect(TrackFasting.length(seconds, locale: english) == "7h 45m")
        #expect(TrackFasting.length(14 * 3600, locale: english) == "14h")
        #expect(TrackFasting.length(40 * 60, locale: english) == "40m")
    }

    @Test("The usual window is the median of nights, evening hours read past midnight")
    func usualWindow() {
        let asleep = [date(9, 1, 23, 30), date(9, 2, 0, 30), date(9, 3, 23, 0), date(9, 4, 0, 0), date(9, 5, 23, 45)]
        let woke = [date(9, 2, 7), date(9, 3, 7, 30), date(9, 4, 6, 30), date(9, 5, 7), date(9, 6, 7)]
        let window = TrackFasting.usualWindow(asleep: asleep, woke: woke, calendar: calendar)
        #expect(window?.from == 23.75)
        #expect(window?.to == 7)
        #expect(TrackFasting.usualWindow(asleep: Array(asleep.prefix(2)), woke: woke, calendar: calendar) == nil)
    }

    // MARK: Caffeine

    @Test("Half of a dose is gone after one half life")
    func caffeineHalves() {
        let dose = TrackCaffeine.Dose(mg: 200, time: date(9, 16, 8))
        #expect(abs(TrackCaffeine.residual(doses: [dose], at: date(9, 16, 13)) - 100) < 0.001)
        #expect(TrackCaffeine.residual(doses: [dose], at: date(9, 16, 7)) == 0)
    }

    @Test("With nothing logged, a standard cup's last call is ten hours before bed")
    func lastCallMatchesPlainFormula() throws {
        let bedtime = date(9, 16, 23)
        let reading = TrackCaffeine.read(doses: [], bedtime: bedtime, now: date(9, 16, 8))
        let lastCall = try #require(reading.lastCall)
        let hours = bedtime.timeIntervalSince(lastCall) / 3600
        #expect(abs(hours - 5 * log2(100.0 / 25)) < 0.001)
        #expect(reading.onBoardNowMg == 0)
        #expect(reading.clearsAt == nil)
    }

    @Test("Coffee already on board pulls the last call earlier, and a spent day has none")
    func lastCallTightens() throws {
        let bedtime = date(9, 16, 23)
        let now = date(9, 16, 12)
        let empty = TrackCaffeine.read(doses: [], bedtime: bedtime, now: now)
        let morning = TrackCaffeine.read(doses: [.init(mg: 150, time: date(9, 16, 8))], bedtime: bedtime, now: now)
        let morningLastCall = try #require(morning.lastCall)
        let emptyLastCall = try #require(empty.lastCall)
        #expect(morningLastCall < emptyLastCall)
        let heavy = TrackCaffeine.read(doses: [.init(mg: 400, time: date(9, 16, 18))], bedtime: bedtime, now: date(9, 16, 19))
        #expect(heavy.isOverBudget)
        #expect(heavy.lastCall == nil)
        let clearsAt = try #require(heavy.clearsAt)
        #expect(clearsAt > bedtime)
    }

    // MARK: Adherence

    @Test("A daily rhythm counts what was kept, and today is due until logged")
    func dailyAdherence() {
        let start = date(9, 10)
        let doses = [date(9, 10, 8), date(9, 11, 8), date(9, 13, 8), date(9, 14, 22)]
        let plan = TrackAdherence.plan(cadence: .daily, startedOn: start, doseDates: doses, now: date(9, 15, 9), calendar: calendar)
        #expect(plan.isDueToday)
        #expect(plan.missedCount == 1)
        #expect(plan.daysLate == 3)
        #expect(plan.streak == 0)
        #expect(plan.adherencePercent == 4.0 / 6.0 * 100)
        #expect(plan.nextDueOn == date(9, 15))
    }

    @Test("Before anything is due there is no percentage, not zero")
    func noAdherenceYet() {
        let weekly = TrackCadence.weekly(weekday: 2)!
        // Tuesday 15 September, started that day: the first Monday is ahead.
        let plan = TrackAdherence.plan(cadence: weekly, startedOn: date(9, 15), doseDates: [], now: date(9, 15, 9), calendar: calendar)
        #expect(plan.adherencePercent == nil)
        #expect(plan.nextDueOn == date(9, 21))
        #expect(!plan.isDueToday)
    }

    @Test("On and off cycles and every N days fall where they should")
    func cadences() {
        let start = date(9, 1)
        let cycle = TrackCadence.cycleOnOff(on: 2, off: 1)!
        #expect(TrackAdherence.isDue(cycle, on: date(9, 2), startedOn: start, calendar: calendar))
        #expect(!TrackAdherence.isDue(cycle, on: date(9, 3), startedOn: start, calendar: calendar))
        #expect(TrackAdherence.isDue(TrackCadence.everyNDays(3)!, on: date(9, 7), startedOn: start, calendar: calendar))
        #expect(!TrackAdherence.isDue(.daily, on: date(8, 31), startedOn: start, calendar: calendar))
        #expect(TrackCadence.everyNDays(0) == nil)
        #expect(TrackCadence.weekly(weekday: 8) == nil)
    }

    // MARK: The glass

    @Test("A fill snaps to the drink's step and never spills")
    func glassSnaps() {
        #expect(TrackIntake.value(forFill: 0.26, max: 1000, step: 50) == 250)
        #expect(TrackIntake.value(forFill: 1.4, max: 1000, step: 50) == 1000)
        #expect(TrackIntake.fill(forValue: 250, max: 1000) == 0.25)
        #expect(TrackIntake.stepsCrossed(from: 240, to: 360, step: 50) == 3)
        #expect(TrackDrink.coffee.caffeine(ml: 250) == 80)
        #expect(TrackDrink.water.caffeine(ml: 250) == 0)
    }

    @Test("The day's glasses fill in order, the last one part way")
    func dayGlasses() {
        let glasses = TrackIntake.glasses(total: 1600, goal: 2000)
        #expect(glasses.count == 8)
        #expect(glasses.prefix(6).allSatisfy { $0 == 1 })
        #expect(abs(glasses[6] - 0.4) < 0.0001)
        #expect(glasses[7] == 0)
        #expect(TrackIntake.litres(1600) == "1.6")
        #expect(TrackIntake.litres(2000) == "2")
    }

    // MARK: Units

    @Test("Weight and height convert both ways and read as people write them")
    func units() {
        #expect(TrackMassUnit.kilograms.text(68.44) == "68.4")
        #expect(abs(TrackMassUnit.pounds.kilograms(TrackMassUnit.pounds.display(70)) - 70) < 0.0001)
        #expect(TrackLengthUnit.centimetres.parts(172).value == "172.0")
        #expect(TrackLengthUnit.feetInches.parts(172.7).value == "5\u{2032} 8\u{2033}")
    }

    @Test("A meal's energy is the Atwater sum, scaled by portions")
    func mealEnergy() {
        let meal = TrackMealEntry(name: "Salmon", meal: .dinner, protein: 38, carbs: 62, fat: 22, portions: 1.5, date: date(9, 16, 18))
        #expect(TrackMealEntry.kilocalories(protein: 38, carbs: 62, fat: 22) == 598)
        #expect(meal.kilocalories == 897)
        #expect(TrackMeal.at(hour: 18) == .dinner)
        #expect(TrackMeal.at(hour: 8) == .breakfast)
    }

    // MARK: Store

    @Test("The store keeps one fast running, ends it, and totals a day's drinks")
    @MainActor
    func store() {
        let store = TrackLogStore(url: nil, calendar: calendar)
        #expect(store.waterMl(on: date(9, 16)) == nil)
        store.addDrink(.water, ml: 250, at: date(9, 16, 8))
        store.addDrink(.coffee, ml: 250, at: date(9, 16, 9))
        store.addDrink(.water, ml: 500, at: date(9, 15, 9))
        #expect(store.waterMl(on: date(9, 16, 12)) == 500)
        #expect(store.caffeineDoses(before: date(9, 16, 12)).map(\.mg) == [80])

        store.startFast(at: date(9, 16, 20), objectiveHours: 14, now: date(9, 16, 20))
        store.startFast(at: date(9, 16, 21), objectiveHours: 16, now: date(9, 16, 21))
        #expect(store.fasts.filter { $0.end == nil }.count == 1)
        #expect(store.currentFast?.objectiveHours == 16)
        let ended = store.endFast(at: date(9, 17, 9))
        #expect(ended?.elapsed(at: date(9, 18)) == 12.0 * 3600)
        #expect(store.currentFast == nil)

        store.setWakeRating(14, on: date(9, 16, 7))
        #expect(store.wakeRating(on: date(9, 16)) == 10)

        let magnesium = store.addSupplement(name: "Magnesium", amount: 300, unit: .milligrams, minute: 22 * 60, startedOn: date(9, 16))
        let again = store.addSupplement(name: "magnesium", amount: 400, unit: .milligrams, minute: 22 * 60, startedOn: date(9, 16))
        #expect(store.supplements.count == 1)
        #expect(again?.amount == 400)
        store.logDose(name: "Magnesium", amount: 400, unit: .milligrams, supplementID: magnesium?.id, at: date(9, 16, 22))
        #expect(store.dose(of: store.supplements[0], on: date(9, 16)) != nil)
    }
}
