import Foundation
import Testing
import SyncCore
import SyncTesting

@Suite struct SyncAgentPullTests {
    func payload(_ id: String, _ body: String) throws -> RecordPayload {
        try RecordPayload(encoding: TestNote(id: RecordID(id), body: body))
    }

    @Test func pullsRecordsAndCommitsTheCursorWithThePage() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        for id in ["a", "b", "c"] {
            await server.serverWrite(type: TestNote.recordType, id: RecordID(id), payload: try payload(id, "remote \(id)"))
        }
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        let stream = device.changes.stream()

        let report = await device.agent.sync()

        #expect(report.pulledRecords == 3)
        #expect(try await device.notes.fetchAll().map(\.body) == ["remote a", "remote b", "remote c"])
        #expect(try device.cursor() == Revision(3))
        var iterator = stream.makeAsyncIterator()
        let batch = try #require(await iterator.next())
        #expect(batch.origin == .remote)
        #expect(batch.changes.count == 3)
        await device.close()
    }

    @Test func pagesUntilTheServerHasNoMore() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        for index in 1...5 {
            await server.serverWrite(type: TestNote.recordType, id: RecordID("n\(index)"), payload: try payload("n\(index)", "v"))
        }
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock(), pullPageSize: 2)

        let report = await device.agent.sync()

        #expect(report.pulledRecords == 5)
        #expect(await server.pullCalls == 3)
        #expect(try device.cursor() == Revision(5))
        await device.close()
    }

    @Test func pendingLocalChangeIsNotOverwrittenByAPull() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: clock)
        try await device.notes.save(TestNote(id: RecordID("a"), body: "first"))
        _ = await device.agent.sync()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("a"), payload: try payload("a", "remote edit"))
        try await device.notes.save(TestNote(id: RecordID("a"), body: "local edit"))
        await server.script([.fail(.transient(status: 503, retryAfter: nil))])

        let report = await device.agent.sync()

        #expect(report.deferred.count == 1)
        #expect(try await device.notes.fetch(RecordID("a"))?.body == "local edit")
        await device.close()
    }

    @Test func remoteTombstoneDeletesTheLocalRow() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("a"), payload: try payload("a", "v"))
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        _ = await device.agent.sync()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("a"), payload: try payload("a", "v"), deleted: true)

        _ = await device.agent.sync()

        #expect(try await device.notes.fetch(RecordID("a")) == nil)
        #expect(try device.cursor() == Revision(2))
        await device.close()
    }

    @Test func ownPushedChangesAreNotAppliedAgainByThePull() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save(TestNote(id: RecordID("a"), body: "mine"))
        let stream = device.changes.stream()

        let report = await device.agent.sync()

        #expect(report.pulledRecords == 0)
        #expect(try device.cursor() == Revision(1))
        device.changes.finish()
        var remoteSaves = 0
        for await batch in stream where batch.origin == .remote {
            remoteSaves += batch.changes.filter { if case .recordSaved = $0 { true } else { false } }.count
        }
        #expect(remoteSaves == 0)
        await device.close()
    }

    @Test func expiredCursorTriggersAFullResyncThatPrunesVanishedRows() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        for id in ["a", "b", "c"] {
            await server.serverWrite(type: TestNote.recordType, id: RecordID(id), payload: try payload(id, "v"))
        }
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        _ = await device.agent.sync()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("b"), payload: try payload("b", "v"), deleted: true)
        await server.serverWrite(type: TestNote.recordType, id: RecordID("d"), payload: try payload("d", "new"))
        await server.purgeTombstones(type: TestNote.recordType)

        let report = await device.agent.sync()

        #expect(report.stoppedBy == nil)
        #expect(try await device.notes.fetchAll().map(\.id.rawValue) == ["a", "c", "d"])
        #expect(try device.cursor() == Revision(5))
        await device.close()
    }

    @Test func aResyncPagesPastThePurgeHorizonWithoutLooping() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("a"), payload: try payload("a", "v"))
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock(), pullPageSize: 1)
        _ = await device.agent.sync()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("b"), payload: try payload("b", "v"))
        await server.serverWrite(type: TestNote.recordType, id: RecordID("b"), payload: try payload("b", "v"), deleted: true)
        await server.serverWrite(type: TestNote.recordType, id: RecordID("c"), payload: try payload("c", "v"))
        await server.purgeTombstones(type: TestNote.recordType)

        let report = await device.agent.sync()

        #expect(report.stoppedBy == nil)
        #expect(report.deferred.isEmpty)
        #expect(try await device.notes.fetchAll().map(\.id.rawValue) == ["a", "c"])
        await device.close()
    }

    @Test func unreadableRemoteRecordIsQuarantinedAndTheCursorStillMoves() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = UnreadableRecordServer()
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())

        _ = await device.agent.sync()

        #expect(try device.quarantineCount() == 1)
        #expect(try device.cursor() == Revision(9))
        await device.close()
    }
}

/// Serves one live record without a payload, which the contract forbids.
struct UnreadableRecordServer: RemoteRecordStore {
    func push(_ changes: [OutgoingChange], type: RecordType, token: AccessToken) async throws(RemoteError) -> [PushOutcome] {
        []
    }

    func pull(_ type: RecordType, after revision: Revision?, limit: Int, resyncing: Bool, token: AccessToken) async throws(RemoteError) -> PullPage {
        guard revision == nil else { return PullPage(records: [], hasMore: false) }
        return PullPage(records: [RemoteRecord(id: RecordID("x"), revision: Revision(9), deleted: false, payload: nil)], hasMore: false)
    }
}
