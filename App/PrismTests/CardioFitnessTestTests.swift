//
//  CardioFitnessTestTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The cardio fitness test: the three equations against worked examples,
/// the choice of test from the equipment, the unit conversions, the runs
/// that must be refused, the safety stop, the cues and where a result sits.
@Suite("Cardio fitness test")
struct CardioFitnessTestTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static let man = CardioTestPerson(age: 40, sex: .male, weightKg: 80, restingHeartRate: 60)

    /// A walk at a steady speed, a distance reading every two seconds.
    private static func walk(_ test: CardioTestProtocol, metresPerSecond: Double, seconds: TimeInterval,
                             heartRate: Double? = 140) -> CardioRun {
        var run = CardioRun(test: test, startedAt: start, elapsed: seconds)
        for time in stride(from: 2.0, through: seconds, by: 2) {
            run.distance.append(CardioSample(time: time, value: time * metresPerSecond))
            if let heartRate { run.heartRate.append(CardioSample(time: time, value: heartRate)) }
        }
        return run
    }

    // MARK: Equations

    @Test("Rockport: the published worked examples")
    func rockportExamples() {
        // 30 year old man, 150 lb, a 12 minute mile, 120 bpm: 58.04.
        let first = CardioEquations.rockport(weightPounds: 150, age: 30, male: true, minutes: 12, heartRate: 120)
        #expect(abs(first - 58.04) < 0.01)
        // 28 year old man, 165 lb, 12.5 minutes, 160 bpm: 49.77.
        let second = CardioEquations.rockport(weightPounds: 165, age: 28, male: true, minutes: 12.5, heartRate: 160)
        #expect(abs(second - 49.77) < 0.01)
        // A woman loses the 6.315 sex term, nothing else.
        let woman = CardioEquations.rockport(weightPounds: 150, age: 30, male: false, minutes: 12, heartRate: 120)
        #expect(abs((first - woman) - 6.315) < 0.000_1)
    }

    @Test("Six minute walk: Burr 2011's terms")
    func burrExample() {
        // 600 m, 70 kg, a man, resting 60 bpm, 30 years: 70.161 + 13.8 minus
        // 19.32 minus 11.58 minus 5.73 = 47.331.
        let man = CardioEquations.sixMinuteWalk(metres: 600, weightKg: 70, female: false, restingHeartRate: 60, age: 30)
        #expect(abs(man - 47.331) < 0.001)
        let woman = CardioEquations.sixMinuteWalk(metres: 600, weightKg: 70, female: true, restingHeartRate: 60, age: 30)
        #expect(abs((man - woman) - 6.79) < 0.000_1)
        // 100 m more walked is 2.3 more.
        let further = CardioEquations.sixMinuteWalk(metres: 700, weightKg: 70, female: false, restingHeartRate: 60, age: 30)
        #expect(abs((further - man) - 2.3) < 0.000_1)
    }

    @Test("Queens College step test: McArdle 1972")
    func queensCollege() {
        #expect(abs(CardioEquations.queensCollege(recoveryHeartRate: 150, male: true) - 48.33) < 0.001)
        #expect(abs(CardioEquations.queensCollege(recoveryHeartRate: 160, male: false) - 36.258) < 0.001)
    }

    // MARK: Units

    @Test("Miles, kilometres, pounds and kilograms convert both ways")
    func units() {
        #expect(CardioUnits.metres(fromMiles: 1) == 1_609.344)
        #expect(abs(CardioUnits.miles(fromMetres: 1_609.344) - 1) < 1e-12)
        #expect(CardioUnits.kilometres(fromMetres: 2_500) == 2.5)
        #expect(abs(CardioUnits.pounds(fromKilograms: 68.038_855_5) - 150) < 1e-6)
        #expect(abs(CardioUnits.kilograms(fromPounds: 150) - 68.038_855_5) < 1e-6)
        #expect(CardioUnits.clock(360) == "6:00")
        #expect(CardioUnits.clock(872.9) == "14:32")
        #expect(CardioUnits.distance(1_609.344, measures: .imperial) == "1.00 mi")
        #expect(CardioUnits.distance(630, measures: .metric) == "0.63 km")
        #expect(CardioUnits.pace(metres: 1_000, seconds: 585, measures: .metric) == "9:45 /km")
        #expect(CardioUnits.pace(metres: 10, seconds: 5, measures: .metric) == nil)
    }

    @Test("A Rockport estimate reads the weight in pounds, whatever the person's units")
    func rockportUsesPounds() throws {
        let person = CardioTestPerson(age: 30, sex: .male, weightKg: CardioUnits.kilograms(fromPounds: 150))
        // 1609.344 m in 12 minutes, 120 bpm throughout.
        let run = Self.walk(.rockportWalk, metresPerSecond: 1_609.344 / 720, seconds: 720, heartRate: 120)
        let estimate = try CardioFitnessTest.evaluate(run, person: person).get()
        #expect(abs(estimate.vo2Max - 58.04) < 0.01)
        #expect(estimate.heartRateSource == .sensor)
        // Age 30 sits in Kline's cohort: the range is the plain error.
        #expect(abs(estimate.high - estimate.low - 10) < 0.001)
    }

    // MARK: Choice

    @Test("The test follows the equipment")
    func choice() {
        let watch = CardioTestEquipment(heartRateStream: true, stepCounter: true, canRunLive: true)
        #expect(CardioTestChoice.recommended(watch) == .rockportWalk)
        #expect(CardioTestChoice.available(watch) == [.rockportWalk, .sixMinuteWalk, .stepTest])

        let phone = CardioTestEquipment(heartRateStream: false, stepCounter: true, canRunLive: true)
        #expect(CardioTestChoice.recommended(phone) == .sixMinuteWalk)
        #expect(!CardioTestChoice.available(phone).contains(.rockportWalk))

        let noCounter = CardioTestEquipment(heartRateStream: false, stepCounter: false, canRunLive: true)
        #expect(CardioTestChoice.available(noCounter) == [.stepTest])

        let mac = CardioTestEquipment(heartRateStream: true, stepCounter: true, canRunLive: false)
        #expect(CardioTestChoice.available(mac).isEmpty)
        #expect(CardioTestChoice.recommended(mac) == nil)
    }

    @Test("The profile the equations need")
    func missingProfile() {
        let empty = CardioTestPerson()
        #expect(empty.missing(for: .rockportWalk) == [.age, .sex, .weight])
        #expect(empty.missing(for: .stepTest) == [.age, .sex])
        let run = Self.walk(.sixMinuteWalk, metresPerSecond: 1.7, seconds: 360)
        #expect(CardioFitnessTest.evaluate(run, person: CardioTestPerson(age: 40, sex: .female))
            == .failure(.missingProfile([.weight])))
    }

    // MARK: Refusals

    @Test("A six minute walk stopped at five minutes is too short")
    func tooShort() {
        let run = Self.walk(.sixMinuteWalk, metresPerSecond: 1.7, seconds: 300)
        #expect(CardioFitnessTest.evaluate(run, person: Self.man) == .failure(.tooShort(needed: 360, got: 300)))
    }

    @Test("A mile counted short is refused")
    func mileShort() {
        let run = Self.walk(.rockportWalk, metresPerSecond: 1.5, seconds: 900)
        guard case .failure(.distanceShort(_, let got)) = CardioFitnessTest.evaluate(run, person: Self.man) else {
            Issue.record("expected a short mile")
            return
        }
        #expect(abs(got - 1_350) < 0.001)
    }

    @Test("A minute with no distance is a lost count")
    func pedometerGap() {
        var run = Self.walk(.sixMinuteWalk, metresPerSecond: 1.7, seconds: 360)
        run.distance.removeAll { $0.time > 100 && $0.time < 170 }
        guard case .failure(.distanceGap(let seconds)) = CardioFitnessTest.evaluate(run, person: Self.man) else {
            Issue.record("expected a gap")
            return
        }
        #expect(seconds >= 70)
        // A short pause is not a gap.
        var paused = Self.walk(.sixMinuteWalk, metresPerSecond: 1.7, seconds: 360)
        paused.distance.removeAll { $0.time > 100 && $0.time < 130 }
        #expect((try? CardioFitnessTest.evaluate(paused, person: Self.man).get()) != nil)
    }

    @Test("No steps counted is no distance")
    func noDistance() {
        let run = CardioRun(test: .sixMinuteWalk, startedAt: Self.start, elapsed: 360)
        #expect(CardioFitnessTest.evaluate(run, person: Self.man) == .failure(.noDistance))
    }

    @Test("A run is refused: these are walking equations")
    func running() {
        let six = Self.walk(.sixMinuteWalk, metresPerSecond: 3, seconds: 360)
        #expect(CardioFitnessTest.evaluate(six, person: Self.man) == .failure(.looksLikeRunning))
        let mile = Self.walk(.rockportWalk, metresPerSecond: 1_609.344 / 400, seconds: 400)
        #expect(CardioFitnessTest.evaluate(mile, person: Self.man) == .failure(.looksLikeRunning))
    }

    @Test("Rockport without a heart rate is refused, and a counted pulse rescues it")
    func rockportHeartRate() throws {
        var run = Self.walk(.rockportWalk, metresPerSecond: 1_609.344 / 840, seconds: 840, heartRate: nil)
        let problem = CardioFitnessTest.evaluate(run, person: Self.man)
        #expect(problem == .failure(.noHeartRate))
        if case .failure(let reason) = problem { #expect(reason.pulseCanRescue) }

        run.countedPulse = CardioPulse.beatsPerMinute(beatsIn15Seconds: 35)
        let estimate = try CardioFitnessTest.evaluate(run, person: Self.man).get()
        #expect(estimate.heartRate == 140)
        #expect(estimate.heartRateSource == .counted)
        #expect(estimate.caveats.contains("Pulse counted by hand"))
    }

    @Test("A heart rate that went quiet before the finish is a gap")
    func heartRateGap() {
        var run = Self.walk(.rockportWalk, metresPerSecond: 1_609.344 / 840, seconds: 840)
        run.heartRate.removeAll { $0.time > 780 }
        #expect(CardioFitnessTest.evaluate(run, person: Self.man) == .failure(.heartRateGap(seconds: 60)))
    }

    @Test("An impossible heart rate is refused")
    func implausibleHeartRate() {
        let run = Self.walk(.rockportWalk, metresPerSecond: 1_609.344 / 840, seconds: 840, heartRate: 260)
        #expect(CardioFitnessTest.evaluate(run, person: Self.man) == .failure(.implausibleHeartRate(260)))
    }

    @Test("The step test reads the recovery window, else the counted pulse")
    func stepRecovery() throws {
        var run = CardioRun(test: .stepTest, startedAt: Self.start, elapsed: 180)
        run.heartRate = [CardioSample(time: 170, value: 160), CardioSample(time: 186, value: 152), CardioSample(time: 196, value: 148)]
        let sensor = try CardioFitnessTest.evaluate(run, person: Self.man).get()
        #expect(sensor.heartRate == 150)
        #expect(abs(sensor.vo2Max - 48.33) < 0.001)
        // 16 percent of the value either side, outside the college cohort
        // half again.
        #expect(abs((sensor.high - sensor.vo2Max) - 48.33 * 0.16 * 1.5) < 0.001)

        var counted = CardioRun(test: .stepTest, startedAt: Self.start, elapsed: 180)
        counted.countedPulse = 160
        let woman = CardioTestPerson(age: 25, sex: .female)
        let estimate = try CardioFitnessTest.evaluate(counted, person: woman).get()
        #expect(abs(estimate.vo2Max - 36.258) < 0.001)
        #expect(estimate.heartRateSource == .counted)

        let bare = CardioRun(test: .stepTest, startedAt: Self.start, elapsed: 180)
        #expect(CardioFitnessTest.evaluate(bare, person: Self.man) == .failure(.noHeartRate))
    }

    @Test("Without a resting heart rate the six minute walk assumes one and widens")
    func assumedResting() throws {
        let run = Self.walk(.sixMinuteWalk, metresPerSecond: 600.0 / 360, seconds: 360)
        var person = Self.man
        let known = try CardioFitnessTest.evaluate(run, person: person).get()
        person.restingHeartRate = nil
        let assumed = try CardioFitnessTest.evaluate(run, person: person).get()
        #expect(assumed.caveats.contains("Typical resting heart rate assumed"))
        #expect(assumed.high - assumed.low > known.high - known.low)
        // 68 for a man instead of 60: 8 times 0.193 lower.
        #expect(abs((known.vo2Max - assumed.vo2Max) - 8 * 0.193) < 0.001)
    }

    // MARK: Safety

    @Test("Stopping for a symptom gives no estimate and the safety screen")
    func symptomStop() {
        var run = Self.walk(.sixMinuteWalk, metresPerSecond: 1.7, seconds: 360)
        run.stop = .chestPain
        #expect(CardioFitnessTest.evaluate(run, person: Self.man) == .failure(.stoppedForSafety(.chestPain)))
        run.stop = .personChose
        #expect(CardioFitnessTest.evaluate(run, person: Self.man) == .failure(.stoppedEarly))
        #expect(CardioStop.heartRateCeiling.isSymptom)
    }

    @Test("A heart rate held past 95 percent of the predicted maximum stops a walk")
    func heartRateCeiling() {
        // Tanaka: 208 minus 0.7 times 40 = 180; 95 percent is 171.
        #expect(CardioSafety.predictedMaxHeartRate(age: 40) == 180)
        let high = [CardioSample(time: 100, value: 172), CardioSample(time: 104, value: 173), CardioSample(time: 108, value: 175)]
        #expect(CardioSafety.assess(high, now: 109, age: 40, test: .sixMinuteWalk) == .stop)
        // One reading is not held.
        #expect(CardioSafety.assess([CardioSample(time: 108, value: 175)], now: 109, age: 40, test: .sixMinuteWalk) == .slowDown)
        // Past 90 percent (162) asks to slow down.
        #expect(CardioSafety.assess([CardioSample(time: 100, value: 165), CardioSample(time: 104, value: 166)], now: 105, age: 40, test: .rockportWalk) == .slowDown)
        #expect(CardioSafety.assess([CardioSample(time: 100, value: 130)], now: 101, age: 40, test: .rockportWalk) == .fine)
        // The step test runs harder: stopped only at the maximum itself.
        #expect(CardioSafety.assess(high, now: 109, age: 40, test: .stepTest) == .fine)
        // A stale reading says nothing.
        #expect(CardioSafety.assess(high, now: 200, age: 40, test: .sixMinuteWalk) == .fine)
    }

    // MARK: Cues and progress

    @Test("Cues come once, at their time or their distance")
    func cues() {
        let six = CardioCuePlan.cues(for: .sixMinuteWalk)
        #expect(CardioCuePlan.due(six, seconds: 0, metres: 0, given: []).map(\.kind) == [.start])
        #expect(CardioCuePlan.due(six, seconds: 181, metres: 300, given: ["start"]).map(\.kind) == [.halfway])
        #expect(CardioCuePlan.due(six, seconds: 360, metres: 600, given: ["start", "half", "minute"]).map(\.kind) == [.end])

        let mile = CardioCuePlan.cues(for: .rockportWalk)
        #expect(CardioCuePlan.due(mile, seconds: 400, metres: 805, given: ["start"]).map(\.kind) == [.halfway])
        #expect(CardioCuePlan.beatsPerMinute(.male) == 96)
        #expect(CardioCuePlan.beatsPerMinute(.female) == 88)
    }

    @Test("Progress and the end of each test")
    func progress() {
        #expect(CardioProgress.fraction(.sixMinuteWalk, seconds: 180, metres: 0) == 0.5)
        #expect(CardioProgress.fraction(.rockportWalk, seconds: 10, metres: 1_609.344 / 4) == 0.25)
        #expect(CardioProgress.isComplete(.rockportWalk, seconds: 900, metres: 1_610))
        #expect(!CardioProgress.isComplete(.stepTest, seconds: 179, metres: 0))
        #expect(CardioProgress.projectedMetres(.sixMinuteWalk, seconds: 120, metres: 200) == 600)
        #expect(CardioPulse.beatsPerMinute(beatsIn15Seconds: 30) == 120)
    }

    // MARK: Where it sits

    @Test("The band reads the same norms as the biological age")
    func band() {
        // A man in his 30s: mean 44, spread 6. At the mean, the middle.
        let middle = CardioFitnessBand.make(vo2Max: 44, age: 35, sex: .male)
        #expect(middle.percentile == 50)
        #expect(middle.word == "Around the middle")
        #expect(middle.group == "men in their 30s")
        // One spread above is the 84th percentile.
        #expect(CardioFitnessBand.make(vo2Max: 50, age: 35, sex: .male).percentile == 84)
        #expect(CardioFitnessBand.make(vo2Max: 25, age: 45, sex: .female).word == "Lower than most")
        #expect(CardioFitnessBand.make(vo2Max: 30, age: 77, sex: .female).group == "women 70 and over")
    }

    @Test("The comparison with Apple Watch")
    func watch() {
        #expect(CardioComparison.againstWatch(test: 44, watch: nil) == nil)
        #expect(CardioComparison.againstWatch(test: 44.5, watch: 43.8) == "Close to Apple Watch's 44")
        #expect(CardioComparison.againstWatch(test: 48, watch: 42) == "6 above Apple Watch's 42")
        #expect(CardioComparison.againstWatch(test: 38, watch: 42) == "4 below Apple Watch's 42")
    }

    @Test("A field test is kept apart from a lab test for the biological age")
    @MainActor
    func fieldTestIsNotLab() {
        let store = FunctionalResultStore(url: nil)
        store.save(FunctionalResult(kind: .fieldVO2, date: .now, values: ["vo2Max": 51]))
        #expect(store.labVO2 == nil)
        #expect(!FunctionalTestKind.reported.contains(.fieldVO2))
        #expect(FunctionalReportReader.guessKind(in: "VO2 max 51 mL/kg/min") == .labVO2)
    }
}
