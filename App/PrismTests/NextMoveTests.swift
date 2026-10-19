//
//  NextMoveTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
@testable import Prism

/// The Next move engine is an arbiter over plain values, so it is tested
/// with a context built by hand and the winner read back.
@Suite("Next move")
struct NextMoveTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute))!
    }

    func context(_ hour: Int, _ minute: Int = 0) -> NextMoveContext {
        NextMoveContext(now: at(hour, minute), calendar: calendar)
    }

    @Test("An empty context proposes nothing but the evening check-in")
    func empty() {
        let arbiter = NextMoveArbiter()
        #expect(arbiter.winner(context(15)) == nil)
        #expect(arbiter.winner(context(20))?.id == "eveningCheckIn.answer")
    }

    @Test("Two stress peaks ask for breathing, inside its hours only")
    func stress() {
        var ctx = context(18, 2)
        ctx.stressScore = 55
        ctx.stressPeaks = 2
        #expect(NextMoveArbiter().winner(ctx)?.id == "stressDownshift.breathe")

        ctx.now = at(22)
        #expect(NextMoveArbiter().rank(ctx).contains { $0.id == "stressDownshift.breathe" } == false)
    }

    @Test("Minutes of calm already taken silence the breathing move")
    func stressCalmed() {
        var ctx = context(15)
        ctx.stressScore = 70
        ctx.mindfulMinutes = 12
        #expect(NextMoveArbiter().rank(ctx).isEmpty)
    }

    @Test("A higher tier wins whatever the impact")
    func tiers() {
        var ctx = context(18)
        ctx.stressScore = 62
        ctx.restingHeartRate = 68
        ctx.restingHeartRateBaseline = 56
        let ranked = NextMoveArbiter().rank(ctx)
        #expect(ranked.first?.id == "restingHeartRate.easeOff")
        #expect(ranked.first?.tier == .urgent)
    }

    @Test("One move per domain: recovery keeps its strongest rule")
    func domainCollapse() {
        var ctx = context(10)
        ctx.restingHeartRate = 62
        ctx.restingHeartRateBaseline = 56
        ctx.recoveryScore = 30
        ctx.recoveryObjective = 60
        let recovery = NextMoveArbiter().rank(ctx).filter { $0.domain == .recovery }
        #expect(recovery.count == 1)
        #expect(recovery.first?.id == "recoveryDeficit.easyDay")
    }

    @Test("A walk is never offered while recovery is well under its usual")
    func contradiction() {
        var ctx = context(15)
        ctx.exerciseMinutes = 5
        ctx.exerciseUsualByNow = 40
        #expect(NextMoveArbiter().rank(ctx).contains { $0.id == "movementGap.walk" })

        ctx.recoveryScore = 40
        ctx.recoveryObjective = 60
        #expect(NextMoveArbiter().rank(ctx).contains { $0.id == "movementGap.walk" } == false)
    }

    @Test("The walk asks for the shortfall, rounded to five minutes")
    func walkMinutes() {
        var ctx = context(15)
        ctx.exerciseMinutes = 8
        ctx.exerciseUsualByNow = 31
        let walk = NextMoveArbiter().rank(ctx).first { $0.id == "movementGap.walk" }
        #expect(walk?.title == "Walk for 20 minutes")
        #expect(walk?.door == .walk(minutes: 20))
    }

    @Test("Sleep debt speaks only near bedtime")
    func sleepDebt() {
        var ctx = context(10)
        ctx.sleepSeconds = 6 * 3600
        ctx.sleepNeedSeconds = 7.5 * 3600
        ctx.habitualBedHour = 23
        #expect(NextMoveArbiter().rank(ctx).contains { $0.domain == .sleep } == false)

        ctx.now = at(21)
        let sleep = NextMoveArbiter().rank(ctx).first { $0.domain == .sleep }
        #expect(sleep?.id == "sleepDebt.extendTonight")
        #expect(sleep?.tier == .urgent)
        #expect(sleep?.title == "Bed 90 minutes earlier")
    }

    @Test("Late at night the lights-out move reads the usual bedtime on the clock face")
    func lateNight() {
        var ctx = context(0, 30)
        ctx.habitualBedHour = 23.25
        #expect(NextMoveArbiter().winner(ctx)?.id == "lateNight.lightsOut")

        ctx.habitualBedHour = 0.25
        #expect(NextMoveArbiter().winner(ctx) == nil)
    }

    @Test("Caffeine past 400 mg says stop; before that, a last call eight hours before bed")
    func caffeine() {
        var ctx = context(13)
        ctx.caffeineMg = 450
        #expect(NextMoveArbiter().winner(ctx)?.id == "caffeine.noneLeft")

        ctx.caffeineMg = 120
        ctx.habitualBedHour = 23
        let lastCall = NextMoveArbiter().winner(ctx)
        #expect(lastCall?.id == "caffeine.lastCall")
        #expect(lastCall?.title == "Last coffee by 15:00")

        ctx.now = at(15, 30)
        #expect(NextMoveArbiter().winner(ctx) == nil)
    }

    @Test("Two night signals moving together raise the illness watch")
    func illness() {
        var ctx = context(9)
        ctx.respiratoryRate = 16.2
        ctx.respiratoryRateBaseline = 14.5
        ctx.wristTemperature = 0.6
        ctx.wristTemperatureBaseline = 0.1
        let watch = NextMoveArbiter().winner(ctx)
        #expect(watch?.id == "illnessWatch.easeToday")
        #expect(watch?.evidence.count == 2)

        ctx.wristTemperature = 0.2
        #expect(NextMoveArbiter().winner(ctx) == nil)
    }

    @Test("Windows wrap past midnight")
    func windows() {
        let night = NextMoveWindow(startHour: 23, endHour: 5)
        #expect(night.contains(hour: 23))
        #expect(night.contains(hour: 2))
        #expect(!night.contains(hour: 5))
        #expect(!night.contains(hour: 12))
        #expect(NextMoveWindow(startHour: 19, endHour: 0).contains(hour: 23))
    }

    @Test("Impact is the product of three factors")
    func impact() {
        #expect(NextMoveImpact(severity: 100, leverage: 100, timeliness: 100).score == 100)
        #expect(NextMoveImpact(severity: 50, leverage: 80, timeliness: 50).score == 20)
        #expect(NextMoveImpact(severity: 0, leverage: 80, timeliness: 50).score == 0)
        #expect(NextMoveImpact(severity: 1, leverage: 1, timeliness: 1).score == 1)
    }

    @Test("Asks round to a step a person can act on")
    func asks() {
        #expect(NextMoveAsk.water(ml: 1_234) == 1000)
        #expect(NextMoveAsk.water(ml: 430) == 400)
        #expect(NextMoveAsk.protein(grams: 27) == 25)
        #expect(NextMoveAsk.movement(minutes: 3) == 10)
    }

    @Test("The usual bedtime is a circular mean, so 23:30 and 00:30 average to midnight")
    @MainActor
    func bedtime() {
        let nights = (0..<6).map { index -> PulseNight in
            let hour = index.isMultiple(of: 2) ? 23 : 0
            let minute = 30
            let day = calendar.date(byAdding: .day, value: -index, to: at(0))!
            let bed = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            return PulseNight(day: day, bedtime: bed, fellAsleep: bed, woke: bed.addingTimeInterval(7 * 3600), asleep: 7 * 3600, deep: nil)
        }
        let hour = NextMoveContext.habitualBedHour(nights, calendar: calendar)!
        #expect(abs(hour) < 0.01 || abs(hour - 24) < 0.01)
    }

    @Test("Track's log fills water and protein, the home log the check-in")
    @MainActor
    func fromLog() {
        let log = HomeLog(url: nil, calendar: calendar)
        let track = TrackLogStore(url: nil, calendar: calendar)
        let now = at(15)
        track.addDrink(.water, ml: 500, at: at(9))
        track.addDrink(.water, ml: 250, at: at(12))
        track.addMeal(TrackMealEntry(name: "Rice bowl", meal: .lunch, protein: 32, carbs: 80, fat: 18, portions: 1, date: at(12, 30)))
        let ctx = NextMoveContext.make(inputs: PulseInputs(now: now), scores: nil, log: log, track: track, calendar: calendar)
        #expect(ctx.waterMl == 750)
        #expect(ctx.waterTargetMl == 2_000)
        #expect(ctx.proteinGrams == 32)
        #expect(ctx.proteinUsualGrams == nil)
        #expect(ctx.checkedInToday == false)
        #expect(NextMoveArbiter().winner(ctx)?.id == "hydrationGap.drink")
    }
}
