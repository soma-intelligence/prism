import Foundation
import Testing
@testable import SyncCore
import SyncTesting

@Suite struct RecordRepositoryTests {
    struct OutboxRow: Equatable {
        let id: String
        let version: Int64
        let enqueuedAt: Int64
    }

    func outbox(_ store: LocalStore) throws -> [OutboxRow] {
        try store.read { context in
            try context.query("SELECT record_id, local_version, enqueued_at FROM sync_outbox ORDER BY record_id", []).map {
                OutboxRow(id: try $0.string("record_id"), version: try $0.int64("local_version"), enqueuedAt: try $0.int64("enqueued_at"))
            }
        }
    }

    @Test func saveWritesRowAndOutboxEntryTogether() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let changes = ChangeBroadcaster()
        let stream = changes.stream()
        let store = try TestSchema.openStore(at: directory.url, clock: ManualClock(), changes: changes)
        let notes = RecordRepository<TestNote>(store: store)

        try await notes.save(TestNote(id: RecordID("a"), body: "hello"))

        #expect(try await notes.fetch(RecordID("a")) == TestNote(id: RecordID("a"), body: "hello"))
        #expect(try outbox(store).map(\.id) == ["a"])
        #expect(try outbox(store).first?.version == 1)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == ChangeBatch(origin: .local, changes: [.recordSaved(TestNote.recordType, RecordID("a"))]))
        await store.close()
    }

    @Test func successiveSavesCollapseIntoOneOutboxEntry() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let clock = ManualClock()
        let store = try TestSchema.openStore(at: directory.url, clock: clock)
        let notes = RecordRepository<TestNote>(store: store)

        try await notes.save(TestNote(id: RecordID("a"), body: "one"))
        let firstEnqueue = try outbox(store).first?.enqueuedAt
        clock.advance(by: .seconds(5))
        try await notes.save(TestNote(id: RecordID("a"), body: "two"))

        let rows = try outbox(store)
        #expect(rows.count == 1)
        #expect(rows.first?.version == 2)
        #expect(rows.first?.enqueuedAt == firstEnqueue)
        #expect(try await notes.pendingChangeCount() == 1)
        await store.close()
    }

    @Test func savingManyRecordsPublishesOneBatch() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let changes = ChangeBroadcaster()
        let stream = changes.stream()
        let store = try TestSchema.openStore(at: directory.url, clock: ManualClock(), changes: changes)
        let notes = RecordRepository<TestNote>(store: store)

        try await notes.save((1...8).map { TestNote(id: RecordID("n\($0)"), body: "item \($0)") })

        var iterator = stream.makeAsyncIterator()
        let batch = try #require(await iterator.next())
        #expect(batch.changes.count == 8)
        #expect(try await notes.fetchAll().count == 8)
        await store.close()
    }

    @Test func deleteLeavesATombstoneAndAnOutboxEntry() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let store = try TestSchema.openStore(at: directory.url, clock: ManualClock())
        let notes = RecordRepository<TestNote>(store: store)
        try await notes.save(TestNote(id: RecordID("a"), body: "hello"))

        try await notes.delete(RecordID("a"))
        try await notes.delete(RecordID("a"))

        #expect(try await notes.fetch(RecordID("a")) == nil)
        let deleted = try store.read { try $0.query("SELECT deleted, local_version FROM test_note WHERE id = 'a'", []).first }
        #expect(deleted?["deleted"] == .integer(1))
        #expect(deleted?["local_version"] == .integer(2))
        #expect(try outbox(store).first?.version == 2)
        await store.close()
    }

    @Test func undecodableRowIsQuarantinedAndOthersStayReadable() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let changes = ChangeBroadcaster()
        let store = try TestSchema.openStore(at: directory.url, clock: ManualClock(), changes: changes)
        let notes = RecordRepository<TestNote>(store: store)
        try await notes.save([TestNote(id: RecordID("a"), body: "good"), TestNote(id: RecordID("b"), body: "soon broken")])
        try await store.write(label: "test.corrupt-row") { tx in
            try tx.run("UPDATE test_note SET payload = '{\"id\":\"b\"}' WHERE id = 'b'")
        }
        let stream = changes.stream()

        let all = try await notes.fetchAll()

        #expect(all.map(\.id.rawValue) == ["a"])
        let quarantined = try store.read { try $0.query("SELECT table_name, row_json FROM quarantine", []) }
        #expect(quarantined.count == 1)
        #expect(quarantined.first?["table_name"] == .text("test_note"))
        #expect(try quarantined.first?.string("row_json").contains("\"id\":\"b\"") == true)
        #expect(try outbox(store).map(\.id) == ["a"])
        var iterator = stream.makeAsyncIterator()
        let batch = try #require(await iterator.next())
        guard case .rowQuarantined(let table, _) = batch.changes.first else {
            Issue.record("expected a quarantine change, got \(batch)")
            return
        }
        #expect(table == "test_note")
        await store.close()
    }

    @Test func payloadWhoseIDDiffersFromTheRowIsQuarantined() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let store = try TestSchema.openStore(at: directory.url, clock: ManualClock())
        let notes = RecordRepository<TestNote>(store: store)
        try await notes.save(TestNote(id: RecordID("a"), body: "good"))
        try await store.write(label: "test.corrupt-row") { tx in
            try tx.run("UPDATE test_note SET payload = '{\"id\":\"z\",\"body\":\"x\",\"rating\":0}' WHERE id = 'a'")
        }

        #expect(try await notes.fetch(RecordID("a")) == nil)
        #expect(try store.read { try $0.query("SELECT COUNT(*) AS n FROM quarantine", []).first?["n"].int64Value } == 1)
        await store.close()
    }
}
