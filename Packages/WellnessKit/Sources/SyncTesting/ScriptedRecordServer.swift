import Foundation
import Synchronization
import SyncCore

public struct StoredRecord: Sendable, Hashable, Codable {
    public var revision: Int64
    public var deleted: Bool
    public var payloadJSON: String?
}

public struct ServerSnapshot: Sendable, Codable {
    public var tables: [String: [String: StoredRecord]]
    public var revision: Int64
    public var horizon: [String: Int64]
}

/// The reference implementation of `RemoteRecordStore`, with scriptable faults.
public actor ScriptedRecordServer: RemoteRecordStore {
    public enum Fault: Sendable, Hashable {
        /// Fail the next call before doing anything.
        case fail(RemoteError)
        /// Perform the next push, then fail as if the response was lost.
        case applyThenFail(RemoteError)
    }

    private var tables: [String: [String: StoredRecord]] = [:]
    private var revision: Int64 = 0
    private var horizon: [String: Int64] = [:]
    private var faults: [Fault] = []
    private var rejectedIDs: Set<RecordID> = []

    public private(set) var pushCalls = 0
    public private(set) var pullCalls = 0
    public private(set) var tokensSeen: [String] = []

    public init() {}

    public init(snapshot: ServerSnapshot) {
        tables = snapshot.tables
        revision = snapshot.revision
        horizon = snapshot.horizon
    }

    public func snapshot() -> ServerSnapshot {
        ServerSnapshot(tables: tables, revision: revision, horizon: horizon)
    }

    public func script(_ faults: [Fault]) {
        self.faults.append(contentsOf: faults)
    }

    public func clearFaults() {
        faults.removeAll()
    }

    public func reject(ids: Set<RecordID>) {
        rejectedIDs.formUnion(ids)
    }

    // MARK: Contract

    public func push(_ changes: [OutgoingChange], type: RecordType, token: AccessToken) async throws(RemoteError) -> [PushOutcome] {
        pushCalls += 1
        tokensSeen.append(token.value)
        let fault = faults.isEmpty ? nil : faults.removeFirst()
        if case .fail(let error) = fault { throw error }
        let outcomes = changes.map { apply($0, type: type.rawValue) }
        if case .applyThenFail(let error) = fault { throw error }
        return outcomes
    }

    public func pull(_ type: RecordType, after revision: Revision?, limit: Int, resyncing: Bool, token: AccessToken) async throws(RemoteError) -> PullPage {
        pullCalls += 1
        tokensSeen.append(token.value)
        if !faults.isEmpty {
            switch faults.removeFirst() {
            case .fail(let error), .applyThenFail(let error): throw error
            }
        }
        let after = revision?.rawValue ?? 0
        if !resyncing, revision != nil, after < (horizon[type.rawValue] ?? 0) {
            throw .cursorExpired
        }
        let newer = (tables[type.rawValue] ?? [:])
            .filter { $0.value.revision > after }
            .sorted { $0.value.revision < $1.value.revision }
        let page = newer.prefix(limit).map { remoteRecord(id: $0.key, stored: $0.value) }
        return PullPage(records: page, hasMore: newer.count > limit)
    }

    // MARK: Test controls

    /// Writes as another device would, bypassing compare-and-set.
    @discardableResult
    public func serverWrite(type: RecordType, id: RecordID, payload: RecordPayload, deleted: Bool = false) -> Revision {
        revision += 1
        tables[type.rawValue, default: [:]][id.rawValue] = StoredRecord(revision: revision, deleted: deleted, payloadJSON: payload.text)
        return Revision(revision)
    }

    /// Removes every tombstone of `type` and records the highest removed revision.
    public func purgeTombstones(type: RecordType) {
        let table = tables[type.rawValue] ?? [:]
        let removed = table.filter { $0.value.deleted }
        guard let highest = removed.map(\.value.revision).max() else { return }
        for id in removed.keys { tables[type.rawValue]?[id] = nil }
        horizon[type.rawValue] = max(horizon[type.rawValue] ?? 0, highest)
    }

    public func record(type: RecordType, id: RecordID) -> StoredRecord? {
        tables[type.rawValue]?[id.rawValue]
    }

    public func liveRecords(type: RecordType) -> [RecordID: RecordPayload] {
        var result: [RecordID: RecordPayload] = [:]
        for (id, stored) in tables[type.rawValue] ?? [:] where !stored.deleted {
            if let json = stored.payloadJSON {
                result[RecordID(id)] = RecordPayload(canonicalJSON: Data(json.utf8))
            }
        }
        return result
    }

    public var currentRevision: Int64 { revision }

    // MARK: Compare and set

    private func apply(_ change: OutgoingChange, type: String) -> PushOutcome {
        if rejectedIDs.contains(change.id) {
            return .rejected(change.id, reason: "rejected by script")
        }
        let incoming = change.payload.text
        guard let current = tables[type]?[change.id.rawValue] else {
            if change.baseRevision != nil {
                return .conflict(change.id, RemoteRecord(id: change.id, revision: Revision(0), deleted: true, payload: nil))
            }
            revision += 1
            tables[type, default: [:]][change.id.rawValue] = StoredRecord(revision: revision, deleted: change.deleted, payloadJSON: incoming)
            return .applied(change.id, Revision(revision))
        }
        if change.baseRevision?.rawValue == current.revision {
            revision += 1
            tables[type]?[change.id.rawValue] = StoredRecord(revision: revision, deleted: change.deleted, payloadJSON: incoming)
            return .applied(change.id, Revision(revision))
        }
        if current.deleted == change.deleted, current.payloadJSON == incoming {
            return .applied(change.id, Revision(current.revision))
        }
        return .conflict(change.id, remoteRecord(id: change.id.rawValue, stored: current))
    }

    private func remoteRecord(id: String, stored: StoredRecord) -> RemoteRecord {
        RemoteRecord(
            id: RecordID(id),
            revision: Revision(stored.revision),
            deleted: stored.deleted,
            payload: stored.payloadJSON.map { RecordPayload(canonicalJSON: Data($0.utf8)) }
        )
    }
}

/// Wraps a record store and runs a hook after each push returns from the inner
/// store, before the push result reaches the caller.
public final class HookedRecordStore: RemoteRecordStore {
    private let inner: any RemoteRecordStore
    private let afterPush: @Sendable (Int) async -> Void
    private let calls = Mutex(0)

    public init(inner: any RemoteRecordStore, afterPush: @escaping @Sendable (Int) async -> Void) {
        self.inner = inner
        self.afterPush = afterPush
    }

    public func push(_ changes: [OutgoingChange], type: RecordType, token: AccessToken) async throws(RemoteError) -> [PushOutcome] {
        let outcomes = try await inner.push(changes, type: type, token: token)
        let call = calls.withLock { calls -> Int in
            calls += 1
            return calls
        }
        await afterPush(call)
        return outcomes
    }

    public func pull(_ type: RecordType, after revision: Revision?, limit: Int, resyncing: Bool, token: AccessToken) async throws(RemoteError) -> PullPage {
        try await inner.pull(type, after: revision, limit: limit, resyncing: resyncing, token: token)
    }
}
