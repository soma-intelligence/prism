import Foundation
import Testing
import SyncCore
import SyncTesting

@Suite struct SyncAgentPushTests {
    func note(_ id: String, _ body: String) -> TestNote { TestNote(id: RecordID(id), body: body) }

    @Test func pushesPendingChangesAndClearsTheOutbox() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save([note("a", "one"), note("b", "two")])

        let report = await device.agent.sync()

        #expect(report.pushedChanges == 2)
        #expect(report.stoppedBy == nil)
        #expect(try device.outboxCount() == 0)
        #expect(await server.liveRecords(type: TestNote.recordType).count == 2)
        await device.close()
    }

    @Test func anEditMadeDuringThePushIsPushedAgain() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        let editor = EditorBox()
        let remote = HookedRecordStore(inner: server) { call in
            if call == 1 { await editor.edit() }
        }
        let device = try TestDevice.open(directory: directory.url, remote: remote, clock: ManualClock())
        await editor.set { try await device.notes.save(TestNote(id: RecordID("a"), body: "edited during push")) }
        try await device.notes.save(note("a", "original"))

        let report = await device.agent.sync()

        #expect(report.pushedChanges == 2)
        #expect(try device.outboxCount() == 0)
        let stored = await server.liveRecords(type: TestNote.recordType)[RecordID("a")]
        #expect(try stored?.decode(TestNote.self).body == "edited during push")
        await device.close()
    }

    @Test func conflictKeepsTheServerVersionAndPublishesTheDiscardedValue() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save(note("a", "first"))
        _ = await device.agent.sync()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("a"), payload: try RecordPayload(encoding: note("a", "from another device")))
        try await device.notes.save(note("a", "local edit"))
        let stream = device.changes.stream()

        let report = await device.agent.sync()

        #expect(report.conflicts == 1)
        #expect(try await device.notes.fetch(RecordID("a"))?.body == "from another device")
        #expect(try device.outboxCount() == 0)
        var iterator = stream.makeAsyncIterator()
        let batch = try #require(await iterator.next())
        #expect(batch.origin == .remote)
        #expect(batch.changes.contains(.conflictResolved(TestNote.recordType, RecordID("a"), discarded: try RecordPayload(encoding: note("a", "local edit")))))
        await device.close()
    }

    @Test func serverDeletionWinsOverALocalEdit() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save(note("a", "first"))
        _ = await device.agent.sync()
        await server.serverWrite(type: TestNote.recordType, id: RecordID("a"), payload: try RecordPayload(encoding: note("a", "first")), deleted: true)
        try await device.notes.save(note("a", "local edit"))

        _ = await device.agent.sync()

        #expect(try await device.notes.fetch(RecordID("a")) == nil)
        #expect(try device.outboxCount() == 0)
        await device.close()
    }

    @Test func rejectedChangeIsFrozenWhileOthersContinue() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        await server.reject(ids: [RecordID("bad")])
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save([note("bad", "x"), note("good", "y")])

        let first = await device.agent.sync()
        let second = await device.agent.sync()

        #expect(first.rejected == 1)
        #expect(first.pushedChanges == 1)
        #expect(second.pushedChanges == 0)
        #expect(try device.frozenCount() == 1)
        #expect(await server.pushCalls == 1)
        await device.close()
    }

    @Test func transientFailurePersistsItsBackoffAcrossARelaunch() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        await server.script([.fail(.transient(status: 503, retryAfter: nil))])
        var device = try TestDevice.open(directory: directory.url, remote: server, clock: clock)
        try await device.notes.save(note("a", "one"))

        let failed = await device.agent.sync()
        #expect(failed.deferred.count == 1)
        let entry = try #require(try device.outboxEntry(RecordID("a")))
        #expect(entry.attempts == 1)
        #expect(entry.nextAttemptAt == clock.now().adding(.milliseconds(1_000)).millisecondsSinceEpoch)
        await device.close()

        device = try TestDevice.open(directory: directory.url, remote: server, clock: clock)
        _ = await device.agent.sync()
        #expect(await server.pushCalls == 1)
        clock.advance(by: .seconds(1))
        let retried = await device.agent.sync()
        #expect(retried.pushedChanges == 1)
        await device.close()
    }

    @Test func retryAfterFromTheServerIsHonored() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        await server.script([.fail(.transient(status: 429, retryAfter: .seconds(60)))])
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: clock)
        try await device.notes.save(note("a", "one"))

        _ = await device.agent.sync()

        #expect(try device.outboxEntry(RecordID("a"))?.nextAttemptAt == clock.now().adding(.seconds(60)).millisecondsSinceEpoch)
        await device.close()
    }

    @Test func offlineStopsWithoutConsumingAnAttempt() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        await server.script([.fail(.offline)])
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save(note("a", "one"))

        let report = await device.agent.sync()

        #expect(report.stoppedBy == .offline)
        #expect(try device.outboxEntry(RecordID("a"))?.attempts == 0)
        await device.close()
    }

    @Test func unauthorizedRefreshesOnceAndSucceeds() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        await server.script([.fail(.unauthorized)])
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save(note("a", "one"))

        let report = await device.agent.sync()

        #expect(report.pushedChanges == 1)
        #expect(await device.tokens.refreshCalls == 1)
        #expect(Array(await server.tokensSeen.prefix(2)) == ["token-1", "token-2"])
        await device.close()
    }

    @Test func repeatedUnauthorizedStopsAndPublishesAuthRequired() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        await server.script([.fail(.unauthorized), .fail(.unauthorized)])
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save(note("a", "one"))
        let stream = device.changes.stream()

        let report = await device.agent.sync()

        #expect(report.stoppedBy == .authRequired)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == ChangeBatch(origin: .local, changes: [.authRequired]))
        await device.close()
    }

    @Test func breakerOpensAfterFiveConsecutiveTransientFailures() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        await server.script(Array(repeating: .fail(.timeout), count: 10))
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: clock)
        try await device.notes.save(note("a", "one"))

        for _ in 0..<5 {
            _ = await device.agent.sync()
            let next = try #require(try device.outboxEntry(RecordID("a"))).nextAttemptAt
            if let open = await device.agent.circuitOpenUntil {
                #expect(open.millisecondsSinceEpoch >= clock.now().millisecondsSinceEpoch)
                break
            }
            clock.set(Instant(millisecondsSinceEpoch: next))
        }
        let blocked = await device.agent.sync()

        guard case .circuitOpen = blocked.stoppedBy else {
            Issue.record("expected an open circuit, got \(String(describing: blocked.stoppedBy))")
            return
        }
        // Pushes and pulls share the remote, so both count toward the threshold.
        #expect(await server.pushCalls + server.pullCalls == 5)
        await device.close()
    }

    @Test func malformedResponsesFreezeAfterThreeAttempts() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        // Each run fails its push and its pull, so script two faults per run.
        await server.script(Array(repeating: .fail(.malformedResponse("garbage")), count: 6))
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: clock, policy: RetryPolicy(breakerThreshold: 100))
        try await device.notes.save(note("a", "one"))

        for _ in 0..<3 {
            _ = await device.agent.sync()
            if let entry = try device.outboxEntry(RecordID("a")), !entry.frozen {
                clock.set(Instant(millisecondsSinceEpoch: entry.nextAttemptAt))
            }
        }

        #expect(try device.frozenCount() == 1)
        #expect(try device.outboxEntry(RecordID("a"))?.lastError?.contains("malformed response") == true)
        await device.close()
    }

    @Test func lostResponseIsRetriedWithoutAConflict() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let clock = ManualClock()
        let server = ScriptedRecordServer()
        await server.script([.applyThenFail(.timeout)])
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: clock)
        try await device.notes.save(note("a", "one"))

        _ = await device.agent.sync()
        clock.advance(by: .seconds(5))
        let report = await device.agent.sync()

        #expect(report.pushedChanges == 1)
        #expect(report.conflicts == 0)
        #expect(await server.currentRevision == 1)
        #expect(try device.outboxCount() == 0)
        await device.close()
    }

    @Test func concurrentSyncCallsShareOneRun() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let server = ScriptedRecordServer()
        let device = try TestDevice.open(directory: directory.url, remote: server, clock: ManualClock())
        try await device.notes.save(note("a", "one"))

        async let first = device.agent.sync()
        async let second = device.agent.sync()
        let reports = await [first, second]

        #expect(reports.map(\.pushedChanges).reduce(0, +) >= 1)
        #expect(await server.pushCalls == 1)
        await device.close()
    }
}

/// Lets a remote hook call back into a device created after the hook.
actor EditorBox {
    private var action: (@Sendable () async throws -> Void)?

    func set(_ action: @escaping @Sendable () async throws -> Void) {
        self.action = action
    }

    func edit() async {
        do {
            try await action?()
        } catch {
            Issue.record("edit during push failed: \(error)")
        }
    }
}
