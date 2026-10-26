//
//  CardioTestSession.swift
//  Prism
//
//  The live half of the cardio fitness test: the clock, the distance polled
//  from the phone's step counter through `PhoneMotion`, the heart rate from a
//  sensor, the cues, the safety stop and the pulse counted by hand. The
//  equations and every rule a run must pass live in ``CardioFitnessTest``.
//
//  The live test runs on iPhone only. A Mac or a headset shows the
//  introduction and says so.
//

import Foundation
import Observation
import SomaWidgetKit
import HealthExportCore
#if canImport(HealthKit)
import HealthKit
#endif
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class CardioTestSession {
    enum Phase: Equatable {
        /// Choosing and getting ready.
        case preparing
        /// Three, two, one.
        case countdown(Int)
        case running
        /// The step test's first five seconds after the last step, before
        /// the pulse is read.
        case settling
        /// Fifteen seconds of counting the pulse by hand.
        case counting
        /// Typing the beats counted.
        case enteringPulse
        case finished
    }

    // MARK: Set up before the start

    var test: CardioTestProtocol = .sixMinuteWalk
    var person = CardioTestPerson()
    private(set) var equipment = CardioTestEquipment(heartRateStream: false, stepCounter: false, canRunLive: CardioTestSession.canRunLive)
    /// Apple Watch's latest VO2 max, for the result to compare with.
    private(set) var watchVO2Max: Double?
    private(set) var isLoaded = false

    // MARK: Live

    private(set) var phase: Phase = .preparing
    /// Seconds since the start, or since the end of the test while settling
    /// and counting.
    private(set) var seconds: TimeInterval = 0
    private(set) var metres: Double = 0
    private(set) var heartRate: Double?
    private(set) var safety: CardioSafety.Call = .fine
    /// Rises with each cue, for the haptic.
    private(set) var cueCount = 0
    /// Rises with each beat of the step test's metronome.
    private(set) var beat = 0
    /// Seconds left in the pulse count.
    private(set) var countLeft: TimeInterval = CardioPulse.countSeconds
    private(set) var outcome: Result<CardioEstimate, CardioRunProblem>?

    private var run: CardioRun?
    private var given: Set<String> = []
    private var loop: Task<Void, Never>?
    private var beats: Task<Void, Never>?
    private var feed: CardioHeartFeed?
    private var startDate: Date?

    /// The run, played at speed with made up readings, so the flow can be
    /// seen and screenshotted on a simulator. Debug only.
    var isSimulated = false
    #if DEBUG
    /// The simulated clock's speed.
    var simulationSpeed = 30.0
    /// A fraction of the test at which the simulated run holds still, for a
    /// screenshot of the live screen (`-fitness.freeze 0.55`).
    var freezeAt: Double?
    #endif

    static var canRunLive: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var available: [CardioTestProtocol] { CardioTestChoice.available(equipment) }
    var missing: [CardioTestPerson.Field] { person.missing(for: test) }
    var progress: Double { CardioProgress.fraction(test, seconds: seconds, metres: metres) }

    // MARK: - Reading who and what

    /// Reads the person and the equipment from Health and the phone, and
    /// picks the test the equipment suits.
    func load(health: HealthDashboard, now: Date = .now) async {
        let metrics = [CardioReads.heartRate, CardioReads.restingHeartRate, LabMetric.bodyMass, LabMetric.vo2Max, LabMetric.dateOfBirth]
        var heartStream = false
        if !health.readsEmptyStore, let source = await health.prepare(metrics) {
            let calendar = Calendar.current
            async let age = LabHealth.age(in: source)
            async let mass = LabHealth.points(LabMetric.bodyMass, days: 365, now: now, calendar: calendar, in: source)
            async let vo2 = LabHealth.points(LabMetric.vo2Max, days: 365, now: now, calendar: calendar, in: source)
            async let resting = LabHealth.points(CardioReads.restingHeartRate, days: 30, now: now, calendar: calendar, in: source)
            async let heart = LabHealth.points(CardioReads.heartRate, days: 2, now: now, calendar: calendar, in: source)
            if person.age == nil { person.age = await age }
            if person.weightKg == nil { person.weightKg = await mass.last?.value }
            let rest = await resting.map(\.value)
            if person.restingHeartRate == nil, !rest.isEmpty { person.restingHeartRate = rest.reduce(0, +) / Double(rest.count) }
            watchVO2Max = await vo2.last?.value
            // A heart rate in the last two days: a watch or a sensor is worn.
            heartStream = !(await heart).isEmpty
        }
        if person.sex == nil {
            person.sex = CardiometabolicProfileStore.shared.profile.sex ?? LabHealth.biologicalSex()
        }
        let motion = health.motion
        equipment = CardioTestEquipment(
            heartRateStream: heartStream,
            stepCounter: motion.isAvailable && motion.authorization == .authorized,
            canRunLive: Self.canRunLive || isSimulated
        )
        if let first = CardioTestChoice.recommended(equipment), !available.contains(test) || !isLoaded {
            test = first
        }
        isLoaded = true
    }

    // MARK: - Running

    func start(motion: PhoneMotion) {
        guard phase == .preparing || phase == .finished else { return }
        reset()
        loop = Task { [weak self] in
            for count in stride(from: 3, through: 1, by: -1) {
                self?.phase = .countdown(count)
                self?.cueCount += 1
                try? await Task.sleep(for: CardioLive.countdownStep)
                if Task.isCancelled { return }
            }
            await self?.begin(motion: motion)
        }
    }

    private func reset() {
        loop?.cancel()
        beats?.cancel()
        seconds = 0
        metres = 0
        heartRate = nil
        safety = .fine
        given = []
        outcome = nil
        countLeft = CardioPulse.countSeconds
        run = nil
    }

    private func begin(motion: PhoneMotion) async {
        let start = Date()
        startDate = start
        run = CardioRun(test: test, startedAt: start, elapsed: 0, isSimulated: isSimulated)
        phase = .running
        keepAwake(true)
        SomaLiveActivities.shared.start(.cardioTest, liveContent(), staleAfter: 30 * 60)
        if !isSimulated {
            let feed = CardioHeartFeed()
            self.feed = feed
            let readings = await feed.start(at: start, activity: test)
            Task { [weak self] in
                for await reading in readings {
                    self?.heard(reading.value, at: reading.date.timeIntervalSince(start))
                }
            }
        }
        if test == .stepTest { startMetronome() }
        var lastPoll = -CardioLive.pollEvery
        var lastLive: TimeInterval = 0
        while !Task.isCancelled, phase == .running {
            var now = clock(since: start)
            #if DEBUG
            if isSimulated, let freezeAt { now = min(now, freezeSeconds(freezeAt)) }
            #endif
            seconds = now
            if isSimulated {
                simulate(at: now)
            } else if test.needsDistance, now - lastPoll >= CardioLive.pollEvery {
                lastPoll = now
                if let day = await motion.counted(from: start, to: Date()), let distance = day.distance, distance > metres {
                    metres = distance
                    run?.distance.append(CardioSample(time: seconds, value: distance))
                }
            }
            cue()
            guardSafety()
            // The lock screen and the island follow every few seconds: the
            // clock runs there on its own, the distance and pulse do not.
            if seconds - lastLive >= Self.liveEvery {
                lastLive = seconds
                SomaLiveActivities.shared.update(.cardioTest, liveContent())
            }
            if CardioProgress.isComplete(test, seconds: seconds, metres: metres) {
                await finishTest()
                return
            }
            try? await Task.sleep(for: CardioLive.tick)
        }
    }

    /// The clock: real seconds, or seconds at speed for a simulated run.
    private func clock(since start: Date) -> TimeInterval {
        let real = Date().timeIntervalSince(start)
        #if DEBUG
        if isSimulated { return real * simulationSpeed }
        #endif
        return real
    }

    #if DEBUG
    private func freezeSeconds(_ fraction: Double) -> TimeInterval {
        if let planned = test.plannedSeconds { return planned * fraction }
        return CardioSimulation.mileSeconds * fraction
    }
    #endif

    private func heard(_ bpm: Double, at time: TimeInterval) {
        heartRate = bpm
        run?.heartRate.append(CardioSample(time: time, value: bpm))
    }

    private func cue() {
        let due = CardioCuePlan.due(CardioCuePlan.cues(for: test), seconds: seconds, metres: metres, given: given)
        for cue in due {
            given.insert(cue.id)
            cueCount += 1
        }
    }

    private func guardSafety() {
        let samples = run?.heartRate ?? []
        let call = CardioSafety.assess(samples, now: seconds, age: person.age, test: test)
        if call != safety {
            safety = call
        }
        if call == .stop { stop(.heartRateCeiling) }
    }

    /// Ends the test early, for the reason the person gave.
    func stop(_ reason: CardioStop) {
        loop?.cancel()
        beats?.cancel()
        run?.elapsed = seconds
        run?.stop = reason
        Task { await feed?.stop() }
        keepAwake(false)
        outcome = run.map { CardioFitnessTest.evaluate($0, person: person) }
        phase = .finished
        endLive()
    }

    /// Leaves the flow, whatever it was doing.
    func cancel() {
        SomaLiveActivities.shared.end(.cardioTest)
        loop?.cancel()
        beats?.cancel()
        Task { await feed?.stop() }
        keepAwake(false)
    }

    private func finishTest() async {
        beats?.cancel()
        run?.elapsed = test.plannedSeconds.map { min(seconds, $0) } ?? seconds
        guard var current = run else { return }
        if test == .stepTest {
            // The pulse is read 5 to 20 seconds after the last step: from the
            // sensor when it reports, else counted by hand.
            phase = .settling
            let end = Date()
            await wait(seconds: CardioFitnessTest.recoveryWindow.lowerBound, from: end)
            if Task.isCancelled { return }
            if isSimulated { simulateRecovery() }
            current = run ?? current
            // No sensor reading over the last fifteen seconds of stepping:
            // the sensor will not catch the recovery either, so the pulse is
            // counted by hand, now, inside the window.
            let elapsed = current.elapsed
            if !current.heartRate.contains(where: { $0.time >= elapsed - CardioPulse.countSeconds }) {
                await countPulse()
                return
            }
            await wait(seconds: CardioFitnessTest.recoveryWindow.upperBound, from: end)
            if Task.isCancelled { return }
            current = run ?? current
        }
        let result = CardioFitnessTest.evaluate(current, person: person)
        if case .failure(let problem) = result, problem.pulseCanRescue {
            await countPulse()
            return
        }
        await conclude()
    }

    /// Waits until `seconds` after `from`, on the test's clock.
    private func wait(seconds target: TimeInterval, from start: Date) async {
        while !Task.isCancelled {
            seconds = clock(since: start)
            if seconds >= target { return }
            try? await Task.sleep(for: CardioLive.tick)
        }
    }

    private func countPulse() async {
        phase = .counting
        let start = Date()
        while !Task.isCancelled {
            countLeft = max(0, CardioPulse.countSeconds - clock(since: start))
            if countLeft <= 0 { break }
            try? await Task.sleep(for: CardioLive.tick)
        }
        if Task.isCancelled { return }
        cueCount += 1
        phase = .enteringPulse
    }

    /// The beats the person counted in fifteen seconds.
    func enterPulse(beats: Int) {
        run?.countedPulse = CardioPulse.beatsPerMinute(beatsIn15Seconds: beats)
        Task { await conclude() }
    }

    private func conclude() async {
        await feed?.stop()
        keepAwake(false)
        outcome = run.map { CardioFitnessTest.evaluate($0, person: person) }
        phase = .finished
        endLive()
    }

    // MARK: - Live Activity

    /// How often the Live Activity's distance and pulse move, in seconds.
    static let liveEvery: TimeInterval = 5

    private func liveContent() -> SomaActivityContent {
        SomaActivityCopy.cardioTest(name: test.title, start: startDate ?? Date(), metres: metres,
                                    heartRate: heartRate, slowDown: safety == .slowDown)
    }

    /// Leaves the run's last numbers on the lock screen for a few minutes.
    private func endLive() {
        var final = liveContent()
        final.detail = "Done"
        final.stoppedAt = seconds
        final.alert = false
        SomaLiveActivities.shared.end(.cardioTest, final: final)
    }

    /// Back to the start of the flow, for another try.
    func again() {
        cancel()
        reset()
        phase = .preparing
    }

    // MARK: - Step test metronome

    private func startMetronome() {
        let interval = 60 / CardioCuePlan.beatsPerMinute(person.sex ?? .female)
        #if DEBUG
        let speed = isSimulated ? simulationSpeed : 1
        #else
        let speed = 1.0
        #endif
        beats = Task { [weak self] in
            let clock = ContinuousClock()
            var next = clock.now
            while !Task.isCancelled {
                next = next.advanced(by: .seconds(interval / speed))
                try? await clock.sleep(until: next)
                guard let self, self.phase == .running else { return }
                self.beat += 1
            }
        }
    }

    // MARK: - Screen

    private func keepAwake(_ awake: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }

    // MARK: - Simulation

    private func simulate(at time: TimeInterval) {
        #if DEBUG
        let reading = CardioSimulation.reading(test, at: time)
        if let distance = reading.metres, distance > metres {
            metres = distance
            run?.distance.append(CardioSample(time: time, value: distance))
        }
        if let bpm = reading.heartRate, (run?.heartRate.last?.time ?? -10) <= time - 2 {
            heard(bpm, at: time)
        }
        #endif
    }

    private func simulateRecovery() {
        #if DEBUG
        guard let end = run?.elapsed else { return }
        for offset in stride(from: 5.0, through: 20.0, by: 3.0) {
            heard(CardioSimulation.recovery(at: offset), at: end + offset)
        }
        #endif
    }
}

/// The live loop's rhythm.
nonisolated enum CardioLive {
    static let tick: Duration = .seconds(0.25)
    static let countdownStep: Duration = .seconds(1)
    /// How often the step counter is asked for the distance so far.
    static let pollEvery: TimeInterval = 2
}

nonisolated enum CardioReads {
    static let heartRate = "HKQuantityTypeIdentifierHeartRate"
    static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
}

#if DEBUG
/// The made up readings of a simulated run: a brisk walker who covers 630 m
/// in six minutes, a mile in 14:30, and a step test whose pulse settles to
/// 128.
nonisolated enum CardioSimulation {
    static let mileSeconds: TimeInterval = 870

    static func reading(_ test: CardioTestProtocol, at time: TimeInterval) -> (metres: Double?, heartRate: Double?) {
        let rise = min(time / 120, 1)
        switch test {
        case .rockportWalk:
            return (time * CardioUnits.metresPerMile / mileSeconds, 92 + 50 * rise + 2 * sin(time / 7))
        case .sixMinuteWalk:
            return (time * 1.75, 88 + 32 * rise + 2 * sin(time / 7))
        case .stepTest:
            return (nil, 90 + 62 * rise + 2 * sin(time / 5))
        }
    }

    static func recovery(at offset: TimeInterval) -> Double { 134 - offset * 0.4 }
}
#endif

// MARK: - Heart rate

/// The heart rate during the test, from two places at once: an iPhone
/// workout session, which hears AirPods Pro 3 and Bluetooth straps, and new
/// heart rate samples in Health, which is where Apple Watch writes. The
/// workout is discarded at the end: the test writes only its VO2 max, and
/// only when the person asks.
@MainActor
final class CardioHeartFeed {
    struct Reading: Sendable {
        var date: Date
        var value: Double
    }

    #if os(iOS) && canImport(HealthKit)
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var relay: Relay?
    private var query: Task<Void, Never>?
    private var continuation: AsyncStream<Reading>.Continuation?

    func start(at start: Date, activity: CardioTestProtocol) async -> AsyncStream<Reading> {
        let (stream, continuation) = AsyncStream<Reading>.makeStream()
        self.continuation = continuation
        guard HKHealthStore.isHealthDataAvailable() else {
            continuation.finish()
            return stream
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity == .stepTest ? .stepTraining : .walking
        configuration.locationType = activity == .stepTest ? .indoor : .outdoor
        if let session = try? HKWorkoutSession(healthStore: store, configuration: configuration) {
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            let relay = Relay(continuation: continuation)
            builder.delegate = relay
            self.session = session
            self.builder = builder
            self.relay = relay
            session.startActivity(with: start)
            try? await builder.beginCollection(at: start)
        }
        let type = HKQuantityType(.heartRate)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            anchor: nil
        )
        let store = store
        query = Task {
            do {
                for try await update in descriptor.results(for: store) {
                    for sample in update.addedSamples {
                        let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                        continuation.yield(Reading(date: sample.endDate, value: bpm))
                    }
                }
            } catch {}
        }
        return stream
    }

    func stop() async {
        query?.cancel()
        query = nil
        if let session, let builder {
            session.end()
            try? await builder.endCollection(at: Date())
            builder.discardWorkout()
        }
        session = nil
        builder = nil
        relay = nil
        continuation?.finish()
        continuation = nil
    }

    /// Hands the builder's latest heart rate on as plain numbers.
    private final class Relay: NSObject, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
        let continuation: AsyncStream<Reading>.Continuation

        init(continuation: AsyncStream<Reading>.Continuation) { self.continuation = continuation }

        nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

        nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
            let type = HKQuantityType(.heartRate)
            guard collectedTypes.contains(type),
                  let bpm = workoutBuilder.statistics(for: type)?.mostRecentQuantity()?
                      .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
            continuation.yield(Reading(date: Date(), value: bpm))
        }
    }
    #else
    func start(at start: Date, activity: CardioTestProtocol) async -> AsyncStream<Reading> {
        AsyncStream { $0.finish() }
    }

    func stop() async {}
    #endif
}

// MARK: - Saving

@MainActor
enum CardioTestSaving {
    /// Keeps the estimate with the Lab's tests, as a field test.
    static func keep(_ estimate: CardioEstimate, store: FunctionalResultStore = .shared) -> FunctionalResult {
        var values: [String: Double] = [
            "vo2Max": estimate.vo2Max, "low": estimate.low, "high": estimate.high,
            "duration": CardioUnits.minutes(estimate.seconds),
        ]
        if let metres = estimate.metres { values["distance"] = metres }
        if let bpm = estimate.heartRate { values["heartRate"] = bpm }
        let result = FunctionalResult(kind: .fieldVO2, date: estimate.date, values: values, note: estimate.test.source)
        store.save(result)
        return result
    }

    /// Writes the estimate to Apple Health as a VO2 max predicted from a
    /// submaximal exercise test. Called only from the person's tap. The type
    /// is in ``HealthAccess/shareTypes()``, so the authorisation call below
    /// returns at once for a person who already answered the one sheet.
    static func saveToHealth(_ estimate: CardioEstimate) async -> LabHealthWriter.Outcome {
        #if canImport(HealthKit)
        guard LabHealthWriter.canWrite else { return .notWritten }
        let store = HKHealthStore()
        let type = HKQuantityType(.vo2Max)
        let unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        let start = estimate.date.addingTimeInterval(-estimate.seconds)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: estimate.vo2Max),
            start: start,
            end: estimate.date,
            metadata: [
                HKMetadataKeyVO2MaxTestType: HKVO2MaxTestType.predictionSubMaxExercise.rawValue,
                "SomaCardioTest": estimate.test.rawValue,
            ]
        )
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
            try await store.save(sample)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .notWritten
        #endif
    }
}
