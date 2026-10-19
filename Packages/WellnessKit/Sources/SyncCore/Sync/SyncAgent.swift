import Foundation

/// What one sync run did.
public struct SyncReport: Sendable, Hashable {
    public var pushedChanges = 0
    public var pulledRecords = 0
    public var conflicts = 0
    public var rejected = 0
    public var stoppedBy: SyncInterruption?
    /// Retryable problems that postponed part of the work to a later run.
    public var deferred: [String] = []

    public init() {}
}

struct LocalRow: Sendable {
    let id: RecordID
    let payload: RecordPayload
    let localVersion: Int64
    let serverRevision: Revision?
    let deleted: Bool
}

struct PendingEntry: Sendable {
    let id: RecordID
    let attempts: Int
    let row: LocalRow?
}

/// Pushes the outbox and pulls server changes for one user, one run at a time.
public actor SyncAgent {
    public nonisolated let recordTypes: [RecordType]
    private let store: LocalStore
    private let remote: any RemoteRecordStore
    private let tokens: TokenGate
    private let policy: RetryPolicy
    private let clock: any SyncClock
    private let random: any RandomSource
    private let changes: ChangeBroadcaster
    private let conflictRules: [RecordType: any ConflictRule]
    private let pushBatchSize: Int
    private let pullPageSize: Int
    private var breaker: CircuitBreaker
    private var running: Task<SyncReport, Never>?

    public init(
        store: LocalStore,
        remote: any RemoteRecordStore,
        tokens: TokenGate,
        recordTypes: [RecordType],
        policy: RetryPolicy = .standard,
        clock: any SyncClock,
        random: any RandomSource,
        changes: ChangeBroadcaster,
        conflictRules: [RecordType: any ConflictRule] = [:],
        pushBatchSize: Int = 100,
        pullPageSize: Int = 500
    ) {
        self.store = store
        self.remote = remote
        self.tokens = tokens
        self.recordTypes = recordTypes
        self.policy = policy
        self.clock = clock
        self.random = random
        self.changes = changes
        self.conflictRules = conflictRules
        self.pushBatchSize = pushBatchSize
        self.pullPageSize = pullPageSize
        self.breaker = CircuitBreaker(threshold: policy.breakerThreshold)
    }

    /// When the circuit breaker is open, the instant it closes.
    public var circuitOpenUntil: Instant? {
        breaker.isOpen(at: clock.now()) ? breaker.openUntil : nil
    }

    /// Pushes every record type, then pulls every record type. A call made
    /// while a run is in progress waits for that run and returns its report.
    public func sync() async -> SyncReport {
        if let running { return await running.value }
        let task = Task { await self.run() }
        running = task
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func run() async -> SyncReport {
        defer { running = nil }
        var report = SyncReport()
        if let until = circuitOpenUntil {
            report.stoppedBy = .circuitOpen(until: until)
            return report
        }
        do {
            for type in recordTypes { try await push(type, report: &report) }
            for type in recordTypes { try await pull(type, report: &report) }
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

    // MARK: Push

    private func push(_ type: RecordType, report: inout SyncReport) async throws {
        let table = Self.table(type)
        while true {
            if Task.isCancelled { throw SyncInterruption.cancelled }
            let now = clock.now()
            let limit = pushBatchSize
            let pending = try store.read { context in
                try Self.loadDue(context, type: type, table: table, now: now, limit: limit)
            }
            if pending.isEmpty { return }

            let orphans = pending.filter { $0.row == nil }.map(\.id)
            if !orphans.isEmpty { try await removeOrphans(orphans, type: type) }
            let sent: [(PendingEntry, LocalRow)] = pending.compactMap { entry in entry.row.map { (entry, $0) } }
            if sent.isEmpty { continue }
            if let until = circuitOpenUntil { throw SyncInterruption.circuitOpen(until: until) }

            let outgoing = sent.map {
                OutgoingChange(id: $0.1.id, baseRevision: $0.1.serverRevision, deleted: $0.1.deleted, payload: $0.1.payload)
            }
            let remote = self.remote
            let outcomes: [PushOutcome]
            do {
                outcomes = try await tokens.perform { token throws(RemoteError) in
                    try await remote.push(outgoing, type: type, token: token)
                }
            } catch {
                switch error {
                case .interrupted(let interruption):
                    throw interruption
                case .remote(let remoteError):
                    if try await deferOrFreeze(remoteError, entries: sent.map(\.0), type: type, report: &report) { return }
                    continue
                }
            }
            breaker.recordSuccess()
            try await apply(outcomes, sent: sent, type: type, table: table, report: &report)
        }
    }

    static func loadDue(_ context: some SQLQuerying, type: RecordType, table: String, now: Instant, limit: Int) throws -> [PendingEntry] {
        let rows = try context.query(
            """
            SELECT o.record_id, o.attempts, t.id AS row_id, t.payload, t.local_version, t.server_revision, t.deleted
            FROM sync_outbox o LEFT JOIN \(table) t ON t.id = o.record_id
            WHERE o.record_type = ? AND o.frozen = 0 AND o.next_attempt_at <= ?
            ORDER BY o.enqueued_at, o.record_id
            LIMIT ?
            """,
            [.text(type.rawValue), .integer(now.millisecondsSinceEpoch), .integer(Int64(limit))]
        )
        return try rows.map { row in
            let id = RecordID(try row.string("record_id"))
            var local: LocalRow?
            if case .text = row["row_id"] {
                local = LocalRow(
                    id: id,
                    payload: RecordPayload(canonicalJSON: Data(try row.string("payload").utf8)),
                    localVersion: try row.int64("local_version"),
                    serverRevision: try row.optionalInt64("server_revision").map { Revision($0) },
                    deleted: try row.bool("deleted")
                )
            }
            return PendingEntry(id: id, attempts: Int(try row.int64("attempts")), row: local)
        }
    }

    private func removeOrphans(_ ids: [RecordID], type: RecordType) async throws {
        try await store.write(label: TransactionLabel.outboxOrphans) { transaction in
            for id in ids {
                try transaction.run(
                    "DELETE FROM sync_outbox WHERE record_type = ? AND record_id = ?",
                    [.text(type.rawValue), .text(id.rawValue)]
                )
            }
        }
    }

    /// Records a failed push. Returns `true` when this record type waits for a later run.
    private func deferOrFreeze(_ error: RemoteError, entries: [PendingEntry], type: RecordType, report: inout SyncReport) async throws -> Bool {
        let attempt = (entries.map(\.attempts).max() ?? 0) + 1
        let disposition = policy.disposition(for: error, attempt: attempt, random: random)
        let ids = entries.map(\.id)
        switch disposition {
        case .waitForNetwork:
            throw SyncInterruption.offline
        case .stop:
            throw SyncInterruption.cancelled
        case .reauthenticate:
            throw SyncInterruption.authRequired
        case .freeze(let reason):
            try await store.write(label: TransactionLabel.outboxFreeze) { transaction in
                for id in ids {
                    try transaction.run(
                        "UPDATE sync_outbox SET frozen = 1, attempts = attempts + 1, last_error = ? WHERE record_type = ? AND record_id = ?",
                        [.text(reason), .text(type.rawValue), .text(id.rawValue)]
                    )
                    transaction.record(.pushRejected(type, id, reason: reason))
                }
            }
            report.rejected += ids.count
            return false
        case .retryLater, .restartFromScratch:
            let delay: Duration
            if case .retryLater(let value) = disposition { delay = value } else { delay = policy.baseDelay }
            if error.countsTowardBreaker { breaker.recordTransientFailure(now: clock.now(), pause: delay) }
            let message = String(describing: error)
            try await store.write(label: TransactionLabel.outboxBackoff) { transaction in
                for id in ids {
                    try Self.backoff(transaction, type: type, id: id, delay: delay, reason: message)
                }
            }
            report.deferred.append("\(type.rawValue): \(message)")
            return true
        }
    }

    private static func backoff(_ transaction: Transaction, type: RecordType, id: RecordID, delay: Duration, reason: String) throws(SQLiteError) {
        try transaction.run(
            "UPDATE sync_outbox SET attempts = attempts + 1, next_attempt_at = ?, last_error = ? WHERE record_type = ? AND record_id = ? AND frozen = 0",
            [.integer(transaction.now.adding(delay).millisecondsSinceEpoch), .text(reason), .text(type.rawValue), .text(id.rawValue)]
        )
    }

    private struct ApplyCounts: Sendable {
        var pushed = 0
        var conflicts = 0
        var rejected = 0
    }

    private func apply(_ outcomes: [PushOutcome], sent: [(PendingEntry, LocalRow)], type: RecordType, table: String, report: inout SyncReport) async throws {
        var rowsByID: [RecordID: LocalRow] = [:]
        for (_, row) in sent { rowsByID[row.id] = row }
        let sentRows = rowsByID
        let rule = conflictRules[type] ?? ServerWins()
        let answered = Set(outcomes.map(\.id))
        let unanswered = sent.map(\.1.id).filter { !answered.contains($0) }
        let retryDelay = policy.delay(forAttempt: 1, retryAfter: nil, random: random)

        let counts = try await store.write(label: TransactionLabel.pushApply, origin: .remote) { transaction -> ApplyCounts in
            var counts = ApplyCounts()
            let now = transaction.now.millisecondsSinceEpoch
            for outcome in outcomes {
                guard let sentRow = sentRows[outcome.id] else { continue }
                let key: [SQLiteValue] = [.text(type.rawValue), .text(outcome.id.rawValue)]
                switch outcome {
                case .applied(let id, let revision):
                    try transaction.run("UPDATE \(table) SET server_revision = ? WHERE id = ?", [.integer(revision.rawValue), .text(id.rawValue)])
                    try transaction.run(
                        "DELETE FROM sync_outbox WHERE record_type = ? AND record_id = ? AND local_version = ?",
                        key + [.integer(sentRow.localVersion)]
                    )
                    counts.pushed += 1

                case .conflict(let id, let server):
                    counts.conflicts += 1
                    let current = try transaction.query("SELECT local_version FROM \(table) WHERE id = ?", [.text(id.rawValue)])
                    let changedDuringPush = current.first?["local_version"].int64Value != sentRow.localVersion
                    let resolution = rule.resolve(
                        type: type,
                        local: sentRow.deleted ? nil : sentRow.payload,
                        localDeleted: sentRow.deleted,
                        server: server
                    )
                    switch resolution {
                    case .keepServer where changedDuringPush, .keepLocal:
                        try transaction.run("UPDATE \(table) SET server_revision = ? WHERE id = ?", [.integer(server.revision.rawValue), .text(id.rawValue)])
                        try transaction.run("UPDATE sync_outbox SET next_attempt_at = ? WHERE record_type = ? AND record_id = ?", [.integer(now)] + key)
                    case .keepServer:
                        if server.deleted {
                            try transaction.run(
                                "UPDATE \(table) SET deleted = 1, deleted_at = COALESCE(deleted_at, ?), server_revision = ?, updated_at = ? WHERE id = ?",
                                [.integer(now), .integer(server.revision.rawValue), .integer(now), .text(id.rawValue)]
                            )
                        } else if let payload = server.payload {
                            try transaction.run(
                                "UPDATE \(table) SET payload = ?, deleted = 0, deleted_at = NULL, server_revision = ?, updated_at = ? WHERE id = ?",
                                [.text(payload.text), .integer(server.revision.rawValue), .integer(now), .text(id.rawValue)]
                            )
                        } else {
                            try Self.backoff(transaction, type: type, id: id, delay: retryDelay, reason: "live server record without payload")
                            continue
                        }
                        try transaction.run("DELETE FROM sync_outbox WHERE record_type = ? AND record_id = ?", key)
                        transaction.record(.conflictResolved(type, id, discarded: sentRow.deleted ? nil : sentRow.payload))
                        transaction.record(server.deleted ? .recordDeleted(type, id) : .recordSaved(type, id))
                    case .merged(let payload):
                        try transaction.run(
                            "UPDATE \(table) SET payload = ?, deleted = 0, deleted_at = NULL, server_revision = ?, local_version = local_version + 1, updated_at = ? WHERE id = ?",
                            [.text(payload.text), .integer(server.revision.rawValue), .integer(now), .text(id.rawValue)]
                        )
                        try Outbox.enqueue(transaction, type: type, id: id)
                        transaction.record(.recordSaved(type, id))
                    }

                case .rejected(let id, let reason):
                    try transaction.run(
                        "UPDATE sync_outbox SET frozen = 1, attempts = attempts + 1, last_error = ? WHERE record_type = ? AND record_id = ?",
                        [.text(reason)] + key
                    )
                    transaction.record(.pushRejected(type, id, reason: reason))
                    counts.rejected += 1
                }
            }
            for id in unanswered {
                try Self.backoff(transaction, type: type, id: id, delay: retryDelay, reason: "no outcome returned for this change")
            }
            return counts
        }
        report.pushedChanges += counts.pushed
        report.conflicts += counts.conflicts
        report.rejected += counts.rejected
    }

    // MARK: Pull

    private struct PageResult: Sendable {
        var count = 0
        var last: Revision?
    }

    private func pull(_ type: RecordType, report: inout SyncReport) async throws {
        let table = Self.table(type)
        var cursor = try store.read { context in try Self.loadCursor(context, type: type) }
        while true {
            if Task.isCancelled { throw SyncInterruption.cancelled }
            if let until = circuitOpenUntil { throw SyncInterruption.circuitOpen(until: until) }
            guard let page = try await fetchPage(type, after: cursor, resyncing: false, report: &report) else { return }
            breaker.recordSuccess()
            let applied = try await applyPage(page, type: type, table: table)
            report.pulledRecords += applied.count
            guard let last = applied.last else { return }
            cursor = last
            if !page.hasMore { return }
        }
    }

    static func loadCursor(_ context: some SQLQuerying, type: RecordType) throws -> Revision? {
        let rows = try context.query("SELECT revision FROM sync_cursor WHERE record_type = ?", [.text(type.rawValue)])
        return rows.first?["revision"].int64Value.map { Revision($0) }
    }

    /// Fetches one page. Returns `nil` when this record type is postponed.
    private func fetchPage(_ type: RecordType, after cursor: Revision?, resyncing: Bool, report: inout SyncReport) async throws -> PullPage? {
        let remote = self.remote
        let limit = pullPageSize
        do {
            return try await tokens.perform { token throws(RemoteError) in
                try await remote.pull(type, after: cursor, limit: limit, resyncing: resyncing, token: token)
            }
        } catch {
            switch error {
            case .interrupted(let interruption):
                throw interruption
            case .remote(.cursorExpired):
                if cursor == nil || resyncing {
                    report.deferred.append("\(type.rawValue): cursor expired during a full pull")
                    return nil
                }
                try await resync(type, report: &report)
                return nil
            case .remote(let remoteError):
                switch policy.disposition(for: remoteError, attempt: 1, random: random) {
                case .waitForNetwork:
                    throw SyncInterruption.offline
                case .stop:
                    throw SyncInterruption.cancelled
                case .reauthenticate:
                    throw SyncInterruption.authRequired
                case .retryLater(let delay):
                    if remoteError.countsTowardBreaker { breaker.recordTransientFailure(now: clock.now(), pause: delay) }
                    report.deferred.append("\(type.rawValue) pull: \(remoteError)")
                    return nil
                case .freeze, .restartFromScratch:
                    report.deferred.append("\(type.rawValue) pull: \(remoteError)")
                    return nil
                }
            }
        }
    }

    private func applyPage(_ page: PullPage, type: RecordType, table: String) async throws -> PageResult {
        guard let last = page.records.map(\.revision).max() else { return PageResult() }
        let records = page.records
        return try await store.write(label: TransactionLabel.pullApply, origin: .remote) { transaction -> PageResult in
            var result = PageResult(count: 0, last: last)
            let now = transaction.now.millisecondsSinceEpoch
            for record in records {
                let id = record.id.rawValue
                let pending = try transaction.query(
                    "SELECT 1 FROM sync_outbox WHERE record_type = ? AND record_id = ?",
                    [.text(type.rawValue), .text(id)]
                )
                if !pending.isEmpty { continue }
                let local = try transaction.query("SELECT server_revision FROM \(table) WHERE id = ?", [.text(id)])
                if let known = try local.first?.optionalInt64("server_revision"), known >= record.revision.rawValue {
                    continue
                }
                if record.deleted {
                    let changed = try transaction.run(
                        "UPDATE \(table) SET deleted = 1, deleted_at = ?, server_revision = ?, updated_at = ? WHERE id = ? AND deleted = 0",
                        [.integer(now), .integer(record.revision.rawValue), .integer(now), .text(id)]
                    )
                    if changed > 0 {
                        transaction.record(.recordDeleted(type, record.id))
                        result.count += 1
                    } else {
                        try transaction.run("UPDATE \(table) SET server_revision = ? WHERE id = ?", [.integer(record.revision.rawValue), .text(id)])
                    }
                } else if let payload = record.payload {
                    try transaction.run(
                        """
                        INSERT INTO \(table) (id, payload, local_version, server_revision, deleted, deleted_at, updated_at)
                        VALUES (?, ?, 0, ?, 0, NULL, ?)
                        ON CONFLICT (id) DO UPDATE SET
                            payload = excluded.payload,
                            server_revision = excluded.server_revision,
                            deleted = 0,
                            deleted_at = NULL,
                            updated_at = excluded.updated_at
                        """,
                        [.text(id), .text(payload.text), .integer(record.revision.rawValue), .integer(now)]
                    )
                    transaction.record(.recordSaved(type, record.id))
                    result.count += 1
                } else {
                    let reason = "live server record without payload"
                    let rowJSON = Row(columns: ["id", "revision"], values: [.text(id), .integer(record.revision.rawValue)]).jsonString()
                    try transaction.run(
                        "INSERT INTO quarantine (module, table_name, row_json, error, quarantined_at) VALUES (?, ?, ?, ?, ?)",
                        [.text(CoreSchema.moduleName), .text(type.rawValue), .text(rowJSON), .text(reason), .integer(now)]
                    )
                    transaction.record(.rowQuarantined(table: type.rawValue, reason: reason))
                }
            }
            try transaction.run(
                "INSERT INTO sync_cursor (record_type, revision) VALUES (?, ?) ON CONFLICT (record_type) DO UPDATE SET revision = MAX(revision, excluded.revision)",
                [.text(type.rawValue), .integer(last.rawValue)]
            )
            return result
        }
    }

    /// Pulls everything again, then tombstones live local rows the server no
    /// longer has, unless they carry a change still waiting to be pushed.
    private func resync(_ type: RecordType, report: inout SyncReport) async throws {
        let table = Self.table(type)
        try await store.write(label: TransactionLabel.cursorReset) { transaction in
            try transaction.run("DELETE FROM sync_cursor WHERE record_type = ?", [.text(type.rawValue)])
        }
        var cursor: Revision?
        var liveIDs = Set<RecordID>()
        while true {
            guard let page = try await fetchPage(type, after: cursor, resyncing: true, report: &report) else { return }
            breaker.recordSuccess()
            let applied = try await applyPage(page, type: type, table: table)
            report.pulledRecords += applied.count
            liveIDs.formUnion(page.records.filter { !$0.deleted }.map(\.id))
            guard let last = applied.last else { break }
            cursor = last
            if !page.hasMore { break }
        }
        let keep = liveIDs
        try await store.write(label: TransactionLabel.resyncPrune, origin: .remote) { transaction in
            let rows = try transaction.query(
                "SELECT id FROM \(table) WHERE deleted = 0 AND id NOT IN (SELECT record_id FROM sync_outbox WHERE record_type = ?)",
                [.text(type.rawValue)]
            )
            let now = transaction.now.millisecondsSinceEpoch
            for row in rows {
                let id = RecordID(try row.string("id"))
                if keep.contains(id) { continue }
                try transaction.run(
                    "UPDATE \(table) SET deleted = 1, deleted_at = ?, server_revision = NULL, updated_at = ? WHERE id = ?",
                    [.integer(now), .integer(now), .text(id.rawValue)]
                )
                transaction.record(.recordDeleted(type, id))
            }
        }
    }

    private static func table(_ type: RecordType) -> String {
        "\"\(type.rawValue)\""
    }
}
