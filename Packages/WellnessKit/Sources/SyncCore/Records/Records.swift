import Foundation

/// A value that syncs. Its canonical JSON encoding is its payload.
public protocol SyncRecord: Codable, Sendable, Equatable {
    static var recordType: RecordType { get }
    var id: RecordID { get }
}

/// Local table layout shared by every record type.
public enum SyncTable {
    /// The `CREATE TABLE` statement for a record type. Kits add generated
    /// columns and indexes on `payload` in later migrations of their own.
    public static func createStatement(for type: RecordType) -> String {
        """
        CREATE TABLE "\(type.rawValue)" (
            id TEXT PRIMARY KEY NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            local_version INTEGER NOT NULL DEFAULT 0,
            server_revision INTEGER,
            deleted INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER,
            updated_at INTEGER NOT NULL
        );
        """
    }
}

/// Tables owned by the foundation itself.
public enum CoreSchema {
    public static let moduleName = "SyncCore"

    public static let migrations: [Migration] = [
        Migration(module: moduleName, version: 1, sql: version1),
    ]

    static let version1 = """
        CREATE TABLE sync_outbox (
            record_type TEXT NOT NULL,
            record_id TEXT NOT NULL,
            local_version INTEGER NOT NULL,
            enqueued_at INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL,
            last_error TEXT,
            frozen INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (record_type, record_id)
        );
        CREATE INDEX sync_outbox_due ON sync_outbox (record_type, frozen, next_attempt_at);

        CREATE TABLE sync_cursor (
            record_type TEXT PRIMARY KEY NOT NULL,
            revision INTEGER NOT NULL
        );

        CREATE TABLE quarantine (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            module TEXT NOT NULL,
            table_name TEXT NOT NULL,
            row_json TEXT NOT NULL,
            error TEXT NOT NULL,
            quarantined_at INTEGER NOT NULL
        );

        CREATE TABLE upload_journal (
            key TEXT PRIMARY KEY NOT NULL,
            stream TEXT NOT NULL,
            file_path TEXT NOT NULL,
            byte_count INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            content_type TEXT NOT NULL,
            state TEXT NOT NULL CHECK (state IN ('queued', 'sending', 'confirmed', 'failed')),
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL,
            sending_since INTEGER,
            created_at INTEGER NOT NULL,
            confirmed_at INTEGER,
            last_error TEXT
        );
        CREATE INDEX upload_journal_due ON upload_journal (state, next_attempt_at);

        CREATE TABLE export_cursor (
            stream TEXT PRIMARY KEY NOT NULL,
            committed_position BLOB,
            staged_position BLOB,
            staged_keys TEXT
        );
        """
}
