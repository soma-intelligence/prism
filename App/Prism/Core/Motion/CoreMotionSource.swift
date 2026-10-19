//
//  CoreMotionSource.swift
//  Prism
//

#if canImport(CoreMotion) && os(iOS)
import CoreMotion
import Foundation

/// The iPhone's own step counter and activity classifier, read through Core
/// Motion with the Motion & Fitness permission. No watch needed.
///
/// Core Motion's objects are not `Sendable`. They are created here, used only
/// through their own thread safe calls, and every value they hand back is
/// copied into a plain struct inside the handler, before it crosses anywhere.
nonisolated final class CoreMotionSource: PhoneMotionSource, @unchecked Sendable {
    private let pedometerReader = CMPedometer()
    private let activityReader = CMMotionActivityManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Soma.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    var authorization: MotionAuthorization {
        guard isAvailable else { return .unavailable }
        switch CMPedometer.authorizationStatus() {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .notDetermined
        }
    }

    /// The question appears when the app first reads the step counter, so
    /// asking is a read of the last minute whose answer is thrown away.
    func requestAccess() async {
        guard authorization == .notDetermined else { return }
        let now = Date()
        _ = try? await pedometer(from: now.addingTimeInterval(-60), to: now)
    }

    func pedometer(from start: Date, to end: Date) async throws -> PedometerDay? {
        guard isAvailable else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            pedometerReader.queryPedometerData(from: start, to: end) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data.map(Self.day))
                }
            }
        }
    }

    func activities(from start: Date, to end: Date) async throws -> [MotionActivitySample] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            activityReader.queryActivityStarting(from: start, to: end, to: queue) { activities, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (activities ?? []).map(Self.sample))
                }
            }
        }
    }

    func pedometerUpdates(from start: Date) -> AsyncStream<PedometerDay> {
        AsyncStream { continuation in
            guard isAvailable else {
                continuation.finish()
                return
            }
            pedometerReader.startUpdates(from: start) { data, _ in
                if let data { continuation.yield(Self.day(data)) }
            }
            continuation.onTermination = { _ in self.pedometerReader.stopUpdates() }
        }
    }

    func activityUpdates() -> AsyncStream<MotionActivitySample> {
        AsyncStream { continuation in
            guard CMMotionActivityManager.isActivityAvailable() else {
                continuation.finish()
                return
            }
            activityReader.startActivityUpdates(to: queue) { activity in
                if let activity { continuation.yield(Self.sample(activity)) }
            }
            continuation.onTermination = { _ in self.activityReader.stopActivityUpdates() }
        }
    }

    // MARK: - Copying out

    private static func day(_ data: CMPedometerData) -> PedometerDay {
        PedometerDay(
            start: data.startDate,
            end: data.endDate,
            steps: data.numberOfSteps.doubleValue,
            distance: data.distance?.doubleValue,
            floorsAscended: data.floorsAscended?.doubleValue,
            floorsDescended: data.floorsDescended?.doubleValue,
            cadence: data.currentCadence?.doubleValue,
            pace: data.averageActivePace?.doubleValue ?? data.currentPace?.doubleValue
        )
    }

    private static func sample(_ activity: CMMotionActivity) -> MotionActivitySample {
        let confidence: MotionConfidence = switch activity.confidence {
        case .low: .low
        case .medium: .medium
        case .high: .high
        @unknown default: .low
        }
        return MotionActivitySample(
            start: activity.startDate,
            kind: MotionActivityKind.from(
                stationary: activity.stationary,
                walking: activity.walking,
                running: activity.running,
                cycling: activity.cycling,
                automotive: activity.automotive
            ),
            confidence: confidence
        )
    }
}
#endif
