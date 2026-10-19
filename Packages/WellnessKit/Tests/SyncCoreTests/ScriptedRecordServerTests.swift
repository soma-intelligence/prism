import Foundation
import Testing
import SyncCore
import SyncTesting

/// The reference server defines the contract every adapter must honor.
@Suite struct ScriptedRecordServerTests {
    let type = TestNote.recordType
    let token = AccessToken(userID: UserID("user-a"), value: "token-1", expiresAt: .distantFuture)

    func payload(_ body: String, id: String = "a") throws -> RecordPayload {
        try RecordPayload(encoding: TestNote(id: RecordID(id), body: body))
    }

    @Test func insertWithoutBaseIsApplied() async throws {
        let server = ScriptedRecordServer()
        let outcomes = try await server.push(
            [OutgoingChange(id: RecordID("a"), baseRevision: nil, deleted: false, payload: try payload("one"))],
            type: type, token: token
        )
        #expect(outcomes == [.applied(RecordID("a"), Revision(1))])
        #expect(await server.tokensSeen == ["token-1"])
    }

    @Test func matchingBaseIsAppliedWithANewRevision() async throws {
        let server = ScriptedRecordServer()
        _ = try await server.push([OutgoingChange(id: RecordID("a"), baseRevision: nil, deleted: false, payload: try payload("one"))], type: type, token: token)
        let outcomes = try await server.push(
            [OutgoingChange(id: RecordID("a"), baseRevision: Revision(1), deleted: false, payload: try payload("two"))],
            type: type, token: token
        )
        #expect(outcomes == [.applied(RecordID("a"), Revision(2))])
    }

    @Test func staleBaseIsAConflictCarryingTheServerRecord() async throws {
        let server = ScriptedRecordServer()
        let revision = await server.serverWrite(type: type, id: RecordID("a"), payload: try payload("server"))
        let outcomes = try await server.push(
            [OutgoingChange(id: RecordID("a"), baseRevision: Revision(revision.rawValue - 1), deleted: false, payload: try payload("local"))],
            type: type, token: token
        )
        #expect(outcomes == [.conflict(RecordID("a"), RemoteRecord(id: RecordID("a"), revision: revision, deleted: false, payload: try payload("server")))])
    }

    @Test func replayOfTheCurrentContentIsAppliedWithoutANewRevision() async throws {
        let server = ScriptedRecordServer()
        _ = try await server.push([OutgoingChange(id: RecordID("a"), baseRevision: nil, deleted: false, payload: try payload("one"))], type: type, token: token)
        let outcomes = try await server.push(
            [OutgoingChange(id: RecordID("a"), baseRevision: nil, deleted: false, payload: try payload("one"))],
            type: type, token: token
        )
        #expect(outcomes == [.applied(RecordID("a"), Revision(1))])
    }

    @Test func baseForAMissingRecordIsAConflictWithATombstone() async throws {
        let server = ScriptedRecordServer()
        let outcomes = try await server.push(
            [OutgoingChange(id: RecordID("gone"), baseRevision: Revision(7), deleted: false, payload: try payload("x", id: "gone"))],
            type: type, token: token
        )
        #expect(outcomes == [.conflict(RecordID("gone"), RemoteRecord(id: RecordID("gone"), revision: Revision(0), deleted: true, payload: nil))])
    }

    @Test func pullPagesInRevisionOrder() async throws {
        let server = ScriptedRecordServer()
        for index in 1...5 {
            _ = await server.serverWrite(type: type, id: RecordID("n\(index)"), payload: try payload("v", id: "n\(index)"))
        }
        let first = try await server.pull(type, after: nil, limit: 2, resyncing: false, token: token)
        #expect(first.records.map(\.revision) == [Revision(1), Revision(2)])
        #expect(first.hasMore)
        let last = try await server.pull(type, after: Revision(4), limit: 2, resyncing: false, token: token)
        #expect(last.records.map(\.revision) == [Revision(5)])
        #expect(!last.hasMore)
    }

    @Test func purgedTombstonesExpireOlderCursors() async throws {
        let server = ScriptedRecordServer()
        _ = await server.serverWrite(type: type, id: RecordID("a"), payload: try payload("v"))
        _ = await server.serverWrite(type: type, id: RecordID("a"), payload: try payload("v"), deleted: true)
        await server.purgeTombstones(type: type)
        await #expect(throws: RemoteError.cursorExpired) { try await server.pull(type, after: Revision(1), limit: 10, resyncing: false, token: token) }
        let fresh = try await server.pull(type, after: nil, limit: 10, resyncing: false, token: token)
        #expect(fresh.records.isEmpty)
        let current = try await server.pull(type, after: Revision(2), limit: 10, resyncing: false, token: token)
        #expect(current.records.isEmpty)
    }

    @Test func scriptedFaultsAreConsumedInOrder() async throws {
        let server = ScriptedRecordServer()
        await server.script([.fail(.offline), .applyThenFail(.timeout)])
        let change = OutgoingChange(id: RecordID("a"), baseRevision: nil, deleted: false, payload: try payload("one"))
        await #expect(throws: RemoteError.offline) { try await server.push([change], type: type, token: token) }
        await #expect(throws: RemoteError.timeout) { try await server.push([change], type: type, token: token) }
        #expect(await server.record(type: type, id: RecordID("a"))?.revision == 1)
        #expect(try await server.push([change], type: type, token: token) == [.applied(RecordID("a"), Revision(1))])
    }

    @Test func rejectedIDsAreRejected() async throws {
        let server = ScriptedRecordServer()
        await server.reject(ids: [RecordID("bad")])
        let outcomes = try await server.push(
            [OutgoingChange(id: RecordID("bad"), baseRevision: nil, deleted: false, payload: try payload("x", id: "bad"))],
            type: type, token: token
        )
        #expect(outcomes == [.rejected(RecordID("bad"), reason: "rejected by script")])
    }

    @Test func snapshotRoundTrips() async throws {
        let server = ScriptedRecordServer()
        _ = await server.serverWrite(type: type, id: RecordID("a"), payload: try payload("v"))
        let data = try JSONEncoder().encode(await server.snapshot())
        let restored = ScriptedRecordServer(snapshot: try JSONDecoder().decode(ServerSnapshot.self, from: data))
        #expect(await restored.liveRecords(type: type) == [RecordID("a"): try payload("v")])
        #expect(await restored.serverWrite(type: type, id: RecordID("b"), payload: try payload("w", id: "b")) == Revision(2))
    }
}
