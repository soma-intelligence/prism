import Foundation
import Testing
import SyncCore
import SyncTesting

@Suite struct UploadJournalTests {
    struct Harness {
        let clock: ManualClock
        let changes: ChangeBroadcaster
        let store: LocalStore
        let journal: UploadJournal
    }

    func makeHarness(_ directory: TemporaryDirectory, remote: any RemoteObjectStore, capBytes: Int64 = 200_000_000) throws -> Harness {
        let clock = ManualClock()
        let changes = ChangeBroadcaster()
        let store = try TestSchema.openStore(at: directory.url.appendingPathComponent("db"), clock: clock, changes: changes)
        let user = UserID("user-a")
        let journal = try UploadJournal(
            store: store,
            directory: directory.url.appendingPathComponent("outgoing"),
            remote: remote,
            tokens: TokenGate(provider: ScriptedTokenProvider(userID: user), userID: user, clock: clock),
            clock: clock,
            random: FixedRandom(0.5),
            changes: changes,
            capBytes: capBytes
        )
        return Harness(clock: clock, changes: changes, store: store, journal: journal)
    }

    func object(_ journal: UploadJournal, key: String, content: String) throws -> ObjectToStage {
        let file = journal.makeTemporaryFile()
        try Data(content.utf8).write(to: file)
        return ObjectToStage(key: key, temporaryFile: file, digest: try OutgoingFile.seal(file), contentType: "application/x-ndjson")
    }

    func outgoingFiles(_ journal: UploadJournal) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: journal.outgoingDirectory.path).filter { $0 != "tmp" }
    }

    @Test func keysAreDeterministicAndContentAddressed() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("sample")
        try Data("hello".utf8).write(to: file)
        let digest = try OutgoingFile.seal(file)
        #expect(digest.byteCount == 5)
        #expect(digest.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        let key = ObjectKey.make(prefix: "raw", userID: UserID("u1"), stream: "heart_rate", windowStart: "20260101", windowEnd: "20260102", sha256: digest.sha256, fileExtension: "ndjson.gz")
        #expect(key == "raw/u1/heart_rate/20260101_20260102_2cf24dba5fb0.ndjson.gz")
    }

    @Test func positionCommitsOnlyWhenEveryObjectIsConfirmed() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let remote = InMemoryObjectStore()
        let harness = try makeHarness(directory, remote: remote)
        let journal = harness.journal
        await remote.fail(key: "k2", with: .transient(status: 503, retryAfter: nil))
        try await journal.stage(
            stream: "steps",
            objects: [try object(journal, key: "k1", content: "one"), try object(journal, key: "k2", content: "two")],
            position: Data("p1".utf8)
        )

        let first = await journal.send()
        #expect(first.confirmed == 1)
        #expect(try journal.committedPosition(stream: "steps") == nil)

        await remote.clearFailures()
        harness.clock.advance(by: .seconds(5))
        let second = await journal.send()

        #expect(second.confirmed == 1)
        #expect(second.committedStreams == ["steps"])
        #expect(try journal.committedPosition(stream: "steps") == Data("p1".utf8))
        #expect(try journal.stagedStep(stream: "steps") == nil)
        #expect(try outgoingFiles(journal).isEmpty)
        #expect(await remote.objects.count == 2)
        await harness.store.close()
    }

    @Test func entryStuckInSendingIsSentAgainAfterTheTimeout() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let remote = InMemoryObjectStore()
        let harness = try makeHarness(directory, remote: remote)
        let journal = harness.journal
        try await journal.stage(stream: "steps", objects: [try object(journal, key: "k1", content: "one")], position: Data("p1".utf8))
        try await harness.store.write(label: "test.simulate-crash") { transaction in
            try transaction.run("UPDATE upload_journal SET state = 'sending', sending_since = ?", [.integer(transaction.now.millisecondsSinceEpoch)])
        }

        _ = await journal.send()
        #expect(await remote.putCalls.isEmpty)

        harness.clock.advance(by: .seconds(901))
        let report = await journal.send()

        #expect(report.confirmed == 1)
        #expect(await remote.putCalls == ["k1"])
        #expect(try journal.committedPosition(stream: "steps") == Data("p1".utf8))
        await harness.store.close()
    }

    @Test func permanentFailureKeepsTheFileAndBlocksOnlyItsStream() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let remote = InMemoryObjectStore()
        let harness = try makeHarness(directory, remote: remote)
        let journal = harness.journal
        await remote.fail(key: "bad", with: .forbidden)
        try await journal.stage(stream: "a", objects: [try object(journal, key: "bad", content: "x")], position: Data("pa".utf8))
        try await journal.stage(stream: "b", objects: [try object(journal, key: "good", content: "y")], position: Data("pb".utf8))
        let stream = harness.changes.stream()

        let report = await journal.send()

        #expect(report.failed == 1)
        #expect(try journal.committedPosition(stream: "a") == nil)
        #expect(try journal.committedPosition(stream: "b") == Data("pb".utf8))
        #expect(try journal.entries(stream: "a").map(\.state) == ["failed"])
        #expect(try outgoingFiles(journal).count == 1)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == ChangeBatch(origin: .local, changes: [.uploadFailed(key: "bad", reason: "forbidden")]))
        await harness.store.close()
    }

    @Test func offlineStopsWithoutConsumingAnAttempt() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let remote = InMemoryObjectStore()
        await remote.script([.offline])
        let harness = try makeHarness(directory, remote: remote)
        let journal = harness.journal
        try await journal.stage(stream: "steps", objects: [try object(journal, key: "k1", content: "one")], position: Data("p1".utf8))

        let report = await journal.send()

        #expect(report.stoppedBy == .offline)
        let entry = try #require(try journal.entries(stream: "steps").first)
        #expect(entry.state == "queued")
        #expect(entry.attempts == 0)
        await harness.store.close()
    }

    @Test func diskCapPausesTheProducerInsteadOfDroppingData() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let harness = try makeHarness(directory, remote: InMemoryObjectStore(), capBytes: 10)
        let journal = harness.journal
        let large = try object(journal, key: "k1", content: String(repeating: "x", count: 20))

        await #expect(throws: StagingError.diskCapExceeded(pendingBytes: 0, capBytes: 10)) {
            try await journal.stage(stream: "steps", objects: [large], position: Data("p1".utf8))
        }
        #expect(FileManager.default.fileExists(atPath: large.temporaryFile.path))
        #expect(try journal.stagedStep(stream: "steps") == nil)
        await harness.store.close()
    }

    @Test func aSecondStepCannotBeStagedBeforeTheFirstCommits() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let harness = try makeHarness(directory, remote: InMemoryObjectStore())
        let journal = harness.journal
        try await journal.stage(stream: "steps", objects: [try object(journal, key: "k1", content: "one")], position: Data("p1".utf8))

        await #expect(throws: StagingError.stepAlreadyStaged(stream: "steps")) {
            try await journal.stage(stream: "steps", objects: [try object(journal, key: "k2", content: "two")], position: Data("p2".utf8))
        }
        await harness.store.close()
    }

    @Test func identicalReexportIsNotUploadedAgain() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let remote = InMemoryObjectStore()
        let harness = try makeHarness(directory, remote: remote)
        let journal = harness.journal
        try await journal.stage(stream: "steps", objects: [try object(journal, key: "k1", content: "same")], position: Data("p1".utf8))
        _ = await journal.send()

        try await journal.stage(stream: "steps", objects: [try object(journal, key: "k1", content: "same")], position: Data("p2".utf8))
        let report = await journal.send()

        #expect(report.committedStreams == ["steps"])
        #expect(await remote.putCalls == ["k1"])
        #expect(try journal.committedPosition(stream: "steps") == Data("p2".utf8))
        #expect(try outgoingFiles(journal).isEmpty)
        await harness.store.close()
    }

    @Test func orphanFilesAreRemoved() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let harness = try makeHarness(directory, remote: InMemoryObjectStore())
        let journal = harness.journal
        try await journal.stage(stream: "steps", objects: [try object(journal, key: "k1", content: "kept")], position: Data("p1".utf8))
        try Data("orphan".utf8).write(to: journal.outgoingDirectory.appendingPathComponent("orphan.upload"))
        try Data("partial".utf8).write(to: journal.makeTemporaryFile())

        let removed = try await journal.removeOrphans()

        #expect(removed == 2)
        #expect(try outgoingFiles(journal).count == 1)
        await harness.store.close()
    }
}
