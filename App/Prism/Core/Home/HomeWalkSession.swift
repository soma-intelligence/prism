//
//  HomeWalkSession.swift
//  Prism
//

import Foundation
import Observation
#if canImport(HealthKit)
import HealthKit
#endif

/// A walk recorded live on the phone, on the
/// `HKWorkoutSession` iOS 26 brought to iPhone. Elapsed time, heart rate from
/// a paired watch or sensor, distance and steps, saved to Apple Health as a
/// walk when it ends.
///
/// Where a live session cannot run (a Mac, no Health store, the person said
/// no), it says why and records nothing.
@MainActor
@Observable
final class HomeWalkSession {
    enum Phase: Equatable {
        case ready, starting, running, paused, saved
        case unavailable(String)
    }

    private(set) var phase: Phase = .ready
    private(set) var startDate: Date?
    /// Seconds walked before the current stretch, for a walk that was paused.
    private(set) var banked: TimeInterval = 0
    private(set) var resumedAt: Date?
    private(set) var heartRate: Double?
    private(set) var heartSeries: [Double] = []
    private(set) var distanceMetres: Double?
    private(set) var steps: Double?

    func elapsed(at now: Date) -> TimeInterval {
        banked + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

#if os(iOS) && canImport(HealthKit)
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var relay: Relay?

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            phase = .unavailable("This device has no Health store, so a walk cannot be recorded here.")
            return
        }
        phase = .starting
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.stepCount),
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                phase = .unavailable("Soma may not save workouts to Apple Health. Allow it in Health, Sharing, Apps, Soma, and start again.")
                return
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .walking
            configuration.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            let relay = Relay(owner: self)
            builder.delegate = relay
            self.session = session
            self.builder = builder
            self.relay = relay
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            startDate = now
            resumedAt = now
            phase = .running
        } catch {
            phase = .unavailable("The walk could not start: \(error.localizedDescription)")
        }
    }

    func pause() {
        guard phase == .running else { return }
        session?.pause()
        banked = elapsed(at: Date())
        resumedAt = nil
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        session?.resume()
        resumedAt = Date()
        phase = .running
    }

    func end() async {
        guard let session, let builder else { return }
        let now = Date()
        banked = elapsed(at: now)
        resumedAt = nil
        session.end()
        do {
            try await builder.endCollection(at: now)
            _ = try await builder.finishWorkout()
            phase = .saved
        } catch {
            phase = .unavailable("The walk ended but could not be saved: \(error.localizedDescription)")
        }
    }

    fileprivate func collected(heart: Double?, distance: Double?, steps: Double?) {
        if let heart {
            heartRate = heart
            heartSeries.append(heart)
        }
        if let distance { distanceMetres = distance }
        if let steps { self.steps = steps }
    }

    /// Hands the builder's readings to the main actor as plain numbers.
    private final class Relay: NSObject, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
        weak var owner: HomeWalkSession?

        init(owner: HomeWalkSession) { self.owner = owner }

        nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

        nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
            let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
                .mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let distance = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter())
            let steps = workoutBuilder.statistics(for: HKQuantityType(.stepCount))?
                .sumQuantity()?.doubleValue(for: .count())
            Task { @MainActor [weak self] in
                self?.owner?.collected(heart: heart, distance: distance, steps: steps)
            }
        }
    }
#else
    func start() async {
        phase = .unavailable("A walk is recorded on iPhone or Apple Watch. This device cannot run a live session.")
    }

    func pause() {}
    func resume() {}
    func end() async {}
#endif
}
