//
//  HealthKitSampleSource.swift
//  HealthExportHealthKit
//

import Foundation
import HealthExportCore

#if canImport(HealthKit)
import HealthKit

/// Reads Apple Health through HealthKit.
///
/// Types are resolved from the catalog's identifier strings at runtime, so a
/// metric the running OS does not know is skipped rather than breaking the
/// build or the request. Every query is bridged to `async` with a continuation
/// that is resumed exactly once and honours cancellation by stopping the query.
public struct HealthKitSampleSource: HealthSampleSource {
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    public func requestAuthorization(for metrics: [HealthMetric]) async throws {
        guard isAvailable else { throw HealthReadError.unavailable }

        // Correlations are filtered out rather than trusted to the caller: a
        // read request naming one raises NSInvalidArgumentException and takes
        // the app down, so the guard belongs next to the call that would crash.
        let types = Set(metrics.filter(\.isReadAuthorizable).compactMap(Self.objectType))
        guard !types.isEmpty else { return }

        guard await shouldRequest(types) else { return }

        try await store.requestAuthorization(toShare: [], read: types)
    }

    /// Whether asking would put a question to the person that they have not
    /// already answered.
    ///
    /// `authorizationStatus(for:)` cannot answer this for a read: it reports
    /// `.notDetermined` for a type that was refused, so that an app cannot
    /// infer the refusal from the status. The request status can, and it is
    /// the store's own record of what it has shown, which is why it is asked
    /// rather than a flag of ours: a flag lives in one app's storage and
    /// drifts from what Health actually did.
    ///
    /// `.unknown` means the store could not decide, and a throw says the same
    /// thing louder. Asking is the safe reading of either: a sheet listing
    /// types that are already settled shows nothing.
    private func shouldRequest(_ types: Set<HKObjectType>) async -> Bool {
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: types)
            return status != .unnecessary
        } catch {
            return true
        }
    }

    // MARK: - Reading

    public func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        if metric.kind == .characteristic {
            return try characteristic(metric)
        }
        return try await samples(metric, from: .distantPast, to: .distantFuture, limit: 1).first
    }

    /// A fact about the person rather than a sample.
    ///
    /// Only the date of birth reads as a number: its value is the age in whole
    /// years today, `start` the birthday and `end` now. The others are coded
    /// facts no surface reads yet, and come back as nothing.
    ///
    /// Health throws when the fact was never entered and when it was not
    /// shared, and the app cannot tell the two apart. Both read as nothing,
    /// which is what a dash on screen says.
    private func characteristic(_ metric: HealthMetric) throws -> HealthReading? {
        guard isAvailable else { throw HealthReadError.unavailable }
        guard metric.identifier == HKCharacteristicTypeIdentifier.dateOfBirth.rawValue else { return nil }
        guard let components = try? store.dateOfBirthComponents() else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        guard let birthday = calendar.date(from: components) else { return nil }
        let now = Date()
        guard let years = calendar.dateComponents([.year], from: birthday, to: now).year, years >= 0 else {
            return nil
        }
        return HealthReading(
            metric: metric.identifier,
            value: Double(years),
            unit: .none,
            start: birthday,
            end: now
        )
    }

    public func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        guard metric.aggregation == .cumulative else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }
        return try await statistic(metric, from: from, to: to, options: .cumulativeSum) {
            $0.sumQuantity()
        }
    }

    public func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        guard metric.aggregation == .discrete else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }
        return try await statistic(metric, from: from, to: to, options: .discreteAverage) {
            $0.averageQuantity()
        }
    }

    public func samples(
        _ metric: HealthMetric,
        from: Date,
        to: Date,
        limit: Int
    ) async throws -> [HealthReading] {
        guard isAvailable else { throw HealthReadError.unavailable }
        guard let type = Self.sampleType(metric) else {
            throw HealthReadError.unknownMetric(metric.identifier)
        }

        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let newestFirst = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKSample] = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: limit,
                    sortDescriptors: [newestFirst]
                ) { _, result, error in
                    if let error {
                        continuation.resume(throwing: HealthReadError.underlying("\(error)"))
                    } else {
                        continuation.resume(returning: result ?? [])
                    }
                }
                store.execute(query)
            }
        } onCancel: {
            // HKSampleQuery has no handle to stop once executed; the
            // continuation still resumes, and the caller's task is already
            // cancelled, so the result is discarded rather than delivered.
        }

        return samples.compactMap { reading(from: $0, metric: metric) }
    }

    /// Every day's sum in one statistics collection query, bucketed by
    /// calendar day and with the sources merged the way the Health app
    /// merges them (a step a phone and a watch both counted counts once).
    public func dailyTotals(_ metric: HealthMetric, from: Date, to: Date, calendar: Calendar) async throws -> [HealthReading] {
        guard metric.aggregation == .cumulative else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }
        guard isAvailable else { throw HealthReadError.unavailable }
        guard let type = Self.quantityType(metric) else {
            throw HealthReadError.unknownMetric(metric.identifier)
        }
        guard let unit = metric.unit.hkUnit else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }

        let anchor = calendar.startOfDay(for: from)
        guard anchor < to else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: to)

        let identifier = metric.identifier
        let canonical = metric.unit
        let readings: [HealthReading] = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    // No samples in range is an empty answer, not a failure.
                    if (error as NSError).code == HKError.errorNoData.rawValue {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: HealthReadError.underlying("\(error)"))
                    }
                    return
                }
                var found: [HealthReading] = []
                collection?.enumerateStatistics(from: anchor, to: to) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    found.append(HealthReading(
                        metric: identifier,
                        value: sum.doubleValue(for: unit),
                        unit: canonical,
                        start: statistics.startDate,
                        end: min(statistics.endDate, to)
                    ))
                }
                continuation.resume(returning: found)
            }
            store.execute(query)
        }

        return readings.sorted { $0.start < $1.start }
    }

    // MARK: - Statistics

    private func statistic(
        _ metric: HealthMetric,
        from: Date,
        to: Date,
        options: HKStatisticsOptions,
        pick: @escaping @Sendable (HKStatistics) -> HKQuantity?
    ) async throws -> HealthReading? {
        guard isAvailable else { throw HealthReadError.unavailable }
        guard let type = Self.quantityType(metric) else {
            throw HealthReadError.unknownMetric(metric.identifier)
        }
        guard let unit = metric.unit.hkUnit else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }

        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)

        let quantity: HKQuantity? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error {
                    // No samples in range is reported as an error by HealthKit.
                    // That is an empty answer, not a failure.
                    let isNoData = (error as NSError).code == HKError.errorNoData.rawValue
                    if isNoData {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: HealthReadError.underlying("\(error)"))
                    }
                } else {
                    continuation.resume(returning: statistics.flatMap(pick))
                }
            }
            store.execute(query)
        }

        guard let quantity else { return nil }
        return HealthReading(
            metric: metric.identifier,
            value: quantity.doubleValue(for: unit),
            unit: metric.unit,
            start: from,
            end: to
        )
    }

    // MARK: - Mapping

    private func reading(from sample: HKSample, metric: HealthMetric) -> HealthReading? {
        let value: Double

        switch sample {
        case let quantity as HKQuantitySample:
            guard let unit = metric.unit.hkUnit else { return nil }
            value = quantity.quantity.doubleValue(for: unit)
        case let category as HKCategorySample:
            // A category's value is its coded case: a sleep stage, a flow level.
            value = Double(category.value)
        case let workout as HKWorkout:
            // A workout's value is coded the same way: the raw value of its
            // `HKWorkoutActivityType`, so a walk reads 52 and a run 37. Its
            // span is the session itself.
            value = Double(workout.workoutActivityType.rawValue)
        default:
            return nil
        }

        let device = sample.device
        let model = [device?.model, device?.manufacturer]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let entered = (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue ?? false

        return HealthReading(
            metric: metric.identifier,
            value: value,
            unit: metric.unit,
            start: sample.startDate,
            end: sample.endDate,
            source: sample.sourceRevision.source.name,
            sourceBundle: sample.sourceRevision.source.bundleIdentifier,
            device: device?.name ?? device?.model,
            deviceModel: model.isEmpty ? nil : model,
            wasUserEntered: entered
        )
    }

    /// Everything the permission sheet can name, including the types that are
    /// not samples.
    public static func objectType(_ metric: HealthMetric) -> HKObjectType? {
        switch metric.kind {
        case .workout:
            HKObjectType.workoutType()
        case .characteristic:
            HKObjectType.characteristicType(
                forIdentifier: HKCharacteristicTypeIdentifier(rawValue: metric.identifier)
            )
        case .correlation:
            HKObjectType.correlationType(
                forIdentifier: HKCorrelationTypeIdentifier(rawValue: metric.identifier)
            )
        case .quantity, .category:
            sampleType(metric)
        }
    }

    static func sampleType(_ metric: HealthMetric) -> HKSampleType? {
        switch metric.kind {
        case .quantity: quantityType(metric)
        case .category:
            HKObjectType.categoryType(
                forIdentifier: HKCategoryTypeIdentifier(rawValue: metric.identifier)
            )
        case .workout: HKObjectType.workoutType()
        case .correlation:
            HKObjectType.correlationType(
                forIdentifier: HKCorrelationTypeIdentifier(rawValue: metric.identifier)
            )
        case .characteristic: nil
        }
    }

    static func quantityType(_ metric: HealthMetric) -> HKQuantityType? {
        HKObjectType.quantityType(
            forIdentifier: HKQuantityTypeIdentifier(rawValue: metric.identifier)
        )
    }
}

// MARK: - Anchored reads

extension HealthKitSampleSource: HealthAnchoredSampleSource {
    /// What changed for `metric` since `anchor`, through `HKAnchoredObjectQuery`.
    ///
    /// The anchor travels as the keyed archive of HealthKit's `HKQueryAnchor`.
    /// Bytes that no longer unarchive (another OS, a corrupted file) start the
    /// read over from the beginning: an upload keyed on the sample's identifier
    /// absorbs the repeat, while a refusal would stop the metric for good.
    public func changes(_ metric: HealthMetric, after anchor: Data?, limit: Int) async throws -> HealthSampleChanges {
        guard isAvailable else { throw HealthReadError.unavailable }
        guard metric.kind != .characteristic, metric.kind != .correlation, let type = Self.sampleType(metric) else {
            throw HealthReadError.unsupportedQuery(metric.identifier)
        }
        let start = Self.unarchive(anchor)
        let pageLimit = max(0, limit)

        let page: (samples: [HKSample], deleted: [HKDeletedObject], anchor: HKQueryAnchor?) =
            try await withCheckedThrowingContinuation { continuation in
                let query = HKAnchoredObjectQuery(
                    type: type,
                    predicate: nil,
                    anchor: start,
                    limit: pageLimit == 0 ? HKObjectQueryNoLimit : pageLimit
                ) { _, samples, deleted, next, error in
                    if let error {
                        continuation.resume(throwing: HealthReadError.underlying("\(error)"))
                    } else {
                        continuation.resume(returning: (samples ?? [], deleted ?? [], next))
                    }
                }
                store.execute(query)
            }

        let added = page.samples.compactMap { sample in
            reading(from: sample, metric: metric).map { HealthSampleRecord(uuid: sample.uuid, reading: $0) }
        }
        let received = page.samples.count + page.deleted.count
        return HealthSampleChanges(
            added: added,
            deleted: page.deleted.map(\.uuid),
            anchor: Self.archive(page.anchor) ?? anchor,
            hasMore: pageLimit > 0 && received >= pageLimit
        )
    }

    static func archive(_ anchor: HKQueryAnchor?) -> Data? {
        guard let anchor else { return nil }
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        } catch {
            return nil
        }
    }

    static func unarchive(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        } catch {
            return nil
        }
    }
}

extension HealthUnit {
    /// The HealthKit unit this canonical unit maps to.
    ///
    /// Built explicitly rather than parsed from a string: a typo in a unit
    /// string is a wrong number on screen, and this way it is a build error.
    public var hkUnit: HKUnit? {
        switch self {
        case .count: .count()
        case .countPerMinute: HKUnit.count().unitDivided(by: .minute())
        case .kilocalorie: .kilocalorie()
        case .kilocaloriePerKilogramHour:
            HKUnit.kilocalorie()
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour()))
        case .meter: .meter()
        case .centimeter: .meterUnit(with: .centi)
        case .minute: .minute()
        case .hour: .hour()
        case .second: .second()
        case .millisecond: .secondUnit(with: .milli)
        case .percent: .percent()
        case .millimeterOfMercury: .millimeterOfMercury()
        case .kilogram: .gramUnit(with: .kilo)
        case .degreeCelsius: .degreeCelsius()
        case .millilitrePerKilogramMinute:
            HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .metrePerSecond: HKUnit.meter().unitDivided(by: .second())
        case .watt: .watt()
        case .milligramPerDecilitre:
            HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case .microsiemens: .siemenUnit(with: .micro)
        case .decibelASPL: .decibelAWeightedSoundPressureLevel()
        case .decibelHearingLevel: .decibelHearingLevel()
        case .litre: .liter()
        case .litrePerMinute: HKUnit.liter().unitDivided(by: .minute())
        case .internationalUnit: .internationalUnit()
        case .gram: .gram()
        case .milligram: .gramUnit(with: .milli)
        case .microgram: .gramUnit(with: .micro)
        case .none: nil
        }
    }
}

#else

/// The platform has no Health store. The type still exists so callers compile
/// everywhere; every call reports the store as unavailable.
public struct HealthKitSampleSource: HealthSampleSource {
    public init() {}

    public var isAvailable: Bool { false }

    public func requestAuthorization(for metrics: [HealthMetric]) async throws {
        throw HealthReadError.unavailable
    }

    public func latest(_ metric: HealthMetric) async throws -> HealthReading? {
        throw HealthReadError.unavailable
    }

    public func total(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        throw HealthReadError.unavailable
    }

    public func average(_ metric: HealthMetric, from: Date, to: Date) async throws -> HealthReading? {
        throw HealthReadError.unavailable
    }

    public func samples(
        _ metric: HealthMetric,
        from: Date,
        to: Date,
        limit: Int
    ) async throws -> [HealthReading] {
        throw HealthReadError.unavailable
    }

    public func dailyTotals(_ metric: HealthMetric, from: Date, to: Date, calendar: Calendar) async throws -> [HealthReading] {
        throw HealthReadError.unavailable
    }
}

extension HealthKitSampleSource: HealthAnchoredSampleSource {
    public func changes(_ metric: HealthMetric, after anchor: Data?, limit: Int) async throws -> HealthSampleChanges {
        throw HealthReadError.unavailable
    }
}

#endif
