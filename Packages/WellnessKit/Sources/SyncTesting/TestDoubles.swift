import Foundation
import Synchronization
import SyncCore

/// A clock that only moves when a test moves it.
public final class ManualClock: SyncClock {
    private struct Sleeper {
        let id: UInt64
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Instant
        var sleepers: [Sleeper] = []
        var nextID: UInt64 = 0
    }

    private let state: Mutex<State>

    public init(now: Instant = Instant(millisecondsSinceEpoch: 1_800_000_000_000)) {
        state = Mutex(State(now: now))
    }

    public func now() -> Instant { state.withLock { $0.now } }

    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    public func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.adding(duration)
            return Self.takeDue(&state)
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    public func set(_ instant: Instant) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = instant
            return Self.takeDue(&state)
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    public func sleep(for duration: Duration) async throws {
        let id = state.withLock { state -> UInt64 in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Immediate { case wait, resume, cancel }
                let immediate = state.withLock { state -> Immediate in
                    if Task.isCancelled { return .cancel }
                    let deadline = state.now.adding(duration)
                    if deadline <= state.now { return .resume }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .wait
                }
                switch immediate {
                case .wait: break
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    private static func takeDue(_ state: inout State) -> [Sleeper] {
        let now = state.now
        let due = state.sleepers.filter { $0.deadline <= now }
        state.sleepers.removeAll { $0.deadline <= now }
        return due
    }
}

/// Readable, ordered identifiers: `prefix-000001`, `prefix-000002`.
public final class SequentialIDs: IDGenerator {
    private let counter = Mutex(0)
    private let prefix: String

    public init(prefix: String = "id") { self.prefix = prefix }

    public func next() -> RecordID {
        let value = counter.withLock { counter -> Int in
            counter += 1
            return counter
        }
        let digits = String(value)
        return RecordID("\(prefix)-\(String(repeating: "0", count: max(0, 6 - digits.count)))\(digits)")
    }
}

/// SplitMix64. Deterministic for a given seed.
public final class SeededRandom: RandomSource {
    private let state: Mutex<UInt64>

    public init(seed: UInt64) { state = Mutex(seed) }

    public func nextUInt64() -> UInt64 {
        state.withLock { state -> UInt64 in
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    public func unitInterval() -> Double {
        Double(nextUInt64() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A value in `0..<bound`.
    public func int(below bound: Int) -> Int {
        precondition(bound > 0)
        return Int(nextUInt64() % UInt64(bound))
    }
}

/// Always returns the same value.
public struct FixedRandom: RandomSource {
    public let value: Double
    public init(_ value: Double) { self.value = value }
    public func unitInterval() -> Double { value }
}

/// A unique directory under the system temporary directory.
public struct TemporaryDirectory: Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wellnesskit-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func remove() {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("TemporaryDirectory: could not remove \(url.path): \(error)")
        }
    }
}

/// Polls `condition` until it holds or `timeout` of real time passes.
public func eventually(
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        await Task.yield()
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            return await condition()
        }
    }
    return await condition()
}
