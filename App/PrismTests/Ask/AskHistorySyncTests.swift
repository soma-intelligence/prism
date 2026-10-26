//
//  AskHistorySyncTests.swift
//  PrismTests
//

import Foundation
import Testing
@testable import Prism

/// The account's two tables in memory, behaving as the migration makes them:
/// a conversation or a message already there is kept as it is, and a message
/// opens its conversation and moves its clock.
actor FakeAskRemote: AskHistoryRemote {
    var rows: [UUID: AskConversationRow] = [:]
    var stored: [String: AskMessageRow] = [:]
    var isOffline = false
    private(set) var messageWrites = 0
    private(set) var messageFetches = 0

    func setOffline(_ offline: Bool) { isOffline = offline }

    func seed(_ row: AskConversationRow, _ messages: [AskMessageRow]) {
        rows[row.id] = row
        for message in messages { stored[message.clientID] = message }
    }

    func forget(_ id: UUID) {
        rows[id] = nil
        stored = stored.filter { $0.value.conversationID != id }
    }

    func insertConversations(_ rows: [AskConversationRow]) async throws {
        try check()
        for row in rows where self.rows[row.id] == nil { self.rows[row.id] = row }
    }

    func insertMessages(_ rows: [AskMessageRow]) async throws {
        try check()
        messageWrites += 1
        for row in rows where stored[row.clientID] == nil {
            stored[row.clientID] = row
            var conversation = self.rows[row.conversationID]
                ?? AskConversationRow(id: row.conversationID, title: row.role == "user" ? row.content : "", createdAt: row.createdAt, updatedAt: row.createdAt)
            conversation.updatedAt = max(conversation.updatedAt, row.createdAt)
            self.rows[row.conversationID] = conversation
        }
    }

    func deleteConversations(_ ids: [UUID]) async throws {
        try check()
        for id in ids { forget(id) }
    }

    func conversations() async throws -> [AskConversationRow] {
        try check()
        return Array(rows.values)
    }

    func messages(in ids: [UUID]) async throws -> [AskMessageRow] {
        try check()
        messageFetches += 1
        let wanted = Set(ids)
        return stored.values.filter { wanted.contains($0.conversationID) }
    }

    private func check() throws {
        if isOffline { throw URLError(.notConnectedToInternet) }
    }
}

@MainActor
@Suite("Ask history in the account")
struct AskHistorySyncTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func turn(_ question: String, _ lead: String, at offset: TimeInterval, canned: Bool = false) -> StoredAskTurn {
        StoredAskTurn(question: question, asked: base.addingTimeInterval(offset), lead: lead, rest: canned ? "From the phone." : nil,
                      signals: canned ? 1 : 0, sources: canned ? ["sleep"] : [], moveTitle: nil, moveReason: nil, moveAspect: nil,
                      isModelMissing: false)
    }

    @Test("Every kept turn is uploaded once: model answers, answers given offline, turns from before sign in")
    func uploadsOnce() async throws {
        let store = AskHistoryStore(inMemory: true)
        let first = try #require(store.append(turn("How did I sleep?", "You slept 7:12.", at: 0, canned: true), to: nil))
        store.append(turn("And tonight?", "Same bedtime.", at: 60), to: first)
        store.append(turn("Can I train hard tomorrow?", "Keep it easy.", at: 120), to: UUID())
        let remote = FakeAskRemote()
        let sync = AskHistorySync(local: store, remote: remote, ledgerURL: nil)

        let report = try await sync.run()
        #expect(report.uploadedTurns == 3)
        #expect(await remote.rows.count == 2)
        #expect(await remote.stored.count == 6)
        let answer = try #require(await remote.stored.values.first { $0.role == "assistant" && $0.meta?.lead == "You slept 7:12." })
        #expect(answer.content == "You slept 7:12. From the phone.")
        #expect(answer.meta?.sources == ["sleep"])

        let writes = await remote.messageWrites
        let again = try await sync.run()
        #expect(again.uploadedTurns == 0)
        #expect(await remote.messageWrites == writes, "nothing new, nothing sent")
        #expect(store.conversations.count == 2)
        #expect(store.conversation(first)?.turns.count == 2, "pulling its own upload back adds nothing")
    }

    @Test("A second upload of the same turns, with the ledger lost, makes no copies")
    func idempotent() async throws {
        let store = AskHistoryStore(inMemory: true)
        store.append(turn("How did I sleep?", "You slept 7:12.", at: 0), to: nil)
        let remote = FakeAskRemote()
        try await AskHistorySync(local: store, remote: remote, ledgerURL: nil).run()
        try await AskHistorySync(local: store, remote: remote, ledgerURL: nil).run()
        #expect(await remote.stored.count == 2)
        #expect(await remote.rows.count == 1)
        #expect(store.conversations.first?.turns.count == 1)
    }

    @Test("Offline, nothing is marked sent; back online, the queue goes out")
    func offlineQueue() async throws {
        let store = AskHistoryStore(inMemory: true)
        store.append(turn("How did I sleep?", "You slept 7:12.", at: 0, canned: true), to: nil)
        let remote = FakeAskRemote()
        await remote.setOffline(true)
        let sync = AskHistorySync(local: store, remote: remote, ledgerURL: nil)
        await #expect(throws: URLError.self) { try await sync.run() }
        #expect(await sync.ledger.uploadedTurns.isEmpty)
        #expect(store.conversations.count == 1, "the phone keeps working")

        store.append(turn("Can I train hard tomorrow?", "Keep it easy.", at: 60), to: nil)
        await remote.setOffline(false)
        let report = try await sync.run()
        #expect(report.uploadedTurns == 2)
        #expect(await remote.stored.count == 4)
    }

    @Test("The ledger survives a relaunch")
    func ledgerPersists() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ask-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AskHistoryStore(inMemory: true)
        store.append(turn("How did I sleep?", "You slept 7:12.", at: 0), to: nil)
        let remote = FakeAskRemote()
        try await AskHistorySync(local: store, remote: remote, ledgerURL: url).run()
        let writes = await remote.messageWrites
        let relaunched = AskHistorySync(local: store, remote: remote, ledgerURL: url)
        #expect(await relaunched.ledger.uploadedTurns.count == 1)
        try await relaunched.run()
        #expect(await remote.messageWrites == writes)
    }

    @Test("A new phone shows every past chat, the way the other phone drew it")
    func newPhone() async throws {
        let remote = FakeAskRemote()
        let conversation = UUID()
        let turnID = UUID()
        await remote.seed(
            AskConversationRow(id: conversation, title: "Last night's sleep", createdAt: base, updatedAt: base.addingTimeInterval(61)),
            [
                AskMessageRow(conversationID: conversation, clientID: AskMessageRow.clientID(turn: turnID, role: "user"),
                              role: "user", content: "How did I sleep?", createdAt: base),
                AskMessageRow(conversationID: conversation, clientID: AskMessageRow.clientID(turn: turnID, role: "assistant"),
                              role: "assistant", content: "You slept 7:12. Keep the same bedtime.", createdAt: base.addingTimeInterval(1),
                              meta: AskMessageMeta(lead: "You slept 7:12.", rest: "Keep the same bedtime.", signals: 1, sources: ["sleep"],
                                                   moveTitle: "Dim the lights", moveReason: "Earlier sleep", moveAspect: "sleep", modelMissing: false)),
                // Written by an older function, with no turn in its ids.
                AskMessageRow(conversationID: conversation, clientID: UUID().uuidString, role: "user", content: "And tonight?",
                              createdAt: base.addingTimeInterval(60)),
                AskMessageRow(conversationID: conversation, clientID: UUID().uuidString, role: "assistant", content: "Same bedtime.",
                              createdAt: base.addingTimeInterval(61), model: "model-a"),
            ]
        )
        let store = AskHistoryStore(inMemory: true)
        let report = try await AskHistorySync(local: store, remote: remote, ledgerURL: nil).run()
        #expect(report.pulled == 1)
        let kept = try #require(store.conversation(conversation))
        #expect(kept.title == "Last night's sleep")
        #expect(kept.turns.map(\.question) == ["How did I sleep?", "And tonight?"])
        #expect(kept.turns.first?.id == turnID)
        #expect(kept.turns.first?.lead == "You slept 7:12.")
        #expect(kept.turns.first?.rest == "Keep the same bedtime.")
        #expect(kept.turns.first?.moveTitle == "Dim the lights")
        #expect(kept.turns.last?.lead == "Same bedtime.")
        #expect(kept.updated == base.addingTimeInterval(61))
    }

    @Test("Merging keeps this phone's turns and adds the account's others, oldest first")
    func merge() {
        let id = UUID()
        let mine = turn("How did I sleep?", "You slept 7:12 (here).", at: 0)
        let theirs = turn("And tonight?", "Same bedtime.", at: 60)
        let local = AskConversationSnapshot(id: id, title: "How did I sleep?", created: base, updated: base, turns: [mine])
        let messages = AskHistoryMerge.messages(StoredAskTurn(id: mine.id, question: mine.question, asked: mine.asked, lead: "Another wording.",
                                                              rest: nil, signals: 0, sources: [], moveTitle: nil, moveReason: nil,
                                                              moveAspect: nil, isModelMissing: false), in: id)
            + AskHistoryMerge.messages(theirs, in: id)
        let row = AskConversationRow(id: id, title: "Sleep check", createdAt: base, updatedAt: base.addingTimeInterval(61))
        let merged = AskHistoryMerge.merge(local: local, remote: row, messages: messages)
        #expect(merged.turns.map(\.id) == [mine.id, theirs.id])
        #expect(merged.turns.first?.lead == "You slept 7:12 (here).", "what the person read wins")
        #expect(merged.title == "Sleep check", "the account's title wins")
        #expect(merged.updated == base.addingTimeInterval(61))
    }

    @Test("A delete in the drawer deletes in the account, even made offline, and is not pulled back")
    func deletes() async throws {
        let store = AskHistoryStore(inMemory: true)
        let id = try #require(store.append(turn("How did I sleep?", "You slept 7:12.", at: 0), to: nil))
        let remote = FakeAskRemote()
        let sync = AskHistorySync(local: store, remote: remote, ledgerURL: nil)
        try await sync.run()
        #expect(await remote.rows[id] != nil)

        await remote.setOffline(true)
        store.delete(id)
        #expect(store.pendingDeletes == [id])
        _ = try? await sync.run()
        #expect(store.pendingDeletes == [id], "kept until the account has it")

        await remote.setOffline(false)
        let report = try await sync.run()
        #expect(report.deleted == 1)
        #expect(await remote.rows[id] == nil)
        #expect(await remote.stored.isEmpty)
        #expect(store.pendingDeletes.isEmpty)
        #expect(store.conversation(id) == nil)
    }

    @Test("A conversation deleted on another phone leaves this one too; one never uploaded stays")
    func deletedElsewhere() async throws {
        let store = AskHistoryStore(inMemory: true)
        let synced = try #require(store.append(turn("How did I sleep?", "You slept 7:12.", at: 0), to: nil))
        let remote = FakeAskRemote()
        let sync = AskHistorySync(local: store, remote: remote, ledgerURL: nil)
        try await sync.run()
        await remote.forget(synced)
        let report = try await sync.run()
        #expect(report.removedHere == 1)
        #expect(store.conversation(synced) == nil)
        #expect(store.pendingDeletes.isEmpty, "not sent back as a delete")
    }

    @Test("A turn kept before turns had ids reads back with the same id every time")
    func legacyTurnID() throws {
        let json = Data(#"{"question":"How did I sleep?","asked":780000000,"lead":"You slept 7:12.","signals":1,"sources":["sleep"],"isModelMissing":false}"#.utf8)
        let first = try JSONDecoder().decode(StoredAskTurn.self, from: json)
        let second = try JSONDecoder().decode(StoredAskTurn.self, from: json)
        #expect(first.id == second.id)
        let reencoded = try JSONDecoder().decode(StoredAskTurn.self, from: JSONEncoder().encode(first))
        #expect(reencoded == first)
    }

    @Test("The question carries its conversation and turn, the ids the account files it under")
    func requestIDs() throws {
        let conversation = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let turn = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let request = try AskClient.request(url: URL(string: "https://qnysyehawitnlcnccyop.supabase.co/functions/v1/ask-soma")!, key: "sb_publishable_x",
                                            messages: [AskWireTurn(role: .user, content: "How did I sleep?")],
                                            context: AskContext(day: "2026-10-03", scores: .init(sleep: 82), metrics: [], person: nil),
                                            conversationID: conversation, turnID: turn)
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["turn_id"] as? String == "44444444-4444-4444-8444-444444444444")
        #expect(AskMessageRow.clientID(turn: turn, role: "assistant") == "44444444-4444-4444-8444-444444444444:assistant")
    }

    @Test("Rows go up with every key, nulls included, so a batch has one shape")
    func rowShape() throws {
        let row = AskHistoryMerge.messages(turn("How did I sleep?", "You slept 7:12.", at: 0), in: UUID())[0]
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        #expect(Set(object.keys) == ["conversation_id", "client_id", "role", "content", "created_at", "model", "prompt_tokens",
                                     "completion_tokens", "is_error", "meta"])
        #expect(row.turnID != nil)
    }
}
