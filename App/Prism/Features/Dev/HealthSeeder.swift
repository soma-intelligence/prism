//
//  HealthSeeder.swift
//  Prism
//

#if DEBUG && targetEnvironment(simulator)
import Foundation
import Observation
import HealthExportCore
import HealthExportHealthKit

#if canImport(HealthKit)
import HealthKit

/// Fills the local Health store with a month of fabricated samples.
///
/// Simulator debug builds only, and it exists for one reason: HealthKit hands
/// back nothing in the Simulator, so every card renders a dash and no layout is
/// ever seen carrying real numbers. This writes through the public save API, so
/// what the pages read back afterwards is genuine HealthKit data that happens to
/// be invented.
///
/// A debug build on a device leaves it out too. The store there is a person's
/// own record: Health in iCloud copies it to their other devices and every app
/// they let read Health sees it, so an invented month passes for a month they
/// lived. And a device never needed it: it has real numbers of its own.
///
/// Everything it writes carries ``marker`` in its metadata, which is what
/// ``removeSeeded()`` deletes. An app may only delete samples it wrote itself,
/// so nothing a person actually recorded can be touched from here.
@MainActor
@Observable
final class HealthSeeder {

    enum Phase: Equatable {
        case idle
        /// The permission sheet is up.
        case authorizing
        case writing
        case done(Summary)
        case failed(String)
    }

    struct Summary: Equatable {
        var samples: Int = 0
        var metrics: Int = 0
        var workouts: Int = 0
        /// Types the store refused, with the reason. Reported rather than
        /// swallowed: a metric silently missing from the store looks exactly
        /// like a metric the app forgot to read.
        var refused: [String] = []
    }

    /// The metadata key every fabricated sample carries.
    static let marker = "SomaSeededFixture"

    /// Days of history written, counting back from today.
    static let days = 30

    private(set) var phase: Phase = .idle
    private(set) var written: Int = 0
    private(set) var total: Int = 0

    private let store = HKHealthStore()
    private let calendar = Calendar.current

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var isRunning: Bool { phase == .authorizing || phase == .writing }

    var fraction: Double { total == 0 ? 0 : Double(written) / Double(total) }

    // MARK: - What can be written

    /// Types HealthKit refuses to let any app write.
    ///
    /// The platform computes these itself, and naming one in a share request
    /// raises `NSInvalidArgumentException`, which terminates the app: the guard
    /// belongs here, next to the call that would crash, exactly as the read side
    /// guards against naming a correlation.
    ///
    /// The list is not guesswork and it is not in any header. It is what
    /// HealthKit itself named, verbatim, in the exception it threw on iOS 27
    /// when the whole catalog was offered to it. Re-derive it the same way when
    /// a new OS moves a type across the line: run the seeder with this set
    /// emptied and read the types out of the crash.
    ///
    /// One entry has not been through that yet: `AudioExposureEvent`, the
    /// environmental twin of the headphone event, which the catalog only
    /// started naming under its real identifier on 2026-10-24. It sits here
    /// beside its twin until a run with the set emptied confirms it.
    static let readOnlyIdentifiers: Set<String> = [
        "HKCategoryTypeIdentifierAppleStandHour",
        "HKCategoryTypeIdentifierAudioExposureEvent",
        "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent",
        "HKCategoryTypeIdentifierHeadphoneAudioExposureEvent",
        "HKCategoryTypeIdentifierHighHeartRateEvent",
        "HKCategoryTypeIdentifierInfrequentMenstrualCycles",
        "HKCategoryTypeIdentifierIrregularHeartRhythmEvent",
        "HKCategoryTypeIdentifierIrregularMenstrualCycles",
        "HKCategoryTypeIdentifierLowCardioFitnessEvent",
        "HKCategoryTypeIdentifierLowHeartRateEvent",
        "HKCategoryTypeIdentifierPersistentIntermenstrualBleeding",
        "HKCategoryTypeIdentifierProlongedMenstrualPeriods",
        "HKCategoryTypeIdentifierSleepApneaEvent",
        "HKQuantityTypeIdentifierAppleExerciseTime",
        "HKQuantityTypeIdentifierAppleMoveTime",
        "HKQuantityTypeIdentifierAppleSleepingWristTemperature",
        "HKQuantityTypeIdentifierAppleStandTime",
        "HKQuantityTypeIdentifierAppleWalkingSteadiness",
        "HKQuantityTypeIdentifierAtrialFibrillationBurden",
        "HKQuantityTypeIdentifierNikeFuel",
        "HKQuantityTypeIdentifierWalkingAsymmetryPercentage",
        "HKQuantityTypeIdentifierWalkingHeartRateAverage",
    ]

    /// Every metric this writes: the catalog's quantities and categories, minus
    /// what the platform reserves for itself.
    ///
    /// Characteristics are absent for a different reason: date of birth and
    /// biological sex have no save API at all. They are entered in the Health
    /// app by hand, once.
    static var seedable: [HealthMetric] {
        HealthMetricCatalog.all.filter { metric in
            (metric.kind == .quantity || metric.kind == .category)
            && !readOnlyIdentifiers.contains(metric.identifier)
        }
    }

    // MARK: - Writing

    func seed() async {
        guard isAvailable else {
            phase = .failed("This device has no Health store.")
            return
        }

        let metrics = Self.seedable
        written = 0
        total = metrics.count + 2  // the generic pass, plus sleep and workouts
        phase = .authorizing

        do {
            try await requestWriteAccess(for: metrics)
        } catch {
            phase = .failed(String(describing: error))
            return
        }

        phase = .writing
        var summary = Summary()
        let dayStarts = Self.dayStarts(days: Self.days, calendar: calendar)

        // A second press replaces the month rather than stacking another one on
        // top of it. Two runs of steps read as twenty thousand a day, which is
        // worse than no data: it looks like a bug in the reader.
        _ = await deleteSeeded(from: metrics)

        for metric in metrics {
            if Task.isCancelled { break }
            defer { written += 1 }

            guard canShare(metric) else {
                summary.refused.append("\(short(metric.identifier)): permission not granted")
                continue
            }
            guard let recipe = HealthSeedCatalog.recipe(for: metric) else { continue }

            let samples = self.samples(for: metric, recipe: recipe, dayStarts: dayStarts)
            guard !samples.isEmpty else { continue }

            do {
                try await store.save(samples)
                summary.samples += samples.count
                summary.metrics += 1
            } catch {
                summary.refused.append("\(short(metric.identifier)): \(message(of: error))")
            }
            await Task.yield()
        }

        // Sleep, blood pressure and mindfulness are shapes rather than sprinkled
        // numbers, so each has its own writer.
        await write(nightlySleepAndMindfulness(dayStarts: dayStarts), into: &summary)
        written += 1
        await write(bloodPressure(dayStarts: dayStarts), into: &summary)
        let sessions = await writeWorkouts(dayStarts: dayStarts, into: &summary)
        summary.workouts = sessions
        written += 1

        phase = .done(summary)
    }

    /// Deletes everything this seeder wrote, and nothing else.
    func removeSeeded() async {
        guard isAvailable else { return }

        phase = .writing
        written = 0
        let metrics = Self.seedable
        total = metrics.count + 1
        let removed = await deleteSeeded(from: metrics, reportingProgress: true)

        phase = .done(Summary(samples: removed, metrics: 0, workouts: 0, refused: []))
    }

    /// Removes the marked samples for these metrics, and the marked workouts.
    ///
    /// HealthKit only ever lets an app delete what that app wrote, and the
    /// predicate narrows it again to what carries the marker, so a sample a
    /// person recorded themselves is out of reach twice over.
    private func deleteSeeded(from metrics: [HealthMetric], reportingProgress: Bool = false) async -> Int {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.marker)
        var removed = 0

        for metric in metrics {
            defer { if reportingProgress { written += 1 } }
            guard let type = Self.sampleType(metric) else { continue }
            removed += (try? await store.deleteObjects(of: type, predicate: predicate)) ?? 0
            await Task.yield()
        }
        removed += (try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate)) ?? 0
        if reportingProgress { written += 1 }
        return removed
    }

    // MARK: - Authorization

    private func requestWriteAccess(for metrics: [HealthMetric]) async throws {
        var types = Set(metrics.compactMap(Self.sampleType))
        types.insert(HKObjectType.workoutType())
        try await store.requestAuthorization(toShare: types, read: [])
    }

    private func canShare(_ metric: HealthMetric) -> Bool {
        guard let type = Self.sampleType(metric) else { return false }
        return store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: - Generic samples

    private func samples(
        for metric: HealthMetric,
        recipe: HealthSeedRecipe,
        dayStarts: [Date]
    ) -> [HKSample] {
        switch metric.kind {
        case .quantity:
            guard let type = Self.quantityType(metric), let unit = metric.unit.hkUnit else { return [] }
            return dayStarts.flatMap { day in
                quantitySamples(type: type, unit: unit, metric: metric, recipe: recipe, day: day)
            }
        case .category:
            guard let type = Self.categoryType(metric) else { return [] }
            let value = HealthSeedCatalog.value(for: metric.identifier)
            return dayStarts.flatMap { day in
                categorySamples(type: type, value: value, recipe: recipe, day: day, metric: metric)
            }
        case .correlation, .workout, .characteristic:
            return []
        }
    }

    private func quantitySamples(
        type: HKQuantityType,
        unit: HKUnit,
        metric: HealthMetric,
        recipe: HealthSeedRecipe,
        day: Date
    ) -> [HKSample] {
        var random = Self.generator(for: metric.identifier, day: day)
        guard Double.random(in: 0..<1, using: &random) < recipe.chance else { return [] }

        let dayValue = Double.random(in: recipe.low...max(recipe.low, recipe.high), using: &random)
        let count = max(1, recipe.perDay)
        // A cumulative metric's range is the day's total, so it is divided; a
        // discrete one is a reading, so each sample stands on its own.
        let isCumulative = metric.aggregation == .cumulative

        // Every sample spans a little time. A zero length one is rejected
        // outright by some types, and the rejection is an Objective C exception
        // raised while the sample is built, which no Swift catch can hold.
        let span: TimeInterval = isCumulative ? 20 * 60 : 60

        return (0..<count).compactMap { index in
            let slot = Self.time(of: day, slot: index, of: count, using: &random, calendar: calendar)
            let jitter = Double.random(in: 0.78...1.22, using: &random)
            let raw = isCumulative ? (dayValue / Double(count)) * jitter
                                   : Double.random(in: recipe.low...max(recipe.low, recipe.high), using: &random)
            let value = max(0, raw)
            guard value > 0 || recipe.low == 0 else { return nil }

            let start = Self.past(slot, lasting: span)
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: start,
                end: start.addingTimeInterval(span),
                metadata: Self.metadata(for: metric.identifier)
            )
        }
    }

    private func categorySamples(
        type: HKCategoryType,
        value: Int,
        recipe: HealthSeedRecipe,
        day: Date,
        metric: HealthMetric
    ) -> [HKSample] {
        var random = Self.generator(for: metric.identifier, day: day)
        guard Double.random(in: 0..<1, using: &random) < recipe.chance else { return [] }

        let count = max(1, recipe.perDay)
        return (0..<count).map { index in
            let slot = Self.time(of: day, slot: index, of: count, using: &random, calendar: calendar)
            let start = Self.past(slot, lasting: 60)
            return HKCategorySample(
                type: type,
                value: value,
                start: start,
                end: start.addingTimeInterval(60),
                metadata: Self.metadata(for: metric.identifier)
            )
        }
    }

    // MARK: - Shapes with their own writer

    /// A night of sleep stages, and the day's mindfulness sessions.
    ///
    /// Sleep is written the way a watch writes it: one `inBed` sample spanning
    /// the night, and stages inside it that a reader can add up.
    private func nightlySleepAndMindfulness(dayStarts: [Date]) -> [HKSample] {
        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession)
        else { return [] }

        var samples: [HKSample] = []

        for day in dayStarts {
            var random = Self.generator(for: "sleep", day: day)

            // The night that ends on this morning starts the evening before.
            let bedHour = Double.random(in: 22.2...23.9, using: &random)
            let bedtime = day.addingTimeInterval(-24 * 3600 + bedHour * 3600)
            let hours = Double.random(in: 6.1...8.6, using: &random)
            let wake = Self.past(bedtime.addingTimeInterval(hours * 3600))
            guard wake > bedtime else { continue }

            samples.append(HKCategorySample(
                type: sleep,
                value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: bedtime,
                end: wake,
                metadata: Self.metadata
            ))

            // Stages fill the night in order, each one a slice of what is left.
            let stages: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepREM, .asleepCore, .awake, .asleepCore, .asleepREM]
            var cursor = bedtime.addingTimeInterval(Double.random(in: 240...900, using: &random))
            for stage in stages where cursor < wake {
                let share: ClosedRange<Double> = stage == .awake ? 0.01...0.04 : 0.09...0.22
                let length = hours * 3600 * Double.random(in: share, using: &random)
                let end = min(wake, cursor.addingTimeInterval(length))
                guard end > cursor else { break }
                samples.append(HKCategorySample(
                    type: sleep,
                    value: stage.rawValue,
                    start: cursor,
                    end: end,
                    metadata: Self.metadata
                ))
                cursor = end
            }

            // Mindfulness, on the days there is any.
            if Double.random(in: 0..<1, using: &random) < 0.55 {
                let sessions = Int.random(in: 1...2, using: &random)
                for index in 0..<sessions {
                    let minutes = Double.random(in: 5...22, using: &random)
                    let start = Self.past(
                        day.addingTimeInterval(Double.random(in: 7...21, using: &random) * 3600 + Double(index) * 600),
                        lasting: minutes * 60
                    )
                    samples.append(HKCategorySample(
                        type: mindful,
                        value: HKCategoryValue.notApplicable.rawValue,
                        start: start,
                        end: start.addingTimeInterval(minutes * 60),
                        metadata: Self.metadata
                    ))
                }
            }
        }

        return samples
    }

    /// Systolic and diastolic, saved as the correlation Health expects so the
    /// pair reads as one measurement rather than two loose numbers.
    private func bloodPressure(dayStarts: [Date]) -> [HKSample] {
        guard let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
              let correlationType = HKObjectType.correlationType(forIdentifier: .bloodPressure)
        else { return [] }

        return dayStarts.compactMap { day in
            var random = Self.generator(for: "bloodPressure", day: day)
            guard Double.random(in: 0..<1, using: &random) < 0.6 else { return nil }

            let at = Self.past(day.addingTimeInterval(Double.random(in: 7...22, using: &random) * 3600), lasting: 60)
            let until = at.addingTimeInterval(60)
            let systolic = HKQuantitySample(
                type: systolicType,
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double.random(in: 108...132, using: &random)),
                start: at,
                end: until,
                metadata: Self.metadata
            )
            let diastolic = HKQuantitySample(
                type: diastolicType,
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double.random(in: 68...86, using: &random)),
                start: at,
                end: until,
                metadata: Self.metadata
            )
            return HKCorrelation(
                type: correlationType,
                start: at,
                end: until,
                objects: [systolic, diastolic],
                metadata: Self.metadata
            )
        }
    }

    /// Recorded sessions, built the way a watch builds them.
    ///
    /// A workout is not a sample that can be saved in a batch: it is collected,
    /// closed, and finished, and the energy and distance inside it belong to the
    /// builder rather than to the store.
    private func writeWorkouts(dayStarts: [Date], into summary: inout Summary) async -> Int {
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            summary.refused.append("Workouts: permission not granted")
            return 0
        }

        let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        var count = 0

        for day in dayStarts {
            var random = Self.generator(for: "workout", day: day)
            guard Double.random(in: 0..<1, using: &random) < 0.42 else { continue }

            let plan = Self.workoutPlans.randomElement(using: &random) ?? Self.workoutPlans[0]
            let minutes = Double.random(in: plan.minutes, using: &random)
            let start = Self.past(
                day.addingTimeInterval(Double.random(in: 6.5...20, using: &random) * 3600),
                lasting: minutes * 60
            )
            let end = start.addingTimeInterval(minutes * 60)

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = plan.activity
            configuration.locationType = plan.outdoors ? .outdoor : .indoor

            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            do {
                try await builder.beginCollection(at: start)

                var inside: [HKSample] = []
                if let energyType, store.authorizationStatus(for: energyType) == .sharingAuthorized {
                    let kilocalories = minutes * Double.random(in: plan.kilocaloriesPerMinute, using: &random)
                    inside.append(HKQuantitySample(
                        type: energyType,
                        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                        start: start,
                        end: end,
                        metadata: Self.metadata
                    ))
                }
                if let metres = plan.metresPerMinute, let distanceType,
                   store.authorizationStatus(for: distanceType) == .sharingAuthorized {
                    inside.append(HKQuantitySample(
                        type: distanceType,
                        quantity: HKQuantity(unit: .meter(), doubleValue: minutes * Double.random(in: metres, using: &random)),
                        start: start,
                        end: end,
                        metadata: Self.metadata
                    ))
                }
                if !inside.isEmpty {
                    try await builder.addSamples(inside)
                }
                try await builder.addMetadata(Self.metadata)
                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
                count += 1
                summary.samples += inside.count + 1
            } catch {
                summary.refused.append("Workout on \(Self.dayLabel(start)): \(message(of: error))")
            }
            await Task.yield()
        }

        return count
    }

    private func write(_ samples: [HKSample], into summary: inout Summary) async {
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            summary.samples += samples.count
            summary.metrics += 1
        } catch {
            summary.refused.append("\(message(of: error))")
        }
    }

    // MARK: - Helpers

    private struct WorkoutPlan {
        let activity: HKWorkoutActivityType
        let minutes: ClosedRange<Double>
        let kilocaloriesPerMinute: ClosedRange<Double>
        let metresPerMinute: ClosedRange<Double>?
        let outdoors: Bool
    }

    private static let workoutPlans: [WorkoutPlan] = [
        WorkoutPlan(activity: .running, minutes: 22...58, kilocaloriesPerMinute: 9...13, metresPerMinute: 155...205, outdoors: true),
        WorkoutPlan(activity: .walking, minutes: 25...70, kilocaloriesPerMinute: 3.5...5.5, metresPerMinute: 75...95, outdoors: true),
        WorkoutPlan(activity: .cycling, minutes: 35...95, kilocaloriesPerMinute: 7...11, metresPerMinute: 320...420, outdoors: true),
        WorkoutPlan(activity: .functionalStrengthTraining, minutes: 30...65, kilocaloriesPerMinute: 5...8, metresPerMinute: nil, outdoors: false),
        WorkoutPlan(activity: .highIntensityIntervalTraining, minutes: 18...35, kilocaloriesPerMinute: 10...14, metresPerMinute: nil, outdoors: false),
        WorkoutPlan(activity: .yoga, minutes: 30...60, kilocaloriesPerMinute: 2.5...4, metresPerMinute: nil, outdoors: false),
        WorkoutPlan(activity: .swimming, minutes: 25...50, kilocaloriesPerMinute: 8...12, metresPerMinute: nil, outdoors: false),
    ]

    private static let metadata: [String: Any] = [marker: true]

    /// The marker, plus whatever the type refuses to be created without.
    ///
    /// Two types in the catalog carry a required metadata key, and a sample
    /// built without it raises `_HKObjectValidationFailureException` at init,
    /// which is thrown before any `save` and so cannot be caught in Swift.
    private static func metadata(for identifier: String) -> [String: Any] {
        switch identifier {
        case "HKQuantityTypeIdentifierInsulinDelivery":
            [marker: true, HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.basal.rawValue]
        case "HKCategoryTypeIdentifierMenstrualFlow":
            [marker: true, HKMetadataKeyMenstrualCycleStart: false]
        default:
            metadata
        }
    }

    /// Midnight of each of the last `days` days, oldest first.
    static func dayStarts(days: Int, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    /// A time inside the day's waking hours for slot `index` of `count`.
    ///
    /// Slots are spread rather than random so a day's samples do not all land in
    /// the same hour, which is what makes an hourly chart look like a person.
    private static func time(
        of day: Date,
        slot index: Int,
        of count: Int,
        using random: inout SplitMix64,
        calendar: Calendar
    ) -> Date {
        let window = 16.0  // 06:00 to 22:00
        let step = window / Double(count)
        let hour = 6 + step * Double(index) + Double.random(in: 0...step * 0.8, using: &random)
        let at = day.addingTimeInterval(hour * 3600)
        // Today's later slots have not happened yet. A sample in the future is
        // rejected by the store, so the day is compressed into what is past.
        let now = Date()
        guard at > now else { return at }
        return now.addingTimeInterval(-Double.random(in: 120...3600, using: &random))
    }

    /// The same instant, or a moment ago when it has not happened yet.
    ///
    /// Today is a partial day, and HealthKit rejects a sample that ends in the
    /// future, which would take the whole batch down with it.
    static func past(_ date: Date, lasting seconds: TimeInterval = 0) -> Date {
        let now = Date()
        guard date.addingTimeInterval(seconds) > now else { return date }
        return now.addingTimeInterval(-seconds - 60)
    }

    /// One generator per metric per day, so a re-run writes the same month.
    private static func generator(for identifier: String, day: Date) -> SplitMix64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in identifier.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        let dayNumber = UInt64(bitPattern: Int64(day.timeIntervalSince1970 / 86400))
        return SplitMix64(seed: hash ^ (dayNumber &* 0x9e37_79b9_7f4a_7c15))
    }

    static func sampleType(_ metric: HealthMetric) -> HKSampleType? {
        switch metric.kind {
        case .quantity: quantityType(metric)
        case .category: categoryType(metric)
        case .workout: HKObjectType.workoutType()
        case .correlation, .characteristic: nil
        }
    }

    static func quantityType(_ metric: HealthMetric) -> HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: metric.identifier))
    }

    static func categoryType(_ metric: HealthMetric) -> HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: metric.identifier))
    }

    private func short(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
    }

    private func message(of error: Error) -> String {
        (error as NSError).localizedDescription
    }

    private static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// A small, fast, seeded generator.
///
/// The system generator would do, but then no two runs would agree, and a bug
/// that only shows up on one month of fabricated data would be unreproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

#endif
#endif
