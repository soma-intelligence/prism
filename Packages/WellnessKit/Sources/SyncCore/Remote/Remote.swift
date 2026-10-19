import Foundation

/// Every failure of a remote call, classified once.
public enum RemoteError: Error, Sendable, Hashable {
    case offline
    case timeout
    /// 5xx, 408, 425, 429 and transport failures worth retrying.
    case transient(status: Int?, retryAfter: Duration?)
    case unauthorized
    case forbidden
    /// Any other 4xx. Permanent for this request.
    case rejected(status: Int, reason: String)
    /// The server dropped tombstones newer than the cursor. Resync from scratch.
    case cursorExpired
    case malformedResponse(String)
    /// The calling task was cancelled.
    case cancelled
}

public struct OutgoingChange: Sendable, Hashable {
    public let id: RecordID
    /// The last server revision this device saw, `nil` before the first push.
    public let baseRevision: Revision?
    public let deleted: Bool
    public let payload: RecordPayload

    public init(id: RecordID, baseRevision: Revision?, deleted: Bool, payload: RecordPayload) {
        self.id = id
        self.baseRevision = baseRevision
        self.deleted = deleted
        self.payload = payload
    }
}

public struct RemoteRecord: Sendable, Hashable {
    public let id: RecordID
    public let revision: Revision
    public let deleted: Bool
    /// Always present for a live record. May be absent for a tombstone.
    public let payload: RecordPayload?

    public init(id: RecordID, revision: Revision, deleted: Bool, payload: RecordPayload?) {
        self.id = id
        self.revision = revision
        self.deleted = deleted
        self.payload = payload
    }
}

public enum PushOutcome: Sendable, Hashable {
    case applied(RecordID, Revision)
    case conflict(RecordID, RemoteRecord)
    case rejected(RecordID, reason: String)

    public var id: RecordID {
        switch self {
        case .applied(let id, _), .conflict(let id, _), .rejected(let id, _): return id
        }
    }
}

public struct PullPage: Sendable, Hashable {
    /// Ordered by revision, tombstones included.
    public let records: [RemoteRecord]
    public let hasMore: Bool

    public init(records: [RemoteRecord], hasMore: Bool) {
        self.records = records
        self.hasMore = hasMore
    }
}

/// The server side of record sync. Every implementation must behave like
/// `ScriptedRecordServer`:
/// - a change is written only when the server revision equals its base
///   (a missing record matches a `nil` base), and receives a new revision
///   from one sequence shared by every record type;
/// - a change whose payload and deleted flag equal the current record is
///   `applied` at the current revision, whatever its base;
/// - otherwise the answer is `conflict` with the current record, or a
///   tombstone at revision 0 when the record does not exist;
/// - pull returns records with a revision above `after`, in revision order,
///   and throws `cursorExpired` when tombstones newer than `after` were purged,
///   except while `resyncing`: a full resync pages from the start and prunes at
///   the end, so it must never be told its own page cursor expired.
public protocol RemoteRecordStore: Sendable {
    func push(_ changes: [OutgoingChange], type: RecordType, token: AccessToken) async throws(RemoteError) -> [PushOutcome]
    func pull(_ type: RecordType, after revision: Revision?, limit: Int, resyncing: Bool, token: AccessToken) async throws(RemoteError) -> PullPage
}

/// Object storage for one-way uploads. `put` overwrites an existing key.
public protocol RemoteObjectStore: Sendable {
    func put(key: String, file: URL, sha256: String, contentType: String, token: AccessToken) async throws(RemoteError)
}

public enum ConflictResolution: Sendable, Hashable {
    /// Restore the server record locally and discard the local change.
    case keepServer
    /// Keep the local change and push it again on top of the server revision.
    case keepLocal
    /// Replace the local payload with this merge and push it on top of the server revision.
    case merged(RecordPayload)
}

public protocol ConflictRule: Sendable {
    func resolve(type: RecordType, local: RecordPayload?, localDeleted: Bool, server: RemoteRecord) -> ConflictResolution
}

/// The default rule: the server wins.
public struct ServerWins: ConflictRule {
    public init() {}

    public func resolve(type: RecordType, local: RecordPayload?, localDeleted: Bool, server: RemoteRecord) -> ConflictResolution {
        .keepServer
    }
}
