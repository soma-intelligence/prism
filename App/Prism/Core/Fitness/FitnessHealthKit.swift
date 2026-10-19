//
//  FitnessHealthKit.swift
//  Prism
//

import Foundation
#if canImport(HealthKit)
import HealthKit
import CoreLocation
#endif

/// The fitness reads the catalog source cannot make: ECG recordings with
/// their voltages, workout routes, and the Move goal.
///
/// None of these is a quantity or a category sample, so `HealthSampleSource`
/// has no shape for them. Each is asked for by the page that shows it, when it
/// opens, and never at launch: an ECG and a map of where a person walks are
/// among the most sensitive things Health holds.
///
/// Reads nothing when the app was launched with `-health.empty YES`, like
/// `EmptyHealthSource`, so a UI test never meets a permission sheet.
nonisolated struct FitnessHealthKit: Sendable {
    /// One ECG recording.
    struct Recording: Equatable, Sendable, Identifiable {
        enum Classification: String, Sendable {
            case sinusRhythm = "Sinus rhythm"
            case atrialFibrillation = "Atrial fibrillation"
            case lowHeartRate = "Low heart rate"
            case highHeartRate = "High heart rate"
            case poorReading = "Poor recording"
            case inconclusive = "Inconclusive"
            case unclassified = "Not classified"
        }

        var id: UUID
        var date: Date
        var classification: Classification
        var averageHeartRate: Double?
        var duration: TimeInterval
        var samplingFrequency: Double?
    }

    var isAvailable: Bool {
#if canImport(HealthKit)
        guard !UserDefaults.standard.bool(forKey: "health.empty") else { return false }
        return HKHealthStore.isHealthDataAvailable()
#else
        return false
#endif
    }

#if canImport(HealthKit)
    private let store = HKHealthStore()

    private func ask(_ types: Set<HKObjectType>) async -> Bool {
        guard isAvailable else { return false }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: types)
            if status != .unnecessary {
                try await store.requestAuthorization(toShare: [], read: types)
            }
            return true
        } catch {
            return false
        }
    }
#endif

    // MARK: - ECG

    /// The latest recordings, newest first. Asks for ECG access first.
    func recordings(limit: Int = 10) async -> [Recording] {
#if canImport(HealthKit)
        guard await ask([HKObjectType.electrocardiogramType()]) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.electrocardiogram()],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { ecg in
            Recording(
                id: ecg.uuid,
                date: ecg.startDate,
                classification: Self.classification(ecg.classification),
                averageHeartRate: ecg.averageHeartRate?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                duration: ecg.endDate.timeIntervalSince(ecg.startDate),
                samplingFrequency: ecg.samplingFrequency?.doubleValue(for: .hertz())
            )
        }
#else
        return []
#endif
    }

    /// The Lead I voltages of one recording, in microvolts, in order.
    func voltages(of recording: Recording) async -> [Double] {
#if canImport(HealthKit)
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForObject(with: recording.id)
        let descriptor = HKSampleQueryDescriptor(predicates: [.electrocardiogram(predicate)], sortDescriptors: [], limit: 1)
        guard let ecg = try? await descriptor.result(for: store).first else { return [] }
        let collected = Collector<Double>()
        return await withCheckedContinuation { continuation in
            let query = HKElectrocardiogramQuery(ecg) { _, result in
                switch result {
                case .measurement(let measurement):
                    if let value = measurement.quantity(for: .appleWatchSimilarToLeadI)?.doubleValue(for: .voltUnit(with: .micro)) {
                        collected.append(value)
                    }
                case .done, .error:
                    continuation.resume(returning: collected.values)
                @unknown default:
                    continuation.resume(returning: collected.values)
                }
            }
            store.execute(query)
        }
#else
        return []
#endif
    }

#if canImport(HealthKit)
    private static func classification(_ value: HKElectrocardiogram.Classification) -> Recording.Classification {
        switch value {
        case .sinusRhythm: .sinusRhythm
        case .atrialFibrillation: .atrialFibrillation
        case .inconclusiveLowHeartRate: .lowHeartRate
        case .inconclusiveHighHeartRate: .highHeartRate
        case .inconclusivePoorReading: .poorReading
        case .inconclusiveOther: .inconclusive
        default: .unclassified
        }
    }
#endif

    // MARK: - Routes

    /// Every workout route from `start` to `end`. Asks for workouts and
    /// routes first.
    func routes(from start: Date, to end: Date) async -> [Territory.Route] {
#if canImport(HealthKit)
        guard await ask([HKObjectType.workoutType(), HKSeriesType.workoutRoute()]) else { return [] }
        let window = HKQuery.predicateForSamples(withStart: start, end: end)
        let workouts = HKSampleQueryDescriptor(
            predicates: [.workout(window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let found = try? await workouts.result(for: store) else { return [] }

        var routes: [Territory.Route] = []
        for workout in found {
            let owned = HKQuery.predicateForObjects(from: workout)
            let routeQuery = HKSampleQueryDescriptor(predicates: [.workoutRoute(owned)], sortDescriptors: [])
            guard let series = try? await routeQuery.result(for: store), !series.isEmpty else { continue }
            var points: [Territory.Point] = []
            for route in series {
                points += await locations(of: route)
            }
            guard points.count >= 2 else { continue }
            routes.append(Territory.Route(
                start: workout.startDate,
                end: workout.endDate,
                activity: Int(workout.workoutActivityType.rawValue),
                points: points
            ))
        }
        return routes
#else
        return []
#endif
    }

#if canImport(HealthKit)
    private func locations(of route: HKWorkoutRoute) async -> [Territory.Point] {
        let collected = Collector<Territory.Point>()
        return await withCheckedContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                for location in locations ?? [] {
                    collected.append(Territory.Point(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.verticalAccuracy >= 0 ? location.altitude : nil
                    ))
                }
                if done || error != nil {
                    continuation.resume(returning: collected.values)
                }
            }
            store.execute(query)
        }
    }
#endif

    // MARK: - Move goal

    /// Today's Move goal in kilocalories, from the Activity rings. Nil when
    /// the rings are not set up or access was not given.
    func moveGoal(now: Date, calendar: Calendar) async -> Double? {
#if canImport(HealthKit)
        guard await ask([HKObjectType.activitySummaryType()]) else { return nil }
        var components = calendar.dateComponents([.era, .year, .month, .day], from: now)
        components.calendar = calendar
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components)
        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                let goal = summaries?.first?.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                continuation.resume(returning: goal.flatMap { $0 > 0 ? $0 : nil })
            }
            store.execute(query)
        }
#else
        return nil
#endif
    }
}

/// Values handed in by a HealthKit callback, which runs on a queue of its own.
nonisolated private final class Collector<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    func append(_ value: Value) {
        lock.withLock { stored.append(value) }
    }

    var values: [Value] { lock.withLock { stored } }
}
