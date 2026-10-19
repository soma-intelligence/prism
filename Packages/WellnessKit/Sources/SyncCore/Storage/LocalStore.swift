import Foundation
import os
import SQLite3
import Synchronization

/// One schema step owned by a module. Versions are applied in order, once.
public struct Migration: Sendable, Hashable {
    public let module: String
    public let version: Int
    public let sql: String

    public init(module: String, version: Int, sql: String) {
        self.module = module
        self.version = version
        self.sql = sql
    }
}

public enum StoreError: Error, Sendable, Hashable {
    case cannotCreateDirectory(path: String, reason: String)
    case cannotOpen(SQLiteError)
    case migrationFailed(module: String, version: Int, reason: String)
    /// The store is failed or closed and refuses work.
    case unavailable(reason: String)
    case sqlite(SQLiteError)
    /// The operation met a corrupt database. The store moved it aside and
    /// rebuilt an empty one. Retry the operation.
    case rebuiltAfterCorruption
}

/// Sees every write transaction just before its `COMMIT`. Production passes none.
public protocol TransactionObserver: Sendable {
    func willCommit(label: String)
}

/// Names of the transactions the foundation runs.
public enum TransactionLabel {
    public static let repositorySave = "repository.save"
    public static let repositoryDelete = "repository.delete"
    public static let quarantine = "repository.quarantine"
    public static let outboxBackoff = "sync.outbox.backoff"
    public static let outboxFreeze = "sync.outbox.freeze"
    public static let outboxOrphans = "sync.outbox.orphans"
    public static let outboxRetryFrozen = "sync.outbox.retry-frozen"
    public static let pushApply = "sync.push.apply"
    public static let pullApply = "sync.pull.apply"
    public static let cursorReset = "sync.cursor.reset"
    public static let resyncPrune = "sync.resync.prune"
    public static let journalStage = "uploads.stage"
    public static let journalSending = "uploads.sending"
    public static let journalConfirm = "uploads.confirm"
    public static let journalFailure = "uploads.failure"
    public static let journalCommit = "uploads.commit"
}

/// A write transaction. Only valid inside the `LocalStore.write` closure.
public final class Transaction: SQLQuerying {
    private let connection: SQLiteConnection
    public let now: Instant
    private(set) var changes: [Change] = []

    init(connection: SQLiteConnection, now: Instant) {
        self.connection = connection
        self.now = now
    }

    @discardableResult
    public func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteError) -> Int {
        try connection.run(sql, bindings)
    }

    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteError) -> [Row] {
        try connection.query(sql, bindings)
    }

    /// Records a change, published after the transaction commits.
    public func record(_ change: Change) {
        changes.append(change)
    }
}

/// A read snapshot. Only valid inside the `LocalStore.read` closure.
public final class ReadContext: SQLQuerying {
    private let connection: SQLiteConnection

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteError) -> [Row] {
        try connection.query(sql, bindings)
    }
}

/// Reader connections, each behind its own lock. Reads run on the caller's thread.
final class ReaderPool: Sendable {
    /// `Mutex` is not copyable, so each lock lives in its own reference.
    private final class Slot: Sendable {
        let connection = Mutex<SQLiteConnection?>(nil)
    }

    private let slots: [Slot]

    init(count: Int) {
        slots = (0..<count).map { _ in Slot() }
    }

    func open(path: String) throws(SQLiteError) {
        for slot in slots {
            try slot.connection.withLock { connection throws(SQLiteError) in
                connection?.close()
                connection = nil
                let reader = try SQLiteConnection(path: path)
                try reader.execute("PRAGMA query_only=ON; PRAGMA busy_timeout=5000")
                connection = reader
            }
        }
    }

    func closeAll() {
        for slot in slots {
            slot.connection.withLock { connection in
                connection?.close()
                connection = nil
            }
        }
    }

    func read<T: Sendable>(_ body: (ReadContext) throws -> T) throws -> T {
        for slot in slots {
            let attempt = slot.connection.withLockIfAvailable { connection -> Result<T, any Error> in
                Result { try Self.snapshotRead(connection, body) }
            }
            if let attempt { return try attempt.get() }
        }
        return try slots[0].connection.withLock { connection -> Result<T, any Error> in
            Result { try Self.snapshotRead(connection, body) }
        }.get()
    }

    private static func snapshotRead<T>(_ connection: SQLiteConnection?, _ body: (ReadContext) throws -> T) throws -> T {
        guard let connection else { throw SQLiteError.closed(nil) }
        try connection.execute("BEGIN")
        defer { _ = connection.executeReturningCode("COMMIT") }
        return try body(ReadContext(connection: connection))
    }
}

/// One SQLite database for one user: a write connection owned by this actor
/// and two reader connections for concurrent snapshot reads.
public actor LocalStore {
    public enum State: Sendable, Hashable {
        case ready
        case failed(StoreError)
        case closed
    }

    public struct RebuildReport: Sendable, Hashable {
        public let movedTo: URL
        /// Outbox entries in the moved file, or `nil` when it could not be read.
        public let lostUnsentChanges: Int?
    }

    public static let fileName = "store.sqlite"

    public nonisolated let directory: URL
    public nonisolated let databaseURL: URL
    public private(set) var state: State
    public private(set) var lastRebuild: RebuildReport?

    private var writer: SQLiteConnection?
    private nonisolated let readers = ReaderPool(count: 2)
    private let migrations: [Migration]
    private let clock: any SyncClock
    private let changes: ChangeBroadcaster
    private let observer: (any TransactionObserver)?
    private let logger: Logger

    private enum OpenFailure: Error {
        case corruption(SQLiteError)
        case migration(StoreError)
        case open(SQLiteError)
    }

    public init(
        directory: URL,
        migrations: [Migration],
        clock: any SyncClock,
        changes: ChangeBroadcaster,
        observer: (any TransactionObserver)? = nil,
        logger: Logger = Logger(subsystem: "WellnessKit", category: "store")
    ) throws(StoreError) {
        self.directory = directory
        self.databaseURL = directory.appendingPathComponent(Self.fileName)
        self.migrations = migrations
        self.clock = clock
        self.changes = changes
        self.observer = observer
        self.logger = logger
        self.state = .closed

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: Self.protectionAttributes
            )
        } catch {
            throw .cannotCreateDirectory(path: directory.path, reason: String(describing: error))
        }

        var rebuild: RebuildReport?
        var opened: SQLiteConnection?
        do {
            opened = try Self.openAndMigrate(databaseURL: databaseURL, readers: readers, migrations: migrations, now: clock.now())
        } catch {
            switch error {
            case .corruption:
                rebuild = Self.moveAside(databaseURL: databaseURL, now: clock.now(), logger: logger)
                do {
                    opened = try Self.openAndMigrate(databaseURL: databaseURL, readers: readers, migrations: migrations, now: clock.now())
                } catch {
                    switch error {
                    case .corruption(let sqlite), .open(let sqlite): throw .cannotOpen(sqlite)
                    case .migration(let failure): state = .failed(failure)
                    }
                }
            case .open(let sqlite):
                throw .cannotOpen(sqlite)
            case .migration(let failure):
                state = .failed(failure)
            }
        }

        if let opened {
            writer = opened
            state = .ready
        }
        if let rebuild {
            lastRebuild = rebuild
            changes.publish(ChangeBatch(origin: .local, changes: [.storeRebuilt(lostUnsentChanges: rebuild.lostUnsentChanges)]))
        }
    }

    /// Runs `body` in one `BEGIN IMMEDIATE` transaction. Changes recorded by the
    /// body are published as one batch after `COMMIT`. A thrown error rolls back.
    @discardableResult
    public func write<T: Sendable>(
        label: String,
        origin: ChangeOrigin = .local,
        _ body: @Sendable (Transaction) throws -> T
    ) throws -> T {
        guard state == .ready, let writer else {
            throw StoreError.unavailable(reason: String(describing: state))
        }
        do {
            try writer.execute("BEGIN IMMEDIATE")
        } catch {
            throw failure(error)
        }
        let transaction = Transaction(connection: writer, now: clock.now())
        let value: T
        do {
            value = try body(transaction)
            observer?.willCommit(label: label)
            try writer.execute("COMMIT")
        } catch {
            let code = writer.executeReturningCode("ROLLBACK")
            if code != SQLITE_OK {
                logger.error("rollback after failed transaction \(label, privacy: .public) returned \(code)")
            }
            if let sqlite = error as? SQLiteError { throw failure(sqlite) }
            throw error
        }
        changes.publish(ChangeBatch(origin: origin, changes: transaction.changes))
        return value
    }

    /// Runs `body` on a reader connection inside one snapshot. Synchronous and
    /// not isolated to the actor, so reads never wait behind writes.
    public nonisolated func read<T: Sendable>(_ body: (ReadContext) throws -> T) throws -> T {
        do {
            return try readers.read(body)
        } catch let error as SQLiteError {
            if error.code == SQLITE_MISUSE {
                throw StoreError.unavailable(reason: "store is not open")
            }
            if error.isCorruption {
                Task { await self.rebuildAfterReaderCorruption() }
            }
            throw StoreError.sqlite(error)
        }
    }

    public func close() {
        writer?.close()
        writer = nil
        readers.closeAll()
        if state == .ready { state = .closed }
    }

    // MARK: Opening and rebuilding

    private func failure(_ error: SQLiteError) -> StoreError {
        guard error.isCorruption else { return .sqlite(error) }
        rebuild()
        return .rebuiltAfterCorruption
    }

    private func rebuildAfterReaderCorruption() {
        guard state == .ready else { return }
        rebuild()
    }

    private func rebuild() {
        writer?.close()
        writer = nil
        readers.closeAll()
        let report = Self.moveAside(databaseURL: databaseURL, now: clock.now(), logger: logger)
        do {
            writer = try Self.openAndMigrate(databaseURL: databaseURL, readers: readers, migrations: migrations, now: clock.now())
            state = .ready
        } catch {
            switch error {
            case .migration(let failure): state = .failed(failure)
            case .corruption(let sqlite), .open(let sqlite): state = .failed(.cannotOpen(sqlite))
            }
        }
        lastRebuild = report
        changes.publish(ChangeBatch(origin: .local, changes: [.storeRebuilt(lostUnsentChanges: report.lostUnsentChanges)]))
    }

    private static func openAndMigrate(
        databaseURL: URL,
        readers: ReaderPool,
        migrations: [Migration],
        now: Instant
    ) throws(OpenFailure) -> SQLiteConnection {
        let writer: SQLiteConnection
        do {
            writer = try SQLiteConnection(path: databaseURL.path)
            try writer.execute("PRAGMA journal_mode=WAL")
            try writer.execute("PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000")
            try writer.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations (module TEXT NOT NULL, version INTEGER NOT NULL, applied_at INTEGER NOT NULL, PRIMARY KEY (module, version))"
            )
        } catch {
            throw error.isCorruption ? .corruption(error) : .open(error)
        }

        for migration in migrations {
            do {
                let applied = try writer.query(
                    "SELECT 1 FROM schema_migrations WHERE module = ? AND version = ?",
                    [.text(migration.module), .integer(Int64(migration.version))]
                )
                if !applied.isEmpty { continue }
                try writer.execute("BEGIN IMMEDIATE")
                try writer.execute(migration.sql)
                try writer.run(
                    "INSERT INTO schema_migrations (module, version, applied_at) VALUES (?, ?, ?)",
                    [.text(migration.module), .integer(Int64(migration.version)), .integer(now.millisecondsSinceEpoch)]
                )
                try writer.execute("COMMIT")
            } catch {
                _ = writer.executeReturningCode("ROLLBACK")
                if error.isCorruption {
                    writer.close()
                    throw .corruption(error)
                }
                writer.close()
                throw .migration(.migrationFailed(module: migration.module, version: migration.version, reason: error.message))
            }
        }

        do {
            try readers.open(path: databaseURL.path)
        } catch {
            writer.close()
            throw error.isCorruption ? .corruption(error) : .open(error)
        }
        return writer
    }

    private static func moveAside(databaseURL: URL, now: Instant, logger: Logger) -> RebuildReport {
        let manager = FileManager.default
        let stem = databaseURL.deletingPathExtension().lastPathComponent
        let target = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("\(stem).corrupt-\(now.millisecondsSinceEpoch).sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            guard manager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: target.path + suffix)
            do {
                try manager.moveItem(at: source, to: destination)
            } catch {
                logger.error("cannot move \(source.path, privacy: .public) aside: \(String(describing: error), privacy: .public)")
                do {
                    try manager.removeItem(at: source)
                } catch {
                    logger.error("cannot remove \(source.path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
        return RebuildReport(movedTo: target, lostUnsentChanges: countOutbox(at: target))
    }

    private static func countOutbox(at url: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let connection = try SQLiteConnection(path: url.path)
            defer { connection.close() }
            let rows = try connection.query("SELECT COUNT(*) AS n FROM sync_outbox")
            return rows.first?["n"].int64Value.map(Int.init)
        } catch {
            return nil
        }
    }

    static var protectionAttributes: [FileAttributeKey: Any]? {
        #if os(iOS) || os(visionOS)
        return [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        return nil
        #endif
    }
}
