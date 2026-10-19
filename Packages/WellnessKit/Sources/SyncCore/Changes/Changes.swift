import Foundation
import Synchronization

/// Where a change came from.
public enum ChangeOrigin: Sendable, Hashable {
    /// Produced on this device: a local write, a local failure, an auth event.
    case local
    /// Applied from the server: pulled records, conflict resolutions.
    case remote
}

/// One observable change. Always a value, never a live database object.
public enum Change: Sendable, Hashable {
    case recordSaved(RecordType, RecordID)
    case recordDeleted(RecordType, RecordID)
    case rowQuarantined(table: String, reason: String)
    /// A local change lost a conflict. `discarded` is the local payload that was
    /// dropped, or `nil` when the discarded change was a deletion.
    case conflictResolved(RecordType, RecordID, discarded: RecordPayload?)
    case pushRejected(RecordType, RecordID, reason: String)
    case uploadFailed(key: String, reason: String)
    case storeRebuilt(lostUnsentChanges: Int?)
    case authRequired
    case authMismatch
}

/// The changes of one committed transaction, or one out-of-transaction event.
public struct ChangeBatch: Sendable, Hashable {
    public let origin: ChangeOrigin
    public let changes: [Change]

    public init(origin: ChangeOrigin, changes: [Change]) {
        self.origin = origin
        self.changes = changes
    }
}

/// Fans change batches out to any number of `AsyncStream` subscribers.
/// Streams buffer without limit so no subscriber ever misses a batch.
public final class ChangeBroadcaster: Sendable {
    private struct State {
        var continuations: [UInt64: AsyncStream<ChangeBatch>.Continuation] = [:]
        var nextID: UInt64 = 0
        var finished = false
    }

    private let state = Mutex(State())

    public init() {}

    public func stream() -> AsyncStream<ChangeBatch> {
        let (stream, continuation) = AsyncStream<ChangeBatch>.makeStream(bufferingPolicy: .unbounded)
        let registered = state.withLock { state -> UInt64? in
            guard !state.finished else { return nil }
            state.nextID += 1
            state.continuations[state.nextID] = continuation
            return state.nextID
        }
        guard let id = registered else {
            continuation.finish()
            return stream
        }
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        return stream
    }

    public func publish(_ batch: ChangeBatch) {
        guard !batch.changes.isEmpty else { return }
        let targets = state.withLock { Array($0.continuations.values) }
        for continuation in targets { continuation.yield(batch) }
    }

    public func finish() {
        let targets = state.withLock { state -> [AsyncStream<ChangeBatch>.Continuation] in
            state.finished = true
            let all = Array(state.continuations.values)
            state.continuations.removeAll()
            return all
        }
        for continuation in targets { continuation.finish() }
    }

    private func remove(_ id: UInt64) {
        state.withLock { state in
            state.continuations[id] = nil
        }
    }
}
