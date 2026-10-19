import Foundation
import Testing
import SyncCore
import SyncTesting

@Suite struct WellnessSessionTests {
    static let notesModule = SchemaModule(
        name: TestSchema.moduleName,
        migrations: Array(TestSchema.migrations.dropFirst(CoreSchema.migrations.count)),
        recordTypes: TestSchema.recordTypes
    )

    func environment(
        _ root: URL,
        user: String,
        server: ScriptedRecordServer,
        clock: ManualClock,
        connectivity: ManualConnectivity = ManualConnectivity(),
        debounce: Duration = .seconds(2)
    ) -> WellnessEnvironment {
        WellnessEnvironment(
            userID: UserID(user),
            tokens: ScriptedTokenProvider(userID: UserID(user)),
            records: server,
            objects: InMemoryObjectStore(),
            clock: clock,
            random: FixedRandom(0.5),
            connectivity: connectivity,
            rootDirectory: root,
            syncDebounce: debounce
        )
    }

    func outboxCount(_ session: WellnessSession) throws -> Int {
        try session.store.read { Int(try $0.query("SELECT COUNT(*) AS n FROM sync_outbox", []).first?["n"].int64Value ?? 0) }
    }

    @Test func twoUsersNeverShareRowsOutboxOrCursors() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let clock = ManualClock()
        let serverA = ScriptedRecordServer()
        let serverB = ScriptedRecordServer()
        let sessionA = try await WellnessSession.open(environment(root.url, user: "user-a", server: serverA, clock: clock, debounce: .seconds(3_600)), modules: [Self.notesModule])
        let sessionB = try await WellnessSession.open(environment(root.url, user: "user-b", server: serverB, clock: clock, debounce: .seconds(3_600)), modules: [Self.notesModule])

        try await sessionA.repository(for: TestNote.self).save(TestNote(id: RecordID("a"), body: "private to a"))
        _ = await sessionA.syncNow()
        _ = await sessionB.syncNow()

        #expect(sessionA.directory != sessionB.directory)
        #expect(try await sessionB.repository(for: TestNote.self).fetchAll().isEmpty)
        #expect(try outboxCount(sessionB) == 0)
        #expect(await serverB.pushCalls == 0)
        #expect(await serverA.liveRecords(type: TestNote.recordType).count == 1)
        await sessionA.close()
        await sessionB.close()
    }

    @Test func aUserCannotHaveTwoOpenSessions() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        let first = try await WellnessSession.open(environment(root.url, user: "user-a", server: server, clock: clock), modules: [Self.notesModule])

        await #expect(throws: SessionError.alreadyOpen(userID: UserID("user-a"))) {
            try await WellnessSession.open(environment(root.url, user: "user-a", server: server, clock: clock), modules: [Self.notesModule])
        }
        await first.close()
        let reopened = try await WellnessSession.open(environment(root.url, user: "user-a", server: server, clock: clock), modules: [Self.notesModule])
        await reopened.close()
    }

    @Test func aLocalWriteSyncsAfterTheDebounce() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        let session = try await WellnessSession.open(environment(root.url, user: "user-a", server: server, clock: clock), modules: [Self.notesModule])

        try await session.repository(for: TestNote.self).save(TestNote(id: RecordID("a"), body: "one"))
        #expect(await eventually { clock.sleeperCount >= 1 })
        #expect(await server.pushCalls == 0)
        clock.advance(by: .seconds(2))

        #expect(await eventually { await server.pushCalls == 1 })
        await session.close()
    }

    @Test func networkReturningTriggersASync() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        let connectivity = ManualConnectivity()
        let session = try await WellnessSession.open(
            environment(root.url, user: "user-a", server: server, clock: clock, connectivity: connectivity, debounce: .seconds(3_600)),
            modules: [Self.notesModule]
        )
        try await session.repository(for: TestNote.self).save(TestNote(id: RecordID("a"), body: "one"))

        connectivity.send(false)
        connectivity.send(true)

        #expect(await eventually { await server.pushCalls == 1 })
        await session.close()
    }

    @Test func aBackedOffChangeIsRetriedWhenItBecomesDue() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        await server.script([.fail(.transient(status: 503, retryAfter: nil))])
        let session = try await WellnessSession.open(
            environment(root.url, user: "user-a", server: server, clock: clock, debounce: .seconds(3_600)),
            modules: [Self.notesModule]
        )
        try await session.repository(for: TestNote.self).save(TestNote(id: RecordID("a"), body: "one"))

        let first = await session.syncNow()
        #expect(first.records.deferred.count == 1)
        #expect(await eventually { clock.sleeperCount >= 2 })
        clock.advance(by: .seconds(1))

        #expect(await eventually { await server.liveRecords(type: TestNote.recordType).count == 1 })
        await session.close()
    }

    @Test func retryFrozenReleasesFrozenEntries() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        await server.reject(ids: [RecordID("a")])
        let session = try await WellnessSession.open(
            environment(root.url, user: "user-a", server: server, clock: clock, debounce: .seconds(3_600)),
            modules: [Self.notesModule]
        )
        try await session.repository(for: TestNote.self).save(TestNote(id: RecordID("a"), body: "one"))
        _ = await session.syncNow()
        let frozen = { try session.store.read { Int(try $0.query("SELECT COUNT(*) AS n FROM sync_outbox WHERE frozen = 1", []).first?["n"].int64Value ?? 0) } }
        #expect(try frozen() == 1)

        try await session.retryFrozen()

        #expect(try frozen() == 0)
        #expect(try outboxCount(session) == 1)
        await session.close()
    }

    @Test func aFailedMigrationIsReportedByOpen() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let broken = SchemaModule(name: "Broken", migrations: [Migration(module: "Broken", version: 1, sql: "CREATE TABLE (")], recordTypes: [])
        do {
            _ = try await WellnessSession.open(environment(root.url, user: "user-a", server: ScriptedRecordServer(), clock: ManualClock()), modules: [broken])
            Issue.record("open should have failed")
        } catch SessionError.storeUnavailable(.migrationFailed(let module, let version, _)) {
            #expect(module == "Broken")
            #expect(version == 1)
        }
        // The failed open released its lock.
        let session = try await WellnessSession.open(environment(root.url, user: "user-a", server: ScriptedRecordServer(), clock: ManualClock()), modules: [Self.notesModule])
        await session.close()
    }

    @Test func localDataCanBeErasedOnlyWhenTheSessionIsClosed() async throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let session = try await WellnessSession.open(environment(root.url, user: "user-a", server: ScriptedRecordServer(), clock: ManualClock()), modules: [Self.notesModule])
        try await session.repository(for: TestNote.self).save(TestNote(id: RecordID("a"), body: "one"))

        #expect(throws: SessionError.alreadyOpen(userID: UserID("user-a"))) {
            try WellnessSession.eraseLocalData(userID: UserID("user-a"), rootDirectory: root.url)
        }
        await session.close()
        try WellnessSession.eraseLocalData(userID: UserID("user-a"), rootDirectory: root.url)

        #expect(!FileManager.default.fileExists(atPath: session.directory.path))
    }

    @Test func unusualUserIDsGetAHashedDirectory() {
        #expect(WellnessSession.directoryName(for: UserID("5f0c1a2e-user_1")) == "5f0c1a2e-user_1")
        let hashed = WellnessSession.directoryName(for: UserID("../escape"))
        #expect(hashed.hasPrefix("u-"))
        #expect(!hashed.contains("/"))
    }
}
