//
//  AskHistorySync.swift
//  Prism
//

import Foundation
import SyncCore
import SyncSupabase

// MARK: Rows

/// One row of `ask_conversations`
/// (`supabase/migrations/20261003120900_ask_conversations.sql`).
nonisolated struct AskConversationRow: Codable, Equatable, Sendable {
    var id: UUID
    var kind: String = AskConversationRow.askKind
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var archived: Bool = false
    /// Kept by the database from the newest message; never sent.
    var lastMessagePreview: String?
    /// Kept by the database from the newest answer; never sent.
    var model: String?

    /// The only kind of chat today: Ask Soma.
    static let askKind = "ask"

    enum CodingKeys: String, CodingKey {
        case id, kind, title, archived, model
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessagePreview = "last_message_preview"
    }

    /// The columns an upload writes, every row the same keys (PostgREST
    /// takes a batch's columns from its rows). The preview and the model are
    /// the database's to keep.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(archived, forKey: .archived)
    }
}

/// What the page shows beside an answer, kept with the message so another
/// phone draws the answer the way this one did.
nonisolated struct AskMessageMeta: Codable, Equatable, Sendable {
    var lead: String?
    var rest: String?
    var signals: Int?
    var sources: [String]?
    var moveTitle: String?
    var moveReason: String?
    var moveAspect: String?
    var modelMissing: Bool?

    enum CodingKeys: String, CodingKey {
        case lead, rest, signals, sources
        case moveTitle = "move_title"
        case moveReason = "move_reason"
        case moveAspect = "move_aspect"
        case modelMissing = "model_missing"
    }
}

/// One row of `ask_messages`. `(user_id, client_id)` is unique, which makes a
/// second write of the same turn harmless.
nonisolated struct AskMessageRow: Codable, Equatable, Sendable {
    var conversationID: UUID
    var clientID: String
    /// user or assistant.
    var role: String
    var content: String
    var createdAt: Date
    var model: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var isError: Bool = false
    var meta: AskMessageMeta?

    enum CodingKeys: String, CodingKey {
        case role, content, model, meta
        case conversationID = "conversation_id"
        case clientID = "client_id"
        case createdAt = "created_at"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case isError = "is_error"
    }

    /// Every key on every row, nulls included, for the same reason as the
    /// conversation's.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationID.uuidString.lowercased(), forKey: .conversationID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(model, forKey: .model)
        try container.encode(promptTokens, forKey: .promptTokens)
        try container.encode(completionTokens, forKey: .completionTokens)
        try container.encode(isError, forKey: .isError)
        try container.encode(meta ?? AskMessageMeta(), forKey: .meta)
    }

    /// The turn a client id names (`<turn>:user`), or nil for a row written
    /// without one.
    var turnID: UUID? {
        guard let colon = clientID.firstIndex(of: ":") else { return nil }
        return UUID(uuidString: String(clientID[..<colon]))
    }

    static func clientID(turn: UUID, role: String) -> String {
        "\(turn.uuidString.lowercased()):\(role)"
    }
}

// MARK: Merge

/// The pure half of the sync: kept turns to rows, rows back to turns, and a
/// local conversation merged with the account's copy.
nonisolated enum AskHistoryMerge {
    /// The conversation's row, as an upload sends it.
    static func row(_ conversation: AskConversationSnapshot) -> AskConversationRow {
        AskConversationRow(id: conversation.id, title: conversation.title, createdAt: conversation.created, updatedAt: conversation.updated)
    }

    /// A kept turn's two messages: the question, then the answer a
    /// millisecond later so the account orders them the way they were asked.
    static func messages(_ turn: StoredAskTurn, in conversation: UUID) -> [AskMessageRow] {
        let answer = [turn.lead, turn.rest].compactMap { $0 }.joined(separator: " ")
        return [
            AskMessageRow(conversationID: conversation, clientID: AskMessageRow.clientID(turn: turn.id, role: "user"),
                          role: "user", content: String(turn.question.prefix(20000)), createdAt: turn.asked),
            AskMessageRow(conversationID: conversation, clientID: AskMessageRow.clientID(turn: turn.id, role: "assistant"),
                          role: "assistant", content: String((answer.isEmpty ? turn.lead : answer).prefix(20000)),
                          createdAt: turn.asked.addingTimeInterval(0.001),
                          meta: AskMessageMeta(lead: turn.lead, rest: turn.rest, signals: turn.signals, sources: turn.sources,
                                               moveTitle: turn.moveTitle, moveReason: turn.moveReason, moveAspect: turn.moveAspect,
                                               modelMissing: turn.isModelMissing)),
        ]
    }

    /// The account's messages of one conversation as turns, oldest first.
    ///
    /// A message names its turn by its client id; a row written without one
    /// (an older function) pairs an answer with the question before it. A
    /// question with no answer is left out: the page has nothing to show for it.
    static func turns(_ messages: [AskMessageRow]) -> [StoredAskTurn] {
        var order: [UUID] = []
        var questions: [UUID: AskMessageRow] = [:]
        var answers: [UUID: AskMessageRow] = [:]
        var open: UUID?
        for message in messages.sorted(by: { ($0.createdAt, $0.role == "user" ? 0 : 1) < ($1.createdAt, $1.role == "user" ? 0 : 1) }) {
            if message.role == "user" {
                let id = message.turnID ?? UUID(uuidString: message.clientID) ?? StoredAskTurn.legacyID(question: message.content, asked: message.createdAt)
                if questions[id] == nil { order.append(id) }
                questions[id] = message
                open = id
            } else if let id = message.turnID ?? open {
                answers[id] = message
                if id == open { open = nil }
            }
        }
        return order.compactMap { id in
            guard let question = questions[id], let answer = answers[id] else { return nil }
            let meta = answer.meta
            return StoredAskTurn(
                id: id, question: question.content, asked: question.createdAt,
                lead: meta?.lead ?? answer.content, rest: meta?.lead == nil ? nil : meta?.rest,
                signals: meta?.signals ?? 0, sources: meta?.sources ?? [],
                moveTitle: meta?.moveTitle, moveReason: meta?.moveReason, moveAspect: meta?.moveAspect,
                isModelMissing: meta?.modelMissing ?? false
            )
        }
    }

    /// A local conversation and the account's copy as one: every turn either
    /// side holds, by id, oldest first. The turn this phone kept wins over
    /// the account's copy of the same turn: it is what the person read. The
    /// account's title wins (the model may have named it), and the later
    /// clock.
    static func merge(local: AskConversationSnapshot?, remote: AskConversationRow, messages: [AskMessageRow]) -> AskConversationSnapshot {
        let remoteTurns = turns(messages)
        guard let local else {
            return AskConversationSnapshot(id: remote.id, title: title(remote: remote, fallback: remoteTurns.first?.question ?? ""),
                                           created: remote.createdAt, updated: remote.updatedAt, turns: remoteTurns)
        }
        let known = Set(local.turns.map(\.id))
        let turns = (local.turns + remoteTurns.filter { !known.contains($0.id) }).sorted { $0.asked < $1.asked }
        // A clock a moment apart is the same clock; moving it would only
        // reorder the drawer for nothing.
        let updated = remote.updatedAt.timeIntervalSince(local.updated) > 1 ? remote.updatedAt : local.updated
        return AskConversationSnapshot(id: local.id, title: title(remote: remote, fallback: local.title),
                                       created: min(local.created, remote.createdAt), updated: updated, turns: turns)
    }

    private static func title(remote: AskConversationRow, fallback: String) -> String {
        let trimmed = remote.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AskHistoryStore.title(fallback) : trimmed
    }
}

// MARK: Ports

/// The store the sync mirrors: ``AskHistoryStore`` in the app, an in-memory
/// one in tests.
@MainActor
protocol AskHistoryLocal: AnyObject, Sendable {
    var pendingDeletes: Set<UUID> { get }
    func snapshot() -> [AskConversationSnapshot]
    func apply(_ merged: [AskConversationSnapshot], removing: Set<UUID>)
    func clearPendingDeletes(_ ids: Set<UUID>)
}

/// The account's two tables.
nonisolated protocol AskHistoryRemote: Sendable {
    /// Creates the conversations that are not there yet; one already there
    /// is kept as it is.
    func insertConversations(_ rows: [AskConversationRow]) async throws
    /// Creates the messages that are not there yet, by `(user_id, client_id)`.
    func insertMessages(_ rows: [AskMessageRow]) async throws
    /// Deletes conversations, and with them their messages.
    func deleteConversations(_ ids: [UUID]) async throws
    func conversations() async throws -> [AskConversationRow]
    func messages(in conversations: [UUID]) async throws -> [AskMessageRow]
}

/// ``AskHistoryRemote`` over the app's Supabase project, with the person's
/// own session: row level security keeps every call to their rows.
nonisolated struct SupabaseAskHistoryRemote: AskHistoryRemote {
    let services: SupabaseServices
    let userID: String

    func insertConversations(_ rows: [AskConversationRow]) async throws {
        try await services.upsert(rows, into: "ask_conversations", onConflict: "id", ignoreDuplicates: true)
    }

    func insertMessages(_ rows: [AskMessageRow]) async throws {
        for start in stride(from: 0, to: rows.count, by: 200) {
            let batch = Array(rows[start..<min(start + 200, rows.count)])
            try await services.upsert(batch, into: "ask_messages", onConflict: "user_id,client_id", ignoreDuplicates: true)
        }
    }

    func deleteConversations(_ ids: [UUID]) async throws {
        try await services.delete(from: "ask_conversations", where: "id", in: ids.map { $0.uuidString.lowercased() })
    }

    func conversations() async throws -> [AskConversationRow] {
        try await services.selectAll(AskConversationRow.self, from: "ask_conversations",
                                     columns: "id,kind,title,created_at,updated_at,archived,last_message_preview,model",
                                     where: "user_id", equals: userID.lowercased(), orderBy: "id")
    }

    func messages(in conversations: [UUID]) async throws -> [AskMessageRow] {
        try await services.select(AskMessageRow.self, from: "ask_messages",
                                  columns: "conversation_id,client_id,role,content,created_at,model,prompt_tokens,completion_tokens,is_error,meta",
                                  where: "conversation_id", in: conversations.map { $0.uuidString.lowercased() }, orderBy: "created_at")
    }
}

// MARK: Sync

/// What this phone knows the account holds, per person, so a pass sends
/// only what is new and fetches only what moved.
nonisolated struct AskSyncLedger: Codable, Equatable, Sendable {
    /// Turns whose two messages the account confirmed.
    var uploadedTurns: Set<UUID> = []
    /// Conversations the account holds (uploaded from here or pulled).
    var conversations: Set<UUID> = []
    /// Each conversation's `updated_at` when it was last merged.
    var stamps: [UUID: Date] = [:]
}

/// What one pass did.
nonisolated struct AskSyncReport: Equatable, Sendable {
    var uploadedTurns = 0
    var deleted = 0
    var pulled = 0
    var removedHere = 0
}

/// Ask's history in the account, both ways.
///
/// A pass, in order:
/// 1. Deletes in the account what the drawer deleted (remembered by the
///    store until this succeeds, so it works after a stretch offline).
/// 2. Uploads every kept turn the account has not confirmed: answers from
///    the model, answers the phone gave offline, turns asked before signing
///    in. Writes are idempotent by the turn's id, so a pass cut short and run
///    again never makes a second copy.
/// 3. Pulls the account's conversations and merges into the store the ones
///    that are new or moved since the last pass, so a new phone shows every
///    past chat. A conversation the account had and no longer has was
///    deleted on another phone, and leaves this one too.
///
/// Offline, a pass stops at its first failed call and the next one picks up
/// where it left: nothing is marked sent until the account said so.
actor AskHistorySync {
    private let local: any AskHistoryLocal
    private let remote: any AskHistoryRemote
    private let ledgerURL: URL?
    private(set) var ledger: AskSyncLedger
    private var running: Task<AskSyncReport, any Error>?

    init(local: any AskHistoryLocal, remote: any AskHistoryRemote, ledgerURL: URL?) {
        self.local = local
        self.remote = remote
        self.ledgerURL = ledgerURL
        if let ledgerURL, let data = FileManager.default.contents(atPath: ledgerURL.path),
           let decoded = try? JSONDecoder().decode(AskSyncLedger.self, from: data) {
            ledger = decoded
        } else {
            ledger = AskSyncLedger()
        }
    }

    /// One pass. Joins a pass already running rather than starting a second.
    @discardableResult
    func run() async throws -> AskSyncReport {
        if let running { return try await running.value }
        let task = Task { try await self.pass() }
        running = task
        defer { running = nil }
        return try await task.value
    }

    private func pass() async throws -> AskSyncReport {
        var report = AskSyncReport()

        // 1. Deletes.
        let deletes = await local.pendingDeletes
        if !deletes.isEmpty {
            try await remote.deleteConversations(Array(deletes).sorted { $0.uuidString < $1.uuidString })
            await local.clearPendingDeletes(deletes)
            ledger.conversations.subtract(deletes)
            for id in deletes { ledger.stamps[id] = nil }
            try save()
            report.deleted = deletes.count
        }

        // 2. Uploads.
        let kept = await local.snapshot()
        let newConversations = kept.filter { !ledger.conversations.contains($0.id) && !$0.turns.isEmpty }
        var pending: [(conversation: UUID, turn: StoredAskTurn)] = []
        for conversation in kept {
            for turn in conversation.turns where !ledger.uploadedTurns.contains(turn.id) {
                pending.append((conversation.id, turn))
            }
        }
        if !newConversations.isEmpty {
            try await remote.insertConversations(newConversations.map(AskHistoryMerge.row))
            ledger.conversations.formUnion(newConversations.map(\.id))
            try save()
        }
        if !pending.isEmpty {
            try await remote.insertMessages(pending.flatMap { AskHistoryMerge.messages($0.turn, in: $0.conversation) })
            ledger.uploadedTurns.formUnion(pending.map(\.turn.id))
            try save()
            report.uploadedTurns = pending.count
        }

        // 3. Pull and merge.
        let rows = try await remote.conversations().filter { $0.kind == AskConversationRow.askKind }
        let stillDeleting = await local.pendingDeletes
        let byID = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let moved = rows.filter { row in
            !stillDeleting.contains(row.id) && (byID[row.id] == nil || ledger.stamps[row.id] != row.updatedAt)
        }
        var merged: [AskConversationSnapshot] = []
        if !moved.isEmpty {
            let messages = try await remote.messages(in: moved.map(\.id))
            let grouped = Dictionary(grouping: messages, by: \.conversationID)
            for row in moved {
                let snapshot = AskHistoryMerge.merge(local: byID[row.id], remote: row, messages: grouped[row.id] ?? [])
                // An empty conversation (its turns never answered) shows
                // nothing in the drawer; it waits until it has one.
                guard !snapshot.turns.isEmpty else { continue }
                merged.append(snapshot)
            }
        }
        let onServer = Set(rows.map(\.id))
        let goneElsewhere = ledger.conversations.subtracting(onServer).intersection(byID.keys)
        await local.apply(merged, removing: goneElsewhere)

        for snapshot in merged { ledger.uploadedTurns.formUnion(snapshot.turns.map(\.id)) }
        for row in moved where merged.contains(where: { $0.id == row.id }) { ledger.stamps[row.id] = row.updatedAt }
        ledger.conversations.formUnion(merged.map(\.id))
        ledger.conversations.subtract(goneElsewhere)
        for id in goneElsewhere { ledger.stamps[id] = nil }
        try save()
        report.pulled = merged.filter { byID[$0.id] == nil }.count
        report.removedHere = goneElsewhere.count
        return report
    }

    private func save() throws {
        guard let ledgerURL else { return }
        try JSONEncoder().encode(ledger).write(to: ledgerURL, options: CloudFiles.writeOptions)
    }
}
