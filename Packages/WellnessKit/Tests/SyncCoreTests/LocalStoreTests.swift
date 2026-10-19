import Foundation
import Synchronization
import Testing
@testable import SyncCore
import SyncTesting

final class LabelRecorder: TransactionObserver {
    let labels = Mutex<[String]>([])
    func willCommit(label: String) { labels.withLock { $0.append(label) } }
}

@Suite struct LocalStoreTests {
    static let notes = Migration(module: "Test", version: 1, sql: "CREATE TABLE note (id TEXT PRIMARY KEY, body TEXT NOT NULL)")

    func makeStore(
        _ directory: TemporaryDirectory,
        migrations: [Migration] = [notes],
        changes: ChangeBroadcaster = ChangeBroadcaster(),
        observer: (any TransactionObserver)? = nil
    ) throws -> LocalStore {
        try LocalStore(directory: directory.url, migrations: migrations, clock: ManualClock(), changes: changes, observer: observer)
    }

    @Test func appliesEachMigrationOnce() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let first = try makeStore(directory)
        await first.close()
        let second = try makeStore(directory)
        let applied = try second.read { try $0.query("SELECT COUNT(*) AS n FROM schema_migrations", []).first?["n"].int64Value }
        #expect(applied == 1)
        #expect(await second.state == .ready)
        await second.close()
    }

    @Test func failedMigrationLeavesStoreFailedWithoutMemoryFallback() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let broken = Migration(module: "Test", version: 2, sql: "CREATE TABLE broken (")
        let store = try makeStore(directory, migrations: [Self.notes, broken])
        guard case .failed(.migrationFailed(let module, let version, _)) = await store.state else {
            Issue.record("expected a failed state, got \(await store.state)")
            return
        }
        #expect(module == "Test")
        #expect(version == 2)
        #expect(throws: StoreError.self) { try store.read { try $0.query("SELECT 1", []) } }
        await #expect(throws: StoreError.self) { try await store.write(label: "test") { _ in } }
        #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent(LocalStore.fileName).path))
        await store.close()

        // The first migration committed on disk even though the second failed.
        let reopened = try makeStore(directory, migrations: [Self.notes])
        #expect(await reopened.state == .ready)
        await reopened.close()
    }

    @Test func rolledBackTransactionPublishesNothing() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let changes = ChangeBroadcaster()
        let stream = changes.stream()
        let store = try makeStore(directory, changes: changes)
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await store.write(label: "test") { tx in
                try tx.run("INSERT INTO note VALUES ('a', 'x')")
                tx.record(.recordSaved(RecordType("note"), RecordID("a")))
                throw Boom()
            }
        }
        try await store.write(label: "test") { tx in
            try tx.run("INSERT INTO note VALUES ('b', 'y')")
            tx.record(.recordSaved(RecordType("note"), RecordID("b")))
        }
        var iterator = stream.makeAsyncIterator()
        let batch = await iterator.next()
        #expect(batch == ChangeBatch(origin: .local, changes: [.recordSaved(RecordType("note"), RecordID("b"))]))
        let ids = try store.read { try $0.query("SELECT id FROM note", []).map { try $0.string("id") } }
        #expect(ids == ["b"])
        await store.close()
    }

    @Test func oneTransactionPublishesOneBatch() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let changes = ChangeBroadcaster()
        let stream = changes.stream()
        let store = try makeStore(directory, changes: changes)
        try await store.write(label: "test", origin: .remote) { tx in
            for id in ["a", "b", "c"] {
                try tx.run("INSERT INTO note VALUES (?, 'x')", [.text(id)])
                tx.record(.recordSaved(RecordType("note"), RecordID(id)))
            }
        }
        var iterator = stream.makeAsyncIterator()
        let batch = try #require(await iterator.next())
        #expect(batch.origin == .remote)
        #expect(batch.changes.count == 3)
        await store.close()
    }

    @Test func observerSeesLabelBeforeCommit() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let recorder = LabelRecorder()
        let store = try makeStore(directory, observer: recorder)
        try await store.write(label: "first") { tx in try tx.run("INSERT INTO note VALUES ('a', 'x')") }
        struct Boom: Error {}
        await #expect(throws: Boom.self) { try await store.write(label: "second") { _ in throw Boom() } }
        #expect(recorder.labels.withLock { $0 } == ["first"])
        await store.close()
    }

    @Test func readsRunConcurrentlyWithWrites() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let store = try makeStore(directory)
        try await store.write(label: "seed") { tx in
            for index in 0..<200 { try tx.run("INSERT INTO note VALUES (?, 'x')", [.text("n\(index)")]) }
        }
        try await withThrowingTaskGroup(of: Int64.self) { group in
            for _ in 0..<8 {
                group.addTask { try store.read { try $0.query("SELECT COUNT(*) AS n FROM note", []).first?["n"].int64Value ?? -1 } }
            }
            group.addTask {
                try await store.write(label: "more") { tx in try tx.run("INSERT INTO note VALUES ('late', 'x')") }
                return 0
            }
            for try await count in group where count != 0 {
                #expect(count == 200 || count == 201)
            }
        }
        await store.close()
    }

    @Test func garbageDatabaseIsMovedAsideAndRebuilt() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.url.appendingPathComponent(LocalStore.fileName)
        try Data(repeating: 0x5A, count: 8192).write(to: path)
        let store = try makeStore(directory)
        #expect(await store.state == .ready)
        let report = try #require(await store.lastRebuild)
        #expect(report.lostUnsentChanges == nil)
        #expect(FileManager.default.fileExists(atPath: report.movedTo.path))
        try await store.write(label: "test") { tx in try tx.run("INSERT INTO note VALUES ('a', 'x')") }
        await store.close()
    }

    @Test func payloadCanonicalizationIsStable() throws {
        struct Sample: Codable, Equatable { var b: Int; var a: String; var when: Date }
        let sample = Sample(b: 2, a: "x", when: Date(timeIntervalSince1970: 1.5))
        let encoded = try RecordPayload(encoding: sample)
        #expect(encoded.text == "{\"a\":\"x\",\"b\":2,\"when\":1500}")
        let reordered = try RecordPayload(validating: Data("{ \"when\": 1500, \"b\": 2, \"a\": \"x\" }".utf8))
        #expect(reordered == encoded)
        #expect(try encoded.decode(Sample.self) == sample)
        #expect(throws: RecordCodingError.self) { try RecordPayload(validating: Data("[1,2]".utf8)) }
    }
}
