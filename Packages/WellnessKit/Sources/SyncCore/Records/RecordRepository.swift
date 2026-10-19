import Foundation

/// Outbox writes, always inside the transaction of the change they describe.
enum Outbox {
    static func enqueue(_ transaction: Transaction, type: RecordType, id: RecordID) throws(SQLiteError) {
        let rows = try transaction.query(
            "SELECT local_version FROM \"\(type.rawValue)\" WHERE id = ?",
            [.text(id.rawValue)]
        )
        guard let version = rows.first?["local_version"].int64Value else { return }
        let now = transaction.now.millisecondsSinceEpoch
        try transaction.run(
            """
            INSERT INTO sync_outbox (record_type, record_id, local_version, enqueued_at, attempts, next_attempt_at, last_error, frozen)
            VALUES (?, ?, ?, ?, 0, ?, NULL, 0)
            ON CONFLICT (record_type, record_id) DO UPDATE SET
                local_version = excluded.local_version,
                attempts = 0,
                next_attempt_at = excluded.next_attempt_at,
                last_error = NULL,
                frozen = 0
            """,
            [.text(type.rawValue), .text(id.rawValue), .integer(version), .integer(now), .integer(now)]
        )
    }
}

/// Reads and writes one record type. Every write enqueues its outbox entry in
/// the same transaction; every read quarantines rows it cannot decode.
public struct RecordRepository<Record: SyncRecord>: Sendable {
    public let store: LocalStore

    public init(store: LocalStore) {
        self.store = store
    }

    private static var table: String { "\"\(Record.recordType.rawValue)\"" }

    public func save(_ record: Record) async throws {
        try await save([record])
    }

    public func save(_ records: [Record]) async throws {
        guard !records.isEmpty else { return }
        var encoded: [(id: RecordID, text: String)] = []
        for record in records {
            encoded.append((record.id, try RecordPayload(encoding: record).text))
        }
        let items = encoded
        let type = Record.recordType
        let table = Self.table
        try await store.write(label: TransactionLabel.repositorySave) { transaction in
            for item in items {
                try transaction.run(
                    """
                    INSERT INTO \(table) (id, payload, local_version, server_revision, deleted, deleted_at, updated_at)
                    VALUES (?, ?, 1, NULL, 0, NULL, ?)
                    ON CONFLICT (id) DO UPDATE SET
                        payload = excluded.payload,
                        local_version = local_version + 1,
                        deleted = 0,
                        deleted_at = NULL,
                        updated_at = excluded.updated_at
                    """,
                    [.text(item.id.rawValue), .text(item.text), .integer(transaction.now.millisecondsSinceEpoch)]
                )
                try Outbox.enqueue(transaction, type: type, id: item.id)
                transaction.record(.recordSaved(type, item.id))
            }
        }
    }

    public func delete(_ id: RecordID) async throws {
        let type = Record.recordType
        let table = Self.table
        try await store.write(label: TransactionLabel.repositoryDelete) { transaction in
            let now = transaction.now.millisecondsSinceEpoch
            let changed = try transaction.run(
                "UPDATE \(table) SET deleted = 1, deleted_at = ?, local_version = local_version + 1, updated_at = ? WHERE id = ? AND deleted = 0",
                [.integer(now), .integer(now), .text(id.rawValue)]
            )
            guard changed > 0 else { return }
            try Outbox.enqueue(transaction, type: type, id: id)
            transaction.record(.recordDeleted(type, id))
        }
    }

    public func fetch(_ id: RecordID) async throws -> Record? {
        let table = Self.table
        let rows = try store.read { context in
            try context.query("SELECT * FROM \(table) WHERE id = ? AND deleted = 0", [.text(id.rawValue)])
        }
        return try await decode(rows).first
    }

    public func fetchAll() async throws -> [Record] {
        let table = Self.table
        let rows = try store.read { context in
            try context.query("SELECT * FROM \(table) WHERE deleted = 0 ORDER BY id", [])
        }
        return try await decode(rows)
    }

    /// Outbox entries of this record type, frozen ones included.
    public func pendingChangeCount() async throws -> Int {
        let type = Record.recordType
        return try store.read { context in
            let rows = try context.query("SELECT COUNT(*) AS n FROM sync_outbox WHERE record_type = ?", [.text(type.rawValue)])
            return Int(rows.first?["n"].int64Value ?? 0)
        }
    }

    // MARK: Decoding and quarantine

    private struct Failure: Sendable {
        let id: String?
        let rowJSON: String
        let reason: String
    }

    private func decode(_ rows: [Row]) async throws -> [Record] {
        var records: [Record] = []
        var failures: [Failure] = []
        for row in rows {
            do {
                let id = try row.string("id")
                let payload = RecordPayload(canonicalJSON: Data(try row.string("payload").utf8))
                let record = try payload.decode(Record.self)
                guard record.id.rawValue == id else {
                    throw RecordCodingError("payload id \(record.id) differs from row id \(id)")
                }
                records.append(record)
            } catch {
                failures.append(Failure(id: row["id"].stringValue, rowJSON: row.jsonString(), reason: String(describing: error)))
            }
        }
        if !failures.isEmpty {
            try await quarantine(failures)
        }
        return records
    }

    private func quarantine(_ failures: [Failure]) async throws {
        let type = Record.recordType
        let table = Self.table
        try await store.write(label: TransactionLabel.quarantine) { transaction in
            for failure in failures {
                try transaction.run(
                    "INSERT INTO quarantine (module, table_name, row_json, error, quarantined_at) VALUES (?, ?, ?, ?, ?)",
                    [.text(CoreSchema.moduleName), .text(type.rawValue), .text(failure.rowJSON), .text(failure.reason), .integer(transaction.now.millisecondsSinceEpoch)]
                )
                if let id = failure.id {
                    try transaction.run("DELETE FROM \(table) WHERE id = ?", [.text(id)])
                    try transaction.run(
                        "DELETE FROM sync_outbox WHERE record_type = ? AND record_id = ?",
                        [.text(type.rawValue), .text(id)]
                    )
                }
                transaction.record(.rowQuarantined(table: type.rawValue, reason: failure.reason))
            }
        }
    }
}
