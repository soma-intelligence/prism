//
//  NextMoveScenarioTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The engine run across a whole day for a few kinds of people: the cue at
/// each hour, and the two promises the owner asked for on 2026-10-21. No
/// bedtime advice outside the evening and the night, and no advice for the
/// day ahead in the night.
@Suite("Next move across a day")
struct NextMoveScenarioTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    static let times: [(Int, Int)] = [(6, 30), (8, 0), (12, 30), (16, 0), (21, 30), (23, 30), (2, 0)]

    /// Moves that ask for bed or sleep timing.
    static let bedtimeIDs: Set<String> = ["sleepDebt.extendTonight", "bedtime.usual", "lateNight.lightsOut"]
    /// Moves that only make sense with the day still ahead.
    static let dayIDs: Set<String> = [
        "sleepDebt.easyDay", "recoveryDeficit.easyDay", "readyToTrain.push", "movementGap.walk",
        "hydrationGap.drink", "caffeine.lastCall", "caffeine.noneLeft", "restingHeartRate.easeOff",
        "lowVariability.gently", "stressDownshift.breathe", "illnessWatch.easeToday",
    ]

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute))!
    }

    enum Profile: String, CaseIterable {
        case earlyRiser, nightOwl, shortNight, highRestingHeart, workoutDone, caffeineLate
    }

    /// A day as the context would read it at `hour`:`minute`: a month of
    /// usual behind it, and only what has happened by then.
    func context(_ profile: Profile, _ hour: Int, _ minute: Int) -> NextMoveContext {
        let now = at(hour, minute)
        var ctx = NextMoveContext(now: now, calendar: calendar)
        ctx.habitualWakeHour = 7
        ctx.habitualBedHour = 23
        ctx.sleepNeedSeconds = 7.5 * 3600
        ctx.sleepSeconds = 7.5 * 3600
        ctx.sleepNights = 14
        ctx.restingHeartRate = 56
        ctx.restingHeartRateBaseline = 56
        ctx.restingHeartRateDays = 30
        ctx.recoveryScore = 66
        ctx.recoveryObjective = 64
        ctx.checkedInToday = true
        let elapsed = Double(max(0, hour - 7)) * 3
        ctx.exerciseMinutes = elapsed
        ctx.exerciseUsualByNow = elapsed
        ctx.workoutsToday = 0
        var woke = at(7)

        switch profile {
        case .earlyRiser:
            ctx.habitualWakeHour = 5.5
            ctx.habitualBedHour = 21.5
            woke = at(5, 30)
        case .nightOwl:
            ctx.habitualWakeHour = 9.5
            ctx.habitualBedHour = 1.5
            woke = at(9, 30)
        case .shortNight:
            ctx.sleepSeconds = 5 * 3600
            woke = at(6)
        case .highRestingHeart:
            ctx.restingHeartRate = 64
        case .workoutDone:
            ctx.recoveryScore = 82
            ctx.workoutsToday = 1
            ctx.exerciseMinutes = 50 + elapsed
        case .caffeineLate:
            let late = at(17, 30)
            ctx.caffeineMg = now >= late ? 200 : 100
            ctx.lastCaffeine = now >= late ? late : at(10)
        }
        // Today's wake is known once it has happened, as Health records it.
        ctx.wokeToday = woke <= now ? woke : nil
        if woke > now {
            // Before waking, last night is not recorded yet.
            ctx.sleepSeconds = nil
            ctx.exerciseMinutes = nil
            ctx.workoutsToday = nil
        }
        if profile == .caffeineLate, now < at(10) { ctx.caffeineMg = nil; ctx.lastCaffeine = nil }
        return ctx
    }

    @Test("No bedtime advice outside the evening and night, no day advice at night, never effort beside ease",
          arguments: Profile.allCases)
    func promises(_ profile: Profile) {
        for (hour, minute) in Self.times {
            let ctx = context(profile, hour, minute)
            let ranked = NextMoveArbiter().rank(ctx)
            let cue = NextMoveArbiter().cue(ctx)
            let label = "\(profile.rawValue) at \(hour):\(minute) (\(ctx.part)): \(ranked.map(\.id))"

            if ctx.part != .evening && ctx.part != .night {
                #expect(ranked.allSatisfy { !Self.bedtimeIDs.contains($0.id) }, "\(label)")
                #expect(!cue.title.lowercased().contains("bed"), "\(label)")
                #expect(!cue.orbWord.lowercased().contains("bed"), "\(label)")
            }
            if ctx.part == .night {
                #expect(ranked.allSatisfy { !Self.dayIDs.contains($0.id) }, "\(label)")
            }
            if ranked.contains(where: { $0.stance == .ease }) {
                #expect(!ranked.contains { $0.stance == .effort }, "\(label)")
            }
            // Every cue says why, in a line with no dash in it.
            #expect(!cue.orbWord.isEmpty)
            #expect(!cue.why.contains("\u{2014}") && !cue.why.contains("\u{2013}") && !cue.why.contains(" - "))
        }
    }

    /// The cue, by profile and time, as the orb would show it.
    func cueID(_ profile: Profile, _ hour: Int, _ minute: Int = 0) -> String {
        NextMoveArbiter().cue(context(profile, hour, minute)).id
    }

    @Test("An early riser: morning at half past six, lights out by half past eleven")
    func earlyRiser() {
        #expect(context(.earlyRiser, 6, 30).part == .morning)
        #expect(cueID(.earlyRiser, 6, 30) == "steady.morning")
        #expect(context(.earlyRiser, 21, 30).part == .night)
        #expect(cueID(.earlyRiser, 23, 30) == "lateNight.lightsOut")
        // Two hours from the usual wake: rest, not a lecture.
        #expect(cueID(.earlyRiser, 2) == "steady.night")
    }

    @Test("A night owl: eight in the morning is still the night, and it never says lights out then")
    func nightOwl() {
        #expect(context(.nightOwl, 8, 0).part == .night)
        #expect(cueID(.nightOwl, 8) == "steady.night")
        #expect(NextMoveArbiter().cue(context(.nightOwl, 8, 0)).orbWord == "Rest well")
        #expect(context(.nightOwl, 12, 30).part == .morning)
        #expect(context(.nightOwl, 23, 30).part == .evening)
        #expect(cueID(.nightOwl, 2) == "steady.night")
    }

    @Test("A short night: a plan for the day in the morning, an earlier bed only in the evening")
    func shortNight() {
        let morning = NextMoveArbiter().cue(context(.shortNight, 8, 0))
        #expect(morning.id == "sleepDebt.easyDay")
        #expect(morning.orbWord == "Go easy")
        #expect(morning.why == "Slept 5 h, 2 h 30 under your usual")
        #expect(morning.message.contains("daylight early"))
        #expect(morning.message.contains("coffee before 15:00"))
        #expect(cueID(.shortNight, 12, 30) == "sleepDebt.easyDay")
        #expect(cueID(.shortNight, 16) != "sleepDebt.easyDay")
        let evening = NextMoveArbiter().cue(context(.shortNight, 21, 30))
        #expect(evening.id == "sleepDebt.extendTonight")
        #expect(evening.title == "In bed by 22:00")
        #expect(evening.message.contains("tonight"))
    }

    @Test("A resting heart rate above the usual: an easy day, then an easy evening, then rest")
    func highRestingHeart() {
        let morning = NextMoveArbiter().cue(context(.highRestingHeart, 8, 0))
        #expect(morning.id == "restingHeartRate.easeOff")
        #expect(morning.why == "Resting heart rate 8 above your usual")
        #expect(cueID(.highRestingHeart, 16) == "restingHeartRate.easeOff")
        #expect(cueID(.highRestingHeart, 21, 30) == "restingHeartRate.easyEvening")
        #expect(cueID(.highRestingHeart, 23, 30) == "steady.night")
    }

    @Test("A workout already done: no nudge to train or walk, and the steady day says what went well")
    func workoutDone() {
        for (hour, minute) in [(8, 0), (12, 30), (16, 0)] {
            let ranked = NextMoveArbiter().rank(context(.workoutDone, hour, minute))
            #expect(!ranked.contains { $0.id == "readyToTrain.push" || $0.id == "movementGap.walk" })
        }
        let steady = NextMoveArbiter().cue(context(.workoutDone, 12, 30))
        #expect(steady.id == "steady.midday")
        #expect(steady.orbWord == "Steady day")
        #expect(steady.why == "Slept 7 h 30, about your usual")
        #expect(steady.evidence.contains { $0.label == "Exercise by now" })
    }

    @Test("Before any workout, a recovery well above the usual is a good day to train")
    func readyToTrain() {
        var ctx = context(.workoutDone, 8, 0)
        ctx.workoutsToday = 0
        ctx.exerciseMinutes = 0
        #expect(NextMoveArbiter().cue(ctx).id == "readyToTrain.push")
        // Never beside a raised resting heart.
        ctx.restingHeartRate = 63
        #expect(NextMoveArbiter().rank(ctx).contains { $0.id == "readyToTrain.push" } == false)
    }

    @Test("Caffeine: a last call before the cut off, nothing after it, and a wind down after a late cup")
    func caffeineLate() {
        let noon = NextMoveArbiter().cue(context(.caffeineLate, 12, 30))
        #expect(noon.id == "caffeine.lastCall")
        #expect(noon.title == "Last coffee by 15:00")
        #expect(!NextMoveArbiter().rank(context(.caffeineLate, 16, 0)).contains { $0.id == "caffeine.lastCall" })
        let evening = NextMoveArbiter().cue(context(.caffeineLate, 21, 30))
        #expect(evening.id == "caffeine.late")
        #expect(evening.why == "Coffee at 17:30, after your 15:00 cut off")
        #expect(cueID(.caffeineLate, 23, 30) == "steady.night")
    }

    @Test("Advice that led for three hours rests for the day; an acted on move leaves at once")
    func cooldownAndActed() {
        let morning = context(.highRestingHeart, 8, 0)
        let history = NextMoveHistory.empty.showing("restingHeartRate.easeOff", at: morning.now, calendar: calendar)
        #expect(NextMoveArbiter().cue(morning, history: history).id == "restingHeartRate.easeOff")
        #expect(NextMoveArbiter().cue(context(.highRestingHeart, 12, 30), history: history).id == "steady.midday")
        // The evening's own advice is new, so it speaks.
        #expect(NextMoveArbiter().cue(context(.highRestingHeart, 21, 30), history: history).id == "restingHeartRate.easyEvening")

        let acted = NextMoveHistory.empty.acting(on: "restingHeartRate.easeOff", at: morning.now, calendar: calendar)
        #expect(NextMoveArbiter().cue(morning, history: acted).id == "steady.morning")
        // Tomorrow starts clean.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: morning.now)!
        #expect(acted.on(tomorrow, calendar: calendar).acted.isEmpty)
    }

    @Test("An urgent move never rests")
    func urgentNeverRests() {
        var ctx = context(.highRestingHeart, 12, 30)
        ctx.restingHeartRate = 70
        let history = NextMoveHistory.empty.showing("restingHeartRate.easeOff", at: at(8), calendar: calendar)
        #expect(NextMoveArbiter().cue(ctx, history: history).id == "restingHeartRate.easeOff")
    }

    @Test("With nothing measured the default claims nothing")
    func steadyClaimsNothing() {
        let ctx = NextMoveContext(now: at(12, 30), calendar: calendar)
        let cue = NextMoveArbiter().cue(ctx)
        #expect(cue.id == "steady.midday")
        #expect(cue.evidence.isEmpty)
        #expect(cue.why.isEmpty)
        #expect(cue.message == "Nothing stands out from your usual right now.")
    }

    @Test("A weak candidate does not lead: the calm default is truer")
    func weakCandidateFallsBack() {
        var ctx = context(.earlyRiser, 12, 30)
        ctx.waterMl = 1_550
        ctx.waterTargetMl = 2_000
        #expect(NextMoveArbiter().cue(ctx).id.hasPrefix("steady."))
    }

    @Test("The debug clock reads HH:mm on today's date, and nothing else")
    func clock() {
        let day = at(15, 12)
        #expect(NextMoveClock.time("08:00", on: day, calendar: calendar) == at(8))
        #expect(NextMoveClock.time("22:30", on: day, calendar: calendar) == at(22, 30))
        #expect(NextMoveClock.time("25:00", on: day, calendar: calendar) == nil)
        #expect(NextMoveClock.time("8", on: day, calendar: calendar) == nil)
        let defaults = UserDefaults(suiteName: "NextMoveScenarioTests.clock")!
        defaults.set("13:00", forKey: NextMoveClock.launchKey)
        #expect(NextMoveClock.now(defaults: defaults, calendar: calendar, real: day) == at(13))
        defaults.removeObject(forKey: NextMoveClock.launchKey)
        #expect(NextMoveClock.now(defaults: defaults, calendar: calendar, real: day) == day)
    }
}
