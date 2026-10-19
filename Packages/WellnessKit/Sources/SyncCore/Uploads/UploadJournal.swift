import CryptoKit
import Foundation
import os

public struct FileDigest: Sendable, Hashable {
    public let sha256: String
    public let byteCount: Int64

    public init(sha256: String, byteCount: Int64) {
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public enum OutgoingFile {
    /// Flushes `url` to disk and returns its SHA-256 and size, reading 1 MiB at a time.
    public static func seal(_ url: URL) throws -> FileDigest {
        let handle = try FileHandle(forUpdating: url)
        try handle.synchronize()
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        var count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            count += Int64(chunk.count)
        }
        try handle.close()
        return FileDigest(sha256: hex(hasher.finalize()), byteCount: count)
    }

    static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        let digits = Array("0123456789abcdef")
        var text = ""
        for byte in bytes {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }
}

public enum ObjectKey {
    /// `{prefix}/{userID}/{stream}/{windowStart}_{windowEnd}_{first 12 hex of sha256}.{fileExtension}`.
    /// The same bytes always get the same key; different bytes never share one.
    public static func make(
        prefix: String,
        userID: UserID,
        stream: String,
        windowStart: String,
        windowEnd: String,
        sha256: String,
        fileExtension: String
    ) -> String {
        "\(prefix)/\(userID.rawValue)/\(stream)/\(windowStart)_\(windowEnd)_\(sha256.prefix(12)).\(fileExtension)"
    }
}

public struct ObjectToStage: Sendable, Hashable {
    public let key: String
    public let temporaryFile: URL
    public let digest: FileDigest
    public let contentType: String

    public init(key: String, temporaryFile: URL, digest: FileDigest, contentType: String) {
        self.key = key
        self.temporaryFile = temporaryFile
        self.digest = digest
        self.contentType = contentType
    }
}

public enum StagingError: Error, Sendable, Hashable {
    case stepAlreadyStaged(stream: String)
    /// Staging would exceed the outgoing cap. Pause the producer and retry later.
    case diskCapExceeded(pendingBytes: Int64, capBytes: Int64)
}

public struct StagedStep: Sendable, Hashable {
    public let position: Data
    public let keys: [String]
}

public struct JournalEntry: Sendable, Hashable {
    public let key: String
    public let stream: String
    public let state: String
    public let attempts: Int
    public let nextAttemptAt: Int64
}

public struct UploadReport: Sendable, Hashable {
    public var confirmed = 0
    public var failed = 0
    public var committedStreams: [String] = []
    public var stoppedBy: SyncInterruption?
    public var deferred: [String] = []

    public init() {}
}

/// Sends files to object storage and moves a producer's position only when
/// every object of its staged step is confirmed.
public actor UploadJournal {
    public nonisolated let outgoingDirectory: URL
    public nonisolated let temporaryDirectory: URL
    private nonisolated let store: LocalStore
    private let remote: any RemoteObjectStore
    private let tokens: TokenGate
    private let policy: RetryPolicy
    private let clock: any SyncClock
    private let random: any RandomSource
    private let changes: ChangeBroadcaster
    private let capBytes: Int64
    private let sendingTimeout: Duration
    private let logger: Logger

    private struct DueEntry: Sendable {
        let key: String
        let filePath: String
        let sha256: String
        let contentType: String
        let attempts: Int
    }

    public init(
        store: LocalStore,
        directory: URL,
        remote: any RemoteObjectStore,
        tokens: TokenGate,
        policy: RetryPolicy = .standard,
        clock: any SyncClock,
        random: any RandomSource,
        changes: ChangeBroadcaster,
        capBytes: Int64 = 200_000_000,
        sendingTimeout: Duration = .seconds(900),
        logger: Logger = Logger(subsystem: "WellnessKit", category: "uploads")
    ) throws {
        self.store = store
        self.outgoingDirectory = directory
        self.temporaryDirectory = directory.appendingPathComponent("tmp", isDirectory: true)
        self.remote = remote
        self.tokens = tokens
        self.policy = policy
        self.clock = clock
        self.random = random
        self.changes = changes
        self.capBytes = capBytes
        self.sendingTimeout = sendingTimeout
        self.logger = logger
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: LocalStore.protectionAttributes)
    }

    /// A fresh file location for a producer to write into before staging.
    public nonisolated func makeTemporaryFile() -> URL {
        temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    // MARK: Staging

    public func stage(stream: String, objects: [ObjectToStage], position: Data) async throws {
        if try stagedStep(stream: stream) != nil {
            throw StagingError.stepAlreadyStaged(stream: stream)
        }
        let pending = try store.read { context in
            try context.query(
                "SELECT COALESCE(SUM(byte_count), 0) AS total FROM upload_journal WHERE state IN ('queued', 'sending', 'failed')",
                []
            ).first?["total"].int64Value ?? 0
        }
        let incoming = objects.reduce(Int64(0)) { $0 + $1.digest.byteCount }
        guard pending + incoming <= capBytes else {
            throw StagingError.diskCapExceeded(pendingBytes: pending, capBytes: capBytes)
        }

        var placed: [(ObjectToStage, String)] = []
        let manager = FileManager.default
        for object in objects {
            let destination = outgoingDirectory.appendingPathComponent(Self.fileName(for: object.key))
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.moveItem(at: object.temporaryFile, to: destination)
            placed.append((object, destination.path))
        }
        let items = placed
        let keysJSON = String(decoding: try JSONSerialization.data(withJSONObject: objects.map(\.key)), as: UTF8.self)

        try await store.write(label: TransactionLabel.journalStage) { transaction in
            let now = transaction.now.millisecondsSinceEpoch
            for (object, path) in items {
                try transaction.run(
                    """
                    INSERT INTO upload_journal (key, stream, file_path, byte_count, sha256, content_type, state, attempts, next_attempt_at, sending_since, created_at, confirmed_at, last_error)
                    VALUES (?, ?, ?, ?, ?, ?, 'queued', 0, ?, NULL, ?, NULL, NULL)
                    ON CONFLICT (key) DO UPDATE SET
                        state = CASE WHEN upload_journal.state = 'confirmed' THEN 'confirmed' ELSE 'queued' END,
                        stream = excluded.stream,
                        file_path = excluded.file_path,
                        byte_count = excluded.byte_count,
                        sha256 = excluded.sha256,
                        content_type = excluded.content_type,
                        attempts = 0,
                        next_attempt_at = excluded.next_attempt_at,
                        sending_since = NULL,
                        last_error = NULL
                    """,
                    [
                        .text(object.key), .text(stream), .text(path), .integer(object.digest.byteCount),
                        .text(object.digest.sha256), .text(object.contentType), .integer(now), .integer(now),
                    ]
                )
            }
            try transaction.run(
                """
                INSERT INTO export_cursor (stream, committed_position, staged_position, staged_keys) VALUES (?, NULL, ?, ?)
                ON CONFLICT (stream) DO UPDATE SET staged_position = excluded.staged_position, staged_keys = excluded.staged_keys
                """,
                [.text(stream), .blob(position), .text(keysJSON)]
            )
        }
    }

    public nonisolated func committedPosition(stream: String) throws -> Data? {
        try store.read { context in
            try context.query("SELECT committed_position FROM export_cursor WHERE stream = ?", [.text(stream)])
                .first?.optionalData("committed_position")
        }
    }

    public nonisolated func stagedStep(stream: String) throws -> StagedStep? {
        let row = try store.read { context in
            try context.query("SELECT staged_position, staged_keys FROM export_cursor WHERE stream = ?", [.text(stream)]).first
        }
        guard let row, let position = try row.optionalData("staged_position") else { return nil }
        return StagedStep(position: position, keys: try Self.decodeKeys(try row.optionalString("staged_keys") ?? "[]"))
    }

    public nonisolated func entries(stream: String) throws -> [JournalEntry] {
        try store.read { context in
            try context.query(
                "SELECT key, stream, state, attempts, next_attempt_at FROM upload_journal WHERE stream = ? ORDER BY created_at, key",
                [.text(stream)]
            ).map { row in
                JournalEntry(
                    key: try row.string("key"),
                    stream: try row.string("stream"),
                    state: try row.string("state"),
                    attempts: Int(try row.int64("attempts")),
                    nextAttemptAt: try row.int64("next_attempt_at")
                )
            }
        }
    }

    // MARK: Sending

    public func send(limit: Int = 50) async -> UploadReport {
        var report = UploadReport()
        var attempted = Set<String>()
        do {
            report.committedStreams += try await commitCompletedSteps()
            while true {
                let now = clock.now()
                let staleBefore = now.adding(.zero - sendingTimeout)
                let due = try store.read { context in
                    try Self.loadDue(context, now: now, staleBefore: staleBefore, limit: limit)
                }.filter { !attempted.contains($0.key) }
                if due.isEmpty { break }
                for entry in due {
                    if Task.isCancelled { throw SyncInterruption.cancelled }
                    attempted.insert(entry.key)
                    try await upload(entry, report: &report)
                }
                report.committedStreams += try await commitCompletedSteps()
            }
        } catch let interruption as SyncInterruption {
            report.stoppedBy = interruption
            switch interruption {
            case .authRequired: changes.publish(ChangeBatch(origin: .local, changes: [.authRequired]))
            case .authMismatch: changes.publish(ChangeBatch(origin: .local, changes: [.authMismatch]))
            case .offline, .circuitOpen, .cancelled: break
            }
        } catch {
            report.deferred.append(String(describing: error))
        }
        return report
    }

    private static func loadDue(_ context: some SQLQuerying, now: Instant, staleBefore: Instant, limit: Int) throws -> [DueEntry] {
        try context.query(
            """
            SELECT key, file_path, sha256, content_type, attempts FROM upload_journal
            WHERE (state = 'queued' AND next_attempt_at <= ?) OR (state = 'sending' AND sending_since <= ?)
            ORDER BY created_at, key
            LIMIT ?
            """,
            [.integer(now.millisecondsSinceEpoch), .integer(staleBefore.millisecondsSinceEpoch), .integer(Int64(limit))]
        ).map { row in
            DueEntry(
                key: try row.string("key"),
                filePath: try row.string("file_path"),
                sha256: try row.string("sha256"),
                contentType: try row.string("content_type"),
                attempts: Int(try row.int64("attempts"))
            )
        }
    }

    private func upload(_ entry: DueEntry, report: inout UploadReport) async throws {
        let file = URL(fileURLWithPath: entry.filePath)
        guard FileManager.default.fileExists(atPath: file.path) else {
            try await markFailed(entry.key, reason: "file missing: \(entry.filePath)")
            report.failed += 1
            return
        }
        let key = entry.key
        try await store.write(label: TransactionLabel.journalSending) { transaction in
            try transaction.run(
                "UPDATE upload_journal SET state = 'sending', sending_since = ? WHERE key = ?",
                [.integer(transaction.now.millisecondsSinceEpoch), .text(key)]
            )
        }
        let remote = self.remote
        do {
            try await tokens.perform { token throws(RemoteError) in
                try await remote.put(key: entry.key, file: file, sha256: entry.sha256, contentType: entry.contentType, token: token)
            }
        } catch {
            switch error {
            case .interrupted(let interruption):
                try await requeue(key, consumeAttempt: false, delay: .zero, reason: nil)
                throw interruption
            case .remote(let remoteError):
                switch policy.disposition(for: remoteError, attempt: entry.attempts + 1, random: random) {
                case .waitForNetwork:
                    try await requeue(key, consumeAttempt: false, delay: .zero, reason: nil)
                    throw SyncInterruption.offline
                case .stop:
                    try await requeue(key, consumeAttempt: false, delay: .zero, reason: nil)
                    throw SyncInterruption.cancelled
                case .reauthenticate:
                    try await requeue(key, consumeAttempt: false, delay: .zero, reason: nil)
                    throw SyncInterruption.authRequired
                case .freeze(let reason):
                    try await markFailed(key, reason: reason)
                    report.failed += 1
                case .retryLater(let delay):
                    try await requeue(key, consumeAttempt: true, delay: delay, reason: String(describing: remoteError))
                    report.deferred.append("\(key): \(remoteError)")
                case .restartFromScratch:
                    try await requeue(key, consumeAttempt: true, delay: policy.baseDelay, reason: String(describing: remoteError))
                    report.deferred.append("\(key): \(remoteError)")
                }
                return
            }
        }
        try await store.write(label: TransactionLabel.journalConfirm) { transaction in
            try transaction.run(
                "UPDATE upload_journal SET state = 'confirmed', confirmed_at = ?, sending_since = NULL, last_error = NULL WHERE key = ?",
                [.integer(transaction.now.millisecondsSinceEpoch), .text(key)]
            )
        }
        report.confirmed += 1
    }

    private func requeue(_ key: String, consumeAttempt: Bool, delay: Duration, reason: String?) async throws {
        try await store.write(label: TransactionLabel.journalFailure) { transaction in
            try transaction.run(
                "UPDATE upload_journal SET state = 'queued', sending_since = NULL, attempts = attempts + ?, next_attempt_at = ?, last_error = COALESCE(?, last_error) WHERE key = ?",
                [
                    .integer(consumeAttempt ? 1 : 0),
                    .integer(transaction.now.adding(delay).millisecondsSinceEpoch),
                    reason.map { .text($0) } ?? .null,
                    .text(key),
                ]
            )
        }
    }

    private func markFailed(_ key: String, reason: String) async throws {
        try await store.write(label: TransactionLabel.journalFailure) { transaction in
            try transaction.run(
                "UPDATE upload_journal SET state = 'failed', sending_since = NULL, attempts = attempts + 1, last_error = ? WHERE key = ?",
                [.text(reason), .text(key)]
            )
            transaction.record(.uploadFailed(key: key, reason: reason))
        }
    }

    // MARK: Committing

    private func commitCompletedSteps() async throws -> [String] {
        let candidates: [(stream: String, keys: [String])] = try store.read { context in
            try context.query("SELECT stream, staged_keys FROM export_cursor WHERE staged_position IS NOT NULL", []).map { row in
                (try row.string("stream"), try Self.decodeKeys(try row.optionalString("staged_keys") ?? "[]"))
            }
        }
        var committed: [String] = []
        for candidate in candidates {
            let keys = Array(Set(candidate.keys))
            let complete = try store.read { context in
                try keys.allSatisfy { key in
                    try context.query("SELECT state FROM upload_journal WHERE key = ?", [.text(key)]).first?["state"] == .text("confirmed")
                }
            }
            guard complete else { continue }
            let stream = candidate.stream
            let files = try await store.write(label: TransactionLabel.journalCommit) { transaction -> [String] in
                var paths: [String] = []
                for key in keys {
                    if let path = try transaction.query("SELECT file_path FROM upload_journal WHERE key = ? AND state = 'confirmed'", [.text(key)]).first?["file_path"].stringValue {
                        paths.append(path)
                    }
                }
                try transaction.run(
                    "UPDATE export_cursor SET committed_position = staged_position, staged_position = NULL, staged_keys = NULL WHERE stream = ? AND staged_position IS NOT NULL",
                    [.text(stream)]
                )
                return paths
            }
            for path in files where FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    logger.error("cannot delete sent file \(path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            committed.append(stream)
        }
        return committed
    }

    // MARK: Housekeeping

    /// Deletes files that no queued, sending or failed entry refers to, and every
    /// temporary file. Call only when no producer is writing, such as at session open.
    public func removeOrphans() async throws -> Int {
        let referenced = Set(try store.read { context in
            try context.query("SELECT file_path FROM upload_journal WHERE state IN ('queued', 'sending', 'failed')", []).map {
                URL(fileURLWithPath: try $0.string("file_path")).lastPathComponent
            }
        })
        let manager = FileManager.default
        var removed = 0
        for url in try manager.contentsOfDirectory(at: outgoingDirectory, includingPropertiesForKeys: nil)
        where url.lastPathComponent != temporaryDirectory.lastPathComponent && !referenced.contains(url.lastPathComponent) {
            try manager.removeItem(at: url)
            removed += 1
        }
        for url in try manager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil) {
            try manager.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    static func fileName(for key: String) -> String {
        OutgoingFile.hex(SHA256.hash(data: Data(key.utf8))) + ".upload"
    }

    static func decodeKeys(_ json: String) throws -> [String] {
        guard let keys = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String] else {
            throw RecordCodingError("staged keys are not a string array")
        }
        return keys
    }
}
