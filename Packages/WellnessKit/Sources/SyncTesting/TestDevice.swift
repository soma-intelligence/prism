import Foundation
import SyncCore

public struct OutboxEntrySnapshot: Sendable, Hashable {
    public let attempts: Int
    public let nextAttemptAt: Int64
    public let frozen: Bool
    public let lastError: String?
}

/// One device of one user: a store with the test note table, a token gate and a sync agent.
public struct TestDevice: Sendable {
    public let directory: URL
    public let changes: ChangeBroadcaster
    public let store: LocalStore
    public let notes: RecordRepository<TestNote>
    public let tokens: ScriptedTokenProvider
    public let gate: TokenGate
    public let agent: SyncAgent

    public static func open(
        directory: URL,
        remote: any RemoteRecordStore,
        clock: any SyncClock,
        user: UserID = UserID("user-a"),
        tokens: ScriptedTokenProvider? = nil,
        random: any RandomSource = FixedRandom(0.5),
        policy: RetryPolicy = .standard,
        observer: (any TransactionObserver)? = nil,
        conflictRules: [RecordType: any ConflictRule] = [:],
        pushBatchSize: Int = 100,
        pullPageSize: Int = 500
    ) throws -> TestDevice {
        let changes = ChangeBroadcaster()
        let store = try TestSchema.openStore(at: directory, clock: clock, changes: changes, observer: observer)
        let provider = tokens ?? ScriptedTokenProvider(userID: user)
        let gate = TokenGate(provider: provider, userID: user, clock: clock)
        let agent = SyncAgent(
            store: store,
            remote: remote,
            tokens: gate,
            recordTypes: TestSchema.recordTypes,
            policy: policy,
            clock: clock,
            random: random,
            changes: changes,
            conflictRules: conflictRules,
            pushBatchSize: pushBatchSize,
            pullPageSize: pullPageSize
        )
        return TestDevice(
            directory: directory,
            changes: changes,
            store: store,
            notes: RecordRepository(store: store),
            tokens: provider,
            gate: gate,
            agent: agent
        )
    }

    public func close() async {
        await store.close()
    }

    public func outboxCount() throws -> Int {
        try count("SELECT COUNT(*) AS n FROM sync_outbox")
    }

    public func frozenCount() throws -> Int {
        try count("SELECT COUNT(*) AS n FROM sync_outbox WHERE frozen = 1")
    }

    public func quarantineCount() throws -> Int {
        try count("SELECT COUNT(*) AS n FROM quarantine")
    }

    public func outboxEntry(_ id: RecordID) throws -> OutboxEntrySnapshot? {
        try store.read { context in
            let rows = try context.query(
                "SELECT attempts, next_attempt_at, frozen, last_error FROM sync_outbox WHERE record_id = ?",
                [.text(id.rawValue)]
            )
            guard let row = rows.first else { return nil }
            return OutboxEntrySnapshot(
                attempts: Int(try row.int64("attempts")),
                nextAttemptAt: try row.int64("next_attempt_at"),
                frozen: try row.bool("frozen"),
                lastError: try row.optionalString("last_error")
            )
        }
    }

    public func cursor() throws -> Revision? {
        try store.read { context in
            try context.query("SELECT revision FROM sync_cursor WHERE record_type = ?", [.text(TestNote.recordType.rawValue)])
                .first?["revision"].int64Value.map { Revision($0) }
        }
    }

    /// Payloads of live rows, keyed by id.
    public func liveRows() throws -> [RecordID: RecordPayload] {
        try store.read { context in
            var result: [RecordID: RecordPayload] = [:]
            for row in try context.query("SELECT id, payload FROM test_note WHERE deleted = 0", []) {
                result[RecordID(try row.string("id"))] = RecordPayload(canonicalJSON: Data(try row.string("payload").utf8))
            }
            return result
        }
    }

    private func count(_ sql: String) throws -> Int {
        try store.read { context in
            Int(try context.query(sql, []).first?["n"].int64Value ?? 0)
        }
    }
}
