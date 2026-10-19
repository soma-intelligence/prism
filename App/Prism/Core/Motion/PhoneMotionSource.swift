//
//  PhoneMotionSource.swift
//  Prism
//

import Foundation
import Synchronization

/// What `PhoneMotion` reads from: Core Motion on an iPhone, a fixture in the
/// tests and the Simulator, nothing on a Mac or a headset.
nonisolated protocol PhoneMotionSource: Sendable {
    /// False when the device has no step counter.
    var isAvailable: Bool { get }

    var authorization: MotionAuthorization { get }

    /// Puts the Motion & Fitness question to the person, if it has no answer
    /// yet. Returns once it has one.
    func requestAccess() async

    /// What the phone counted between two dates, or nil when it holds nothing.
    /// Core Motion keeps seven days.
    func pedometer(from start: Date, to end: Date) async throws -> PedometerDay?

    /// The activity changes between two dates, oldest first.
    func activities(from start: Date, to end: Date) async throws -> [MotionActivitySample]

    /// Live counts since `start`, each one cumulative.
    func pedometerUpdates(from start: Date) -> AsyncStream<PedometerDay>

    /// Live activity changes.
    func activityUpdates() -> AsyncStream<MotionActivitySample>
}

/// A device with no step counter, or a launch that must not ask anything.
nonisolated struct UnavailableMotionSource: PhoneMotionSource {
    var isAvailable: Bool { false }
    var authorization: MotionAuthorization { .unavailable }
    func requestAccess() async {}
    func pedometer(from start: Date, to end: Date) async throws -> PedometerDay? { nil }
    func activities(from start: Date, to end: Date) async throws -> [MotionActivitySample] { [] }
    func pedometerUpdates(from start: Date) -> AsyncStream<PedometerDay> { AsyncStream { $0.finish() } }
    func activityUpdates() -> AsyncStream<MotionActivitySample> { AsyncStream { $0.finish() } }
}

/// A phone with steps and activity written in advance.
///
/// The tests drive `PhoneMotion` with it, and the Simulator, which has no
/// motion hardware, shows its sample day. It starts unanswered when asked to,
/// so a test can watch the question being put.
nonisolated final class PhoneMotionFixtureSource: PhoneMotionSource {
    private struct State {
        var authorization: MotionAuthorization
        var accessRequests = 0
    }

    private let state: Mutex<State>
    let days: [PedometerDay]
    let samples: [MotionActivitySample]
    let live: [PedometerDay]

    init(
        authorization: MotionAuthorization = .authorized,
        days: [PedometerDay] = [],
        samples: [MotionActivitySample] = [],
        live: [PedometerDay] = []
    ) {
        state = Mutex(State(authorization: authorization))
        self.days = days
        self.samples = samples
        self.live = live
    }

    var isAvailable: Bool { true }

    var authorization: MotionAuthorization { state.withLock { $0.authorization } }

    /// How many times the question was put.
    var accessRequests: Int { state.withLock { $0.accessRequests } }

    func requestAccess() async {
        state.withLock { state in
            guard state.authorization == .notDetermined else { return }
            state.accessRequests += 1
            state.authorization = .authorized
        }
    }

    /// The days that start inside the range, added up.
    func pedometer(from start: Date, to end: Date) async throws -> PedometerDay? {
        guard authorization == .authorized else { return nil }
        let inside = days.filter { $0.start >= start && $0.start < end }
        guard let first = inside.first else { return nil }
        func sum(_ value: (PedometerDay) -> Double?) -> Double? {
            let present = inside.compactMap(value)
            return present.isEmpty ? nil : present.reduce(0, +)
        }
        return PedometerDay(
            start: first.start,
            end: inside.map(\.end).max() ?? end,
            steps: inside.reduce(0) { $0 + $1.steps },
            distance: sum(\.distance),
            floorsAscended: sum(\.floorsAscended),
            floorsDescended: sum(\.floorsDescended),
            cadence: inside.count == 1 ? first.cadence : nil,
            pace: inside.count == 1 ? first.pace : nil
        )
    }

    func activities(from start: Date, to end: Date) async throws -> [MotionActivitySample] {
        guard authorization == .authorized else { return [] }
        return samples.filter { $0.start >= start && $0.start < end }
    }

    func pedometerUpdates(from start: Date) -> AsyncStream<PedometerDay> {
        let live = authorization == .authorized ? self.live : []
        return AsyncStream { continuation in
            for day in live { continuation.yield(day) }
            continuation.finish()
        }
    }

    func activityUpdates() -> AsyncStream<MotionActivitySample> { AsyncStream { $0.finish() } }
}

extension PhoneMotionFixtureSource {
    /// A plausible week for the Simulator: today so far, and six days before,
    /// with a morning walk, a drive and an evening run on the timeline.
    static func sampleWeek(now: Date = .now, calendar: Calendar = .current) -> PhoneMotionFixtureSource {
        let today = calendar.startOfDay(for: now)
        let totals: [Double] = [8_420, 11_903, 6_210, 9_874, 12_456, 4_980]
        var days: [PedometerDay] = totals.enumerated().compactMap { offset, steps in
            guard let start = calendar.date(byAdding: .day, value: -(offset + 1), to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return PedometerDay(
                start: start, end: end, steps: steps, distance: steps * 0.74,
                floorsAscended: (steps / 1_200).rounded(), floorsDescended: (steps / 1_300).rounded()
            )
        }
        let elapsed = now.timeIntervalSince(today)
        let soFar = (elapsed / 86_400 * 9_000).rounded()
        days.append(PedometerDay(
            start: today, end: now, steps: soFar, distance: soFar * 0.74,
            floorsAscended: (soFar / 1_200).rounded(), floorsDescended: (soFar / 1_300).rounded(),
            cadence: 1.8, pace: 0.78
        ))

        func at(_ hour: Double) -> Date { today.addingTimeInterval(hour * 3_600) }
        let plan: [(Double, MotionActivityKind)] = [
            (7, .stationary), (7.5, .walking), (8, .automotive), (8.5, .stationary),
            (12.5, .walking), (13, .stationary), (18, .running), (18.6, .walking), (18.8, .stationary),
        ]
        let samples = plan
            .map { MotionActivitySample(start: at($0.0), kind: $0.1, confidence: .high) }
            .filter { $0.start <= now }
        return PhoneMotionFixtureSource(days: days, samples: samples)
    }
}
