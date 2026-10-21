//
//  PulseTodayTests.swift
//  PrismTests
//

import Foundation
import Testing
import HealthExportCore
import SomaUI
@testable import Prism

/// The Today page is arithmetic over what Health returned, so it is tested as
/// arithmetic: readings in, the page's words and numbers out. A fixed calendar
/// and a 24 hour locale keep the times the same on every machine.
@Suite("Pulse today")
@MainActor
struct PulseTodayTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")

    /// 26 September 2026 at `hour`:`minute`, or a day before or after it.
    func at(_ hour: Int, _ minute: Int = 0, day offset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func sleep(_ code: Int, _ start: Date, _ end: Date) -> HealthReading {
        HealthReading(metric: "HKCategoryTypeIdentifierSleepAnalysis", value: Double(code), unit: .none, start: start, end: end)
    }

    func reading(_ metric: String, _ value: Double, at date: Date, lasting seconds: TimeInterval = 60) -> HealthReading {
        HealthReading(metric: metric, value: value, unit: .none, start: date, end: date.addingTimeInterval(seconds))
    }

    func page(_ inputs: PulseInputs) -> PulseToday {
        PulseToday.make(from: inputs, calendar: calendar, locale: locale)
    }

    /// A night of `hours` asleep from 23:00 the evening before `day`, in
    /// stages the way a watch writes them.
    func night(hours: Double, day offset: Int, bedtime: (Int, Int) = (23, 0), deepMinutes: Double = 60) -> [HealthReading] {
        let start = at(bedtime.0, bedtime.1, day: offset - (bedtime.0 >= 18 ? 1 : 0))
        let end = start.addingTimeInterval(hours * 3600)
        let deepEnd = start.addingTimeInterval(deepMinutes * 60)
        return [
            sleep(0, start.addingTimeInterval(-10 * 60), end),
            sleep(4, start, deepEnd),
            sleep(3, deepEnd, end),
        ]
    }

    // MARK: - Nights

    @Test("Two sources recording the same night count its hours once")
    func overlappingSourcesCountOnce() {
        let watch = [sleep(3, at(23, day: -1), at(3)), sleep(4, at(3), at(4)), sleep(3, at(4), at(7))]
        let app = [sleep(1, at(23, 30, day: -1), at(6, 30))]
        let nights = PulseNights.nights(from: watch + app, calendar: calendar)

        #expect(nights.count == 1)
        #expect(nights.first?.asleep == TimeInterval(8 * 3600))
        #expect(nights.first?.deep == TimeInterval(3600))
        #expect(nights.first?.woke == at(7))
    }

    @Test("A night recorded as plain asleep has no deep sleep to count, which is not zero")
    func unstagedNightHasNoDeep() {
        let nights = PulseNights.nights(from: [sleep(1, at(23, day: -1), at(7))], calendar: calendar)
        #expect(nights.first?.deep == nil)
        #expect(nights.first?.asleep == TimeInterval(8 * 3600))
    }

    @Test("An afternoon nap does not become the night")
    func napLosesToTheNight() {
        let samples = night(hours: 7, day: 0) + [sleep(1, at(14), at(15))]
        let nights = PulseNights.nights(from: samples, calendar: calendar)
        #expect(nights.count == 1)
        #expect(nights.first?.asleep == TimeInterval(7 * 3600))
    }

    @Test("Sleep that ends after six in the evening belongs to the next day")
    func eveningSleepIsTomorrows() {
        let nights = PulseNights.nights(from: [sleep(1, at(18, 30), at(19, 30))], calendar: calendar)
        #expect(nights.first?.day == calendar.startOfDay(for: at(12, day: 1)))
    }

    // MARK: - An empty store

    @Test("An empty store reads as dashes and says so, rather than as zeros")
    func emptyStoreIsHonest() {
        let today = page(PulseInputs(now: at(15)))

        #expect(today.sleep.value == nil)
        #expect(today.mind.value == nil)
        #expect(today.activity.value == nil)
        #expect(today.energyLevel == nil)
        #expect(today.sleepCard.value == nil)
        #expect(today.heartCard.value == nil)
        #expect(today.bodyCard.value == nil)
        #expect(today.nights == Array(repeating: nil, count: 7))
        #expect(today.moves.isEmpty)
        #expect(today.carrying == nil)
        #expect(today.hasData == false)
        #expect(today.headline == "Nothing to read yet.")
        #expect(today.events.map(\.title) == ["Now"])
        #expect(today.events.last?.detail == "Nothing recorded yet today.")
    }

    // MARK: - Sleep

    @Test("A night well under the usual carries the morning, and says by how much")
    func shortNightCarriesSleep() {
        var samples: [HealthReading] = []
        for offset in -14 ... -1 { samples += night(hours: 7.5, day: offset) }
        samples += night(hours: 5.5, day: 0)
        let today = page(PulseInputs(now: at(10), sleep: samples))

        // The row under the orb holds scores now, and none were passed; the
        // hours read on the sleep card.
        #expect(today.sleep.value == nil)
        #expect(today.sleepCard.value == "5:30")
        #expect(today.carrying == .sleep)
        // At ten in the morning a short night is a plan for the day, never a
        // bedtime.
        #expect(today.headline == "Easy day after a short night")
        #expect(today.reason.contains("You slept 5 h 30, 2 h under your usual."))
        #expect(today.moves.first?.aspect == .sleep)
        #expect(today.moves.first?.title == "Easy day after a short night")
        #expect(today.cue?.orb == "Go easy")
        #expect(today.cue?.why == "Slept 5 h 30, 2 h under your usual")
        #expect(today.events.first?.title == "Woke up")
        #expect(today.events.first?.detail == "Slept 5:30, 60 min of deep sleep.")
    }

    @Test("At eight in the morning nothing says go to bed, and the orb does not wind down")
    func noBedtimeInTheMorning() {
        for lastNight in [5.5, 7.5] {
            var samples: [HealthReading] = []
            for offset in -14 ... -1 { samples += night(hours: 7.5, day: offset) }
            samples += night(hours: lastNight, day: 0)
            let today = page(PulseInputs(now: at(8), sleep: samples))
            #expect(!today.moves.contains { $0.title.hasPrefix("In bed") }, "\(today.moves.map(\.title))")
            let orb = PulseNowAction.make(today: today, at: at(8), calendar: calendar)
            #expect(String(localized: orb.label) != "Wind down")
            #expect(String(localized: orb.label) == (lastNight < 7 ? "Go easy" : "Steady day"))
        }
    }

    @Test("Bedtime comes from the month's longest nights")
    func bedtimeFollowsTheLongestNights() {
        var samples: [HealthReading] = []
        for offset in -20 ... -1 {
            // Long nights start at 22:30, short ones after midnight.
            samples += offset.isMultiple(of: 2)
                ? night(hours: 8, day: offset, bedtime: (22, 30))
                : night(hours: 6, day: offset, bedtime: (0, 30))
        }
        samples += night(hours: 7.4, day: 0, bedtime: (23, 0))
        let today = page(PulseInputs(now: at(21), sleep: samples))
        let move = today.moves.first { $0.aspect == .sleep }

        // The helper gets into bed ten minutes before sleep: 22:20, rounded
        // down to the quarter hour.
        #expect(move?.title == "In bed by 22:15")
        #expect(move?.reason == "Your longest nights this month started before 22:30.")
    }

    @Test("Last night against the week: the longest one says so")
    func longestNightOfTheWeek() {
        var samples: [HealthReading] = []
        for offset in -6 ... -1 { samples += night(hours: 7, day: offset) }
        samples += night(hours: 8, day: 0, deepMinutes: 68)
        let today = page(PulseInputs(now: at(9), sleep: samples))

        #expect(today.sleepCard.summary == "Your longest night this week, 68 min deep.")
        #expect(today.nights.last == 8)
        #expect(today.nights.count == 7)
    }

    // MARK: - Heart

    @Test("A heart raised at rest is a stress peak; one on the move, or alone, is not")
    func stressPeaks() {
        let heart = "HKQuantityTypeIdentifierHeartRate"
        let resting = (-20 ... 0).map { reading("HKQuantityTypeIdentifierRestingHeartRate", 55, at: at(8, day: $0)) }
        let raisedStill = [reading(heart, 95, at: at(14, 30)), reading(heart, 104, at: at(14, 38))]
        let raisedWalking = [reading(heart, 110, at: at(11, 0)), reading(heart, 112, at: at(11, 6))]
        let lonely = [reading(heart, 120, at: at(12, 30))]
        let steps = [
            reading("HKQuantityTypeIdentifierStepCount", 800, at: at(10, 58), lasting: 10 * 60),
            reading("HKQuantityTypeIdentifierStepCount", 40, at: at(9, 0), lasting: 5 * 60),
        ]
        let today = page(PulseInputs(
            now: at(15),
            heartRate: raisedStill + raisedWalking + lonely,
            restingHeartRate: resting,
            steps: steps,
            stepsToday: 840
        ))

        let peaks = today.events.filter { $0.title == "Stress peak" }
        #expect(peaks.count == 1)
        #expect(peaks.first?.time == "14:30")
        #expect(peaks.first?.detail == "Heart at 104 while still, 49 above resting.")
        #expect(today.carrying == .mind)
        #expect(today.headline == "Breathe for 10 minutes")
        #expect(today.cue?.why == "Heart 49 above resting at 14:30, while still")
    }

    @Test("Without any steps today, stillness cannot be told, so nothing is called a peak")
    func noStepsNoPeaks() {
        let heart = "HKQuantityTypeIdentifierHeartRate"
        let resting = (-20 ... 0).map { reading("HKQuantityTypeIdentifierRestingHeartRate", 55, at: at(8, day: $0)) }
        let today = page(PulseInputs(
            now: at(15),
            heartRate: [reading(heart, 95, at: at(14, 30)), reading(heart, 104, at: at(14, 38))],
            restingHeartRate: resting
        ))
        #expect(!today.events.contains { $0.title == "Stress peak" })
    }

    @Test("Resting heart rate is read against the month before it")
    func restingAgainstUsual() {
        var resting = (-20 ... -1).map { reading("HKQuantityTypeIdentifierRestingHeartRate", 58, at: at(8, day: $0)) }
        resting.append(reading("HKQuantityTypeIdentifierRestingHeartRate", 54, at: at(8)))
        let today = page(PulseInputs(now: at(15), restingHeartRate: resting))

        #expect(today.heartCard.value == "54")
        #expect(today.heartCard.summary == "4 below your usual.")
        #expect(today.restingBand == 58...58)
        #expect(today.restingDays.last == 54)
        #expect(today.restingDays.count == 14)
    }

    @Test("A resting rate five above the usual asks for an easy evening, as the card says")
    func raisedRestingAsksForEase() {
        var resting = (-20 ... -1).map { reading("HKQuantityTypeIdentifierRestingHeartRate", 55, at: at(8, day: $0)) }
        resting.append(reading("HKQuantityTypeIdentifierRestingHeartRate", 59.6, at: at(8)))
        let today = page(PulseInputs(now: at(20), restingHeartRate: resting))

        #expect(today.heartCard.summary == "5 above your usual.")
        #expect(today.moves.contains { $0.aspect == .heart })
    }

    @Test("HRV under the usual asks for a slower day")
    func variabilityTrend() {
        let metric = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
        var readings = (-20 ... -1).map { reading(metric, 48, at: at(3, day: $0)) }
        readings.append(reading(metric, 38, at: at(3)))
        let today = page(PulseInputs(now: at(9), heartRateVariability: readings))

        // The Mind value is a score now, so HRV shows in the move instead.
        #expect(today.mind.value == nil)
        #expect(today.moves.first?.aspect == .mind)
        #expect(today.moves.first?.reason == "HRV is 38 ms, under your usual 48. Slow breathing and an easy pace help it come back.")
    }

    // MARK: - Workouts

    @Test("A walk counts its steps, a gym session its minutes in zone 3 and above")
    func workoutsAreCountedTheirOwnWay() {
        let walkStart = at(12, 5)
        let gymStart = at(17, 30)
        let walk = HealthReading(metric: "HKWorkoutTypeIdentifier", value: 52, unit: .none,
                                 start: walkStart, end: walkStart.addingTimeInterval(35 * 60))
        let gym = HealthReading(metric: "HKWorkoutTypeIdentifier", value: 50, unit: .none,
                                start: gymStart, end: gymStart.addingTimeInterval(55 * 60))
        // Age 40: a maximum of 180, zone 3 from 126. Thirty one minutes above it.
        let heart = (0 ..< 55 * 2).map { index in
            reading("HKQuantityTypeIdentifierHeartRate", index < 62 ? 140 : 110, at: gymStart.addingTimeInterval(Double(index) * 30))
        }
        let today = page(PulseInputs(
            now: at(19, 46),
            heartRate: heart,
            workouts: [walk, gym],
            workoutSteps: [walkStart: 3900],
            age: 40
        ))

        let details = Dictionary(uniqueKeysWithValues: today.events.map { ($0.title, $0.detail ?? "") })
        #expect(details["Walk"] == "35 min, 3,900 steps.")
        #expect(details["Gym"] == "55 min, 31 of them in zone 3 and above.")
        #expect(today.events.map(\.title) == ["Walk", "Gym", "Now"])
    }

    @Test("The body card reads fitness age off the watch's VO2 max, or says it needs one")
    func bodyCard() {
        let missing = page(PulseInputs(now: at(9), age: 46)).bodyCard
        #expect(missing.value == nil)
        #expect(missing.summary == "Fitness age needs a VO2 max from your watch.")
        let read = page(PulseInputs(now: at(9), age: 46, vo2Max: 48, sex: .male)).bodyCard
        #expect(read.value == "25")
        #expect(read.summary == "21 under your age, read off your watch’s VO2 max.")
        #expect(page(PulseInputs(now: at(9), vo2Max: 48, sex: .male)).bodyCard.summary == "Read off your watch’s VO2 max.")
        #expect(!missing.summary.contains("visit"))
    }

    // MARK: - Done moves

    @Test("A tick belongs to its day")
    func ticksResetOvernight() {
        var done = PulseDoneMoves(stored: "")
        done.toggle(.mind, on: at(20), calendar: calendar)

        #expect(done.aspects(on: at(22), calendar: calendar) == [.mind])
        #expect(done.aspects(on: at(8, day: 1), calendar: calendar).isEmpty)

        let reread = PulseDoneMoves(stored: done.stored)
        #expect(reread.aspects(on: at(21), calendar: calendar) == [.mind])
    }
}
